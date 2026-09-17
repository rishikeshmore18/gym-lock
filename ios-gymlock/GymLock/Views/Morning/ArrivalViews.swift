import SwiftUI

/// The brief moment between "the phone thinks you're at the gym" and "you are".
///
/// Most users should barely register this screen. It exists because entering a
/// geofence is not the same as arriving — a bus stopping outside would otherwise
/// hand somebody their apps back on the way past — so the phone waits a couple
/// of quiet minutes before believing it.
///
/// What the screen deliberately does *not* do is explain any of that. No timer,
/// no countdown, no "dwell check in progress". A number to watch would turn a
/// piece of background diligence into a task, and the user is meant to be
/// walking to a locker room, not supervising their phone.
struct ConfirmingArrivalView: View {
    let session: GymSession
    let gymName: String?
    let onSkipToTrouble: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.accentWash.opacity(0.6), Theme.canvas],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(leadingSymbol: "mappin.and.ellipse")

                Spacer(minLength: 12)

                VStack(spacing: 22) {
                    HaloedGlyph(systemName: "mappin.and.ellipse", size: 96, isPulsing: true)
                        .frame(height: 195)

                    VStack(spacing: 8) {
                        Text("you're here.")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(Theme.ink)

                        if let gymName {
                            Text(gymName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }

                    // Three dots rather than a progress bar: it says "working"
                    // without inviting anyone to watch it finish.
                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Theme.accent.opacity(isPulsing ? 0.85 : 0.28))
                                .frame(width: 7, height: 7)
                                .animation(
                                    reduceMotion
                                        ? nil
                                        : .easeInOut(duration: 0.75)
                                            .repeatForever()
                                            .delay(Double(index) * 0.18),
                                    value: isPulsing
                                )
                        }
                    }

                    Text("confirming arrival…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)

                    Text("you can put your phone away. your apps unlock on their own.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
                .padding(.horizontal, Theme.pageMargin)

                Spacer(minLength: 12)

                Button("having trouble?") {
                    Haptics.tap()
                    onSkipToTrouble()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkTertiary)
                .padding(.bottom, 18)
            }
        }
        .task {
            guard !reduceMotion else { return }
            isPulsing = true
        }
    }
}

// MARK: - Trouble

/// Shown when arrival genuinely could not be established.
///
/// The tone here is the whole point. Technology failed — a basement gym, a bad
/// fix, location switched off — and the user may well be standing on the gym
/// floor right now with their apps locked. Treating that as a missed workout
/// would be both wrong and infuriating.
///
/// So: no blame, no "you didn't go", and three ways forward that all work.
struct ArrivalTroubleView: View {
    let gymName: String?
    let onRetry: () -> Void
    let onConfirmManually: () -> Void
    let onQuickWorkout: () -> Void
    let onRelease: () -> Void

    var body: some View {
        MorningScreen {
            VStack(spacing: 22) {
                HaloedGlyph(systemName: "location.slash.fill", size: 84, tint: Theme.inkSecondary)
                    .frame(height: 168)

                VStack(spacing: 8) {
                    Text("GymLock couldn't confirm your location.")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("that's a phone problem, not a you problem. basements and thick walls do this.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    MorningPrimaryButton(
                        title: "try again",
                        systemImage: "arrow.clockwise",
                        trailingImage: nil
                    ) {
                        onRetry()
                    }

                    MorningChoiceRow(
                        title: gymName.map { "I'm at \($0)" } ?? "I'm at the gym",
                        subtitle: "unlock my apps and count today",
                        systemImage: "checkmark.circle.fill"
                    ) {
                        onConfirmManually()
                    }

                    MorningChoiceRow(
                        title: "quick workout instead",
                        subtitle: "keeps your momentum",
                        systemImage: "house.fill"
                    ) {
                        onQuickWorkout()
                    }

                    MorningChoiceRow(
                        title: "unlock my apps",
                        subtitle: "no visit recorded — nothing held against you",
                        systemImage: "lock.open.fill"
                    ) {
                        onRelease()
                    }
                }

                Text("this isn't recorded as a missed workout.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
            }
        } footer: {
            EmptyView()
        }
    }
}

// MARK: - Arrival success

/// The screen after a confirmed arrival.
///
/// Two facts, stated separately and honestly: the user showed up, and Apple
/// Health either did or did not independently see a workout. The second one is
/// never a failure state — most people lifting weights are not wearing a watch
/// that logs it, and marking them down for that would be punishing them for
/// their hardware.
struct GymArrivedView: View {
    let session: GymSession
    let gymName: String?
    let momentumWeeks: Int
    let gymVisitsThisMonth: Int
    let shieldCapability: ShieldCapability
    let onDone: () -> Void
    /// Opens the Story editor for this morning. The peak of the product is
    /// the one place sharing is worth offering, and it is offered, not pushed:
    /// a text link under the primary action, in the style of "having trouble?".
    var onShare: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.accentWash, Theme.canvas],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(
                    trailingTitle: "Done",
                    trailingAction: onDone,
                    leadingSymbol: "checkmark.seal.fill"
                )

                ScrollView {
                    VStack(spacing: 20) {
                        seal
                        heading
                        unlockCard
                        statusCard
                        statsRow
                    }
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.top, 12)
                    .padding(.bottom, 22)
                }
                .scrollIndicators(.hidden)

                MorningPrimaryButton(title: "go train", systemImage: nil, trailingImage: nil) {
                    onDone()
                }
                .padding(.horizontal, Theme.pageMargin)
                .padding(.bottom, onShare == nil ? 14 : 4)

                if let onShare {
                    Button("share this") {
                        Haptics.tap()
                        onShare()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(minHeight: 36)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Share this morning")
                }
            }
        }
        .task { withAnimation(Theme.settle) { hasAppeared = true } }
    }

    // MARK: - Pieces

    private var seal: some View {
        ZStack {
            Circle()
                .fill(Theme.surface)
                .frame(width: 124, height: 124)
                .shadow(color: Theme.accent.opacity(0.18), radius: 24, y: 8)

            Image(systemName: "checkmark")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.accentWarm, Theme.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.9)
        .opacity(hasAppeared ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text("you made it.")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text(gymName.map { "checked in at \($0)." } ?? "you showed up.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 14)
    }

    /// States exactly what happened to the apps, including in demo mode.
    private var unlockCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(shieldCapability.isReal ? "apps unlocked" : "apps would unlock here")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text(shieldCapability.isReal
                    ? "nothing else to do. go train."
                    : "demo mode — real blocking needs Screen Time approval.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .warmCard(radius: 20)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 16)
    }

    /// The two-line truth: showed up, and whether Health saw anything.
    private var statusCard: some View {
        VStack(spacing: 0) {
            statusRow(
                icon: "figure.walk",
                title: "showed up",
                detail: session.arrivedAt.map { TimeOfDay(from: $0).displayString } ?? "confirmed",
                isConfirmed: true
            )

            Rectangle().fill(Theme.border).frame(height: 1)

            statusRow(
                icon: "heart.fill",
                title: "workout detected",
                detail: session.detectedWorkout?.summary ?? "no workout data",
                isConfirmed: session.workoutDetected
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .warmCard(radius: 20)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 18)
    }

    /// An unconfirmed row is grey and quiet — never a red cross.
    private func statusRow(
        icon: String,
        title: String,
        detail: String,
        isConfirmed: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isConfirmed ? Theme.accent : Theme.inkTertiary)
                .frame(width: 34, height: 34)
                .background(
                    (isConfirmed ? Theme.accent : Theme.inkTertiary).opacity(0.11),
                    in: .circle
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: isConfirmed ? "checkmark" : "minus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isConfirmed ? Theme.accent : Theme.inkTertiary.opacity(0.55))
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(isConfirmed ? detail : "not recorded")")
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(value: "\(momentumWeeks)", label: "week streak", icon: "flame.fill")
            statTile(value: "\(gymVisitsThisMonth)", label: "gym visits", icon: "dumbbell.fill")
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared || reduceMotion ? 0 : 20)
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.accent)

            Text(value)
                .font(.system(size: 30, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .warmCard(radius: 20)
    }
}
