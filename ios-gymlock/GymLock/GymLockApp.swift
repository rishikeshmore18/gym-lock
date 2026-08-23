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
    /// Owns the morning state machine for the lifetime of the app, so a session
    /// survives the user moving between screens.
    @State private var coordinator = GymSessionCoordinator()
    @State private var alarmPlayer = AlarmSoundPlayer()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(coordinator)
                .environment(alarmPlayer)
                .task {
                    coordinator.attach(to: store)
                    await coordinator.syncAlarms()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Re-syncing on every foreground is what keeps the OS in
                    // step after a timezone change, a reinstall, or an edit made
                    // while the app was suspended. `replaceAll` is idempotent,
                    // so this converges rather than accumulating duplicates.
                    guard phase == .active else { return }
                    Task { await coordinator.syncAlarms() }
                }
        }
    }
}
