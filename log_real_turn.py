import requests
import time

URL = "http://localhost:8000/log"
TID = "vibe-v7-real-calibration"

# 1. Thought Start (User hit Enter)
print("Reasoning start...")
requests.post(URL, json={
    "task_id": TID, "event_type": "thought_start", "timestamp": time.time(),
    "data": {"name": "Complex Feature Implementation (Perceived 10min)"}, "ide": "Vibe coding"
})

time.sleep(5)  # Simulate 5s Reasoning in demo (scales to 10min in real)

# 2. First API Request Start
print("API Request start...")
requests.post(URL, json={
    "task_id": TID, "event_type": "start", "timestamp": time.time(),
    "data": {"name": "Complex Feature Implementation (Perceived 10min)"}
})

time.sleep(2)  # Latency

# 3. Streaming Code
print("Streaming...")
requests.post(URL, json={
    "task_id": TID, "event_type": "stream", "timestamp": time.time(),
    "data": {"chunk_size": 800}
})

time.sleep(3)  # Generation

# 4. Stop (Human perceived completion)
print("Finished.")
requests.post(URL, json={
    "task_id": TID, "event_type": "stop", "timestamp": time.time(),
    "data": {"total_tokens": 800}
})
