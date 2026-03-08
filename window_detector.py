try:
    from AppKit import NSWorkspace
    import time

    def get_active_window_info():
        active_app = NSWorkspace.sharedWorkspace().frontmostApplication()
        if active_app:
            return {
                "app_name": active_app.localizedName(),
                "bundle_id": active_app.bundleIdentifier()
            }
        return None

except ImportError:
    # Fallback for non-macOS environments or if pyobjc fails
    def get_active_window_info():
        return {"app_name": "Unknown", "bundle_id": "unknown"}

if __name__ == "__main__":
    while True:
        print(get_active_window_info())
        time.sleep(1)
