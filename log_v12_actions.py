import requests
import time

URL = "http://localhost:8000/log"
TID = "vibe-v12-action-test"
NOW = time.time()

# 1. Thought Start
requests.post(URL, json={"task_id": TID, "event_type": "thought_start", "timestamp": NOW, "data": {"name": "UI & Logic Update (Turn 12)"}})
time.sleep(1)

# 2. Agent Actions (Reasoning phase)
requests.post(URL, json={"task_id": TID, "event_type": "agent_action", "timestamp": time.time(), "data": {"action": "Reading server.py"}})
time.sleep(1)
requests.post(URL, json={"task_id": TID, "event_type": "agent_action", "timestamp": time.time(), "data": {"action": "Updating CSS"}})
time.sleep(1)

# 3. API Start (Latency)
requests.post(URL, json={"task_id": TID, "event_type": "start", "timestamp": time.time()})
time.sleep(2)

# 4. Stream (Generation)
requests.post(URL, json={"task_id": TID, "event_type": "stream", "timestamp": time.time(), "data": {"chunk_size": 200}}) # Small burst

# 5. Stop
requests.post(URL, json={"task_id": TID, "event_type": "stop", "timestamp": time.time(), "data": {"total_tokens": 200}})
