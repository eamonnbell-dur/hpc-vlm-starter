#!/usr/bin/env python3
"""
Batch image extraction. Loops through images in a directory (or a file list)
and saves one JSON per image. Features skip-on-exists for safe resubmission
and a threaded executor for high concurrency.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import concurrent.futures
from pathlib import Path

from extract_one import (
    b64_data_url, call_vllm_chat, call_with_retries,
    extract_first_json, load_prompt,
)


def process_image(image_path: str, endpoint: str, model: str, mode: str,
                  prompt: str, prompt_b_template: str,
                  max_tokens: int, temperature: float, timeout: int) -> dict:

    image_url = b64_data_url(image_path)

    if mode == "one_pass":
        def do():
            resp = call_vllm_chat(endpoint, model, prompt,
                                  image_url, max_tokens, temperature, timeout)
            txt = resp["choices"][0]["message"]["content"]
            return extract_first_json(txt)

        parsed = call_with_retries(do, tries=3)
        result = parsed

    else:  # two_pass
        def do_a():
            resp_a = call_vllm_chat(endpoint, model, prompt,
                                    image_url, max_tokens, temperature, timeout)
            txt_a = resp_a["choices"][0]["message"]["content"]
            a = extract_first_json(txt_a)
            raw_text = a.get("raw_text", "")
            if not raw_text:
                raise ValueError("Empty raw_text from transcription step.")
            return raw_text

        raw_text = call_with_retries(do_a, tries=3)

        prompt_b = prompt_b_template.replace("{raw_text}", raw_text)

        def do_b():
            resp_b = call_vllm_chat(endpoint, model, prompt_b,
                                    None, max_tokens, temperature, timeout)
            txt_b = resp_b["choices"][0]["message"]["content"]
            return extract_first_json(txt_b)

        fields = call_with_retries(do_b, tries=3)
        result = {"raw_text": raw_text, "fields": fields}

    return {
        "source_file": os.path.abspath(image_path),
        "parsed": result,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-dir", required=False)
    ap.add_argument("--output-dir", required=True)
    ap.add_argument("--endpoint", default="http://127.0.0.1:8000/v1/chat/completions")
    ap.add_argument("--model", default="my-extractor")
    ap.add_argument("--mode", choices=["one_pass", "two_pass"], default="one_pass")
    ap.add_argument("--prompt-file", required=True, help="Path to extraction prompt")
    ap.add_argument("--prompt-file-pass-b", default=None, help="(two_pass) structuring prompt")
    ap.add_argument("--max-tokens", type=int, default=1024)
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--pattern", default="*.jpg")
    ap.add_argument("--failed-log", default=None)
    ap.add_argument("--workers", type=int, default=1)
    ap.add_argument("--file-list", default=None)
    ap.add_argument("--timeout", type=int, default=120)
    args = ap.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.failed_log is None:
        args.failed_log = str(output_dir / f"failed_cards_{args.model}.txt")

    # Load prompts
    prompt = load_prompt(args.prompt_file)
    prompt_b_template = ""
    if args.mode == "two_pass":
        if not args.prompt_file_pass_b:
            print("Error: --prompt-file-pass-b required for two_pass mode", file=sys.stderr)
            return 1
        prompt_b_template = load_prompt(args.prompt_file_pass_b)

    # Collect image paths
    if args.file_list:
        with open(args.file_list, "r") as f:
            image_paths = [line.split('\t')[0].strip() for line in f if line.strip()]
    else:
        if not args.input_dir:
            print("Error: Must provide either --input-dir or --file-list", file=sys.stderr)
            return 1
        image_paths = sorted(glob.glob(os.path.join(args.input_dir, args.pattern)))
        if not image_paths:
            image_paths = sorted(glob.glob(os.path.join(args.input_dir, args.pattern.upper())))

    if not image_paths:
        print("No images found to process.", file=sys.stderr)
        return 1

    print(f"Found {len(image_paths)} images to process using {args.workers} workers.")

    failed = []

    def process_and_save(image_path: str, index: int, total: int):
        stem = Path(image_path).stem
        out_path = output_dir / f"{stem}.json"

        # Skip-on-exists: safe to resubmit without duplication
        if out_path.exists():
            print(f"[{index}/{total}] Skipping {stem} (already exists)")
            return None

        print(f"[{index}/{total}] Processing {stem} ...", end=" ", flush=True)
        try:
            result = process_image(
                image_path=image_path,
                endpoint=args.endpoint,
                model=args.model,
                mode=args.mode,
                prompt=prompt,
                prompt_b_template=prompt_b_template,
                max_tokens=args.max_tokens,
                temperature=args.temperature,
                timeout=args.timeout,
            )
            with open(out_path, "w", encoding="utf-8") as f:
                json.dump(result, f, indent=2, ensure_ascii=False)
            print("OK")
            return None
        except Exception as e:
            print(f"FAILED: {e}")
            return f"{image_path}\t{e}"

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(process_and_save, path, i + 1, len(image_paths)): path
            for i, path in enumerate(image_paths)
        }
        for future in concurrent.futures.as_completed(futures):
            error_res = future.result()
            if error_res:
                failed.append(error_res)

    if failed:
        with open(args.failed_log, "w") as f:
            f.write("\n".join(failed) + "\n")
        print(f"\n{len(failed)} failed. See {args.failed_log}")

    print(f"\nDone. {len(image_paths) - len(failed)} cards processed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
