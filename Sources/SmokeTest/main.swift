import AppKit
import Runestone

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                      styleMask: [.titled],
                      backing: .buffered,
                      defer: false)
window.orderFrontRegardless()

let textView = TextView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
window.contentView = textView

textView.theme = DefaultTheme()
textView.text = "Smoke test"
textView.selectedRange = NSRange(location: 0, length: 5)

guard textView.text == "Smoke test" else {
    fputs("Unexpected text content\n", stderr)
    exit(1)
}
guard textView.selectedRange.length == 5 else {
    fputs("Unexpected selection\n", stderr)
    exit(1)
}
guard textView.becomeFirstResponder() else {
    fputs("Failed to become first responder\n", stderr)
    exit(1)
}
textView.insertText("!")
guard textView.text == "Smoke test!" else {
    fputs("Insert text failed\n", stderr)
    exit(1)
}
print("Smoke test passed")
