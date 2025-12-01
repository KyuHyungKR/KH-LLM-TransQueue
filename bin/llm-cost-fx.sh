#!/usr/bin/env bash
# llm-cost-fx.sh
# FX Helper: Reads config/llm-cost-fx.conf
# Output: "RATE LABEL" (RATE = units per 1 USD)

set -euo pipefail

llm_cost_get_fx() {
  local code="${1:-KRW}"
  local base_dir
  local conf
  local line
  local rate=""
  local label="$code"

  # Determine BASE_DIR
  if [[ -n "${BASE_DIR:-}" ]]; then
    base_dir="$BASE_DIR"
  else
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    base_dir="$(cd "$script_dir/.." && pwd)"
  fi

  conf="$base_dir/conf/llm-cost-fx.conf"

  if [[ -f "$conf" ]]; then
    # Col 1=Code, 2=Rate, 3...=Label
    line="$(awk -v c="$code" '$1 == c { print $2, $3; exit }' "$conf")"
    if [[ -n "$line" ]]; then
      rate="${line%% *}"
      label="${line#* }"
    fi
  fi

  # Default fallback: 1.0
  if [[ -z "$rate" ]]; then
    rate="1"
    label="$code"
  fi

  printf '%s %s\n' "$rate" "$label"
}
