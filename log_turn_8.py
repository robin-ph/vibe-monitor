import requests
import time

URL = "http://localhost:8000/log"
TID = "vibe-v8-sync-turn"
START_TIME = 1772737325 # 03:02:05 UTC+8 roughly

# 1. Thought Start (User message received)
requests.post(URL, json={
    "task_id": TID, "event_type": "thought_start", "timestamp": START_TIME,
    "data": {"name": "Calibration Response (Turn 8)"}
})

# 2. Start (Agent starts execution/planning)
requests.post(URL, json={
    "task_id": TID, "event_type": "start", "timestamp": START_TIME + 2,
    "data": {"name": "Calibration Response (Turn 8)"}
})

# 3. Stream (Middle of generating)
requests.post(URL, json={
    "task_id": TID, "event_type": "stream", "timestamp": time.time() - 2,
    "data": {"chunk_size": 1500}
})

# 4. Stop (Last character typed)
requests.post(URL, json={
    "task_id": TID, "event_type": "stop", "timestamp": time.time(),
    "data": {"total_tokens": 1500}
})
