# gpt-subtrans.py: KH LLM TransQueue Core Translation Engine
# Core Python logic for reading SRT, calling OpenAI API, and logging token usage.

import argparse
import os
import sys
import time
import re
from pathlib import Path
from typing import List

try:
    import pysrt
    from openai import OpenAI, APIError
except ImportError:
    # This should be caught by the Bash installer, but serves as a final guard.
    print("[FATAL] Required libraries (openai, pysrt) are not installed.")
    sys.exit(31) # Exit code for missing script dependency

# --- Configuration ---
# API Key is expected to be set in the environment variable by single_trans.sh
client = OpenAI()

# --- Functions for Subtitle Processing ---

def read_instruction_file(file_path: Path) -> str:
    # # English # Reads the prompt instruction from the specified file.
    # # 한글 # 지정된 파일에서 프롬프트 인스트럭션을 읽습니다.
    if not file_path.exists():
        raise FileNotFoundError(f"Instruction file not found: {file_path}")
    with open(file_path, 'r', encoding='utf-8') as f:
        return f.read().strip()

def format_subtitle_batch(batch: List[pysrt.Subtitle]) -> str:
    # # English # Formats a list of subtitles into a clean string for the LLM.
    # # 한글 # LLM이 처리하기 쉽도록 자막 목록을 깔끔한 문자열로 포맷합니다.
    output = []
    for sub in batch:
        # Use a consistent, simple format: 'index | start_time --> end_time | text'
        output.append(
            f"{sub.index} | {sub.start} --> {sub.end} | {sub.text.replace('\n', ' ')}"
        )
    return "\n".join(output)

def create_translation_prompt(instruction: str, batch_text: str, target_lang: str) -> str:
    # # English # Combines the system instruction and the subtitle data into a final prompt.
    # # 한글 # 시스템 인스트럭션과 자막 데이터를 결합하여 최종 프롬프트를 만듭니다.
    return (
        f"{instruction}\n\n"
        f"Target Language: {target_lang}\n\n"
        f"Please translate the following subtitle block, maintaining the index, timecodes, "
        f"and line breaks exactly as they are. Only modify the text content.\n\n"
        f"--- SUBTITLE BATCH ---\n"
        f"{batch_text}\n"
        f"--- END OF BATCH ---"
    )

def parse_translated_batch(batch: List[pysrt.Subtitle], translated_text: str) -> List[pysrt.Subtitle]:
    # # English # Parses the LLM's response and updates the subtitle objects.
    # # 한글 # LLM의 응답을 파싱하고 자막 객체의 텍스트를 업데이트합니다.
    updated_subs = []
    for sub in batch:
        # # English # Use the index to find the corresponding translated line in the response.
        # # 한글 # 인덱스를 사용하여 응답에서 해당 번역 라인을 찾습니다.
        # Pattern: Starts with the index (e.g., '123 |'), followed by the timecode and then the text.
        pattern = re.compile(rf"^{sub.index}\s+\|\s+.*?\|\s+(.*)", re.MULTILINE)
        match = pattern.search(translated_text)

        new_text = sub.text # Default to original text if parsing fails

        if match:
            # Clean up the extracted text: remove leading/trailing spaces, replace '\n' from extraction.
            new_text = match.group(1).strip().replace("\\n", "\n")
        
        # Create a new subtitle object with the original properties and the new text
        new_sub = pysrt.Subtitle(
            index=sub.index,
            start=sub.start,
            end=sub.end,
            text=new_text
        )
        updated_subs.append(new_sub)
        
    return updated_subs

def get_sub_batches(subs: pysrt.SubRipFile, max_batch_size: int, scene_threshold: float) -> List[List[pysrt.Subtitle]]:
    # # English # Splits the full subtitle list into smaller batches.
    # # 한글 # 전체 자막 목록을 작은 배치로 분할합니다.
    
    batches = []
    current_batch = []
    
    for i, sub in enumerate(subs):
        # # English # Scene Threshold Logic (currently disabled by setting threshold to 0 in scheduler)
        # # 한글 # Scene Threshold 로직 (현재 스케줄러에서 0으로 설정되어 비활성화)
        if scene_threshold > 0 and current_batch:
            # # English # Check if the gap between the current sub and the last one in the batch exceeds the threshold.
            # # 한글 # 현재 자막과 배치 마지막 자막 사이의 간격이 임계값을 초과하는지 확인합니다.
            last_sub = subs[i - 1]
            gap = sub.start.ordinal - last_sub.end.ordinal
            if gap / 1000 > scene_threshold: # Convert milliseconds to seconds
                batches.append(current_batch)
                current_batch = []
        
        current_batch.append(sub)

        # # English # Batch Size Limit
        # # 한글 # 배치 크기 제한
        if len(current_batch) >= max_batch_size:
            batches.append(current_batch)
            current_batch = []
            
    if current_batch:
        batches.append(current_batch)
        
    return batches

# --- Main Translation Logic ---

def translate_file(input_path: Path, output_path: Path, prompt_path: Path, 
                   model_name: str, target_lang: str, max_batch_size: int, 
                   scene_threshold: float, temperature: float, max_retries: int = 3, backoff_sec: int = 10):
    
    # # English # 1. Initial setup and file checks.
    # # 한글 # 1. 초기 설정 및 파일 검사.
    instruction = read_instruction_file(prompt_path)
    
    # Load all subtitles
    subs = pysrt.open(input_path, encoding='utf-8')
    if not subs:
        print(f"[WARN] Input file {input_path.name} is empty.")
        return
    
    all_translated_subs = []
    total_prompt_tokens = 0
    total_completion_tokens = 0

    # Split into batches
    batches = get_sub_batches(subs, max_batch_size, scene_threshold)
    print(f"[INFO] Total subtitles: {len(subs)}. Split into {len(batches)} batches.")

    # # English # 2. Process each batch.
    # # 한글 # 2. 각 배치를 처리합니다.
    for i, batch in enumerate(batches):
        batch_text = format_subtitle_batch(batch)
        system_prompt = instruction
        user_prompt = create_translation_prompt(system_prompt, batch_text, target_lang)
        
        success = False
        for attempt in range(max_retries):
            try:
                # API Call
                response = client.chat.completions.create(
                    model=model_name,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt}
                    ],
                    temperature=temperature,
                )
                
                translated_text = response.choices[0].message.content
                
                # Log token usage for single_trans.sh to parse
                usage = response.usage
                print(f"Token usage (Batch {i+1}/{len(batches)}): prompt={usage.prompt_tokens}, completion={usage.completion_tokens}")
                total_prompt_tokens += usage.prompt_tokens
                total_completion_tokens += usage.completion_tokens
                
                # Parse and store
                translated_batch = parse_translated_batch(batch, translated_text)
                all_translated_subs.extend(translated_batch)
                
                success = True
                break
                
            except APIError as e:
                # # English # Handle API specific errors (e.g., authentication, rate limit)
                # # 한글 # API 특정 오류(인증, 속도 제한 등) 처리
                error_message = str(e)
                if "API key" in error_message or "authentication" in error_message:
                    print(f"[FATAL] OpenAI API Key Error: {error_message}")
                    sys.exit(40) # Custom error code for API Key Missing (as per scheduler)
                elif "Rate limit" in error_message or "quota" in error_message:
                    print(f"[WARN] Rate limit hit. Retrying in {backoff_sec}s (Attempt {attempt + 1}/{max_retries})...")
                    time.sleep(backoff_sec * (attempt + 1)) # Exponential backoff simulation
                    continue
                else:
                    print(f"[ERROR] API Error on batch {i+1}: {error_message}")
                    sys.exit(42) # Custom error code for General API Failure
            
            except Exception as e:
                print(f"[FATAL] Unexpected Error on batch {i+1}: {e}")
                sys.exit(32) # Custom error code for General Engine Failure

        if not success:
            print(f"[FATAL] Failed to translate batch {i+1} after {max_retries} attempts.")
            sys.exit(33) # Custom error code for Persistent Batch Failure
            
    # # English # 3. Save the final translated file.
    # # 한글 # 3. 최종 번역된 파일을 저장합니다.
    output_subs = pysrt.SubRipFile(items=all_translated_subs)
    output_subs.save(output_path, encoding='utf-8')

    # # English # Final summary log (used by single_trans.sh)
    # # 한글 # 최종 요약 로그 (single_trans.sh에서 사용)
    print(f"Total tokens logged: prompt={total_prompt_tokens}, completion={total_completion_tokens}")
    
# --- Argument Parsing and Entry Point ---

def main():
    parser = argparse.ArgumentParser(description="KH LLM Subtitle Translator Core Engine")
    parser.add_argument("input_file", type=Path, help="Path to the input SRT file.")
    parser.add_argument("-m", "--model", default="gpt-4.1-mini", help="LLM model name.")
    parser.add_argument("-l", "--lang", required=True, help="Target language code (e.g., ko, en).")
    parser.add_argument("-o", "--outputfile", type=Path, required=True, help="Path to the output SRT file.")
    parser.add_argument("--instructionfile", type=Path, required=True, help="Path to the prompt instruction file.")
    parser.add_argument("--maxbatchsize", type=int, default=50, help="Max subtitles per API call.")
    parser.add_argument("--scenethreshold", type=float, default=0.0, help="Time gap (seconds) to force a batch split.")
    parser.add_argument("--temperature", type=float, default=0.3, help="API temperature/creativity.")
    
    args = parser.parse_args()

    # Check existence of input and instruction files early
    if not args.input_file.exists():
        print(f"[FATAL] Input file not found: {args.input_file}")
        sys.exit(31)
    if not args.instructionfile.exists():
        print(f"[FATAL] Instruction file not found: {args.instructionfile}")
        sys.exit(31)

    try:
        translate_file(
            input_path=args.input_file,
            output_path=args.outputfile,
            prompt_path=args.instructionfile,
            model_name=args.model,
            target_lang=args.lang,
            max_batch_size=args.maxbatchsize,
            scene_threshold=args.scenethreshold,
            temperature=args.temperature
        )
    except FileNotFoundError as e:
        print(f"[FATAL] File not found during execution: {e}")
        sys.exit(31) # File not found (e.g., instruction file disappeared)
    except Exception as e:
        # Catch unexpected errors not handled inside translate_file
        print(f"[FATAL] Unhandled internal error: {e}")
        sys.exit(32)

if __name__ == "__main__":
    main()
