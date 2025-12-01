#!/usr/bin/env bash
# KH LLM TransQueue - Engine Installation Script (v1.1 - Path Fixed)

# --- Configuration & Path Setup ---
# # English # Set strict mode: exit immediately if a command exits with a non-zero status.
# # 한글 # 엄격 모드 설정: 명령어가 0이 아닌 상태로 종료되면 즉시 스크립트 종료.
set -euo pipefail

# # English # Determine the script's directory.
# # 한글 # 스크립트의 디렉토리를 결정합니다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# # English # FIX: Set BASE_DIR to the project root (one level up from bin/).
# # 한글 # 수정: BASE_DIR를 프로젝트 루트(bin/에서 한 단계 위)로 설정합니다.
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# # English # Define core directories and files based on the corrected BASE_DIR.
# # 한글 # 수정된 BASE_DIR를 기준으로 핵심 디렉토리와 파일을 정의합니다.
ENGINE_DIR="$BASE_DIR/engine"
VENV_NAME="envsubtrans"
VENV_PATH="$ENGINE_DIR/$VENV_NAME"
PYTHON_BIN="$VENV_PATH/bin/python"
REQUIREMENTS_FILE="$BASE_DIR/requirements.txt"
SCRIPTS_DIR="$ENGINE_DIR/scripts"

# # English # Define the source/destination for the core translation script.
# # 한글 # 핵심 번역 스크립트의 원본/대상 경로를 정의합니다.
# # English # NOTE: Assuming 'gpt-subtrans.py' is bundled in a 'source' directory for portability.
# # 한글 # 참고: 'gpt-subtrans.py'는 포터빌리티를 위해 'source' 디렉토리에 번들되어 있다고 가정합니다.
GPT_SUBTRANS_SRC="$BASE_DIR/source/gpt-subtrans.py"
GPT_SUBTRANS_DEST="$SCRIPTS_DIR/gpt-subtrans.py"


# --- Helper Functions ---

# # English # Print a section separator.
# # 한글 # 구분을 위한 헤더를 출력합니다.
line() { printf '\n==================== %s ====================\n' "$1"; }

# # English # Check for required tools (Python 3).
# # 한글 # 필수 도구(Python 3)의 존재 여부를 확인합니다.
check_tools() {
    line "1. Checking Required Tools (Python & Venv)"
    if ! command -v python3 >/dev/null 2>&1; then
        echo "[ERROR] python3 is required but not found. Please install it." >&2
        exit 10 # Custom Error Code for Missing Tools
    fi
    echo "[OK] python3 found at $(command -v python3)"
}


# --- Main Installation Steps ---

# 1. Check tools
check_tools

# 2. Create Directory Structure
line "2. Setting Up Directory Structure (Project Root: $BASE_DIR)"
mkdir -p "$ENGINE_DIR" "$SCRIPTS_DIR" "$BASE_DIR/source" "$BASE_DIR/conf"
echo "[OK] Created core directories (engine, scripts, source, conf)"


# 3. Create Python Virtual Environment (Venv)
line "3. Creating Python Virtual Environment ($VENV_NAME)"
if [[ -d "$VENV_PATH" ]]; then
    echo "[INFO] Existing virtual environment found. Removing old Venv..."
    rm -rf "$VENV_PATH"
fi

# # English # Create the virtual environment using the standard module.
# # 한글 # 표준 모듈을 사용하여 가상 환경을 생성합니다.
if python3 -m venv "$VENV_PATH"; then
    echo "[OK] Virtual environment created at $VENV_PATH"
else
    echo "[ERROR] Failed to create virtual environment." >&2
    exit 20 # Custom Error Code for Venv Failure
fi


# 4. Install Dependencies
line "4. Installing Python Dependencies"
if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
    echo "[ERROR] requirements.txt not found at $REQUIREMENTS_FILE." >&2
    echo "       Please create it with required packages (e.g., openai, pysrt)." >&2
    exit 30 # Custom Error Code for Missing File
fi

# # English # Use the python executable within the new virtual environment to install packages.
# # 한글 # 새로 생성된 가상 환경 내의 python 실행 파일을 사용하여 패키지를 설치합니다.
if "$PYTHON_BIN" -m pip install --upgrade pip; then
    echo "[OK] Pip upgraded."
else
    echo "[WARN] Failed to upgrade pip. Continuing with installation."
fi

if "$PYTHON_BIN" -m pip install -r "$REQUIREMENTS_FILE"; then
    echo "[OK] All dependencies from $REQUIREMENTS_FILE installed successfully."
else
    echo "[ERROR] Failed to install Python dependencies." >&2
    echo "       Check the contents of requirements.txt." >&2
    exit 31 # Custom Error Code for Dependency Install Failure
fi


# 5. Place Core Translation Script
line "5. Placing Core Translation Script (gpt-subtrans.py)"
# # English # We assume the user has the Python core logic. If not, this step will fail.
# # 한글 # 사용자가 Python 핵심 로직을 가지고 있다고 가정합니다. 그렇지 않다면 이 단계는 실패할 것입니다.
if [[ -f "$GPT_SUBTRANS_SRC" ]]; then
    cp "$GPT_SUBTRANS_SRC" "$GPT_SUBTRANS_DEST"
    chmod +x "$GPT_SUBTRANS_DEST"
    echo "[OK] Copied and placed $GPT_SUBTRANS_DEST"
else
    echo "[ERROR] Core script source not found: $GPT_SUBTRANS_SRC" >&2
    echo "       You need to place the Python translation script 'gpt-subtrans.py' in the 'source/' directory." >&2
    exit 40
fi


# --- Finalization ---

line "6. Installation Complete"
echo "[SUCCESS] KH-LLM-TransQueue Engine is ready."
echo "Python Path : $PYTHON_BIN"
echo "Script Path : $GPT_SUBTRANS_DEST"
echo "Run the scheduler from the bin directory: $BASE_DIR/bin/llm-scheduler.sh"

exit 0
