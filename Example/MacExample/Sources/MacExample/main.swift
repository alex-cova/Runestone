import AppKit
import Runestone

final class MacExampleAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let textView = TextView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        textView.theme = DefaultTheme()
        textView.text = """
        // Runestone macOS Example
        func greet(name: String) {
            print("Hello, \\(name)!")
        }
        """
        textView.showLineNumbers = true
        textView.isLineWrappingEnabled = true

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Runestone"
        window.contentView = textView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
let delegate = MacExampleAppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
