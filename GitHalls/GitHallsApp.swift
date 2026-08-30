//
//  GitHallsApp.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import SwiftUI

@main
struct GitHallsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        Settings {
            JiraSettingsView()
        }
    }
}
