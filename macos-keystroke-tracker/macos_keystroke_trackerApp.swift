//
//  macos_keystroke_trackerApp.swift
//  macos-keystroke-tracker
//
//  Created by Marcus DelVecchio on 2023-11-15.
//

import SwiftUI

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
    
    let menu = ApplicationMenu()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
            // create a status item and set its properties
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem.button {
                
                // increase the font size
                let fontSize: CGFloat = 14.0 // Change this value to the desired font size
                let font = NSFont.systemFont(ofSize: fontSize)
                
                button.font = font
                button.title = "Text App"
                
                // adjust the baselineOffset to center the text vertically
                if let font = button.font {
                    let offset = -(font.capHeight - font.xHeight) / 2 + 0.6 // adjusting vertical offset of the text
                    button.attributedTitle = NSAttributedString(
                        string: "Text App",
                        attributes: [NSAttributedString.Key.baselineOffset: offset]
                    )
                }
            }

            // create a menu with a quit option
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(terminateApp), keyEquivalent: "q"))
            statusItem.menu = menu
        }

    @objc func terminateApp() {
        NSApplication.shared.terminate(self)
    }

    // stub action for a menu item
    @objc func menuItemClicked() {
        print("Menu item clicked")
    }

    // stub action for the Quit menu item
    @objc func quitClicked() {
        NSApplication.shared.terminate(self)
    }
}
