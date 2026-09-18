//
//  kivoApp.swift
//  kivo
//
//  Created by Thawatchai Chumsook on 18/09/2026.
//

import SwiftUI
import SwiftData

@main
struct kivoApp: App {

    var sharedModelContainer: ModelContainer = {

        let schema = Schema([
            Item.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {

        WindowGroup {
            ContentView()
        }
        // Without this SwiftUI picks its own opening size from the content,
        // which on a split view comes out far larger than the dashboard
        // needs and leaves the tiles stranded across a wide, empty frame.
        // This is the size the layout is designed around.
        .defaultSize(width: 1000, height: 660)
        .windowResizability(.contentMinSize)
        .modelContainer(sharedModelContainer)

        // Declaring this scene is what adds Kivo ▸ Settings… (⌘,) to the
        // app menu — the native home for settings on macOS, and the reason
        // the window doesn't need a gear of its own.
        Settings {
            SettingsView()
        }
    }
}
