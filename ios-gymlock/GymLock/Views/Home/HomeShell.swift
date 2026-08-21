import SwiftUI

/// The post-onboarding app shell.
///
/// The mountain scene and its camera live here rather than inside the Home
/// screen, so switching tabs tears the renderer down — stopping all GPU work —
/// while the built world and the user's viewpoint survive untouched. Coming
/// back to Home re-attaches an existing scene instead of rebuilding a mountain.
struct HomeShell: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var scene = MountainSceneController()
    @State private var environment = EnvironmentDirector()
    @State private var camera = MountainCameraState()
    @State private var selection: AppTab = .home
    /// The greeting's one flex belongs to the launch, not to the tab.
    @State private var hasPlayedEntrance = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.ignoresSafeArea()

            Group {
                switch selection {
                case .home:
                    MountainHomeScreen(camera: $camera, hasPlayedEntrance: $hasPlayedEntrance)
                case .alarm:
                    AlarmScreen()
                case .progress:
                    ProgressScreen()
                case .profile:
                    ProfileScreen()
                }
            }
            .transition(.opacity)
            // Keeps content clear of the floating bar and the home indicator.
            .safeAreaPadding(.bottom, 78)

            GymLockTabBar(selection: $selection)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
        }
        .environment(scene)
        .environment(environment)
        .tint(Theme.accent)
        .onAppear {
            environment.start()
            scene.setEnvironment(environment.state, animated: false)
        }
        .onChange(of: selection) { _, tab in
            // The scene only runs while it is on screen.
            scene.setPaused(tab != .home)
        }
        .onChange(of: scenePhase) { _, phase in
            let isActive = phase == .active
            scene.setPaused(!isActive || selection != .home)
            if isActive {
                environment.start()
            } else {
                environment.stop()
            }
        }
    }
}

/// The Alarm destination.
///
/// A status surface for the alarm the user configured during onboarding, not a
/// second configuration flow — the settings already exist and are edited from
/// one place.
struct AlarmScreen: View {
    @Environment(AppStore.self) private var store
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("your alarm goes off fifteen minutes before the window you said you lose.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineSpacing(2)
                        .padding(.bottom, 2)

                    bigTimeCard

                    detailRow(
                        icon: "music.note",
                        title: "sound",
                        value: store.profile.alarmSoundLabel
                    )
                    detailRow(
                        icon: "calendar",
                        title: "days",
                        value: store.schedule.daysSummary
                    )
                    detailRow(
                        icon: "figure.run",
                        title: "gym time",
                        value: store.schedule.gymTime.displayString
                    )

                    if store.profile.wantsNightLock {
                        detailRow(
                            icon: "moon.fill",
                            title: "night lock",
                            value: store.schedule.bedtime.displayString
                        )
                    }

                    Button {
                        Haptics.tap()
                        isEditing = true
                    } label: {
                        Text("edit my locks")
                    }
                    .buttonStyle(PrimaryCTAStyle(isEnabled: true))
                    .padding(.top, 6)
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Alarm")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $isEditing) { ScheduleEditSheet() }
        }
    }

    private var bigTimeCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.profile.alarmTime.displayString)
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text("fifteen minutes before \(store.profile.failureTime.displayString.lowercased())")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .warmCard()
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.11), in: .circle)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.border, lineWidth: 1)
        }
    }
}

/// Journey history in list form.
///
/// Deliberately not a second copy of the 3D scene — one heavy renderer per app
/// is the right number, and a list is the better tool for scanning history.
struct ProgressScreen: View {
    @Environment(AppStore.self) private var store

    private var snapshot: JourneySnapshot { JourneySnapshot.make(from: store) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary

                    if snapshot.pins.isEmpty {
                        emptyState
                    } else {
                        ForEach(snapshot.pins.reversed()) { pin in
                            weekRow(pin)
                        }
                    }
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Progress")
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            summaryCell(value: "\(store.journey.totalVerified)", caption: "sessions")
            Rectangle().fill(Theme.border).frame(width: 1, height: 36)
            summaryCell(value: "\(snapshot.streak)", caption: "day streak")
            Rectangle().fill(Theme.border).frame(width: 1, height: 36)
            summaryCell(value: "\(snapshot.missedWeeks)", caption: "weeks missed")
        }
        .padding(.vertical, 16)
        .warmCard()
    }

    private func summaryCell(value: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("nothing here yet.")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("your first verified session starts the climb.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .warmCard()
    }

    private func weekRow(_ pin: WeekPin) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(rowColour(pin).opacity(pin.state == .completed ? 1 : 0.14))
                    .frame(width: 34, height: 34)
                if pin.state == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                } else if pin.state == .missed {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(white: 0.55))
                } else {
                    Text("\(pin.id + 1)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(rowColour(pin))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(pin.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(pin.detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer()

            if pin.state != .upcoming {
                Text("\(pin.verified)/\(pin.planned)")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pin.accessibilityDescription)
    }

    private func rowColour(_ pin: WeekPin) -> Color {
        switch pin.state {
        case .completed, .partial, .current, .start: Theme.accent
        case .missed, .upcoming: Color(white: 0.55)
        }
    }
}

/// Profile and settings.
struct ProfileScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(EnvironmentDirector.self) private var environment

    @State private var isEditingSchedule = false
    // TEMPORARY (dev only) — remove this and `devRestartSection` below.
    @State private var isConfirmingRestart = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identityCard
                    locksCard
                    environmentCard
                    principleCard
                    devRestartSection
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Profile")
            .sheet(isPresented: $isEditingSchedule) { ScheduleEditSheet() }
        }
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            Text(String(store.greetingName.prefix(1)).uppercased())
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Theme.accent, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.greetingName)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(store.profile.targetWorkoutsPerWeek) gym days a week")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
            }

            Spacer()
        }
        .padding(18)
        .warmCard()
    }

    private var locksCard: some View {
        Button {
            Haptics.tap()
            isEditingSchedule = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(Theme.accent.opacity(0.11), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("your locks")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("\(store.schedule.daysSummary) · \(store.schedule.gymTime.displayString)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(18)
            .warmCard()
        }
        .buttonStyle(PressableRowStyle())
    }

    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("mountain weather")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(environment.state.summary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            Text(
                environment.isUsingLocalTimeOnly
                    ? "using your device clock. turn on location and the mountain will match your real weather."
                    : "your mountain follows the light and weather where you are."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if environment.canOfferWeather {
                Button {
                    Haptics.tap()
                    environment.requestWeatherAccess()
                } label: {
                    Text("enable local weather")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .warmCard()
    }

    private var principleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("no guilt. no streak-shaming.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("miss a week and the trail goes around the rock. it never ends.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: Theme.cardRadius))
    }

    // MARK: - TEMPORARY dev affordance
    // Delete this section before shipping.

    private var devRestartSection: some View {
        VStack(spacing: 10) {
            Button {
                isConfirmingRestart = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text("restart onboarding")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.ink.opacity(0.05), in: .rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(Theme.ink.opacity(0.18))
                )
            }

            Text("dev only — wipes your name, locks and history")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.top, 8)
        .confirmationDialog(
            "Start over as a first-time user?",
            isPresented: $isConfirmingRestart,
            titleVisibility: .visible
        ) {
            Button("Restart onboarding", role: .destructive) {
                Haptics.commit()
                store.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your name, both locks and everything on your mountain.")
        }
    }
}
