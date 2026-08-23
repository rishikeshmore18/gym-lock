import SwiftUI

/// The mission screen: one tiny physical action between "I'm going" and the
/// countdown.
///
/// The mission is not exercise and it is not a test. It is a way of getting the
/// body out of the position it was arguing from, which is why every option takes
/// under a minute and why "another mission" is permanently on screen. A user who
/// cannot complete the mission they were given must never be stuck — they have
/// already committed, and the app's job from here is to help.
struct ActivationMissionView: View {
    let session: GymSession
    let onComplete: () -> Void
    let onChoose: (ActivationMissionType) -> Void
    let onReroll: (Set<MissionCapability>) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @Environment(AppStore.self) private var store

    @State private var camera = MissionCameraModel()
    @State private var motion = MotionMissionMonitor()
    @State private var speech = SpeechMissionVerifier()
    @State private var isRunning = false

    /// What this device can honestly verify right now.
    private var capabilities: Set<MissionCapability> {
        var set: Set<MissionCapability> = []
        if camera.canVerify { set.insert(.camera) }
        if motion.canVerify { set.insert(.motion) }
        if speech.canVerify { set.insert(.speech) }
        // Never empty: the walk-to-door fallback needs only the pedometer, and
        // an empty pool would leave the user staring at nothing.
        if set.isEmpty { set.insert(.motion) }
        return set
    }

    private var mission: ActivationMissionType {
        session.mission ?? .universalFallback
    }

    /// Two alternatives to show under the primary card.
    private var alternatives: [ActivationMissionType] {
        Array(
            ActivationMissionType.candidates(
                available: capabilities,
                excluding: mission,
                allowingOwnershipMissions: store.usesGymBag
            )
            .prefix(2)
        )
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(
                    trailingTitle: "Cancel",
                    trailingAction: onCancel,
                    leadingSymbol: "bolt.fill"
                )

                ScrollView {
                    VStack(spacing: 20) {
                        hero
                        primaryCard
                        if !alternatives.isEmpty { alternativesSection }
                        escapeHatch
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task {
            camera.refreshAvailability()
            motion.refreshAvailability()
            await speech.refreshAvailability()
        }
        .fullScreenCover(isPresented: $isRunning) {
            MissionRunnerView(
                mission: mission,
                phrase: session.mirrorPhrase,
                camera: camera,
                motion: motion,
                speech: speech,
                onVerified: {
                    isRunning = false
                    onComplete()
                },
                onAnotherMission: {
                    isRunning = false
                    onReroll(capabilities)
                },
                onDismiss: { isRunning = false }
            )
        }
    }

    // MARK: - Pieces

    private var hero: some View {
        VStack(spacing: 14) {
            HaloedGlyph(systemName: "lock.fill", size: 84, isPulsing: true)
                .frame(height: 165)

            VStack(spacing: 6) {
                Text("mission to start moving")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                Text("one small thing, then the clock starts.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The mission being offered, with its own start action.
    private var primaryCard: some View {
        Button {
            Haptics.tap()
            isRunning = true
        } label: {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: mission.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            LinearGradient(
                                colors: [Theme.accentWarm, Theme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: .circle
                        )
                        .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 4)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(mission.title)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)

                        Text(mission.subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Label(
                        "about \(mission.estimatedSeconds) sec",
                        systemImage: "clock"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)

                    Spacer()

                    Text("start")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Theme.accent, in: .capsule)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1.5)
        }
    }

    private var alternativesSection: some View {
        VStack(spacing: 10) {
            MorningSectionLabel(title: "or choose another")

            ForEach(alternatives) { option in
                MorningChoiceRow(
                    title: option.title,
                    subtitle: option.subtitle,
                    systemImage: option.icon
                ) {
                    onChoose(option)
                }
            }
        }
    }

    /// Always present. An accessibility need, a dead sensor, or simply a bad
    /// morning must not be able to strand someone who already said yes.
    private var escapeHatch: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                onReroll(capabilities)
            } label: {
                Label("another mission", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            Button {
                Haptics.tap()
                onSkip()
            } label: {
                Text("skip and start my window")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.top, 4)
    }
}
