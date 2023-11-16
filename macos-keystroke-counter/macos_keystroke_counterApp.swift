import SwiftUI
import ApplicationServices

@main
struct macos_keystroke_trackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsWindow()
                .environmentObject(appDelegate)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Settings") {
                    appDelegate.menu.showSettings()
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var mainWindow: NSWindow!
    static private(set) var instance: AppDelegate!
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    @Published var keystrokeCount: Int {
        didSet {
            UserDefaults.standard.set(keystrokeCount, forKey: "keystrokesToday")
        }
    }

    @Published var totalKeystrokes: Int {
        didSet {
            UserDefaults.standard.set(totalKeystrokes, forKey: "totalKeystrokes")
        }
    }

    private var eventTap: CFMachPort?
    var menu: ApplicationMenu!

    override init() {
        self.keystrokeCount = UserDefaults.standard.integer(forKey: "keystrokesToday")
        self.totalKeystrokes = UserDefaults.standard.integer(forKey: "totalKeystrokes")
        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create a status item and set its properties
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let fontSize: CGFloat = 14.0
            let font = NSFont.systemFont(ofSize: fontSize)
            button.font = font
            updateKeystrokesCount()

            if let font = button.font {
                let offset = -(font.capHeight - font.xHeight) / 2 + 0.6
                button.attributedTitle = NSAttributedString(
                    string: "\(keystrokeCount) keystrokes",
                    attributes: [NSAttributedString.Key.baselineOffset: offset]
                )
            }
        }

        // Create the main window but don't show it
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        mainWindow.title = "Keystroke Counter"
        
        // Initialize ApplicationMenu only once
        menu = ApplicationMenu(mainWindow: mainWindow, appDelegate: self)

        // Create the menu
        menu.buildMenu()

        statusItem.menu = menu.menu
        statusItem.button?.action = #selector(menu.toggleMenu)

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
        totalKeystrokes += 1
        updateKeystrokesCount()
    }

    func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let mask = CGEventMask(eventMask) | CGEventFlags.maskCommand.rawValue

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
        UserDefaults.standard.synchronize()
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        NSApplication.shared.terminate(self)
    }
}

class ApplicationMenu: ObservableObject {
    var appDelegate: AppDelegate
    var menu: NSMenu!
    var mainWindow: NSWindow?
    var settingsWindow: NSWindow?

    init(mainWindow: NSWindow?, appDelegate: AppDelegate) {
        self.mainWindow = mainWindow
        self.appDelegate = appDelegate
        buildMenu()
    }

    func buildMenu() {
        menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self

        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(terminateApp), keyEquivalent: "q")
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            // Initialize the settings window
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )

            settingsWindow?.title = "Settings"
            settingsWindow?.contentViewController = NSHostingController(rootView: SettingsWindow().environmentObject(appDelegate))
        }

        // Show or bring to front the settings window
        if let settingsWindow = self.settingsWindow {
            if settingsWindow.isVisible {
                settingsWindow.orderOut(nil)
            } else {
                settingsWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc func terminateApp() {
        NSApplication.shared.terminate(self)
    }

    @objc func toggleMenu() {
        if let button = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength).button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
        }
    }
}

struct SettingsWindow: View {
    @State private var endpointURL = ""
    @State private var updateInterval = 0
    @State private var statusBarInfoSelection = 0
    @State private var clearKeystrokesDaily = false
    @EnvironmentObject var appDelegate: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Send updates to
            GroupBox(label: Text("Send updates to")) {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("Endpoint URL", text: $endpointURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Stepper(value: $updateInterval, in: 0...3600, step: 1) {
                        Text("Update Interval: \(updateInterval) seconds")
                    }
                }
                .padding()
            }

            // Status bar info
            GroupBox(label: Text("Status bar info")) {
                VStack(alignment: .leading, spacing: 5) {
                    RadioButtonGroup(items: ["Keystrokes from today", "All-time keystrokes"], selected: $statusBarInfoSelection)
                }
                .padding()
            }

            // Keystroke stats
            GroupBox(label: Text("Keystroke stats")) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("All-time keystrokes: \(appDelegate.totalKeystrokes)")
                    Text("Keystrokes today: \(appDelegate.keystrokeCount)")
                }
                .padding()
            }

            // Other settings
            GroupBox(label: Text("Other settings")) {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("Clear keystrokes daily", isOn: $clearKeystrokesDaily)
                    Button("Delete all keystroke data") {
                        // Handle delete action
                    }
                }
                .padding()
            }

            Spacer()
        }
        .padding(15)
        .frame(minWidth: 300, minHeight: 450)
        .padding()
    }
}

struct RadioButtonGroup: View {
    let items: [String]
    @Binding var selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<items.count, id: \.self) { index in
                RadioButton(
                    text: items[index],
                    isSelected: index == selected,
                    action: { selected = index }
                )
            }
        }
    }
}

struct RadioButton: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                Text(text)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LazyView<Content: View>: View {
    var content: () -> Content

    init(_ content: @autoclosure @escaping () -> Content) {
        self.content = content
    }

    var body: Content {
        content()
    }
}
