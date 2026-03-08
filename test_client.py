import time
import random
from monitor_client import VibeMonitor

def simulate_vibe_coding():
    monitor = VibeMonitor()
    
    print("Starting Task: Code Generation")
    tid = monitor.start_task("Code Generation")
    
    # Simulate first response delay (latency)
    time.sleep(1.2)
    
    total_tokens = 0
    for _ in range(20):
        # Simulate streaming chunks
        chunk = random.randint(10, 50)
        total_tokens += chunk
        monitor.log_stream(tid, chunk)
        time.sleep(0.1) # Simulate network streaming speed
        
    monitor.stop_task(tid, total_tokens)
    print(f"Task Complete. Total tokens: {total_tokens}")

    print("Starting Task: Refactoring")
    tid2 = monitor.start_task("Refactoring")
    time.sleep(0.8)
    for _ in range(10):
        chunk = random.randint(20, 80)
        monitor.log_stream(tid2, chunk)
        time.sleep(0.05)
    monitor.stop_task(tid2, 500)
    print("Refactoring Complete.")

if __name__ == "__main__":
    simulate_vibe_coding()
