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
    print("[FATAL] Required libraries (openai, pysrt) are not installed.")
    sys.exit(31) 

client = OpenAI()

def read_instruction_file(file_path: Path) -> str:
    if not file_path.exists():
        raise FileNotFoundError(f"Instruction file not found: {file_path}")
    with open(file_path, 'r', encoding='utf-8') as f:
        return f.read().strip()

def format_subtitle_batch(batch: List[pysrt.Subtitle]) -> str:
    output = []
    for sub in batch:
        output.append(
            f"{sub.index} | {sub.start} --> {sub.end} | {sub.text.replace('\n', ' ')}"
        )
    return "\n".join(output)

def create_translation_prompt(instruction: str, batch_text: str, target_lang: str) -> str:
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
    updated_subs = []
    for sub in batch:
        pattern = re.compile(rf"^{sub.index}\s+\|\s+.*?\|\s+(.*)", re.MULTILINE)
        match = pattern.search(translated_text)

        new_text = sub.text 

        if match:
            new_text = match.group(1).strip().replace("\\n", "\n")
        
        new_sub = pysrt.Subtitle(
            index=sub.index,
            start=sub.start,
            end=sub.end,
            text=new_text
        )
        updated_subs.append(new_sub)
        
    return updated_subs

def get_sub_batches(subs: pysrt.SubRipFile, max_batch_size: int, scene_threshold: float) -> List[List[pysrt.Subtitle]]:
    batches = []
    current_batch = []
    
    for i, sub in enumerate(subs):
        if scene_threshold > 0 and current_batch:
            last_sub = subs[i - 1]
            gap = sub.start.ordinal - last_sub.end.ordinal
            if gap / 1000 > scene_threshold: 
                batches.append(current_batch)
                current_batch = []
        
        current_batch.append(sub)

        if len(current_batch) >= max_batch_size:
            batches.append(current_batch)
            current_batch = []
            
    if current_batch:
        batches.append(current_batch)
        
    return batches

def translate_file(input_path: Path, output_path: Path, prompt_path: Path, 
                   model_name: str, target_lang: str, max_batch_size: int, 
                   scene_threshold: float, temperature: float, max_retries: int = 3, backoff_sec: int = 10):
    
    instruction = read_instruction_file(prompt_path)
    
    subs = pysrt.open(input_path, encoding='utf-8')
    if not subs:
        print(f"[WARN] Input file {input_path.name} is empty.")
        return
    
    all_translated_subs = []
    total_prompt_tokens = 0
    total_completion_tokens = 0

    batches = get_sub_batches(subs, max_batch_size, scene_threshold)
    print(f"[INFO] Total subtitles: {len(subs)}. Split into {len(batches)} batches.")

    for i, batch in enumerate(batches):
        batch_text = format_subtitle_batch(batch)
        system_prompt = instruction
        user_prompt = create_translation_prompt(system_prompt, batch_text, target_lang)
        
        success = False
        for attempt in range(max_retries):
            try:
                response = client.chat.completions.create(
                    model=model_name,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt}
                    ],
                    temperature=temperature,
                )
                
                translated_text = response.choices[0].message.content
                
                usage = response.usage
                print(f"Token usage (Batch {i+1}/{len(batches)}): prompt={usage.prompt_tokens}, completion={usage.completion_tokens}")
                total_prompt_tokens += usage.prompt_tokens
                total_completion_tokens += usage.completion_tokens
                
                translated_batch = parse_translated_batch(batch, translated_text)
                all_translated_subs.extend(translated_batch)
                
                success = True
                break
                
            except APIError as e:
                error_message = str(e)
                if "API key" in error_message or "authentication" in error_message:
                    print(f"[FATAL] OpenAI API Key Error: {error_message}")
                    sys.exit(40) 
                elif "Rate limit" in error_message or "quota" in error_message:
                    print(f"[WARN] Rate limit hit. Retrying in {backoff_sec}s (Attempt {attempt + 1}/{max_retries})...")
                    time.sleep(backoff_sec * (attempt + 1)) 
                    continue
                else:
                    print(f"[ERROR] API Error on batch {i+1}: {error_message}")
                    sys.exit(42) 
            
            except Exception as e:
                print(f"[FATAL] Unexpected Error on batch {i+1}: {e}")
                sys.exit(32) 

        if not success:
            print(f"[FATAL] Failed to translate batch {i+1} after {max_retries} attempts.")
            sys.exit(33) 
            
    output_subs = pysrt.SubRipFile(items=all_translated_subs)
    output_subs.save(output_path, encoding='utf-8')

    print(f"Total tokens logged: prompt={total_prompt_tokens}, completion={total_completion_tokens}")
    
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
        sys.exit(31) 
    except Exception as e:
        print(f"[FATAL] Unhandled internal error: {e}")
        sys.exit(32)

if __name__ == "__main__":
    main()
