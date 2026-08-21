import SwiftUI
import simd

/// The centre of the app after onboarding.
///
/// The layout deliberately does not scroll. The mountain owns a drag gesture,
/// and a scroll view wrapped around it would spend the user's first week
/// fighting them for the same finger. Everything is sized to fit one viewport
/// instead, with the mountain taking whatever height is left over.
struct MountainHomeScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(MountainSceneController.self) private var scene
    @Environment(EnvironmentDirector.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var camera: MountainCameraState
    /// Owned by the shell so the entrance plays once per launch, not once per
    /// visit to the Home tab.
    @Binding var hasPlayedEntrance: Bool

    @State private var greetingShown = false
    @State private var flex: CGFloat = 1
    @State private var selectedWeek: WeekPin?
    @State private var isEditingSchedule = false
    @State private var isConfirmingVerify = false

    private var snapshot: JourneySnapshot { JourneySnapshot.make(from: store) }
    private var status: DayStatus { DayStatus.current(store: store) }

    var body: some View {
        // Derived once per render: every figure below comes from the same
        // snapshot, so the mountain and the numbers can never disagree.
        let snapshot = self.snapshot

        return GeometryReader { proxy in
            let compact = proxy.size.height < 720

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 22)
                    .padding(.bottom, compact ? 6 : 10)

                greeting(compact: compact)
                    .padding(.horizontal, 22)

                mountainCard(compact: compact, snapshot: snapshot)
                    .padding(.horizontal, 14)
                    .padding(.top, compact ? 10 : 14)

                statsCard(snapshot)
                    .padding(.horizontal, 14)
                    .padding(.top, compact ? 8 : 12)

                Spacer(minLength: 0)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .task {
            guard !greetingShown else { return }
            // A short, contained entrance: content is interactive almost
            // immediately, and nothing plays a cinematic.
            withAnimation(.easeOut(duration: 0.4)) { greetingShown = true }
            guard !reduceMotion, !hasPlayedEntrance else { return }
            hasPlayedEntrance = true
            try? await Task.sleep(for: .milliseconds(420))
            flexEmoji()
        }
        .sheet(item: $selectedWeek) { pin in
            WeekDetailSheet(pin: pin, photoFileName: photoFileName(for: pin))
        }
        .sheet(isPresented: $isEditingSchedule) {
            ScheduleEditSheet()
        }
        .confirmationDialog(
            "Log today's session?",
            isPresented: $isConfirmingVerify,
            titleVisibility: .visible
        ) {
            Button("Yes, I trained today") {
                store.markWorkoutVerified()
                Haptics.commit()
                scene.celebrateVerifiedWorkout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This marks the session on your mountain.")
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack {
            Text("GymLock")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)

            Spacer()

            Button {
                Haptics.tap()
                isEditingSchedule = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)

                    if status.isUrgent {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: -4, y: 4)
                    }
                }
            }
            .accessibilityLabel(status.isUrgent ? "Notifications, one unread" : "Notifications")
        }
    }

    private func greeting(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("hey, \(store.greetingName)!")
                    .font(.system(size: compact ? 30 : 34, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("💪")
                    .font(.system(size: compact ? 26 : 30))
                    .scaleEffect(flex)
                    .rotationEffect(.degrees(Double(flex - 1) * 90))
            }

            Text("show up, and your weekly progress\nmoves up the mountain.")
                .font(.system(size: compact ? 13 : 14, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(greetingShown ? 1 : 0)
        .offset(y: greetingShown || reduceMotion ? 0 : 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hey \(store.greetingName). Show up, and your weekly progress moves up the mountain.")
    }

    /// One restrained flex when Home first settles. Never repeats.
    private func flexEmoji() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) { flex = 1.08 }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.75).delay(0.22)) { flex = 1 }
    }

    // MARK: - Mountain

    /// Day 0 shows the capture from onboarding; later weeks show their own
    /// check-in photo. Weeks without one show nothing at all.
    private func photoFileName(for pin: WeekPin) -> String? {
        if pin.isStart {
            guard let media = store.profile.day0Media, media.kind == .photo else { return nil }
            return media.fileName
        }
        return store.journey.weekPhotos[pin.id]
    }

    private func mountainCard(compact: Bool, snapshot: JourneySnapshot) -> some View {
        ZStack(alignment: .top) {
            MountainView(
                spec: snapshot.spec,
                pins: snapshot.pins,
                onSelectWeek: { selectedWeek = $0 },
                camera: $camera
            )

            VStack {
                HStack(alignment: .top) {
                    hintChip
                    Spacer(minLength: 8)
                    statusChip
                }
                .padding(12)

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    if environment.canOfferWeather {
                        weatherPrompt
                    }
                    Spacer(minLength: 8)
                    zoomControls(snapshot)
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 330 : 400)
        .clipShape(.rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 16, y: 6)
        .task(id: environment.state) {
            scene.setEnvironment(environment.state)
        }
    }

    private var hintChip: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Pinch to zoom", systemImage: "hand.draw")
                .font(.system(size: 10, weight: .semibold))
            Text("Drag to explore your path")
                .font(.system(size: 9, weight: .medium))
                .padding(.leading, 17)
        }
        .foregroundStyle(chipInk.opacity(0.75))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(chipBackground, in: .rect(cornerRadius: 12))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The one contextual line that changes with the user's state.
    private var statusChip: some View {
        Button {
            switch status {
            case .noSchedule:
                isEditingSchedule = true
            case .timeToGo:
                Haptics.medium()
                store.commitToToday()
            case .lockedIn:
                isConfirmingVerify = true
            default:
                isConfirmingVerify = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(statusTint)

                VStack(alignment: .leading, spacing: 0) {
                    Text(status.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(chipInk)
                    Text(status.detail)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(statusTint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(chipBackground, in: .capsule)
            .overlay {
                Capsule().strokeBorder(statusTint.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.title) \(status.detail)")
    }

    private var statusTint: Color {
        if status.isPositive { return Color(red: 0.17, green: 0.56, blue: 0.36) }
        if status.isUrgent { return Theme.accent }
        return scene.palette.prefersDarkChrome ? Color.white.opacity(0.7) : Theme.inkSecondary
    }

    private var chipInk: Color {
        scene.palette.prefersDarkChrome ? .white : Theme.ink
    }

    private var chipBackground: Color {
        scene.palette.prefersDarkChrome ? Color.black.opacity(0.5) : Color.white.opacity(0.85)
    }

    private var weatherPrompt: some View {
        Button {
            Haptics.tap()
            environment.requestWeatherAccess()
        } label: {
            Label("Enable local weather", systemImage: "cloud.sun")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(chipInk.opacity(0.8))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(chipBackground, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Lets the mountain match the weather where you are.")
    }

    /// Whether the user has wandered far enough that finding their way back is
    /// worth a button. They are never snapped back automatically.
    private func isCameraOffCentre(_ spec: MountainWorldSpec) -> Bool {
        guard scene.phase == .ready else { return false }
        let home = MountainCameraFraming.initial(for: scene, spec: spec)
        return simd_distance(camera.target, home.target) > 34
            || abs(camera.yaw - home.yaw) > 0.20
            || abs(camera.distance - home.distance) > 58
    }

    private func zoomControls(_ snapshot: JourneySnapshot) -> some View {
        VStack(spacing: 1) {
            if isCameraOffCentre(snapshot.spec) {
                Button {
                    Haptics.tap()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) {
                        camera = MountainCameraFraming.initial(for: scene, spec: snapshot.spec)
                    }
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recentre on your current progress")

                Rectangle().fill(Theme.border).frame(height: 1)
            }

            zoomButton("plus", delta: 0.78)
            Rectangle().fill(Theme.border).frame(height: 1)
            zoomButton("minus", delta: 1.28)
        }
        .animation(.easeInOut(duration: 0.2), value: isCameraOffCentre(snapshot.spec))
        .frame(width: 32)
        .background(chipBackground, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    private func zoomButton(_ icon: String, delta: Float) -> some View {
        Button {
            Haptics.tap()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                var next = camera
                next.distance *= delta
                next.clamp()
                camera = next
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(chipInk.opacity(0.8))
                .frame(width: 32, height: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon == "plus" ? "Zoom in" : "Zoom out")
    }

    // MARK: - Stats

    private func statsCard(_ snapshot: JourneySnapshot) -> some View {
        VStack(spacing: 0) {
            StreakStatsRow(
                streak: snapshot.streak,
                missedWeeks: snapshot.missedWeeks,
                nextCheckIn: snapshot.nextCheckInLabel
            )

            if !snapshot.hasSchedule {
                Divider().overlay(Theme.border)

                Button {
                    Haptics.tap()
                    isEditingSchedule = true
                } label: {
                    HStack(spacing: 6) {
                        Text("No GymLock scheduled")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        Text("Set schedule")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.surface, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
    }
}

/// Tapping a checkpoint opens its week.
struct WeekDetailSheet: View {
    let pin: WeekPin
    let photoFileName: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pin.title.lowercased())
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(pin.detail.lowercased())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(pin.state == .missed ? Theme.inkSecondary : Theme.accent)
                }

                if pin.state != .upcoming {
                    HStack(spacing: 10) {
                        ForEach(0..<max(pin.planned, 1), id: \.self) { index in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index < pin.verified ? Theme.accent : Theme.surfaceMuted)
                                .frame(height: 34)
                        }
                    }
                    .accessibilityLabel("\(pin.verified) of \(pin.planned) sessions verified")
                }

                // Photos only appear where one exists. No empty avatar slots.
                if let photoFileName,
                   let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
                       .first?.appendingPathComponent(photoFileName),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 220)
                        .clipShape(.rect(cornerRadius: 18))
                        .accessibilityLabel("Your progress photo for \(pin.title)")
                }

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationContentInteraction(.scrolls)
        .tint(Theme.accent)
    }

    /// Missed weeks are never framed as damage. The route goes round the rock.
    private var message: String {
        switch pin.state {
        case .start: "this is where you started. everything above it is yours."
        case .completed: "every planned session that week was verified."
        case .partial: "not the full week, but not nothing. it counts."
        case .missed: "this one didn't happen. the trail continues past it — nothing was lost."
        case .current: "you're here. \(pin.verified) of \(pin.planned) done so far."
        case .upcoming: "not here yet."
        }
    }
}
