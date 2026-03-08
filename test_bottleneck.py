import time
import random
from monitor_client import VibeMonitor

def simulate_bottleneck_scenarios():
    monitor = VibeMonitor()
    
    # Scenario 1: Model Latency Bottleneck (Cloud is slow to respond)
    print("\n--- Scenario 1: High Latency (Cloud Prep is slow) ---")
    tid1 = monitor.start_task("Latency-Heavy Task")
    time.sleep(3.5) # Fake 3.5s latency
    for _ in range(5):
        monitor.log_stream(tid1, 20)
        time.sleep(0.1)
    monitor.stop_task(tid1)
    
    # Scenario 2: Generation Bottleneck (TPS is low)
    print("\n--- Scenario 2: Low TPS (Generation is slow) ---")
    tid2 = monitor.start_task("Generation-Heavy Task")
    time.sleep(0.2)
    for _ in range(20):
        monitor.log_stream(tid2, 5) # Small chunks
        time.sleep(0.3) # Slow streaming
    monitor.stop_task(tid2)

    # Scenario 3: Local Apply Bottleneck (IDE/Files are slow)
    print("\n--- Scenario 3: High Apply Time (Local IDE is laggy) ---")
    tid3 = monitor.start_task("Apply-Heavy Task")
    time.sleep(0.5)
    for _ in range(10):
        monitor.log_stream(tid3, 40)
        time.sleep(0.1)
    # Simulate time taken by IDE to apply changes after stream ends
    time.sleep(4.0) 
    monitor.stop_task(tid3)

if __name__ == "__main__":
    simulate_bottleneck_scenarios()
