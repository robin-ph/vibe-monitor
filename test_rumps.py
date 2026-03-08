import rumps

class TestApp(rumps.App):
    def __init__(self):
        super(TestApp, self).__init__("Test", title="TEST!!")

if __name__ == "__main__":
    TestApp().run()
