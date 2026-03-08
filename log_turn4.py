import requests
import time

URL = "http://localhost:8000/log"
TID = "turn-4-chat"

# Start
requests.post(URL, json={
    "task_id": TID, "event_type": "start", "timestamp": time.time(),
    "data": {"name": "User Question: Metrics explanation"}, "ide": "Vibe Chat"
})

time.sleep(1) # Latency simulation

# Stream
requests.post(URL, json={
    "task_id": TID, "event_type": "stream", "timestamp": time.time(),
    "data": {"chunk_size": 200}
})

time.sleep(2) # Generation simulation

# Stream End
requests.post(URL, json={
    "task_id": TID, "event_type": "stream", "timestamp": time.time(),
    "data": {"chunk_size": 300}
})

# Stop
requests.post(URL, json={
    "task_id": TID, "event_type": "stop", "timestamp": time.time(),
    "data": {"total_tokens": 500}
})
