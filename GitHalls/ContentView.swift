//
//  ContentView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            Text("GitHalls")
                .task {
                    let service = GitService()
                    let repoURL = URL(fileURLWithPath:"/Users/erikson.santos/XProjects/GitHalls")
                    do {
                        let changes = try await service.status(at: repoURL)
                        print(changes)
                    }catch{
                        print("Erro \(error)")
                    }
                }
        } detail: {
            Button("Test Git") { testGit() }
            Text("Select an item")
        }
    }
    
    private func testGit() {
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "--version"]
            let pipe = Pipe()
            process.standardOutput = pipe

            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            print(String(decoding: data, as: UTF8.self))
        }
    }

}

#Preview {
    ContentView()
}
