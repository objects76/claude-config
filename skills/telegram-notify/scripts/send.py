"""Send a text message to a fixed Telegram chat via the Bot API.

Token is read from the `telegram4llm` environment variable.
Chat id is hardcoded below.

Requires `httpx` installed in the global Python environment:
    pip install httpx
"""

import argparse
import os
import socket
import sys

import httpx

# Hardcoded recipient chat id.
CHAT_ID = "54885728"

API = "https://api.telegram.org/bot{token}/sendMessage"


def send(text: str, parse_mode: str | None = None) -> dict:
    token = os.environ.get("TELEGRAM4LLM") or os.environ.get("TELEGRAM_BOT_TOKEN")
    if not token:
        sys.exit(
            "Error: environment variable 'telegram4llm' or 'TELEGRAM_BOT_TOKEN' is not set."
        )

    payload: dict[str, object] = {
        "chat_id": CHAT_ID,
        "text": f"[{socket.gethostname()}]\n{text}",
    }
    if parse_mode:
        payload["parse_mode"] = parse_mode

    resp = httpx.post(API.format(token=token), json=payload, timeout=10.0)
    data = resp.json()
    if not data.get("ok"):
        sys.exit(f"Telegram API error: {data}")
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description="Send a Telegram notification.")
    parser.add_argument("text", help="Message text to send.")
    parser.add_argument(
        "--parse-mode",
        choices=["Markdown", "MarkdownV2", "HTML"],
        default=None,
        help="Enable formatting (default: plain text).",
    )
    args = parser.parse_args()

    result = send(args.text, parse_mode=args.parse_mode)
    print(f"Sent (message_id={result['result']['message_id']})")


if __name__ == "__main__":
    main()
