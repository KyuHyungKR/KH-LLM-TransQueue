#!/usr/bin/env bash
set -euo pipefail

: "${E_OPENAI_API_KEY_MISSING:=40}"

# ======================================
# Base path & FX helper
# ======================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Load FX helper if exists
if [[ -f "$BASE_DIR/bin/llm-cost-fx.sh" ]]; then
  # shellcheck source=/dev/null
  . "$BASE_DIR/bin/llm-cost-fx.sh"
fi

# ============================================================
# KH LLM TransQueue - Simple Scheduler v9 (Stable)
# ============================================================

COST_LIB="$BASE_DIR/bin/llm-cost.sh"
if [[ -f "$COST_LIB" ]]; then
  # shellcheck source=/dev/null
  . "$COST_LIB"
fi

LLM_ERRORS="$BASE_DIR/bin/llm-errors.sh"
if [[ -f "$LLM_ERRORS" ]]; then
  # shellcheck disable=SC1090
  . "$LLM_ERRORS"
fi

SRT_DIR="$BASE_DIR/srt"
INPUT_DIR="$SRT_DIR/input"
SUCCESS_DIR="$SRT_DIR/success"
FAILED_DIR="$SRT_DIR/failed"
OUTPUT_DIR="$SRT_DIR/output"
TEMP_DIR="$BASE_DIR/temp"
LOG_DIR="$BASE_DIR/log"
JOBLOG_DIR="$TEMP_DIR/joblogs"

mkdir -p "$INPUT_DIR" "$SUCCESS_DIR" "$FAILED_DIR" "$OUTPUT_DIR" \
         "$TEMP_DIR" "$LOG_DIR" "$JOBLOG_DIR"

SINGLE_TRANS="$BASE_DIR/bin/single_trans.sh"

# ------------------------------
# Defaults & runtime options
# ------------------------------
DEFAULT_PROMPT_NAME="movie_drama_prompt.txt"
DEFAULT_CONFIG_NAME="movie_drama_config.txt"
DEFAULT_LANGCODE="ko"
DEFAULT_MAX_JOBS=3

PROMPT_NAME="$DEFAULT_PROMPT_NAME"
CONFIG_NAME="$DEFAULT_CONFIG_NAME"
LANGCODE="$DEFAULT_LANGCODE"
MAX_JOBS="$DEFAULT_MAX_JOBS"
DRY_RUN=0

: "${META_MODEL:=gpt-4.1-mini}"
: "${META_BILLING:=batch}"          # batch / standard 등
: "${META_SRC_LANG:=Auto}"          # Auto / en / ja ...
: "${META_BATCH_SIZE:=50}"          # 1회 요청에 묶을 SRT 블록 수
: "${META_SCENE_THRESHOLD:=auto}"   # auto / 숫자
: "${META_TEMPERATURE:=0.3}"
: "${META_RETRY:=3}"
: "${META_BACKOFF_SEC:=10}"
: "${META_QUEUE_SORT:=name}"
: "${META_CURRENCY:=KRW}"           # KRW / JPY / PHP ...

# openai_price.conf 로부터 단가/환율 보조 정보
KRW_PER_USD=1450
if [[ -f "$BASE_DIR/conf/openai_price.conf" ]]; then
  # shellcheck disable=SC1090
  source "$BASE_DIR/conf/openai_price.conf" || true
  : "${KRW_PER_USD:=1450}"
fi

usage() {
  cat <<EOF_USAGE
Usage: $(basename "$0") [options]

Options:
  -n, --dry-run         Show queue only (Dry run)
  --prompt NAME         Prompt filename (Default: $DEFAULT_PROMPT_NAME)
  --config NAME         Config filename (Default: $DEFAULT_CONFIG_NAME)
  --lang CODE           Target language code (Default: $DEFAULT_LANGCODE)
  -j, --max-jobs N      Max parallel jobs (Default: $DEFAULT_MAX_JOBS)
  -h, --help            Show this help
EOF_USAGE
}

# ------------------------------
# Parse Options
# ------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1; shift ;;
    --prompt)
      PROMPT_NAME="${2:-}"; shift 2 ;;
    --config)
      CONFIG_NAME="${2:-}"; shift 2 ;;
    --lang)
      LANGCODE="${2:-}"; shift 2 ;;
    -j|--max-jobs)
      MAX_JOBS="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

if ! [[ "$MAX_JOBS" =~ ^[0-9]+$ ]] || (( MAX_JOBS < 1 )); then
  MAX_JOBS="$DEFAULT_MAX_JOBS"
fi

RUN_ID="$(date +%F_%H%M%S)"; export RUN_ID
QUEUE_FILE="$TEMP_DIR/queue_${RUN_ID}.tsv"
SCHED_LOG="$LOG_DIR/scheduler_${RUN_ID}.log"
SUMMARY_TSV="$LOG_DIR/summary_${LANGCODE}_${RUN_ID}.tsv"

: > "$QUEUE_FILE"
: > "$SCHED_LOG"
echo -e "run_id\tfile_index\tbasename\tprompt_tokens\toutput_tokens\ttotal_tokens\tcost_usd\tcost_local\telapsed_sec" > "$SUMMARY_TSV"

export LLM_MODEL_NAME="$META_MODEL"
export LLM_BILLING_MODE="$META_BILLING"
export LLM_BATCH_SIZE="$META_BATCH_SIZE"
export LLM_SCENE_THRESHOLD="$META_SCENE_THRESHOLD"
export LLM_TEMPERATURE="$META_TEMPERATURE"
export META_CURRENCY="$META_CURRENCY"

# ------------------------------
# Stage 1: Build Queue
# ------------------------------
declare -a JOB_FILE
QUEUE_COUNT=0

while IFS= read -r input_file; do
  [[ -z "$input_file" ]] && continue
  basename="$(basename "$input_file")"
  QUEUE_COUNT=$((QUEUE_COUNT + 1))
  JOB_FILE[$QUEUE_COUNT]="$input_file"
  printf "%d\t%s\n" "$QUEUE_COUNT" "$input_file" >> "$QUEUE_FILE"
done < <(find "$INPUT_DIR" -maxdepth 1 -type f -name '*.srt' | sort)

TOTAL_JOBS="$QUEUE_COUNT"

# ------------------------------
# Header Output [ROLLBACK TO STABLE WIDTH]
# ------------------------------
SEP="==========================================================================="
echo "$SEP"
echo "  KH LLM TransQueue - Simple Scheduler v9"
echo "$SEP"
# Using fixed width 28 (The last stable width)
printf "  %-28s : %s\n"         "RUN_ID"                    "$RUN_ID"
printf "  %-28s : %s / %s\n"    "A.I Model/Billing"         "$META_MODEL" "$META_BILLING"
printf "  %-28s : %s → %s\n"    "Language (Source →Target)" "$META_SRC_LANG" "$LANGCODE"
printf "  %-28s : %s\n"         "Prompt"                    "$PROMPT_NAME"
printf "  %-28s : %s\n"         "Max Jobs"                  "$MAX_JOBS"
printf "  %-28s : %s\n"         "Batch Size"                "$META_BATCH_SIZE"
printf "  %-28s : %s / %s\n"    "Scene/Temperature"         "$META_SCENE_THRESHOLD" "$META_TEMPERATURE"
printf "  %-28s : %s / %ss\n"   "Retry/Backoff"             "$META_RETRY" "$META_BACKOFF_SEC"
printf "  %-28s : %s\n"         "Queue Sort"                "$META_QUEUE_SORT"
printf "  %-28s : %s\n"         "Local Currency"            "$META_CURRENCY"
echo
echo "============================== Queue Preview ==============================="
while IFS=$'\t' read -r idx path; do
  [[ -z "$idx" ]] && continue
  printf "%-3s %s\n" "$idx" "$path"
done < "$QUEUE_FILE"
echo "$SEP"
echo

if (( DRY_RUN )); then
  echo "[DRY_RUN] Queue generated. Exiting..."
  exit 0
fi

# ------------------------------
# Stage 2: Parallel Execution
# ------------------------------
declare -A PID2JOB
declare -a JOB_LOGFILE

COMPLETED_OK=0
COMPLETED_FAIL=0
HAD_API_KEY_MISSING=0

for ((j=1; j<=TOTAL_JOBS; j++)); do
  JOB_LOGFILE[$j]="$JOBLOG_DIR/job_${RUN_ID}_$(printf '%03d' "$j").log"
  : > "${JOB_LOGFILE[$j]}"
done

NEXT_JOB_ID=1
RUNNING=0
START_TS=$(date +%s)

cleanup() {
  echo
  echo "== Scheduler Finished =="
  echo "Log file   : $SCHED_LOG"
  echo "Summary TSV: $SUMMARY_TSV"
}
trap cleanup EXIT

while (( COMPLETED_OK + COMPLETED_FAIL < TOTAL_JOBS )); do
  # 1) Start new jobs
  while (( RUNNING < MAX_JOBS && NEXT_JOB_ID <= TOTAL_JOBS )); do
    job_id="$NEXT_JOB_ID"
    NEXT_JOB_ID=$((NEXT_JOB_ID + 1))

    input_file="${JOB_FILE[$job_id]}"
    base="$(basename "$input_file")"
    job_log="${JOB_LOGFILE[$job_id]}"

    printf "▶ (%d/%d) Translating %s\n" "$job_id" "$TOTAL_JOBS" "$base"
    echo "------------------------------------------------------------"

    "$SINGLE_TRANS" \
      "$PROMPT_NAME" \
      "$CONFIG_NAME" \
      "$LANGCODE" \
      "$job_id" \
      "$TOTAL_JOBS" \
      "$input_file" \
      "$SUMMARY_TSV" "$RUN_ID" >"$job_log" 2>&1 &

    pid=$!
    PID2JOB["$pid"]="$job_id"
    RUNNING=$((RUNNING + 1))
  done

  # 2) Wait for one job
  set +e
  wait -n -p finished_pid 2>/dev/null
  status=$?
  set -e

  job_id="${PID2JOB[$finished_pid]:-0}"
  if (( job_id == 0 )); then
    RUNNING=$((RUNNING > 0 ? RUNNING - 1 : 0))
    continue
  fi
  unset "PID2JOB[$finished_pid]"
  RUNNING=$((RUNNING - 1))

  input_file="${JOB_FILE[$job_id]}"
  base="$(basename "$input_file")"
  job_log="${JOB_LOGFILE[$job_id]}"

  if (( status == 0 )); then
    COMPLETED_OK=$((COMPLETED_OK + 1))

    summary_raw="$(grep -m1 '→' "$job_log" | tail -n1 || true)"
    if [[ -n "$summary_raw" ]]; then
      right_part="${summary_raw#*→}"
      printf '◎ (%d/%d) Completed %s →%s\n' \
        "$job_id" "$TOTAL_JOBS" "$base" "$right_part"
    else
      printf '◎ (%d/%d) Completed %s (exit=0)\n' \
        "$job_id" "$TOTAL_JOBS" "$base"
    fi

    mv -f -- "$input_file" "$SUCCESS_DIR/$base"
  else
    COMPLETED_FAIL=$((COMPLETED_FAIL + 1))
    if declare -F llm_status_reason >/dev/null 2>&1; then
      reason="$(llm_status_reason "$status")"
      printf '■ (%d/%d) Failed %s (reason: %s, exit=%d)\n' \
        "$job_id" "$TOTAL_JOBS" "$base" "$reason" "$status"
    else
      printf '■ (%d/%d) Failed %s (exit=%d)\n' \
        "$job_id" "$TOTAL_JOBS" "$base" "$status"
    fi

    E_KEY_MISSING_VAL=${E_OPENAI_API_KEY_MISSING:-40}
    if [[ "$status" -eq "$E_KEY_MISSING_VAL" ]]; then
      HAD_API_KEY_MISSING=1
    fi

    move_to_failed=1
    case "$status" in
      20|30|31|32|40|41|42|61|90)
        move_to_failed=0
        ;;
    esac

    if (( move_to_failed )); then
      mv -f -- "$input_file" "$FAILED_DIR/$base"
    fi
  fi
  echo "------------------------------------------------------------"
done

END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

# ------------------------------
# Stage 3: Summary
# ------------------------------
TOTAL_PROMPT_TOKENS=0
TOTAL_OUTPUT_TOKENS=0
TOTAL_TOKENS=0
TOTAL_COST_USD=0

if [[ -s "$SUMMARY_TSV" ]]; then
  read -r TOTAL_PROMPT_TOKENS TOTAL_OUTPUT_TOKENS TOTAL_TOKENS TOTAL_COST_USD _ <<<"$(
    awk -F'\t' -v RUN_ID="$RUN_ID" '
      BEGIN{pt=0;ot=0;tt=0;cu=0;cl=0}
      NR>1 && $1==RUN_ID {pt+=$4; ot+=$5; tt+=$6; cu+=$7; cl+=$8}
      END{printf "%.0f %.0f %.0f %.6f %.6f", pt, ot, tt, cu, cl}
    ' "$SUMMARY_TSV"
  )"
fi

SUMMARY_SEP="========== KH LLM Translation Summary =========="
echo
echo "$SUMMARY_SEP"
printf "Total files : %d\n"  "$TOTAL_JOBS"

if [ "$TOTAL_JOBS" -eq 0 ]; then
  echo
  echo "  [WARNING] No subtitle files found in the input folder."
  echo
fi

printf "Success     : %d\n"  "$COMPLETED_OK"
printf "Failed      : %d\n"  "$COMPLETED_FAIL"

if [[ "$HAD_API_KEY_MISSING" -eq 1 ]]; then
  echo
  echo "  [ERROR] OpenAI API key is not configured."
  echo "          Please run './llm-api-key-manager.sh' in bin/ directory to configure it."
fi

printf "Total time  : %dm %02ds\n" "$ELAPSED_MIN" "$ELAPSED_SEC"
echo
printf "Max Job     : %d\n"  "$MAX_JOBS"
printf "Model       : %s\n"  "$META_MODEL"
printf "Billing     : %s\n"  "$META_BILLING"
printf "Lang        : %s\n"  "$LANGCODE"
echo

printf "%-17s : %s\n" "Prompt Tokens" "${TOTAL_PROMPT_TOKENS:-0}"
printf "%-17s : %s\n" "Output Tokens" "${TOTAL_OUTPUT_TOKENS:-0}"
printf "%-17s : %s\n" "Total Tokens"  "${TOTAL_TOKENS:-0}"
echo

# ------------------------------
# Currency FX helper (llm-cost-fx.conf 기반)
# ------------------------------
CURRENCY_CODE="${META_CURRENCY:-KRW}"
fx_rate="1"
fx_label="$CURRENCY_CODE"

FX_CONF="$BASE_DIR/conf/llm-cost-fx.conf"
if [[ -f "$FX_CONF" ]]; then
  FX_LINE="$(awk -v code="$CURRENCY_CODE" '$1 == code { print $2, (NF>=3 ? $3 : $1); exit }' "$FX_CONF")"
  if [[ -n "$FX_LINE" ]]; then
    read -r fx_rate fx_label <<<"$FX_LINE"
  fi
fi

if [[ -z "${fx_rate:-}" ]]; then
  fx_rate="1"
  fx_label="$CURRENCY_CODE"
fi

local_cost="$TOTAL_COST_USD"
if [[ -n "${fx_rate:-}" ]]; then
  local_cost="$(awk -v usd="$TOTAL_COST_USD" -v r="$fx_rate" 'BEGIN{printf "%.2f", usd*r}')"
fi

# Cost: 소수 둘째 자리까지
printf "%-17s : %.2f\n" "Cost (USD)"            "$TOTAL_COST_USD"
printf "%-17s : %.2f\n" "Cost ($CURRENCY_CODE)" "$local_cost"

# FX Rate: 소수 둘째 자리
FX_RATE_FMT="$(awk -v r="${fx_rate:-0}" 'BEGIN{printf "%.2f", r+0}')"
printf "%-17s : %s\n" "$CURRENCY_CODE per USD" "$FX_RATE_FMT"
echo
echo "$SEP"
