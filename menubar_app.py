import rumps
import json
import threading
import websocket
import time
import requests
import logging
import os

# Set up logging to a file
log_file = os.path.expanduser("~/vibe_menubar.log")
logging.basicConfig(filename=log_file, level=logging.INFO, 
                    format='%(asctime)s - %(levelname)s - %(message)s')

class VibeMenubarApp(rumps.App):
    def __init__(self):
        logging.info("Initializing Vibe Menubar App")
        super(VibeMenubarApp, self).__init__("Vibe", title="Vibe: --")
        self.current_speed = 0
        self.current_ide = "Unknown"
        self.last_update = time.time()
        
        # Start the WebSocket connection in a separate thread
        threading.Thread(target=self.ws_thread, daemon=True).start()
        # Start a timer to update the title periodically
        self.update_timer = rumps.Timer(self.update_title, 1)
        self.update_timer.start()

    def ws_thread(self):
        while True:
            try:
                ws = websocket.WebSocketApp(
                    "ws://localhost:8000/ws",
                    on_message=self.on_message,
                    on_error=self.on_error,
                    on_close=self.on_close
                )
                ws.run_forever()
            except Exception as e:
                print(f"WS Error: {e}")
            time.sleep(2)  # Reconnect delay

    def on_message(self, ws, message):
        msgs = json.loads(message)
        if not isinstance(msgs, list):
            msgs = [msgs]
            
        for msg in msgs:
            if msg['event_type'] == 'stream':
                self.current_speed += msg['data']['chunk_size']
            if 'ide' in msg and msg['ide']:
                self.current_ide = msg['ide']

    def on_error(self, ws, error):
        print(f"WS Error detail: {error}")

    def on_close(self, ws, close_status_code, close_msg):
        print("WS Closed")

    def update_title(self, _):
        # Calculate speed since last check (every 1s)
        speed = self.current_speed
        self.current_speed = 0 # Reset for next second
        
        # Fetch status if no events coming in
        display_name = "Unknown"
        try:
            r = requests.get("http://localhost:8000/status", timeout=0.1)
            if r.status_code == 200:
                data = r.json()
                current = data.get("current_ide", "Unknown")
                is_dev = data.get("is_dev", False)
                # If in a dev tool, show it. If not, show last dev tool but dimmed/marked
                if is_dev:
                    display_name = f"● {current}"
                else:
                    display_name = f"○ {current}" # Hollow circle for non-dev apps
        except:
            pass

        # Update the menubar title
        self.title = f"[{display_name}] {speed} t/s"

    @rumps.clicked("Open Dashboard")
    def open_dashboard(self, _):
        import webbrowser
        import os
        path = os.path.abspath("index.html")
        webbrowser.open(f"file://{path}")

    @rumps.clicked("Run Test")
    def run_test(self, _):
        import subprocess
        subprocess.Popen(["python3", "test_client.py"])

if __name__ == "__main__":
    VibeMenubarApp().run()
