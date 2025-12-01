#!/usr/bin/env bash
set -u

# KH LLM TransQueue - Main Menu (Final Polish + Height 29)

BASE_DIR="/download/KH-LLM-TransQueue"
PRESET_DIR="$BASE_DIR/preset"
BIN_DIR="$BASE_DIR/bin"
SCHEDULER_SCRIPT="$BIN_DIR/llm-scheduler.sh"

# Dialog Helper
dlg_menu() {
  local title="$1"; local text="$2"; local height="$3"; local width="$4"; local menu_height="$5"; shift 5
  local result
  result="$(dialog --clear --title "$title" --menu "$text" "$height" "$width" "$menu_height" "$@" 3>&1 1>&2 2>&3)" || return 1
  printf '%s\n' "$result"
}

# Defaults
META_MODEL="gpt-4.1-mini"
META_BILLING="batch"
META_SRC_LANG="Auto"
META_TGT_LANG="ko"
META_BATCH_SIZE="50"
META_MAX_JOBS="3"
META_SCENE_THRESHOLD="3"
META_TEMPERATURE="0.3"
META_RETRY="3"
META_BACKOFF_SEC="25"
META_QUEUE_SORT="name"
META_CURRENCY="KRW"
PROMPT_FILE="movie_drama_prompt.txt"
CURRENT_PRESET_FILE=""

mkdir -p "$PRESET_DIR"

# ----------------------------------------
# 1. Preset Selection
# ----------------------------------------
select_preset() {
    local options=(); local files=()
    options+=("0" "Start with Default Settings (Skip Preset)")
    local i=1; local NAME_WIDTH=35
    
    if [[ -d "$PRESET_DIR" ]]; then
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            files+=("$file")
            local f_path="$PRESET_DIR/$file"; local p_model="?"; local p_lang="?"
            if [[ -f "$f_path" ]]; then
                p_model=$(grep "MODEL_NAME=" "$f_path" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
                p_lang=$(grep "LANG_TARGET=" "$f_path" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
            fi
            local display_name="$file"
            if [ ${#display_name} -gt $NAME_WIDTH ]; then display_name="${display_name:0:$((NAME_WIDTH-3))}..."; fi
            local label=$(printf "%-${NAME_WIDTH}s  [ %s | %s ]" "$display_name" "${p_model:-?}" "${p_lang:-?}")
            options+=("$i" "$label")
            ((i++))
        done < <(ls -1 "$PRESET_DIR" 2>/dev/null)
    fi
    
    local header="Current Default Settings:\n"
    header+="--------------------------------\n"
    header+="Model       : $META_MODEL\n"
    header+="Lang        : $META_SRC_LANG -> $META_TGT_LANG\n"
    header+="Jobs / Batch: ${META_MAX_JOBS:-3} / $META_BATCH_SIZE\n"
    header+="--------------------------------\n"
    header+="Select a preset, or choose '0' to keep defaults:"

    # [UI FIX] Height 32 -> 29
    local choice=$(dlg_menu "KH LLM TransQueue - Preset" "$header" 29 85 14 "${options[@]}") || return
    
    if [ "$choice" == "0" ]; then
        return
    fi

    if [ -n "$choice" ]; then
        local index=$((choice - 1))
        echo "${files[$index]}"
    fi
}

# ------------------------------
# Settings Editors (중략 - 변경 없음)
# ------------------------------
edit_model() {
    local choice=$(dlg_menu "AI Model" "Select AI Model:" 16 60 6 \
        "gpt-4.1-mini" "Best Cost/Performance" \
        "gpt-5.1-mini" "Balanced" \
        "gpt-5.1" "High Performance" \
        "gpt-4o" "Legacy High" \
        "Custom" "Enter manually") || return
    if [ "$choice" == "Custom" ]; then choice=$(dialog --inputbox "Enter model name:" 10 50 "$META_MODEL" 3>&1 1>&2 2>&3) || return; fi
    [[ -n "$choice" ]] && META_MODEL="$choice"
}

edit_billing() {
    local choice=$(dlg_menu "Billing Mode" "Select Billing Mode:" 15 60 4 \
        "batch" "50% Discount (Delayed)" \
        "flex" "Standard Price" \
        "standard" "Full Price (Instant)" \
        "priority" "Premium Price") || return
    [[ -n "$choice" ]] && META_BILLING="$choice"
}

edit_batch_size() {
    local choice=$(dlg_menu "Batch Size" "How many subtitle lines to send per API request?\nLarger batches are faster but may reduce accuracy." 24 60 14 \
        "10" "Very Safe (Slow)" \
        "20" "Safe" \
        "30" "Conservative" \
        "40" "Moderate" \
        "50" "Standard (Default)" \
        "60" "Standard+" \
        "70" "High" \
        "80" "Aggressive" \
        "90" "Very Aggressive" \
        "100" "Maximum Limit" \
        "Custom" "Manual Input") || return
    if [ "$choice" == "Custom" ]; then choice=$(dialog --inputbox "Enter batch size:" 10 40 "$META_BATCH_SIZE" 3>&1 1>&2 2>&3) || return; fi
    [[ -n "$choice" ]] && META_BATCH_SIZE="$choice"
}

edit_max_jobs() {
    local choice=$(dlg_menu "Max Parallel Jobs" "How many files to process concurrently?" 18 55 6 \
        "1" "Sequential (Safe)" \
        "2" "Dual Process" \
        "3" "Standard (Default)" \
        "4" "High Load" \
        "5" "Maximum" \
        "Custom" "Manual") || return
    if [ "$choice" == "Custom" ]; then choice=$(dialog --inputbox "Enter max jobs:" 10 40 "${META_MAX_JOBS:-3}" 3>&1 1>&2 2>&3) || return; fi
    [[ -n "$choice" ]] && META_MAX_JOBS="$choice"
}

get_lang_list() {
    cat <<END
af Afrikaans
sq Albanian
am Amharic
ar Arabic
bn Bengali
bs Bosnian
bg Bulgarian
my Burmese
km Cambodian
yue Cantonese
ceb Cebuano
zh Chinese
zh-CN Chinese_Simplified
zh-TW Chinese_Traditional
hr Croatian
cs Czech
da Danish
nl Dutch
en English
et Estonian
tl Filipino_Tagalog
fi Finnish
fr French
de German
el Greek
gn Guarani
gu Gujarati
ha Hausa
he Hebrew
hi Hindi
hu Hungarian
is Icelandic
id Indonesian
it Italian
ja Japanese
kn Kannada
kk Kazakh
km Khmer
ko Korean
ku Kurdish
lo Lao
lv Latvian
lt Lithuanian
mk Macedonian
ms Malay
ml Malayalam
mr Marathi
mn Mongolian
ne Nepali
no Norwegian
fa Persian_Farsi
pl Polish
pt Portuguese
pt-BR Portuguese_Brazil
pa Punjabi
qu Quechua
ro Romanian
ru Russian
sr Serbian
si Sinhala
sk Slovak
sl Slovenian
so Somali
es Spanish
es-419 Spanish_Latin_America
sw Swahili
sv Swedish
ta Tamil
te Telugu
th Thai
tr Turkish
uk Ukrainian
ur Urdu
uz Uzbek
vi Vietnamese
yo Yoruba
zu Zulu
END
}

edit_lang() {
    local target="$1"
    local title="Target Language"
    local current="$META_TGT_LANG"
    local options=()
    
    if [ "$target" == "src" ]; then 
        title="Source Language"
        current="$META_SRC_LANG"
        options+=("Auto" "Automatic (Src only)")
        options+=("en" "English (en)")
        options+=("ko" "Korean (ko)")
    else
        options+=("ko" "Korean (ko)")
        options+=("en" "English (en)")
        options+=("ceb" "Cebuano (ceb)")
    fi

    local sorted_langs=$(get_lang_list | sort)
    while read -r code label; do
        if [ "$target" == "src" ] && [[ "$code" == "en" || "$code" == "ko" ]]; then continue; fi
        if [ "$target" == "tgt" ] && [[ "$code" == "ko" || "$code" == "en" || "$code" == "ceb" ]]; then continue; fi
        options+=("$code" "$label ($code)")
    done <<< "$sorted_langs"
    options+=("Custom" "Manual Input")

    local choice=$(dlg_menu "$title" "Select Language Code:" 22 70 15 "${options[@]}") || return
    if [ "$choice" == "Custom" ]; then choice=$(dialog --inputbox "Enter lang code:" 10 40 "$current" 3>&1 1>&2 2>&3) || return; fi
    if [[ -n "$choice" ]]; then
        if [ "$target" == "src" ]; then META_SRC_LANG="$choice"; else META_TGT_LANG="$choice"; fi
    fi
}

edit_prompt() {
    local p_files=$(ls "$BASE_DIR/prompt" 2>/dev/null)
    local p_list=()
    local preview_width=60
    
    if [ -z "$p_files" ]; then dialog --msgbox "No prompt files found." 10 60; return; fi

    for p in $p_files; do
        local content_preview=""
        local full_path="$BASE_DIR/prompt/$p"
        if [[ -f "$full_path" ]]; then
            local first_line=$(head -n 1 "$full_path" | tr -d '\r')
            if [ ${#first_line} -gt $preview_width ]; then
                content_preview="${first_line:0:$((preview_width-3))}..."
            else
                content_preview="$first_line"
            fi
        fi
        p_list+=("$p" "${content_preview:-No Description}")
    done
    
    local info="Select a file. (Right: First line preview)\n\n"
    info+="Location: KH-LLM-TransQueue/prompt/\n"
    info+="To edit : Add/Modify .txt files in the folder above."

    local p_choice=$(dlg_menu "Prompt Profile" "$info" 22 110 10 "${p_list[@]}") || return
    [[ -n "$p_choice" ]] && PROMPT_FILE="$p_choice"
}

edit_temperature() {
    local choice=$(dlg_menu "Temperature" "Controls randomness.\nLower = Deterministic, Higher = Creative." 18 60 9 \
        "0.1" "Strict / Focused" \
        "0.2" "Conservative" \
        "0.3" "Standard (Default)" \
        "0.4" "Balanced" \
        "0.5" "Creative" \
        "0.6" "More Random" \
        "0.7" "High Creativity" \
        "0.8" "Maximum (Risky)") || return
    [[ -n "$choice" ]] && META_TEMPERATURE="$choice"
}

edit_scene_threshold() {
    local choice=$(dlg_menu "Scene Threshold" "Gap in seconds to detect a new scene.\nHelps context separation." 18 60 9 \
        "1" "1 second" \
        "2" "2 seconds" \
        "3" "3 seconds (Default)" \
        "4" "4 seconds" \
        "5" "5 seconds" \
        "6" "6 seconds" \
        "8" "8 seconds" \
        "Custom" "Manual") || return
    if [ "$choice" == "Custom" ]; then choice=$(dialog --inputbox "Enter threshold:" 10 40 "$META_SCENE_THRESHOLD" 3>&1 1>&2 2>&3) || return; fi
    [[ -n "$choice" ]] && META_SCENE_THRESHOLD="$choice"
}

edit_retry() {
    local choice=$(dlg_menu "Retry Count" "Max automatic retries on API failure." 15 50 6 \
        "1" "1 Attempt" \
        "2" "2 Attempts" \
        "3" "3 Attempts (Default)" \
        "4" "4 Attempts" \
        "5" "5 Attempts") || return
    [[ -n "$choice" ]] && META_RETRY="$choice"
}

edit_backoff() {
    local choice=$(dlg_menu "Backoff Delay" "Wait time (seconds) before retrying." 18 50 8 \
        "10" "10s (Fast)" \
        "15" "15s" \
        "20" "20s" \
        "25" "25s (Default)" \
        "30" "30s" \
        "40" "40s" \
        "50" "50s (Slow)") || return
    [[ -n "$choice" ]] && META_BACKOFF_SEC="$choice"
}

edit_sort() {
    local choice=$(dlg_menu "Queue Sort Order" "Order of files to be processed." 15 50 3 \
        "name" "By Name (A-Z)" \
        "mtime" "By Time (Newest First)" \
        "size" "By Size (Largest First)") || return
    [[ -n "$choice" ]] && META_QUEUE_SORT="$choice"
}

get_currency_list() {
    cat <<END
AED United_Arab_Emirates_Dirham
ARS Argentine_Peso
AUD Australian_Dollar
BDT Bangladeshi_Taka
BHD Bahraini_Dinar
BND Brunei_Dollar
BRL Brazilian_Real
CAD Canadian_Dollar
CHF Swiss_Franc
CLP Chilean_Peso
CNY Chinese_Yuan
COP Colombian_Peso
CZK Czech_Koruna
DKK Danish_Krone
EGP Egyptian_Pound
ETB Ethiopian_Birr
EUR Euro
FJD Fijian_Dollar
GBP British_Pound_Sterling
HKD Hong_Kong_Dollar
HUF Hungarian_Forint
IDR Indonesian_Rupiah
ILS Israeli_New_Shekel
INR Indian_Rupee
JOD Jordanian_Dinar
JPY Japanese_Yen
KES Kenyan_Shilling
KHR Cambodian_Riel
KWD Kuwaiti_Dinar
KZT Kazakhstani_Tenge
LKR Sri_Lankan_Rupee
LYD Libyan_Dinar
MMK Myanmar_Kyat
MNT Mongolian_Tögrög
MOP Macanese_Pataca
MXN Mexican_Peso
MYR Malaysian_Ringgit
NOK Norwegian_Krone
NPR Nepalese_Rupee
NZD New_Zealand_Dollar
OMR Omani_Rial
PHP Philippine_Peso
PKR Pakistani_Rupee
PLN Polish_Zloty
QAR Qatari_Riyal
RON Romanian_Leu
RUB Russian_Ruble
SAR Saudi_Arabian_Riyal
SEK Swedish_Krona
SGD Singapore_Dollar
THB Thai_Baht
TRY Turkish_Lira
TWD New_Taiwan_Dollar
UZS Uzbekistani_Soʻm
VND Vietnamese_Dong
ZAR South_African_Rand
END
}

edit_currency() {
    local options=()
    options+=("KRW" "KRW - Korean Won")
    options+=("USD" "USD - United States Dollar")
    
    local sorted_curr=$(get_currency_list | sort)
    while read -r code label; do
        if [[ "$code" == "KRW" || "$code" == "USD" ]]; then continue; fi
        options+=("$code" "${label//_/ }")
    done <<< "$sorted_curr"
    
    local choice=$(dlg_menu "Local Currency" "Select Currency for Cost Display:" 22 70 15 "${options[@]}") || return
    [[ -n "$choice" ]] && META_CURRENCY="$choice"
}

# ------------------------------
# Run Scheduler
# ------------------------------
run_scheduler_tmux() {
    local cmd="env META_MODEL=\"$META_MODEL\" META_BILLING=\"$META_BILLING\" META_BATCH_SIZE=\"$META_BATCH_SIZE\" \
META_SRC_LANG=\"$META_SRC_LANG\" META_SCENE_THRESHOLD=\"$META_SCENE_THRESHOLD\" META_TEMPERATURE=\"$META_TEMPERATURE\" \
META_RETRY=\"$META_RETRY\" META_BACKOFF_SEC=\"$META_BACKOFF_SEC\" META_QUEUE_SORT=\"$META_QUEUE_SORT\" \
META_CURRENCY=\"$META_CURRENCY\" \
$SCHEDULER_SCRIPT --max-jobs \"$META_MAX_JOBS\" --lang \"$META_TGT_LANG\" --prompt \"$PROMPT_FILE\""

    local sess="kh-llm-transq_$(date +%H%M%S)"
    if ! command -v tmux &> /dev/null; then dialog --msgbox "Error: tmux not found" 10 40; return; fi
    
    tmux new-session -d -s "$sess" "$cmd; echo; echo '=== KH LLM TransQueue finished. Press Enter to close tmux ==='; read"
    if [ -n "${TMUX:-}" ]; then tmux switch-client -t "$sess"; else tmux attach-session -t "$sess"; fi
}

# ------------------------------
# Preset Save Check
# ------------------------------
build_preset_signature() {
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$META_MODEL" "$META_BILLING" "$META_BATCH_SIZE" "$META_MAX_JOBS" "$META_SRC_LANG" "$META_TGT_LANG" \
    "$PROMPT_FILE" "$META_SCENE_THRESHOLD" "$META_TEMPERATURE" "$META_RETRY" "$META_BACKOFF_SEC" "$META_QUEUE_SORT" "$META_CURRENCY"
}

check_and_maybe_save_preset() {
  local current_sig="$(build_preset_signature)"
  if [[ -z "${PRESET_SIG:-}" || "$current_sig" == "$PRESET_SIG" ]]; then return 0; fi

  set +e
  dialog --clear --title "Preset Changed" --yesno "Settings have been changed.\nSave as a new preset file?" 10 60
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then return 0; fi

  local default_input_name="new_preset"
  if [[ -n "${CURRENT_PRESET_FILE:-}" && "$CURRENT_PRESET_FILE" != "Default (None)" ]]; then
      default_input_name="$CURRENT_PRESET_FILE"
  fi

  local preset_name
  preset_name="$(dialog --title "Save Preset" --inputbox "Enter preset name:\n(Use letters/numbers/underscore)" 10 60 "$default_input_name" 3>&1 1>&2 2>&3)" || return 0
  preset_name="${preset_name// /_}"
  
  local preset_file="$BASE_DIR/preset/${preset_name}"
  mkdir -p "$BASE_DIR/preset"
  {
    printf 'MODEL_NAME=%q\n' "$META_MODEL"
    printf 'BILLING_MODE=%q\n' "$META_BILLING"
    printf 'BATCH_SIZE=%q\n' "$META_BATCH_SIZE"
    printf 'MAX_JOBS=%q\n' "$META_MAX_JOBS"
    printf 'LANG_SOURCE=%q\n' "$META_SRC_LANG"
    printf 'LANG_TARGET=%q\n' "$META_TGT_LANG"
    printf 'PROMPT_FILE=%q\n' "$PROMPT_FILE"
    printf 'TEMPERATURE=%q\n' "$META_TEMPERATURE"
    printf 'SCENE_THRESHOLD=%q\n' "$META_SCENE_THRESHOLD"
    printf 'RETRY_ATTEMPTS=%q\n' "$META_RETRY"
    printf 'BACKOFF_SECONDS=%q\n' "$META_BACKOFF_SEC"
    printf 'QUEUE_SORT=%q\n' "$META_QUEUE_SORT"
    printf 'CURRENCY_CODE=%q\n' "$META_CURRENCY"
  } > "$preset_file"
}

# ------------------------------
# Helper to Load Preset Variables
# ------------------------------
apply_preset() {
    local pfile="$1"
    if [[ -f "$pfile" ]]; then
        source "$pfile"
        [[ -n "${MODEL_NAME:-}" ]] && META_MODEL="$MODEL_NAME"
        [[ -n "${BILLING_MODE:-}" ]] && META_BILLING="$BILLING_MODE"
        [[ -n "${BATCH_SIZE:-}" ]] && META_BATCH_SIZE="$BATCH_SIZE"
        [[ -n "${MAX_JOBS:-}" ]] && META_MAX_JOBS="$MAX_JOBS"
        [[ -n "${LANG_SOURCE:-}" ]] && META_SRC_LANG="$LANG_SOURCE"
        [[ -n "${LANG_TARGET:-}" ]] && META_TGT_LANG="$LANG_TARGET"
        [[ -n "${PROMPT_FILE:-}" ]] && PROMPT_FILE="$PROMPT_FILE"
        [[ -n "${SCENE_THRESHOLD:-}" ]] && META_SCENE_THRESHOLD="$SCENE_THRESHOLD"
        [[ -n "${TEMPERATURE:-}" ]] && META_TEMPERATURE="$TEMPERATURE"
        [[ -n "${RETRY_ATTEMPTS:-}" ]] && META_RETRY="$RETRY_ATTEMPTS"
        [[ -n "${BACKOFF_SECONDS:-}" ]] && META_BACKOFF_SEC="$BACKOFF_SECONDS"
        [[ -n "${QUEUE_SORT:-}" ]] && META_QUEUE_SORT="$QUEUE_SORT"
        [[ -n "${CURRENCY_CODE:-}" ]] && META_CURRENCY="$CURRENCY_CODE"
        CURRENT_PRESET_FILE="${pfile##*/}"
    fi
}

# ------------------------------
# Main Entry
# ------------------------------
selected_file="$(select_preset)"
if [[ -n "$selected_file" ]]; then apply_preset "$PRESET_DIR/$selected_file"; else CURRENT_PRESET_FILE="Default (None)"; fi
PRESET_SIG="$(build_preset_signature)"

while true; do
    display="Current Settings:\n"
    display+="--------------------------------\n"
    display+="Preset      : ${CURRENT_PRESET_FILE}\n"
    display+="Model       : $META_MODEL\n"
    display+="Billing     : $META_BILLING\n"
    display+="Lang        : $META_SRC_LANG -> $META_TGT_LANG\n"
    display+="Jobs / Batch: $META_MAX_JOBS / $META_BATCH_SIZE\n"
    display+="Currency    : $META_CURRENCY\n"
    display+="--------------------------------\n"
    display+="Select an item to edit, or choose RUN."

    choice=$(dlg_menu "KH LLM TransQueue - Settings" "$display" 32 85 14 \
        1 "AI model" \
        2 "Billing mode" \
        3 "Batch size" \
        4 "Max parallel jobs" \
        5 "Source language" \
        6 "Target language" \
        7 "Prompt profile" \
        8 "Temperature" \
        9 "Scene threshold" \
        10 "Retry / Backoff" \
        11 "Queue sort" \
        12 "Local currency" \
        13 "▶ RUN with these settings" \
        14 "Exit without running") || exit 0

    case "$choice" in
        1) edit_model ;; 2) edit_billing ;; 3) edit_batch_size ;; 4) edit_max_jobs ;; 5) edit_lang "src" ;; 6) edit_lang "tgt" ;;
        7) edit_prompt ;; 8) edit_temperature ;; 9) edit_scene_threshold ;;
        10) edit_retry; edit_backoff ;;
        11) edit_sort ;;
        12) edit_currency ;;
        13) check_and_maybe_save_preset; run_scheduler_tmux; break ;;
        14) clear; exit 0 ;;
    esac
done
