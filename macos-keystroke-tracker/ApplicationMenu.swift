//
//  ApplicationMenu.swift
//  macos-keystroke-tracker
//
//  Created by Marcus DelVecchio on 2023-11-15.
//

import Foundation
import SwiftUI

class ApplicationMenu: NSObject {
    let menu = NSMenu()
    
    func createMenu() -> NSMenu {
        let view = ContentView()
        let topView = NSHostingController(rootView: view)
        topView.view.frame.size = CGSize(width: 200, height: 200)
        
        let customMenuItem = NSMenuItem()
        customMenuItem.view = topView.view
        menu.addItem(customMenuItem)
        menu.addItem(NSMenuItem.separator())
        return menu
    }
}
