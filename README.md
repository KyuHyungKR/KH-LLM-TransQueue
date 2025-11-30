👑 KH LLM TransQueue (v1.2: Final Stability)🌎 English VersionKH-LLM-TransQueue is a lightweight subtitle parallel processing system that combines the concurrency of Bash scripting with the LLM integration capabilities of Python. All elements are designed with 'Modularity' and 'Portability' as the highest priorities.🌟 Project Overview & ArchitectureThis project uses a Master-Worker architecture to efficiently process multiple subtitle files and track cost and token usage in real-time.Core Components|| Component | Role | Design Feature || bin/llm-scheduler.sh | Master Orchestrator | Uses Bash's wait -n to manage parallel workers in the background and uses set +e handling to prevent the entire queue from failing if a worker fails. || bin/single_trans.sh | Atomic Worker | The minimum unit of file processing. It ensures that only the failing file is marked as failed, protecting the rest of the queue. || source/gpt-subtrans.py | LLM Engine Core | Python logic that calls the OpenAI API, handles subtitle batching, and outputs token usage to stdout for cost tracking. || engine/envsubtrans | Runtime Environment | An isolated Python Virtual Environment (venv) automatically created by llm-install-engine.sh. Eliminates OS environment dependencies. || conf/ | Financial DB & API | Separates sensitive financial data (API keys, model pricing, exchange rates) for enhanced security. |🛠️ Installation & Environment SetupThe project can be deployed anywhere with Python 3 and Bash installed.1. Clone Project and Verify Structuregit clone [YOUR_REPO_URL] KH-LLM-TransQueue
cd KH-LLM-TransQueue

# Required directory structure
# Place SRT files to be translated in srt/input
mkdir -p srt/input srt/output srt/success srt/failed


2. Engine Installation (Dependencies & Venv)Run llm-install-engine.sh from the project root to build the Python virtual environment and install required libraries (openai, pysrt).# Ensure the script has execution permission
chmod +x bin/llm-install-engine.sh

# Start environment build
./bin/llm-install-engine.sh


3. API Key Configuration (Key Management)The API key is stored securely in conf/openai_api.key and managed via llm-api-key-manager.sh.# Run the interactive key management tool
./bin/llm-api-key-manager.sh
# Select Option 2 to input and save your API Key (sk-...).


🚀 Usage1. Prepare Prompt and Configuration FilesSample prompt files (*.txt) and config files (*.txt) are provided by default in the prompt/ directory.Note: Configuration files are typically created and updated when settings are specified and saved through a separate TUI/CLI menu. You can modify the file manually, or use the TUI to set and save the configuration.2. Run the SchedulerPlace your subtitle files in srt/input and run the scheduler.# Basic execution
./bin/llm-scheduler.sh

# Example execution with options
./bin/llm-scheduler.sh \
    --prompt movie_drama_prompt.txt \
    --config gpt4_high_temp_config.txt \
    --lang ko \
    -j 5


3. Check ResultsTranslated Subtitles: srt/output/Success/Fail Files: srt/success/ and srt/failed/Final Summary and Cost Report: log/summary_*.tsv💰 Cost and Financial ManagementVerify the configuration files in the conf/ folder for accurate cost tracking.| Filename | Purpose | | conf/openai_price.conf | Defines input/output token pricing (USD) per model. | | conf/llm-cost-fx.conf | Defines exchange rates (KRW, JPY, etc.) relative to USD. |🇰🇷 한글 버전KH-LLM-TransQueue는 Bash 스크립트의 병렬 처리 능력과 Python의 LLM 연동 능력을 결합한 경량 자막 병렬 번역 시스템입니다. 시스템의 모든 요소는 **'모듈성'**과 **'포터빌리티(Portable)'**를 최우선 가치로 설계되었습니다.🌟 프로젝트 개요 및 아키텍처이 프로젝트는 마스터-워커(Master-Worker) 구조를 사용하여 다수의 자막 파일을 효율적으로 처리하고, 비용 및 토큰 사용량을 실시간으로 추적합니다.핵심 요소 (Core Components)| 요소 (Component) | 역할 (Role) | 특징 (Design Feature) || bin/llm-scheduler.sh | 마스터 오케스트레이터 | Bash의 wait -n 기능을 사용하여 백그라운드에서 병렬 워커를 관리하고, set +e 처리를 통해 워커 실패 시 전체 큐를 보호합니다. || bin/single_trans.sh | 원자적 워커 | 파일당 처리의 최소 단위입니다. 비용 로깅이 실패해도 해당 파일만 실패 처리하고 큐를 보호합니다. || source/gpt-subtrans.py | LLM 엔진 코어 | Python 환경에서 OpenAI API를 호출하여 자막을 배치 처리하고 토큰 사용량을 stdout으로 출력합니다. || engine/envsubtrans | 런타임 환경 | llm-install-engine.sh로 자동 생성되는 격리된 Python 가상 환경(venv)입니다. OS 환경 종속성을 제거합니다. || conf/ | 금융 정보 DB & API | API 키, 모델별 가격, 환율 등 민감한 재정 관련 데이터를 분리 보관하여 보안을 강화합니다. |🛠️ 설치 및 환경 구축 (Installation)이 프로젝트는 Python 3와 Bash가 설치된 환경이면 어디든 배포 가능합니다.1. 프로젝트 클론 및 구조 확인git clone [YOUR_REPO_URL] KH-LLM-TransQueue
cd KH-LLM-TransQueue

# 필수 디렉토리 구조
# srt/input에 번역할 SRT 파일을 넣어주세요.
mkdir -p srt/input srt/output srt/success srt/failed


2. 엔진 설치 (Dependencies & Venv)프로젝트 루트에서 llm-install-engine.sh를 실행하여 Python 가상 환경을 구축하고 필요한 라이브러리(openai, pysrt)를 설치합니다.# llm-install-engine.sh 파일에 실행 권한이 있는지 확인하세요.
chmod +x bin/llm-install-engine.sh

# 환경 구축 시작
./bin/llm-install-engine.sh


3. API 키 설정 (Key Management)API 키는 conf/openai_api.key 파일에 저장되며, llm-api-key-manager.sh를 통해 안전하게 관리됩니다.# 대화형 키 관리 도구 실행
./bin/llm-api-key-manager.sh
# 옵션 2를 선택하여 API 키(sk-...)를 입력하고 저장하세요.


🚀 사용법 (Usage)1. 프롬프트 및 설정 파일 준비prompt/ 디렉토리에 번역 스타일을 정의한 샘플 프롬프트 파일(*.txt)과 컨피그 파일(*.txt)이 기본으로 제공됩니다.참고: 컨피그 파일은 보통 별도의 TUI/CLI 메뉴에서 설정을 지정하고 저장할 때 생성 및 업데이트됩니다. 수동으로 파일을 직접 수정하거나, TUI에서 설정 후 저장하여 사용하십시오.2. 스케줄러 실행srt/input에 자막 파일을 넣고 스케줄러를 실행합니다.# 가장 기본적인 실행
./bin/llm-scheduler.sh

# 옵션을 사용한 실행 예시
./bin/llm-scheduler.sh \
    --prompt movie_drama_prompt.txt \
    --config gpt4_high_temp_config.txt \
    --lang ko \
    -j 5


3. 결과 확인결과 자막: srt/output/성공/실패 파일: srt/success/ 및 srt/failed/최종 요약 및 비용 보고서: log/summary_*.tsv💰 비용 및 금융 관리 설정비용 추적의 정확성을 위해 conf/ 폴더의 설정 파일을 확인하세요.| 파일명 | 용도 || conf/openai_price.conf | 모델별 인풋/아웃풋 토큰당 가격(USD) 정의 || conf/llm-cost-fx.conf | USD 기준 통화 환율 정의 (KRW, JPY 등) |🙏 Acknowledgements (감사의 글)🇬🇧 EnglishThis project includes and extends the LLM-Subtrans engine by machinewrapped (MIT License). The original engine and its components are licensed under MIT, and the license terms are preserved in: engine/LICENSE.llm-subtrans. KH-LLM-TransQueue adds: A full Bash-based scheduling system, Multi-queue translation orchestration, Currency-aware cost tracking, and TUI presets.🇰🇷 한국어이 프로젝트에는 machinewrapped 개발자가 MIT 라이선스로 배포한 LLM-Subtrans 엔진이 포함되어 있으며, 해당 엔진을 기반으로 KH-LLM-TransQueue가 확장되었습니다.📄 License (라이선스)KH-LLM-TransQueue is distributed under the MIT License. See the LICENSE file in the repository root for full license text.KH-LLM-TransQueue는 MIT 라이선스로 배포되며, 자세한 내용은 저장소 루트의 LICENSE 파일을 참고해 주세요.본 프로젝트는 LLM-Subtrans 및 그 종속 라이브러리들의 라이선스를 engine/LICENSE.llm-subtrans 파일에 명시된 형태 그대로 존중하고 준수합니다.
