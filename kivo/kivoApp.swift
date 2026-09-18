//
//  kivoApp.swift
//  Kivo
//

import SwiftUI

@main
struct kivoApp: App {

    var body: some Scene {

        WindowGroup {
            ContentView()
        }
        // Without this SwiftUI picks its own opening size from the content,
        // which on a split view comes out far larger than the dashboard
        // needs and leaves the tiles stranded across a wide, empty frame.
        // This is the size the layout is designed around.
        .defaultSize(width: 1000, height: 660)
        // The title bar is empty now, so let the content run under it
        // rather than leaving a grey strip that matches neither the black
        // sidebar nor the near-black page.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        // Declaring this scene is what adds Kivo ▸ Settings… (⌘,) to the
        // app menu — the native home for settings on macOS, and the reason
        // the window doesn't need a gear of its own.
        Settings {
            SettingsView()
        }
    }
}
