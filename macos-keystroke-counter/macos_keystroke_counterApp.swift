/*
 * Copyright (c) 2023 Marcus Del Vecchio
 * All rights reserved.
 * Application available at https://github.com/MarcusDelvecchio/macos-keystroke-counter/tree/master
 */

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
    var activity: NSObjectProtocol?
    var mainWindow: NSWindow!
    static private(set) var instance: AppDelegate!
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var updateInterval = Int(UserDefaults.standard.string(forKey: "updateInterval") ?? "30") ?? 30
    
    // Variables for maintaining keystroke data
    var keystrokeData: [Int] = []
    var currentTimeIndex: Int = 0
    var endpointURL: String = ""
    
    // The number of keystrokes at the beginning of the interval, so that when we send the data we can add the keystrokes from the leystroke data on to this value incrementally
    var keystrokesAtBeginningOfInterval: Int = 0
    
    // how precise the key detection logic is. keystrokeData data will be an array of Integers where each Int represents the number of keystrokes that took place in each period. If updatePrecision = 4, then it will be the number of keystrokes in each 250ms period (4 periods per second)
    var updatePrecision: Int = 20
    
    // keys for UserDefaults data
    let sendingUpdatesEnabledKey = "sendingUpdatesEnabled"
    let updateEndpointURIKey = "updateEndpointURI"
    let updateIntervalKey = "updateInterval"
    
    private var currentDateKey: String {
       let dateFormatter = DateFormatter()
       dateFormatter.dateFormat = "yyyy-MM-dd"
       return dateFormatter.string(from: Date())
    }
    
    var clearKeystrokesDaily: Bool {
        get {
            UserDefaults.standard.bool(forKey: "clearKeystrokesDaily")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "clearKeystrokesDaily")
        }
    }

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
        self.keystrokesAtBeginningOfInterval = UserDefaults.standard.integer(forKey: "keystrokesToday")
        self.totalKeystrokes = UserDefaults.standard.integer(forKey: "totalKeystrokes")
        self.endpointURL = UserDefaults.standard.string(forKey: updateEndpointURIKey) ?? ""
        self.keystrokeData = Array(repeating: 0, count: updateInterval * updatePrecision)
        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Disable App Nap
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Application counts user input data in the background")
        
        // Create a status item and set its properties
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let fontSize: CGFloat = 14.0
            let font = NSFont.systemFont(ofSize: fontSize)
            button.font = font
            updateKeystrokesCount()

            if let font = button.font {
                let offset = -(font.capHeight - font.xHeight) / 2 + 1.0
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
        
        // If sending updates is enabled start timer to send update data after every interval
        if UserDefaults.standard.bool(forKey: self.sendingUpdatesEnabledKey) {
            setupTimeIndexIncrementer()
        }
    }
    
    func updateKeystrokesCount() {
        if let button = statusItem.button {
            button.title = "\(keystrokeCount) keystrokes"

            if let font = button.font {
                let offset = -(font.capHeight - font.xHeight) / 2 + 1.0
                button.attributedTitle = NSAttributedString(
                    string: "\(keystrokeCount) keystrokes",
                    attributes: [NSAttributedString.Key.baselineOffset: offset]
                )
            }
        }
    }
    
    func sendKeystrokeData(keyStrokeArray: [Int], keystrokesAtBeginningOfInterval: Int) {
        // Get the current date and time
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let currentDateTime = dateFormatter.string(from: Date())

        // Create a KeystrokeDataObject
        let keystrokeObject = KeystrokeDataObject(
            timestamp: currentDateTime,
            intervalData: keyStrokeArray,
            keystrokeCountBefore: keystrokesAtBeginningOfInterval, // the number of keystokes that we were at at the beginning of the interval
            keystrokeCountAfter: self.keystrokeCount,
            intervalLength: self.updateInterval,
            updatePrecision: self.updatePrecision // todo logic needs to be added to change update precision and store it in UserDefaults
        )

        // Convert the object to JSON data
        guard let jsonData = try? JSONEncoder().encode(keystrokeObject) else {
            print("Error converting object to JSON data.")
            return
        }

        // Create the URL
        guard let url = URL(string: endpointURL) else {
            print("Invalid URL.")
            return
        }

        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Create and configure the URLSession
        let session = URLSession.shared

        // Create the data task
        let task = session.dataTask(with: request) { (data, response, error) in
            // Handle the response
            if let error = error {
                print("Error sending data: \(error.localizedDescription)")
            } else if let data = data {
                // Handle the response data if needed
                let responseData = String(data: data, encoding: .utf8)
                print("Response data: \(responseData ?? "No data")")
            }
        }

        // Start the data task
        task.resume()
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

        // If sendUpdatesEnabled is true, update the keystroke data
        if UserDefaults.standard.bool(forKey: self.sendingUpdatesEnabledKey) {
            // Increment the keystrokeData at the current time index
            self.keystrokeData[self.currentTimeIndex] += 1
        }

        // Check if it's a new day
        if clearKeystrokesDaily {
            if let lastDate = UserDefaults.standard.string(forKey: "lastDate") {
                if lastDate != currentDateKey {
                    // Store in keystroke history
                    let keystrokesHistoryKey = "keystrokesHistory_\(currentDateKey)"
                    let dailyKeystrokes = UserDefaults.standard.integer(forKey: "keystrokesToday")
                    UserDefaults.standard.set(dailyKeystrokes, forKey: keystrokesHistoryKey)

                    // Reset daily keystrokes count
                    keystrokeCount = 0
                    UserDefaults.standard.set(currentDateKey, forKey: "lastDate")
                }
            } else {
                UserDefaults.standard.set(currentDateKey, forKey: "lastDate")
            }
        }
    }
    
    func setupTimeIndexIncrementer() {
        // Create a timer that calls the incrementTimeIndex method [updatePrecision] times per second
        let timer = Timer.scheduledTimer(timeInterval: 1.0/Double(updatePrecision), target: self, selector: #selector(incrementTimeIndex), userInfo: nil, repeats: true)
        
        // Run the timer on the current run loop
        RunLoop.current.add(timer, forMode: .common)
    }
    
    @objc func incrementTimeIndex() {
        // Increment currentTimeIndex
        currentTimeIndex += 1
        
        // Reset currentTimeIndex to 0 when it reaches limit value and send the keystroke data
        if currentTimeIndex == Int(Double(updateInterval)*Double(updatePrecision)) {
            // send the data and reset the values
            sendKeystrokeData(keyStrokeArray: keystrokeData, keystrokesAtBeginningOfInterval: keystrokesAtBeginningOfInterval)
            keystrokesAtBeginningOfInterval = self.keystrokeCount // set the value at the beginning of the interval again
            keystrokeData = Array(repeating: 0, count: updateInterval*updatePrecision) // create array of zeros for the interval. Array length is (how many seconds our intervals are)*(how many times per second we detect keystrokes)
            currentTimeIndex = 0
        }

        // Uncommment print statement for timer increment debugging
        // print("Timestamp: \(Date()) - Current Time Index: \(currentTimeIndex)")
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
    enum NavigationItem: Hashable {
        case settings, keystrokeHistory
    }

    @State private var selectedItem: NavigationItem? = .settings
    @State private var endpointURL = ""
    @State private var updateInterval = 0
    @State private var statusBarInfoSelection = 0
    @State private var clearKeystrokesDaily = false
    @EnvironmentObject var appDelegate: AppDelegate

    var body: some View {
        NavigationView {
            List {
                NavigationLink(
                    destination: LazyView(SettingsView()),
                    tag: .settings,
                    selection: $selectedItem
                ) {
                    Label("Settings", systemImage: "gearshape")
                }
                .padding()
                .frame(height: 15) // Adjust the height of the navigation items

                NavigationLink(
                    destination: LazyView(KeystrokeHistoryView()),
                    tag: .keystrokeHistory,
                    selection: $selectedItem
                ) {
                    Label("History", systemImage: "chart.bar.fill") // Shorten the label
                }
                .padding()
                .frame(height: 15) // Adjust the height of the navigation items
            }
            .listStyle(SidebarListStyle())

            // Main content
            VStack(alignment: .leading, spacing: 10) {
                switch selectedItem {
                case .settings:
                    SettingsView()
                case .keystrokeHistory:
                    KeystrokeHistoryView()
                default:
                    EmptyView()
                }
            }
            .padding(15)
            .frame(minWidth: 100,  maxWidth: 300, minHeight: 450)
            .padding()
        }
        .frame(minWidth: 500, maxWidth: 700, minHeight: 600)
    }
}

struct SettingsView: View {
    @State private var endpointURL = UserDefaults.standard.string(forKey: "updateEndpointURI") ?? ""
    @State private var updateIntervalStr = UserDefaults.standard.string(forKey: "updateInterval") ?? "30"
    @State private var statusBarInfoSelection = 0
    @State private var clearKeystrokesDaily = false
    @EnvironmentObject var appDelegate: AppDelegate
    
    // Validation for sending updates inputs
    @State private var sendUpdatesEnabled = UserDefaults.standard.bool(forKey: "sendingUpdatesEnabled") ?? false
    @State private var sendUpdatesButtonDisabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Display the keystroke history
            Text("Settings")
                .font(.title)
                .foregroundColor(.blue)
            
            // Send updates to
            GroupBox(label: Text("Send updates to").font(.headline)) {
                VStack(alignment: .leading, spacing: 5) {
                    // Endpoint URI
                    HStack {
                        Text("Endpoint URI")
                        Spacer()
                    }
                    TextField("http://your/api/url", text: $endpointURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(sendUpdatesEnabled)
                        .onChange(of: endpointURL) { newValue in
                            updateEndpointChanged(newValue)
                        }

                    // Update Interval
                    HStack {
                        Text("Update Interval")
                        Spacer()
                        Text("seconds")
                            .foregroundColor(.secondary)
                            .padding(.trailing, 5)
                    }
                    TextField("30", text: $updateIntervalStr)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(sendUpdatesEnabled)
                        .onChange(of: updateIntervalStr) { newValue in
                            updateIntervalChanged(newValue)
                        }

                    // Send Keystroke Updates Button
                    Button(action: {
                        sendUpdatesButtonPressed()
                    }) {
                        Text(sendUpdatesEnabled ? "Disable Send Updates" : "Enable Send Updates")
                    }
                    .padding(.top, 5)
                    .disabled(sendUpdatesButtonDisabled)

                    // Display reason for button being disabled
                    if !sendUpdatesEnabled {
                        Text(disabledButtonText())
                            .foregroundColor(.gray)
                            .padding(.top, 5)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: 300)
            .onAppear {
                // Initialize sendUpdatesButtonDisabled when the view appears
                sendUpdatesButtonDisabled = !areSendUpdatesInputsValid()
            }

            // Status bar info
            GroupBox(label: Text("Status bar info").font(.headline)) {
                VStack(alignment: .leading, spacing: 5) {
                    RadioButtonGroup(items: ["Keystrokes from today", "All-time keystrokes"], selected: $statusBarInfoSelection)
                }
                .padding(8)
            }

            // Keystroke stats
            GroupBox(label: Text("Keystroke stats").font(.headline)) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("All-time keystrokes: \(appDelegate.totalKeystrokes)")
                    Text("Keystrokes today: \(appDelegate.keystrokeCount)")
                }
                .padding(8)
            }

            // Other settings
            GroupBox(label: Text("Other settings").font(.headline)) {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("Store daily keystrokes", isOn: $appDelegate.clearKeystrokesDaily)
                    Button("Delete all keystroke data") {
                        // Handle delete action
                        clearAllKeystrokeData()
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(15)
        .frame(minWidth: 100, maxWidth: 400, minHeight: 450)
        .padding()
    }
    
    func clearAllKeystrokeData() {
        // Display confirmation modal
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to clear all keystroke data?"
        alert.informativeText = "This action cannot be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear All")
        let response = alert.runModal()

        if response == .alertSecondButtonReturn {
            // Clear all keystroke data
            UserDefaults.standard.removeObject(forKey: "keystrokesToday")
            UserDefaults.standard.removeObject(forKey: "lastDate")
            UserDefaults.standard.removeObject(forKey: "totalKeystrokes")
            UserDefaults.standard.removeObject(forKey: "clearKeystrokesDaily")

            // Clear keystroke history
            let historyKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("keystrokesHistory_") }
            for key in historyKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
            
            // Update local variables
            appDelegate.keystrokeCount = 0
            appDelegate.totalKeystrokes = 0

            // Display success message
            displaySuccess("Keystroke Data  Cleared Successfully")
        }
    }
    
    func updateEndpointChanged(_ newValue: String) {
        UserDefaults.standard.set(newValue, forKey: "updateEndpointURI")
        updateSendUpdatesButtonDisabled()
    }

    func updateIntervalChanged(_ newValue: String) {
        UserDefaults.standard.set(newValue, forKey: "updateInterval")
        updateSendUpdatesButtonDisabled()
    }

    func sendUpdatesButtonPressed() {
        sendUpdatesEnabled.toggle()
        UserDefaults.standard.set(sendUpdatesEnabled, forKey: "sendingUpdatesEnabled")
        updateSendUpdatesButtonDisabled()
    }

    func updateSendUpdatesButtonDisabled() {
        sendUpdatesButtonDisabled = !areSendUpdatesInputsValid()
    }
    
    func areSendUpdatesInputsValid() -> Bool {
        let validEndpoint = isValidEndpoint(endpointURL)
        let validInterval = Int(updateIntervalStr) ?? 0 > 0
        return validEndpoint && validInterval
    }
    
    func isValidEndpoint(_ endpoint: String) -> Bool {
        return endpoint.lowercased().hasPrefix("http://") || endpoint.lowercased().hasPrefix("https://")
    }
    
    func disabledButtonText() -> String {
        if !isValidEndpoint(endpointURL) && !(Int(updateIntervalStr) ?? 0 > 0) {
            return "Missing values for sending updates"
        } else if !isValidEndpoint(endpointURL) {
            return "Valid HTTP/HTTPS endpoint required."
        } else {
            return "Update interval must be an positive integer"
        }
    }
    
    // Display success message in an alert
    func displaySuccess(_ message: String) {
        let successAlert = NSAlert()
        successAlert.messageText = message
        successAlert.alertStyle = .informational
        successAlert.addButton(withTitle: "OK")
        successAlert.runModal()
    }
    
    // Display error message in an alert
    func displayError(_ message: String) {
        let errorAlert = NSAlert()
        errorAlert.messageText = message
        errorAlert.alertStyle = .critical
        errorAlert.addButton(withTitle: "OK")
        errorAlert.runModal()
    }
}

struct KeystrokeHistoryView: View {
    var body: some View {
        // Display the keystroke history
        Text("Keystroke History")
            .font(.title)
            .foregroundColor(.blue)
            .padding(.top, 20)

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let todayHistory = getTodayKeystrokeHistory() {
                    Text(todayHistory)
                }

                ForEach(getKeystrokeHistory(), id: \.self) { historyEntry in
                    Text(historyEntry)
                }

                if getKeystrokeHistory().isEmpty && getTodayKeystrokeHistory() == nil {
                    Text("No keystroke history yet.")
                        .padding()
                }
            }
        }
    }
    
    func getTodayKeystrokeHistory() -> String? {
        let currentDateKey = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        guard let todayKeystrokes = UserDefaults.standard.value(forKey: "keystrokesHistory_\(currentDateKey)") as? Int else {
            return nil
        }

        return "\(currentDateKey): \(todayKeystrokes) keystrokes"
    }

    func getKeystrokeHistory() -> [String] {
        var history: [String] = []

        // Fetch keystroke history from UserDefaults
        let historyKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("keystrokesHistory_") }
        for key in historyKeys {
            if let keystrokes = UserDefaults.standard.value(forKey: key) as? Int {
                let dateString = key.replacingOccurrences(of: "keystrokesHistory_", with: "")
                let entry = "\(dateString): \(keystrokes) keystrokes"
                history.append(entry)
            }
        }

        return history
    }

    func getDateFromHistoryKey(_ key: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = key.replacingOccurrences(of: "keystrokesHistory_", with: "")
        return dateFormatter.date(from: dateString)
    }

    func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d"
        return dateFormatter.string(from: date)
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

struct KeystrokeDataObject: Codable {
    let timestamp: String
    let intervalData: [Int]
    let keystrokeCountBefore: Int
    let keystrokeCountAfter: Int
    let intervalLength: Int
    let updatePrecision: Int
}
