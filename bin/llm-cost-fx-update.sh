#!/usr/bin/env bash
set -euo pipefail

line() { printf '\n==================== %s ====================\n\n' "$1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONF_DIR="$BASE_DIR/config"
CONF_FILE="$CONF_DIR/llm-cost-fx.conf"
JSON_FILE="$CONF_DIR/llm-cost-fx.json.tmp"

mkdir -p "$CONF_DIR"

BACKUP="${CONF_FILE}.bak_$(date +%Y%m%d_%H%M%S)"

line "BACKUP"
if [[ -f "$CONF_FILE" ]]; then
  cp "$CONF_FILE" "$BACKUP"
  echo "[OK] Backup created: $BACKUP"
else
  echo "[INFO] No existing llm-cost-fx.conf, nothing to backup."
fi

line "FETCH RATES (from open.er-api.com, base=USD)"

API_URL="https://open.er-api.com/v6/latest/USD"

if ! command -v curl >/dev/null 2>&1; then
  echo "[ERROR] curl not found. Please install curl." >&2
  exit 1
fi

if ! curl -fsS "$API_URL" -o "$JSON_FILE"; then
  echo "[ERROR] Failed to fetch FX rates from $API_URL" >&2
  exit 1
fi

python3 "$BASE_DIR/bin/llm-cost-fx-build.py" "$JSON_FILE" "$CONF_FILE"

rm -f "$JSON_FILE"

line "DONE"
