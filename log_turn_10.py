import requests
import time

URL = "http://localhost:8000/log"
TID = "vibe-turn-10-calibration"
NOW = time.time()

# 1. Thought Start (Perceived Start)
requests.post(URL, json={"task_id": TID, "event_type": "thought_start", "timestamp": NOW})
time.sleep(1)

# 2. API Start (Latency starts)
requests.post(URL, json={"task_id": TID, "event_type": "start", "timestamp": time.time()})
time.sleep(1)

# 3. INSTANT STREAM (Single chunk - 0s generation)
requests.post(URL, json={"task_id": TID, "event_type": "stream", "timestamp": time.time(), "data": {"chunk_size": 1200}})
# requests.post(URL, json={"task_id": TID, "event_type": "stream", "timestamp": time.time(), "data": {"chunk_size": 300}})

# 4. Stop (Immediate stop after stream)
requests.post(URL, json={"task_id": TID, "event_type": "stop", "timestamp": time.time(), "data": {"total_tokens": 1200}})
