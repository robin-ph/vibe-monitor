"""
Vibe Monitor Server v3.0
Turn-based time tracking for Claude Code sessions.
Collects events via hooks, parses transcripts for thinking metrics.
Daily auto-archive: data resets each day, old data archived by date.
"""
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
from datetime import datetime, timezone, date
import time
import json
import os
import asyncio
import glob

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Data Models ───

class HookEvent(BaseModel):
    event: str
    timestamp: float
    session_id: str = ""
    tool_name: str = ""
    tool_input: Dict[str, Any] = {}
    transcript_path: str = ""

# ─── State ───

turns: List[Dict[str, Any]] = []          # Completed turn summaries (today)
current_turn: Optional[Dict[str, Any]] = None  # Active turn being tracked
active_connections: List[WebSocket] = []

DATA_DIR = os.path.dirname(os.path.abspath(__file__))
HISTORY_FILE = os.path.join(DATA_DIR, "vibe_history_v2.json")
CURRENT_TURN_FILE = os.path.join(DATA_DIR, "current_turn.json")
ARCHIVE_DIR = os.path.join(DATA_DIR, "archive")

# ─── Project Extraction ───

def extract_project_info(transcript_path: str) -> Dict[str, str]:
    """Extract project ID and short display name from transcript path.

    Transcript path format:
    /Users/penghan/.claude/projects/-Users-penghan-Desktop-vibe-robin-coding-moniter/session.jsonl
    """
    if not transcript_path:
        return {"id": "unknown", "name": "Unknown"}

    try:
        parts = transcript_path.split("/projects/")
        if len(parts) < 2:
            return {"id": "unknown", "name": "Unknown"}

        project_hash = parts[1].split("/")[0]  # e.g. -Users-penghan-Desktop-vibe-robin-coding-moniter

        # Extract readable name: strip up to "-Desktop-" prefix
        segments = project_hash.split("-Desktop-")
        if len(segments) > 1:
            short = segments[-1]  # e.g. vibe-robin-coding-moniter
        else:
            short = project_hash.lstrip("-")

        return {"id": project_hash, "name": short or "Unknown"}
    except Exception:
        return {"id": "unknown", "name": "Unknown"}

# ─── Daily Archive ───

def get_today_str() -> str:
    """Get today's date as YYYY-MM-DD string."""
    return date.today().isoformat()

def check_daily_reset():
    """Check if data is from a previous day; if so, archive and reset."""
    global turns

    try:
        with open(HISTORY_FILE, "r") as f:
            data = json.load(f)
    except Exception:
        return  # No history file, nothing to archive

    saved_date = data.get("date", "")
    today = get_today_str()

    if saved_date and saved_date != today and data.get("turns"):
        # Archive yesterday's data
        os.makedirs(ARCHIVE_DIR, exist_ok=True)
        archive_file = os.path.join(ARCHIVE_DIR, f"vibe_{saved_date}.json")
        try:
            with open(archive_file, "w") as f:
                json.dump(data, f, indent=2)
            print(f"[archive] Saved {len(data.get('turns', []))} turns from {saved_date} → {archive_file}")
        except Exception as e:
            print(f"[archive error] {e}")

        # Reset today
        turns = []
        save_history()
        print(f"[daily reset] New day: {today}")

def load_history():
    global turns, current_turn

    # Check for daily reset first
    check_daily_reset()

    try:
        with open(HISTORY_FILE, "r") as f:
            data = json.load(f)
            saved_date = data.get("date", "")
            today = get_today_str()
            if saved_date == today:
                turns = data.get("turns", [])
            elif not saved_date and data.get("turns"):
                # Legacy data without date field — adopt as today's data
                turns = data.get("turns", [])
                print(f"[migrate] Legacy data ({len(turns)} turns) adopted as {today}")
                save_history()  # Re-save with today's date
            else:
                turns = []
    except Exception:
        turns = []

    # Restore in-progress turn that survived a server restart
    try:
        if os.path.exists(CURRENT_TURN_FILE):
            with open(CURRENT_TURN_FILE, "r") as f:
                current_turn = json.load(f)
            print(f"[restore] Recovered in-progress turn: T{current_turn.get('turn_number')}")
    except Exception:
        current_turn = None

def save_history():
    try:
        with open(HISTORY_FILE, "w") as f:
            json.dump({
                "date": get_today_str(),
                "turns": turns,
            }, f, indent=2)
    except Exception as e:
        print(f"[save error] {e}")

def save_current_turn():
    """Persist current_turn so it survives server restarts."""
    try:
        if current_turn:
            with open(CURRENT_TURN_FILE, "w") as f:
                json.dump(current_turn, f)
        elif os.path.exists(CURRENT_TURN_FILE):
            os.remove(CURRENT_TURN_FILE)
    except Exception as e:
        print(f"[save current_turn error] {e}")

load_history()

# ─── Transcript Parsing ───

def parse_iso_ts(ts_str: str) -> float:
    """Parse ISO timestamp to unix epoch float."""
    try:
        dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
        return dt.timestamp()
    except Exception:
        return 0.0

def parse_transcript_thinking(transcript_path: str, turn_start_ts: float) -> Dict[str, Any]:
    """
    Parse the JSONL transcript to extract thinking metrics for the current turn.

    Strategy:
    - Find messages after turn_start_ts
    - Identify thinking blocks and measure:
      - Total thinking characters → estimate tokens
      - Duration: time from last input (user msg / tool_result) to thinking block arrival
    - Calculate tokens/s
    """
    result = {"duration": 0, "chars": 0, "tokens": 0, "tps": 0, "output_duration": 0, "output_chars": 0}

    if not transcript_path or not os.path.exists(transcript_path):
        return result

    try:
        messages = []
        with open(transcript_path, "r") as f:
            for line in f:
                try:
                    obj = json.loads(line.strip())
                except json.JSONDecodeError:
                    continue

                ts_str = obj.get("timestamp")
                if not ts_str:
                    continue
                ts = parse_iso_ts(ts_str)
                if ts < turn_start_ts - 1:  # Small buffer before turn start
                    continue

                msg_type = obj.get("type")
                if msg_type not in ("user", "assistant"):
                    continue

                # Extract content block types, thinking text, and output text
                content = obj.get("message", {}).get("content", [])
                thinking_chars = 0
                output_chars = 0
                content_types = []

                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict):
                            btype = block.get("type", "")
                            content_types.append(btype)
                            if btype == "thinking":
                                thinking_chars += len(block.get("thinking", ""))
                            elif btype == "text":
                                output_chars += len(block.get("text", ""))
                elif isinstance(content, str):
                    content_types.append("text")
                    output_chars += len(content)

                messages.append({
                    "ts": ts,
                    "msg_type": msg_type,
                    "content_types": content_types,
                    "thinking_chars": thinking_chars,
                    "output_chars": output_chars,
                })

        # Calculate model processing metrics
        last_input_ts = turn_start_ts
        total_thinking_chars = 0
        total_thinking_duration = 0.0
        total_output_chars = 0
        total_output_duration = 0.0
        last_assistant_ts = None
        first_assistant_after_input = True

        for msg in messages:
            if msg["msg_type"] == "user":
                last_input_ts = msg["ts"]
                first_assistant_after_input = True
                last_assistant_ts = None

            elif msg["msg_type"] == "assistant":
                if first_assistant_after_input:
                    duration = msg["ts"] - last_input_ts
                    if duration > 0:
                        if msg["thinking_chars"] > 0:
                            total_thinking_duration += duration
                            total_thinking_chars += msg["thinking_chars"]
                        else:
                            total_thinking_duration += duration
                    first_assistant_after_input = False
                    last_assistant_ts = msg["ts"]
                else:
                    if last_assistant_ts and msg["output_chars"] > 0:
                        out_dur = msg["ts"] - last_assistant_ts
                        if out_dur > 0:
                            total_output_duration += out_dur
                            total_output_chars += msg["output_chars"]
                    if msg["thinking_chars"] > 0:
                        total_thinking_chars += msg["thinking_chars"]
                    last_assistant_ts = msg["ts"]

        # Detect tool execution periods from transcript
        transcript_tool_time = 0.0
        api_call_count = 0

        for i, msg in enumerate(messages):
            if msg["msg_type"] == "assistant":
                api_call_count += 1
                if "tool_use" in msg.get("content_types", []):
                    for j in range(i + 1, len(messages)):
                        if messages[j]["msg_type"] == "user":
                            gap = messages[j]["ts"] - msg["ts"]
                            if 0 < gap < 600:
                                transcript_tool_time += gap
                            break

        # Estimate tokens (mixed Chinese/English: ~3.5 chars per token)
        tokens = int(total_thinking_chars / 3.5) if total_thinking_chars > 0 else 0
        tps = round(tokens / total_thinking_duration, 1) if total_thinking_duration > 0 else 0

        result = {
            "duration": round(total_thinking_duration, 2),
            "chars": total_thinking_chars,
            "tokens": tokens,
            "tps": tps,
            "output_duration": round(total_output_duration, 2),
            "output_chars": total_output_chars,
            "transcript_tool_time": round(transcript_tool_time, 2),
            "api_call_count": max(api_call_count, 1),
        }
    except Exception as e:
        print(f"[transcript parse error] {e}")

    return result

# ─── Turn Finalization ───

def finalize_turn(turn: Dict) -> Dict[str, Any]:
    """Calculate final metrics for a completed turn."""
    total = turn["end_time"] - turn["start_time"]

    # Calculate tool time with per-tool breakdown
    tools = []
    tool_time = 0.0
    for te in turn.get("tool_events", []):
        end = te.get("end") or turn["end_time"]
        duration = max(0, end - te["start"])
        tool_time += duration
        tools.append({
            "tool": te["tool"],
            "duration": round(duration, 2),
            "detail": te.get("detail", ""),
        })

    # Parse transcript for thinking metrics
    thinking = parse_transcript_thinking(
        turn.get("transcript_path", ""),
        turn["start_time"],
    )

    # ─── 5-category time split ───
    thinking_time = thinking["duration"]
    output_time = thinking.get("output_duration", 0)

    hook_tool_time = tool_time
    transcript_tool_time = thinking.get("transcript_tool_time", 0)
    recovered_tool_time = max(0, transcript_tool_time - hook_tool_time)
    total_tool_time = hook_tool_time + recovered_tool_time

    residual = max(0, total - thinking_time - total_tool_time - output_time)

    api_calls = thinking.get("api_call_count", 1)
    network_time = min(api_calls * 1.5, residual)

    unaccounted_time = max(0, residual - network_time)

    tool_counts = {}
    for t in tools:
        name = t["tool"]
        tool_counts[name] = tool_counts.get(name, 0) + 1

    project = extract_project_info(turn.get("transcript_path", ""))

    return {
        "id": turn["id"],
        "turn_number": turn.get("turn_number", 0),
        "start_time": turn["start_time"],
        "total_time": round(total, 2),
        "thinking_time": round(thinking_time, 2),
        "thinking_tokens": thinking["tokens"],
        "thinking_tps": thinking["tps"],
        "tool_time": round(total_tool_time, 2),
        "tool_time_hook": round(hook_tool_time, 2),
        "tool_time_recovered": round(recovered_tool_time, 2),
        "tool_count": len(tools),
        "tool_breakdown": tool_counts,
        "tools": tools,
        "output_time": round(output_time, 2),
        "output_chars": thinking.get("output_chars", 0),
        "network_time": round(network_time, 2),
        "unaccounted_time": round(unaccounted_time, 2),
        "api_calls": api_calls,
        "project_id": project["id"],
        "project_name": project["name"],
    }

# ─── Hook Endpoint ───

@app.post("/hook")
async def hook(event: HookEvent):
    global current_turn, turns

    # Check daily reset on every hook event
    today = get_today_str()
    try:
        with open(HISTORY_FILE, "r") as f:
            data = json.load(f)
        saved_date = data.get("date", "")
        if saved_date and saved_date != today and data.get("turns"):
            # Day changed! Archive and reset.
            os.makedirs(ARCHIVE_DIR, exist_ok=True)
            archive_file = os.path.join(ARCHIVE_DIR, f"vibe_{saved_date}.json")
            with open(archive_file, "w") as f:
                json.dump(data, f, indent=2)
            print(f"[archive] Day changed → archived {saved_date}")
            turns = []
            save_history()
            await broadcast({"type": "reset"})
    except Exception:
        pass

    if event.event == "UserPromptSubmit":
        # If previous turn wasn't closed, finalize it
        if current_turn and not current_turn.get("end_time"):
            current_turn["end_time"] = event.timestamp
            summary = finalize_turn(current_turn)
            turns.append(summary)
            save_history()
            await broadcast({"type": "turn_complete", "data": summary})

        # Start new turn
        turn_number = len(turns) + 1
        project = extract_project_info(event.transcript_path)
        current_turn = {
            "id": f"turn-{turn_number}-{int(event.timestamp)}",
            "turn_number": turn_number,
            "start_time": event.timestamp,
            "session_id": event.session_id,
            "transcript_path": event.transcript_path,
            "project_id": project["id"],
            "project_name": project["name"],
            "tool_events": [],
            "end_time": None,
        }
        save_current_turn()
        await broadcast({
            "type": "turn_start",
            "turn_number": turn_number,
            "project_name": project["name"],
            "ts": event.timestamp,
        })

    elif event.event == "PreToolUse":
        if current_turn:
            detail = ""
            ti = event.tool_input
            if ti.get("file_path"):
                detail = os.path.basename(ti["file_path"])
            elif ti.get("pattern"):
                detail = ti["pattern"][:50]
            elif ti.get("command"):
                detail = ti["command"][:50]

            current_turn["tool_events"].append({
                "tool": event.tool_name,
                "start": event.timestamp,
                "end": None,
                "detail": detail,
            })
            save_current_turn()
            await broadcast({
                "type": "tool_start",
                "tool": event.tool_name,
                "detail": detail,
                "ts": event.timestamp,
            })

    elif event.event == "PostToolUse":
        if current_turn and current_turn["tool_events"]:
            for te in reversed(current_turn["tool_events"]):
                if te["end"] is None and te["tool"] == event.tool_name:
                    te["end"] = event.timestamp
                    break
            save_current_turn()
            await broadcast({
                "type": "tool_end",
                "tool": event.tool_name,
                "ts": event.timestamp,
            })

    elif event.event == "Stop":
        if current_turn:
            current_turn["end_time"] = event.timestamp
            if event.transcript_path:
                current_turn["transcript_path"] = event.transcript_path

            summary = finalize_turn(current_turn)
            turns.append(summary)
            save_history()
            await broadcast({"type": "turn_complete", "data": summary})
            current_turn = None
            save_current_turn()

    return {"status": "ok"}

# ─── API Endpoints ───

# --- API Aliases for DESIGN_SPEC.md ---

@app.get("/api/turns")
async def get_api_turns():
    turns = []
    for i, s in enumerate(summary_history):
        data = s["data"]
        turns.append({
            "id": data["task_id"],
            "turn_number": i + 1,
            "start_time": time.time() - data["total"], # Estimate
            "total_time": data["total"],
            "thinking_time": data["reasoning"],
            "thinking_tokens": data["tokens"],
            "thinking_tps": data["tps"],
            "tool_time": data["generation"],
            "tool_count": len(data["actions"]),
            "tool_breakdown": {a: 1 for a in data["actions"]},
            "output_time": data["applying"],
            "projectName": "Unknown"
        })
    return {"turns": turns, "date": time.strftime("%Y-%m-%d")}

@app.get("/api/current")
async def get_api_current():
    if not current_turn:
        return {"active": False}

    now = time.time()
    elapsed = now - current_turn["start_time"]
    tool_time = sum(
        ((te["end"] if te.get("end") is not None else now) - te["start"])
        for te in current_turn.get("tool_events", [])
    )
    return {
        "active": True,
        "turn_number": current_turn.get("turn_number", 0),
        "elapsed": round(elapsed, 1),
        "tool_time": round(tool_time, 1),
        "tool_count": len(current_turn.get("tool_events", [])),
        "current_tool": (
            current_turn["tool_events"][-1]["tool"]
            if current_turn.get("tool_events") and current_turn["tool_events"][-1]["end"] is None
            else None
        ),
    }

@app.get("/api/history")
async def get_history():
    """List available archive dates."""
    archives = []
    if os.path.exists(ARCHIVE_DIR):
        for f in sorted(glob.glob(os.path.join(ARCHIVE_DIR, "vibe_*.json")), reverse=True):
            fname = os.path.basename(f)
            # vibe_2026-03-05.json → 2026-03-05
            d = fname.replace("vibe_", "").replace(".json", "")
            try:
                with open(f, "r") as fh:
                    data = json.load(fh)
                total_turns = len(data.get("turns", []))
                total_time = sum(t.get("total_time", 0) for t in data.get("turns", []))
                archives.append({
                    "date": d,
                    "turns": total_turns,
                    "total_time": round(total_time, 1),
                })
            except Exception:
                archives.append({"date": d, "turns": 0, "total_time": 0})
    return {"today": get_today_str(), "archives": archives}

@app.get("/api/history/{date_str}")
async def get_history_date(date_str: str):
    """Get archived data for a specific date."""
    archive_file = os.path.join(ARCHIVE_DIR, f"vibe_{date_str}.json")
    if not os.path.exists(archive_file):
        return {"error": "not found", "date": date_str}
    try:
        with open(archive_file, "r") as f:
            data = json.load(f)
        return data
    except Exception as e:
        return {"error": str(e)}

@app.post("/api/reset")
async def reset_session():
    global turns, current_turn
    turns = []
    current_turn = None
    save_history()
    save_current_turn()
    await broadcast({"type": "reset"})
    return {"status": "ok"}

# ─── WebSocket ───

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    active_connections.append(websocket)
    try:
        await websocket.send_text(json.dumps({
            "type": "init",
            "turns": turns,
            "date": get_today_str(),
            "active": current_turn is not None,
        }))
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        if websocket in active_connections:
            active_connections.remove(websocket)

async def broadcast(message: dict):
    dead = []
    for ws in active_connections:
        try:
            await ws.send_text(json.dumps(message))
        except Exception:
            dead.append(ws)
    for ws in dead:
        if ws in active_connections:
            active_connections.remove(ws)

# ─── Static Files ───

@app.get("/")
async def index():
    return FileResponse(os.path.join(DATA_DIR, "index.html"))

@app.get("/script.js")
async def script():
    return FileResponse(os.path.join(DATA_DIR, "script.js"), media_type="application/javascript")

@app.get("/style.css")
async def style():
    return FileResponse(os.path.join(DATA_DIR, "style.css"), media_type="text/css")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
