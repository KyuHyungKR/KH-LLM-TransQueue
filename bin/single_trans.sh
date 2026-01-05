#!/usr/bin/env bash
echo "[SHELL DEBUG] $(date) - Args: $*" >> /download/KH-LLM-TransQueue/log/debug_engine.log
set -eo pipefail

# -----------------------------------------------------------------------------
# [FIXED] Dynamic Base Path Calculation
# [FIXED] 동적 기본 경로 계산
# -----------------------------------------------------------------------------
# Finds the project root based on the current script's location (bin/single_trans.sh).
# 현재 스크립트(bin/single_trans.sh)의 위치를 기준으로 프로젝트 루트를 찾습니다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# --- LANG FIX ---
echo "[DEBUG] Argument 3 (Lang): $3" >> /download/KH-LLM-TransQueue/log/debug_engine.log
TARGET_FULL=""
[ "$3" = "ko" ] && TARGET_FULL="Korean (한국어)"
export TARGET_LANG="$TARGET_FULL"


# ------------------------------
# API Key Check & Load
# API 키 확인 및 로딩
# ------------------------------
kh_llm_require_api_key() {
  # 1. Check if the key is already set in the current environment (e.g., from scheduler export).
  # 1. 키가 현재 환경 변수에 이미 설정되어 있는지 확인합니다.
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then return 0; fi
  
  # Try loading from file using BASE_DIR
  # BASE_DIR를 사용하여 설정 파일에서 키 로드를 시도합니다.
  if [[ -f "$BASE_DIR/conf/openai_api.env" ]]; then . "$BASE_DIR/conf/openai_api.env"; fi
  
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    # If key is still missing, try reading the raw key file.
    # 키가 여전히 없으면, raw 키 파일을 읽어옵니다.
    local key_file="$BASE_DIR/conf/openai_api.key"
    if [[ -f "$key_file" ]]; then
      local k
      # Read key, strip newlines, and export it.
      # 키를 읽고 개행 문자를 제거한 후 환경 변수로 내보냅니다.
      k="$(tr -d "\r\n" < "$key_file" 2>/dev/null || true)"
      [[ -n "$k" ]] && export OPENAI_API_KEY="$k"
    fi
  fi

  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    # Final check: If key is still missing, exit with API_KEY_MISSING code (40).
    # 최종 확인: 키가 없으면 에러 메시지를 출력하고 코드 40으로 종료합니다.
    echo "[ERROR] OpenAI API key is not configured." >&2
    exit 40
  fi
}

# Run Check
# 키 검사 실행
kh_llm_require_api_key

# ------------------------------
# Arguments (Received from Scheduler)
# 인자 (스케줄러로부터 수신)
# ------------------------------
PROMPT_NAME="${1:-}"
CONFIG_NAME="${2:-}"
LANGCODE="${3:-}"
FILE_INDEX="${4:-}"
FILE_TOTAL="${5:-}"
INPUT_FILE="${6:-}"
SUMMARY_TSV="${7:-}"
RUN_ID_ARG="${8:-}"
RUN_ID="${RUN_ID_ARG:-$RUN_ID}"

# Basic input validation
# 기본 입력 유효성 검사
if [[ -z "$INPUT_FILE" || -z "$SUMMARY_TSV" ]]; then exit 1; fi

# ------------------------------
# [CORE FIX] Engine Paths (Relative)
# [핵심 수정] 엔진 경로 (상대 경로)
# ------------------------------
# Path to the Python executable and the translation script, relative to BASE_DIR.
# BASE_DIR를 기준으로 파이썬 실행 파일 및 번역 스크립트 경로를 정의합니다.
PYTHON="$BASE_DIR/engine/envsubtrans/bin/python"
GPT_SUBTRANS="$BASE_DIR/engine/scripts/gpt-subtrans.py"

LOG_DIR="$BASE_DIR/log"
OUTPUT_DIR="$BASE_DIR/srt/output"
mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

# Cost Lib Load
# 비용 라이브러리 로드
COST_LIB="$BASE_DIR/bin/llm-cost.sh"
if [[ -f "$COST_LIB" ]]; then
  . "$COST_LIB"
  # Initialize cost library variables if the functions exist.
  # 함수가 존재하면 비용 라이브러리 변수들을 초기화합니다.
  if declare -F llm_cost_init >/dev/null; then
    llm_cost_init "${RUN_ID:-}" "$SUMMARY_TSV" "${META_CURRENCY:-KRW}"
  fi
fi

LLM_ERRORS="$BASE_DIR/bin/llm-errors.sh"
if [[ -f "$LLM_ERRORS" ]]; then . "$LLM_ERRORS"; else E_OK=0; fi

# Check Dependencies (Engine Check)
# 의존성 검사 (엔진 파일 존재 여부)
# Verify Python executable permissions and existence (Exit 30 if missing).
# 파이썬 실행 파일의 권한 및 존재 여부를 확인합니다.
if [[ ! -x "$PYTHON" ]]; then
    echo "[ERROR] Python engine not found at: $PYTHON" >&2
    echo "        Please run './bin/llm-install-engine.sh' to install dependencies." >&2
    exit 30
fi

# Verify gpt-subtrans script existence (Exit 31 if missing).
# gpt-subtrans 스크립트의 존재 여부를 확인합니다.
if [[ ! -f "$GPT_SUBTRANS" ]]; then
    echo "[ERROR] Translation script not found at: $GPT_SUBTRANS" >&2
    exit 31
fi

# Defaults
# 기본값 설정
MODEL_NAME="${LLM_MODEL_NAME:-gpt-4.1-mini}"
BILLING_MODE="${LLM_BILLING_MODE:-batch}"
MAX_BATCH_SIZE="${LLM_BATCH_SIZE:-50}"
SCENE_THRESHOLD="${LLM_SCENE_THRESHOLD:-3}"
TEMPERATURE="${LLM_TEMPERATURE:-0.3}"
PROMPT_FILE="$BASE_DIR/prompt/$PROMPT_NAME"

# Scene Threshold compatibility fix (Converts 'auto' to '0' for the Python parser).
# Scene Threshold 호환성 수정 ('auto'를 '0'으로 변환).
if [[ "$SCENE_THRESHOLD" == "auto" ]]; then SCENE_THRESHOLD=0; fi

BASENAME="$(basename "$INPUT_FILE")"
STEM="${BASENAME%.srt}"
OUTPUT_FILE="$OUTPUT_DIR/${STEM}.${LANGCODE}.srt"
RAW_LOG="$LOG_DIR/raw_${STEM}_${LANGCODE}.log"
: > "$RAW_LOG"
FILE_START_TS=$(date +%s)
echo "[DIAG] Engine Start - Lang: $LANGCODE" >> /download/KH-LLM-TransQueue/log/debug_engine.log

# Run Python Engine
# 파이썬 엔진 실행
if ! "$PYTHON" "$GPT_SUBTRANS" -m "$MODEL_NAME" -l "$TARGET_LANG"  --instructionfile "$PROMPT_FILE" --maxbatchsize "$MAX_BATCH_SIZE"  --scenethreshold "$SCENE_THRESHOLD" --temperature "$TEMPERATURE"  -o "$OUTPUT_FILE" "$INPUT_FILE" >"$RAW_LOG" 2>&1; then
  
  # Error Handling: Check raw log for specific API failure patterns.
  # 에러 처리: API 로그에서 특정 실패 패턴을 검색합니다.
  if grep -qi "API key" "$RAW_LOG"; then 
     exit 40
  elif grep -qi "rate limit" "$RAW_LOG"; then 
     exit 41
  else 
     exit 33 # Generic Python/Engine failure
  fi
fi

FILE_END_TS=$(date +%s)
ELAPSED=$((FILE_END_TS - FILE_START_TS))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

# Parse Usage
# 토큰 사용량 파싱
SUM_PT=0; SUM_CT=0; SUM_TT=0
if [[ -f "$RAW_LOG" ]]; then
  read -r SUM_PT SUM_CT SUM_TT <<< "$(python3 -c 'import sys, re; t=open(sys.argv[1]).read(); pt=sum(int(m.group(1)) for m in re.finditer(r"prompt=(\d+)", t)); ct=sum(int(m.group(1)) for m in re.finditer(r"completion=(\d+)", t)); print(f"{pt} {ct} {pt+ct}")' "$RAW_LOG")"
fi

# Calculate Cost
# 비용 계산
COST_TOTAL_USD=0; COST_TOTAL_LOCAL=0; CURRENCY_CODE="${META_CURRENCY:-KRW}"
if declare -F llm_cost_calc_usd >/dev/null; then COST_TOTAL_USD="$(llm_cost_calc_usd "$MODEL_NAME" "$BILLING_MODE" "$SUM_PT" "$SUM_CT")"; fi
if declare -F llm_cost_convert_usd >/dev/null; then COST_TOTAL_LOCAL="$(llm_cost_convert_usd "$COST_TOTAL_USD" "$CURRENCY_CODE")"; fi

# Format for Display
# 화면 표시용 포맷팅
TOKENS_FMT=$(printf "%'d" "$SUM_TT")
COST_USD_FMT=$(printf "%.4f" "$COST_TOTAL_USD")
if [[ "$CURRENCY_CODE" =~ ^(KRW|JPY|VND|IDR)$ ]]; then COST_LOCAL_FMT=$(printf "%.0f" "$COST_TOTAL_LOCAL"); else COST_LOCAL_FMT=$(printf "%.2f" "$COST_LOCAL_LOCAL"); fi

# Print Success Line (Scheduler picks this up)
# 성공 라인 출력 (스케줄러가 이 라인을 읽어 요약합니다.)
echo "◎ (${FILE_INDEX}/${FILE_TOTAL}) Done!! ${BASENAME}  →  ${ELAPSED_MIN}m ${ELSED_SEC}s | Tokens ${TOKENS_FMT} | USD ${COST_USD_FMT} | ${CURRENCY_CODE} ${COST_LOCAL_FMT}"

# Append final processed data to the Summary TSV file.
# 최종 처리 데이터를 Summary TSV 파일에 추가합니다.
printf "%s\t%d\t%s\t%d\t%d\t%d\t%.6f\t%.6f\t%d\n" "${RUN_ID:-}" "$FILE_INDEX" "$BASENAME" "$SUM_PT" "$SUM_CT" "$SUM_TT" "$COST_TOTAL_USD" "$COST_TOTAL_LOCAL" "$ELAPSED" >> "$SUMMARY_TSV"
exit 0
