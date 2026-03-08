#!/usr/bin/env python3
"""
Thin hook script for Claude Code → Vibe Monitor.
Reads hook event from stdin, POSTs to monitor server.
Uses only stdlib for zero-dependency execution.
"""
import sys
import json
import time
import urllib.request

MONITOR_URL = "http://localhost:8000/hook"

def main():
    try:
        input_data = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    event = input_data.get("hook_event_name", "")
    if not event:
        sys.exit(0)

    payload = {
        "event": event,
        "timestamp": time.time(),
        "session_id": input_data.get("session_id", ""),
        "tool_name": input_data.get("tool_name", ""),
        "tool_input": {},
        "transcript_path": input_data.get("transcript_path", ""),
    }

    # For PreToolUse, include tool input summary (name only, keep it small)
    if event == "PreToolUse":
        tool_input = input_data.get("tool_input", {})
        # Extract useful info without sending large payloads
        if isinstance(tool_input, dict):
            payload["tool_input"] = {
                k: v for k, v in tool_input.items()
                if k in ("command", "pattern", "file_path", "query", "prompt", "skill")
                and isinstance(v, str) and len(v) < 200
            }

    try:
        req = urllib.request.Request(
            MONITOR_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        urllib.request.urlopen(req, timeout=1)
    except Exception:
        pass  # Never block Claude Code

if __name__ == "__main__":
    main()
