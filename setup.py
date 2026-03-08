from setuptools import setup

APP = ['menubar_app.py']
DATA_FILES = []
OPTIONS = {
    'argv_emulation': True,
    'plist': {
        'LSUIElement': True, # Back to menubar-only for the final version
    },
    'packages': ['rumps', 'websocket', 'requests'],
}

setup(
    name="VibeMonitor",
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
    setup_requires=['py2app'],
)
