import SwiftUI

// MARK: - Header

/// The small wordmark that sits at the top of every morning screen, with an
/// optional escape hatch on the right.
///
/// The trailing action is never destructive-looking and never hidden: at 6:31 in
/// the morning a user must always be able to see the way out of a screen, or
/// they will find it in Settings instead.
struct MorningHeader: View {
    var trailingTitle: String?
    var trailingAction: (() -> Void)?
    var leadingSymbol: String = "lock.fill"

    var body: some View {
        ZStack {
            HStack(spacing: 7) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("GymLock")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }

            if let trailingTitle, let trailingAction {
                HStack {
                    Spacer()
                    Button(trailingTitle) {
                        Haptics.tap()
                        trailingAction()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.top, 6)
    }
}

// MARK: - Hero

/// A symbol inside a white disc, ringed by faint concentric haloes.
///
/// The haloes are what keep a single icon from looking marooned on a large warm
/// canvas. They are drawn at very low opacity and, when `isPulsing`, breathe
/// outward slowly — never fast enough to read as an animation demanding
/// attention.
struct HaloedGlyph: View {
    let systemName: String
    var size: CGFloat = 108
    var tint: Color = Theme.accent
    var isPulsing = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { ring in
                let scale = 1.0 + Double(ring) * 0.42

                Circle()
                    .strokeBorder(tint.opacity(0.16 - Double(ring) * 0.033), lineWidth: 1)
                    .frame(width: size * scale, height: size * scale)
                    .scaleEffect(isExpanded ? 1.05 : 1)
                    .opacity(isExpanded ? 0.7 : 1)
            }

            Circle()
                .fill(Theme.surface)
                .frame(width: size, height: size)
                .shadow(color: tint.opacity(0.14), radius: 22, y: 6)

            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size * 2.3, height: size * 2.3)
        .onChange(of: isPulsing && !reduceMotion, initial: true) { _, active in
            guard active else {
                withAnimation(.easeOut(duration: 0.4)) { isExpanded = false }
                return
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                isExpanded = true
            }
        }
    }
}

/// The four-point spark used as a quiet divider between a headline and its
/// actions.
struct SparkMark: View {
    var size: CGFloat = 22
    var tint: Color = Theme.accentWarm

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(0.4), radius: 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Status pill

/// A small capsule stating a fact, such as "ALARM FIRED 6:30 AM".
struct StatusPill: View {
    let label: String
    var value: String?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(tint)

            if let value {
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Theme.surface, in: .capsule)
        .overlay { Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 1) }
        .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
    }
}

// MARK: - Buttons

/// The primary morning action: a coral bar with an icon disc and a label.
///
/// Wider and taller than the onboarding CTA because these are pressed by someone
/// half awake, often one-handed, sometimes in the dark.
struct MorningPrimaryButton: View {
    let title: String
    var systemImage: String?
    var trailingImage: String? = "arrow.right"
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else { return }
            Haptics.medium()
            action()
        } label: {
            HStack(spacing: 14) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.22), in: .circle)
                }

                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                if let trailingImage {
                    Image(systemName: trailingImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(MorningPrimaryStyle(isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}

private struct MorningPrimaryStyle: ButtonStyle {
    var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                LinearGradient(
                    colors: [Theme.accentWarm, Theme.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: 20)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.4)
            .shadow(
                color: Theme.accent.opacity(isEnabled ? 0.28 : 0),
                radius: configuration.isPressed ? 10 : 18,
                y: configuration.isPressed ? 4 : 8
            )
            .animation(Theme.stateChange, value: configuration.isPressed)
            .animation(Theme.stateChange, value: isEnabled)
    }
}

/// A secondary choice: white card, tinted icon disc, chevron.
struct MorningChoiceRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String
    var tint: Color = Theme.accent
    var trailingImage: String = "chevron.right"
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: trailingImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MorningCardStyle())
    }
}

/// Card press feedback: a small dim, no scale, matching the rest of the app.
struct MorningCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Theme.surface.opacity(configuration.isPressed ? 0.86 : 1),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
            .animation(Theme.stateChange, value: configuration.isPressed)
    }
}

// MARK: - Section label

/// A quiet all-caps rule with a title, used to separate groups without adding
/// another card.
struct MorningSectionLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.9)
                .foregroundStyle(Theme.inkTertiary)
                .layoutPriority(1)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }
}

// MARK: - Plan summary

/// The three-line plan strip: wake, time to gym, gym by.
///
/// One card rather than four, because four large tiles would make a simple
/// sequence look like a dashboard.
struct PlanSummaryCard: View {
    let wake: TimeOfDay
    let timeToGymMinutes: Int
    let gymBy: TimeOfDay

    var body: some View {
        VStack(spacing: 0) {
            row(label: "wake", value: wake.displayString, icon: "sunrise.fill")
            divider
            row(label: "time to gym", value: "\(timeToGymMinutes) min", icon: "figure.walk.departure")
            divider
            row(label: "gym by", value: gymBy.displayString, icon: "dumbbell.fill", isEmphasised: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .warmCard(radius: 20)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }

    private func row(
        label: String,
        value: String,
        icon: String,
        isEmphasised: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEmphasised ? Theme.accent : Theme.inkTertiary)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)

            Spacer()

            Text(value)
                .font(.system(size: isEmphasised ? 19 : 17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isEmphasised ? Theme.accent : Theme.ink)
        }
        .padding(.vertical, 13)
    }
}

// MARK: - Scaffold

/// The standard morning screen: header, scrolling body, pinned footer.
///
/// The footer sits outside the scroll view so the primary action is always
/// reachable without a scroll, which matters when the screen is being used in a
/// hurry.
struct MorningScreen<Content: View, Footer: View>: View {
    var trailingTitle: String?
    var trailingAction: (() -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                MorningHeader(trailingTitle: trailingTitle, trailingAction: trailingAction)

                ScrollView {
                    content
                        .padding(.horizontal, Theme.pageMargin)
                        .padding(.top, 18)
                        .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)

                footer
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.bottom, 10)
            }
        }
    }
}
