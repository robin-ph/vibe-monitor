import time
import requests
import uuid
from typing import Optional, Dict, Any

class VibeMonitor:
    def __init__(self, server_url: str = "http://localhost:8000"):
        self.server_url = server_url
        self.log_url = f"{server_url}/log"

    def _send(self, task_id: str, event_type: str, data: Dict[str, Any]):
        payload = {
            "task_id": task_id,
            "event_type": event_type,
            "timestamp": time.time(),
            "data": data
        }
        try:
            # Using a small timeout to not block the main process too much
            requests.post(self.log_url, json=payload, timeout=0.5)
        except Exception:
            # Silently fail to not interrupt the actual API call
            pass

    def start_task(self, name: str, task_id: Optional[str] = None) -> str:
        tid = task_id or f"{name}-{uuid.uuid4().hex[:6]}"
        self._send(tid, "start", {"name": name})
        return tid

    def stop_task(self, task_id: str, total_tokens: Optional[int] = None):
        self._send(task_id, "stop", {"total_tokens": total_tokens})

    def log_stream(self, task_id: str, chunk_size: int):
        self._send(task_id, "stream", {"chunk_size": chunk_size})

    def log_phase(self, task_id: str, phase_name: str):
        """Log a transition to a new phase (e.g., 'thinking', 'applying', 'testing')."""
        self._send(task_id, "phase", {"phase": phase_name})

# Usage Decorator for easy integration
def monitor_vibe(name: str):
    def decorator(func):
        def wrapper(*args, **kwargs):
            monitor = VibeMonitor()
            tid = monitor.start_task(name)
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                # If the result is a generator (streaming), we might need special handling
                # But for now, we assume simple return
                monitor.stop_task(tid)
                return result
            except Exception as e:
                monitor.stop_task(tid, {"error": str(e)})
                raise e
        return wrapper
    return decorator
