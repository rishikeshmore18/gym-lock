//
//  GymLockApp.swift
//  GymLock
//
//  Created by Rork on August 17, 2026.
//

import SwiftUI

@main
struct GymLockApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
