//
//  ContentView.swift
//  macos-keystroke-tracker
//
//  Created by Marcus DelVecchio on 2023-11-15.
//

import SwiftUI

struct ContentView: View {
    @State private var keystrokesToday = 0
    @State private var totalKeystrokes = 0
    @State private var keystrokeData = []
    
    // variables form app storage
    @AppStorage("updateInterval") var updateInterval = 60
    @AppStorage("updateLocation") var updateLocation = ""
    
    var body: some View {
        VStack {
            HStack(alignment: .center) {
                 Text("send updates every ")
            }
            HStack(alignment: .center) {
                 Text("send updates to ")
            }
            HStack(alignment: .center) {
                 Text("send updates to ")
            }
        }
        .padding()
    }
    
    func saveData(data: Array<Int>){
        if !updateLocation.isEmpty {
            // send data to api
            
        }
        
        // save data to local storage
    }
}

struct InfoView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 200, height: 200)
    }
}

struct Previews_ContentView_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}

struct Previews_ContentView_Previews_2: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}

struct Previews_ContentView_Previews_3: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}
