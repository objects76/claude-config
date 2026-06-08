---
name: export-all
description: Export the current Claude Code conversation transcript (.jsonl session log) into the project directory, pretty-printed with real newlines inside string values so it is human-readable. Use when the user asks to "export this dialog", "copy the conversation json", "dump chat history to a file", or wants to share/inspect the current session's raw transcript outside of Claude Code.
allowed-tools: Bash(ls:*), Bash(python3:*), Bash(wc:*), Bash(pwd:*), Bash(tr:*)
---

# Export Current Claude Code Dialog

Copies the current session's transcript from `~/.claude/projects/…` into the project directory, pretty-printed with real newlines in place of escaped `\n` so long code/tool-result blocks are readable.

## When to Use

Trigger on requests like:
- "export the current conversation"
- "copy the session jsonl here"
- "dump chat history as readable file"
- "save this dialog to the project"

## Session Location

- Base: `~/.claude/projects/<slug>/<session-id>.jsonl`
- `<slug>` is the absolute project path with **both `/` and `_` replaced by `-`**. Example: `/home/jjkim/Desktop/work/AgentWS/nanobot_ws/nanobot` → `-home-jjkim-Desktop-work-AgentWS-nanobot-ws-nanobot`.
- **Current session** = the most recently modified `.jsonl` in that directory.
- Format: one JSON object per line.

## Arguments

`ARGUMENTS` (optional) — desired output filename or path.
- Omitted → default to `claude-session-<session-id>.jsonl` in `$PROJECT_DIR`.
- Bare filename → written to `$PROJECT_DIR/<name>`.
- Contains `/` → relative to `$PROJECT_DIR` unless it starts with `/` or `~`.
- Keep the `.jsonl` extension unless the user explicitly asked for `.md` / `.txt` etc.

**Mandatory prefix**: the output file basename must always start with `claude-session-`. If the user-supplied name does not, prepend it (directory part is preserved). Example: `tools/weather.jsonl` → `tools/claude-session-weather.jsonl`. If the name already starts with `claude-session-`, leave it as-is.

Strip surrounding quotes/backticks and trailing punctuation. Do not invent a name — only use what the user typed.

## Procedure

### 1. Resolve source and destination

```bash
PROJECT_DIR="$(pwd)"
SLUG="$(echo "$PROJECT_DIR" | tr '/_' '--')"
SESSION_DIR="$HOME/.claude/projects/$SLUG"
SRC="$(ls -1t "$SESSION_DIR"/*.jsonl | head -1)"

# $ARG = the user-supplied ARGUMENTS, or empty.
if [ -z "$ARG" ]; then
    DST="$PROJECT_DIR/claude-session-$(basename "$SRC")"
else
    if [[ "$ARG" == /* || "$ARG" == ~* ]]; then
        DST="${ARG/#\~/$HOME}"
    else
        DST="$PROJECT_DIR/$ARG"
    fi
    DST_DIR="$(dirname "$DST")"
    DST_BASE="$(basename "$DST")"
    [[ "$DST_BASE" != claude-session-* ]] && DST_BASE="claude-session-$DST_BASE"
    DST="$DST_DIR/$DST_BASE"
fi
```

If `$DST` already exists and is not the default session path, confirm with the user before overwriting.

If the user already exported earlier and wants a **fresh** copy, always re-read from `$SRC` — the previously pretty-printed file is no longer valid JSON.

### 2. Copy + reformat in one pass

```bash
python3 - "$SRC" "$DST" <<'PY'
import json, re, sys

src, dst = sys.argv[1], sys.argv[2]
out = []
with open(src, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        obj = json.loads(line)
        text = json.dumps(obj, indent=2, ensure_ascii=False)
        text = re.sub(r'(?<!\\)\\([nt])', lambda m: {'n': '\n', 't': '\t'}[m.group(1)], text)
        text = re.sub(r'\\\\([nt])', r'\\\1', text)
        out.append(text)

with open(dst, "w", encoding="utf-8") as f:
    f.write("\n\n".join(out) + "\n")

print(f"wrote {len(out)} records to {dst}")
PY
```

Why a single pass: the pretty-printed output is not valid JSON, so a two-step (copy then reformat) approach would fail on the second pass.

### 3. Report

Print one line with source, destination, record count, and size. Example:

```
Exported 240 records from ~/.claude/projects/.../ea9c2a48-....jsonl
  → /home/jjkim/.../ea9c2a48-....jsonl (576 KB, 15,766 lines)
```

Warn once: the output is **not valid JSONL** anymore (real newlines inside strings break line-based parsers). For programmatic use, re-copy the original from `~/.claude/projects/`.

## Safety

- Read-only on `~/.claude/projects/`. Never modify or delete originals.
- Confirm before overwriting any existing file at `$DST` that is not the default session path.
