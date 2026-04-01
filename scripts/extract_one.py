#!/usr/bin/env python3
"""
Single-image VLM extraction client.
Loads the extraction prompt from an external text file so the pipeline
is reusable across different document types and collections.
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
import sys
import time
from typing import Any, Dict, Optional


def b64_data_url(image_path: str) -> str:
    """Encode a local image as a base64 data URL for the OpenAI vision API."""
    mime, _ = mimetypes.guess_type(image_path)
    mime = mime or "image/jpeg"
    with open(image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    return f"data:{mime};base64,{b64}"


def extract_first_json(text: str) -> Any:
    """Pull the first JSON object or array from model output text."""
    text = text.strip()
    try:
        return json.loads(text)
    except Exception:
        pass
    m = re.search(r"(\{.*\}|\[.*\])", text, flags=re.DOTALL)
    if not m:
        raise ValueError("No JSON found in model output.")
    return json.loads(m.group(1))


def load_prompt(path: str) -> str:
    """Read a prompt from a text file."""
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip()


# ── Connection pooling for high-concurrency batch use ──
import requests

_SESSION = requests.Session()
_ADAPTER = requests.adapters.HTTPAdapter(pool_connections=32, pool_maxsize=32)
_SESSION.mount("http://", _ADAPTER)
_SESSION.mount("https://", _ADAPTER)


def post_chat(endpoint: str, payload: Dict[str, Any], timeout: int) -> Dict[str, Any]:
    r = _SESSION.post(endpoint, json=payload, timeout=timeout)
    r.raise_for_status()
    return r.json()


def call_vllm_chat(
    endpoint: str,
    model: str,
    prompt: str,
    image_url: Optional[str],
    max_tokens: int,
    temperature: float,
    timeout: int,
) -> Dict[str, Any]:
    content = [{"type": "text", "text": prompt}]
    if image_url is not None:
        content.append({"type": "image_url", "image_url": {"url": image_url}})

    payload: Dict[str, Any] = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    return post_chat(endpoint, payload, timeout=timeout)


def call_with_retries(fn, tries: int = 3, backoff: float = 1.5):
    last_err = None
    for i in range(tries):
        try:
            return fn()
        except Exception as e:
            last_err = e
            time.sleep(backoff ** i)
    raise last_err


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract structured data from a single image using a VLM.")
    ap.add_argument("--image", required=True, help="Path to image file")
    ap.add_argument("--endpoint", default="http://127.0.0.1:8000/v1/chat/completions")
    ap.add_argument("--model", default="my-extractor")
    ap.add_argument("--mode", choices=["one_pass", "two_pass"], default="one_pass")
    ap.add_argument("--prompt-file", required=True, help="Path to extraction prompt (.txt)")
    ap.add_argument("--prompt-file-pass-b", default=None, help="(two_pass only) Path to structuring prompt")
    ap.add_argument("--max-tokens", type=int, default=1024)
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--out", default=None, help="Output file path (default: stdout)")
    args = ap.parse_args()

    prompt = load_prompt(args.prompt_file)
    image_url = b64_data_url(args.image)

    if args.mode == "one_pass":
        def do():
            resp = call_vllm_chat(args.endpoint, args.model, prompt,
                                  image_url, args.max_tokens, args.temperature, args.timeout)
            txt = resp["choices"][0]["message"]["content"]
            return resp, extract_first_json(txt)

        resp, parsed = call_with_retries(do, tries=3)

    else:  # two_pass
        if not args.prompt_file_pass_b:
            print("Error: --prompt-file-pass-b required for two_pass mode", file=sys.stderr)
            return 1

        prompt_b_template = load_prompt(args.prompt_file_pass_b)

        # Pass A: transcription (vision)
        def do_a():
            resp_a = call_vllm_chat(args.endpoint, args.model, prompt,
                                    image_url, args.max_tokens, args.temperature, args.timeout)
            txt_a = resp_a["choices"][0]["message"]["content"]
            a = extract_first_json(txt_a)
            raw_text = a.get("raw_text", "")
            if not raw_text:
                raise ValueError("Empty raw_text from transcription step.")
            return resp_a, raw_text

        resp_a, raw_text = call_with_retries(do_a, tries=3)

        # Pass B: structured extraction (text-only)
        prompt_b = prompt_b_template.replace("{raw_text}", raw_text)

        def do_b():
            resp_b = call_vllm_chat(args.endpoint, args.model, prompt_b,
                                    None, args.max_tokens, args.temperature, args.timeout)
            txt_b = resp_b["choices"][0]["message"]["content"]
            return resp_b, extract_first_json(txt_b)

        resp_b, fields = call_with_retries(do_b, tries=3)
        resp = {"pass_a": resp_a, "pass_b": resp_b}
        parsed = {"raw_text": raw_text, "fields": fields}

    out_obj = {
        "source_file": os.path.abspath(args.image),
        "parsed": parsed,
    }

    out_str = json.dumps(out_obj, indent=2, ensure_ascii=False)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(out_str + "\n")
    else:
        print(out_str)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
