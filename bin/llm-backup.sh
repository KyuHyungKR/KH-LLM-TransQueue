#!/usr/bin/env bash
set -e

# KH LLM TransQueue - Backup Script (Portable)

# [FIXED] Dynamic Relative Path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_ROOT="$BASE_DIR/backup"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_NAME="KH-LLM-GoldenBackup_${TIMESTAMP}.tar.gz"
BACKUP_PATH="$BACKUP_ROOT/$BACKUP_NAME"

# 백업 폴더 생성
mkdir -p "$BACKUP_ROOT"

echo "========================================================"
echo "📦 KH LLM TransQueue System Backup"
echo "--------------------------------------------------------"
echo "Targets: bin/, conf/, prompt/"
echo "Save to: $BACKUP_PATH"

# 압축 실행 (bin, conf, prompt만 포함)
tar -czf "$BACKUP_PATH" \
    -C "$BASE_DIR" \
    bin conf prompt

echo "--------------------------------------------------------"
if [[ -f "$BACKUP_PATH" ]]; then
    echo "✅ Backup Successful!"
    echo "Size: $(du -h "$BACKUP_PATH" | cut -f1)"
    echo "File: $BACKUP_NAME"
else
    echo "❌ Backup Failed"
fi
echo "========================================================"
