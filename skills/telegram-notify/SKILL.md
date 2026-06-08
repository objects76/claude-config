---
name: telegram-notify
description: Send a message to Telegram. Use ONLY when the user explicitly asks to send or be notified via Telegram (e.g. "텔레그램으로 알려줘 / 텔레그램으로 보내줘 / send this to telegram / ping me on telegram"). Do not trigger automatically on task or job completion unless the user explicitly requested a Telegram notification.
---

# Telegram Notify

## Usage

Run `scripts/send.py` (located in this skill's scripts directory) with the message as the first argument:

```bash
python3 scripts/send.py "메시지 내용"
```

Optional flags:

- `--parse-mode Markdown` (or `HTML`) to enable formatting. Default is plain text.
