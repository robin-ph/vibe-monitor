import requests
import time

URL = "http://localhost:8000/log"
TID = "vibe-v9-multistream-audit"
NOW = time.time()

# 1. Thought Start (Perceived Start)
requests.post(URL, json={"task_id": TID, "event_type": "thought_start", "timestamp": NOW})
time.sleep(1)

# 2. API Start (Latency starts)
requests.post(URL, json={"task_id": TID, "event_type": "start", "timestamp": time.time()})
time.sleep(2) # 2s Latency (Red)

# 3. Stream Part 1 (Generation starts)
requests.post(URL, json={"task_id": TID, "event_type": "stream", "timestamp": time.time(), "data": {"chunk_size": 400}})
time.sleep(3) # 3s Generation (Blue)

# 4. Stream Part 2 (Generation continues)
requests.post(URL, json={"task_id": TID, "event_type": "stream", "timestamp": time.time(), "data": {"chunk_size": 400}})
time.sleep(2) # 2s Apply (Yellow) phase starts after last token

# 5. Stop
requests.post(URL, json={"task_id": TID, "event_type": "stop", "timestamp": time.time(), "data": {"total_tokens": 800}})
