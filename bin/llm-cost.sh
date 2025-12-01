#!/usr/bin/env bash
# KH LLM TransQueue - Cost Library (English)
# Used by single_trans.sh / llm-scheduler.sh

: "${BASE_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

LLM_COST_PRICE_CONF="${LLM_COST_PRICE_CONF:-$BASE_DIR/conf/openai_price.conf}"
LLM_COST_FX_CONF="${LLM_COST_FX_CONF:-$BASE_DIR/conf/llm-cost-fx.conf}"

_llm_cost_price_loaded=0
_llm_cost_fx_loaded=0

# Load Price Config
llm_cost__load_price() {
  if [[ $_llm_cost_price_loaded -eq 1 ]]; then return 0; fi
  if [[ -f "$LLM_COST_PRICE_CONF" ]]; then
    . "$LLM_COST_PRICE_CONF"
  else
    echo "[WARN] Price config not found: $LLM_COST_PRICE_CONF (Cost will be 0)" >&2
  fi
  _llm_cost_price_loaded=1
}

# Load FX Config
llm_cost__load_fx() {
  if [[ $_llm_cost_fx_loaded -eq 1 ]]; then return 0; fi
  if [[ -f "$LLM_COST_FX_CONF" ]]; then
    . "$LLM_COST_FX_CONF"
  else
    # Defaults
    FX_DEFAULT_CURRENCY="${FX_DEFAULT_CURRENCY:-KRW}"
    FX_USD_KRW="${FX_USD_KRW:-1450}"
    echo "[WARN] FX config not found: $LLM_COST_FX_CONF (Using defaults)" >&2
  fi
  _llm_cost_fx_loaded=1
}

# Init (Placeholder)
llm_cost_init() { :; }

# Normalize Model Name Key (gpt-4.1-mini -> GPT_4_1_MINI)
llm_cost__model_key() {
  local model="$1"
  model="${model//./_}"
  model="${model//-/_}"
  printf '%s\n' "${model^^}"
}

# Calculate USD Cost
llm_cost_calc_usd() {
  local model="$1" billing="$2" pt="$3" ct="$4"
  llm_cost__load_price
  
  local key="$(llm_cost__model_key "$model")"
  local bill="${billing^^}"
  
  local in_var="PRICE_${key}_${bill}_INPUT_USD"
  local out_var="PRICE_${key}_${bill}_OUTPUT_USD"
  
  local pin="${!in_var:-0}"
  local pout="${!out_var:-0}"
  
  # Cost = (Prompt * Pin + Completion * Pout) / 1000
  awk -v pt="$pt" -v ot="$ct" -v pin="$pin" -v pout="$pout" \
      'BEGIN{printf "%.6f", (pt*pin + ot*pout)/1000.0}'
}

# Convert USD to Local Currency
llm_cost_convert_usd() {
  local usd="$1"
  local currency="${2:-KRW}"
  
  if [[ -z "$usd" ]]; then echo "0"; return; fi
  if [[ "$currency" == "USD" ]]; then echo "$usd"; return; fi
  
  llm_cost__load_fx
  
  local rate=""
  # Read directly from FX conf
  if [[ -f "$LLM_COST_FX_CONF" ]]; then
    rate=$(awk -v c="$currency" '$1==c {print $2; exit}' "$LLM_COST_FX_CONF")
  fi
  
  rate="${rate:-1}" # Default 1.0
  
  # Return raw value (formatting is done in scheduler)
  awk -v u="$usd" -v r="$rate" 'BEGIN{printf "%.6f", u*r}'
}
