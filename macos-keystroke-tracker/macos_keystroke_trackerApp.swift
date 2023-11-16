//
//  macos_keystroke_trackerApp.swift
//  macos-keystroke-tracker
//
//  Created by Marcus DelVecchio on 2023-11-15.
//

import SwiftUI

extension NSEvent {
    var isAKeyDownEvent: Bool {
        return type == .keyDown
    }
}

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

    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // create a status item and set its properties
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // increase the font size
            let fontSize: CGFloat = 14.0 // Change this value to the desired font size
            let font = NSFont.systemFont(ofSize: fontSize)

            button.font = font
            updateKeystrokesCount()

            // adjust the baselineOffset to center the text vertically
            if let font = button.font {
                let offset = -(font.capHeight - font.xHeight) / 2 + 0.6 // adjusting vertical offset of the text
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

        // Register for key events globally
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.keystrokeCount += 1
            self?.updateKeystrokesCount()
        }
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

    @objc func terminateApp() {
        NSEvent.removeMonitor(eventMonitor)
        NSApplication.shared.terminate(self)
    }

    // stub action for a menu item
    @objc func menuItemClicked() {
        print("Menu item clicked")
    }

    // stub action for the Quit menu item
    @objc func quitClicked() {
        NSEvent.removeMonitor(eventMonitor)
        NSApplication.shared.terminate(self)
    }
}
