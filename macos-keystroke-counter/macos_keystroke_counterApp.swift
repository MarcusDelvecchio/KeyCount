import SwiftUI
import ApplicationServices

@main
struct macos_keystroke_trackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var instance: AppDelegate!
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var keystrokeCount = 0
    let menu = ApplicationMenu()

    private var eventTap: CFMachPort?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create a status item and set its properties
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Increase the font size
            let fontSize: CGFloat = 14.0 // Change this value to the desired font size
            let font = NSFont.systemFont(ofSize: fontSize)
            button.font = font
            updateKeystrokesCount()

            // Adjust the baselineOffset to center the text vertically
            if let font = button.font {
                let offset = -(font.capHeight - font.xHeight) / 2 + 0.6 // Adjusting vertical offset of the text
                button.attributedTitle = NSAttributedString(
                    string: "\(keystrokeCount) keystrokes",
                    attributes: [NSAttributedString.Key.baselineOffset: offset]
                )
            }
        }

        // Create a menu with sections and items
        let menu = NSMenu()

        // Section title
        let sectionTitleItem = NSMenuItem()
        sectionTitleItem.title = "Send updates to:"
        menu.addItem(sectionTitleItem)

        // Endpoint URL input
        let endpointItem = NSMenuItem()
        let endpointLabel = NSTextField(labelWithString: "Endpoint URL:")
        let endpointTextField = NSTextField()
        endpointItem.view = NSStackView(views: [endpointLabel, endpointTextField])
        menu.addItem(endpointItem)

        // Interval input
        let intervalItem = NSMenuItem()
        let intervalLabel = NSTextField(labelWithString: "Interval:")
        let intervalTextField = NSTextField()
        let intervalUnitLabel = NSTextField(labelWithString: "seconds")
        let intervalStack = NSStackView(views: [intervalLabel, intervalTextField, intervalUnitLabel])
        intervalStack.orientation = .horizontal
        intervalItem.view = intervalStack
        menu.addItem(intervalItem)

        // Quit button
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(terminateApp), keyEquivalent: "q")

        statusItem.menu = menu

        // Request accessibility permissions
        requestAccessibilityPermission()

        // Register for key events using event tap
        setupEventTap()
    }

    func updateKeystrokesCount() {
        if let button = statusItem.button {
            button.title = "\(keystrokeCount) keystrokes"

            if let font = button.font {
                let offset = -(font.capHeight - font.xHeight) / 2 + 0.6
                button.attributedTitle = NSAttributedString(
                    string: "\(keystrokeCount) keystrokes",
                    attributes: [NSAttributedString.Key.baselineOffset: offset]
                )
            }
        }
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            print("Please enable accessibility permissions for the app.")
        }
    }

    func handleEvent(_ event: CGEvent) {
        keystrokeCount += 1
        updateKeystrokesCount()
    }

    func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let mask = CGEventMask(eventMask)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return nil
                }

                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                appDelegate.handleEvent(event)

                return Unmanaged.passRetained(event)
            },
            userInfo: selfPointer
        )

        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            CFRunLoopRun()
        }
    }

    @objc func terminateApp() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        NSApplication.shared.terminate(self)
    }
}
