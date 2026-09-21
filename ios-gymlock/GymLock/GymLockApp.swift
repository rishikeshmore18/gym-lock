//
//  GymLockApp.swift
//  GymLock
//
//  Created by Rork on August 17, 2026.
//

import SwiftUI
import UserNotifications

@main
struct GymLockApp: App {
    @State private var store = AppStore()
    /// Owns the morning state machine for the lifetime of the app, so a session
    /// survives the user moving between screens.
    @State private var coordinator = GymSessionCoordinator()
    @State private var alarmPlayer = AlarmSoundPlayer()

    /// Held for the lifetime of the app: `UNUserNotificationCenter` keeps only
    /// a weak reference to its delegate.
    private let notificationDelegate = AlarmNotificationDelegate()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Both of these must happen before the system can deliver a launch
        // notification. Doing it in `.task` is too late for a cold launch from
        // an alarm tap: the response is dropped and the morning never starts.
        UNUserNotificationCenter.current().delegate = notificationDelegate
        AlarmNotificationDelegate.registerCategories()
    }

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
                    guard phase == .active else { return }

                    // Everything that has to recover from time passing while the
                    // app was not running happens here: the shield failsafe, the
                    // shield/session reconciliation, and any workout Health wrote
                    // in the meantime.
                    coordinator.applicationDidBecomeActive()

                    // Re-syncing alarms on every foreground keeps the OS in step
                    // after a timezone change, a reinstall, or an edit made while
                    // suspended. `replaceAll` is idempotent, so this converges
                    // rather than accumulating duplicates.
                    Task { await coordinator.syncAlarms() }
                }
        }
    }
}
