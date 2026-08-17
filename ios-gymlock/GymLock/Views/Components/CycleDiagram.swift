import SwiftUI

/// The cyclical loop the user is stuck in: twelve nodes on a dashed ring, a
/// hesitant figure at the centre, and a travelling highlight that makes the
/// trap legible without a single word of explanation.
struct CycleDiagram: View {
    /// Index of the node currently highlighted, or `nil` for none.
    let activeNodeIndex: Int?
    /// 0...1 draw-on progress for the ring and its nodes.
    let revealProgress: CGFloat

    private let nodes = ProblemCycle.nodes
    private let labelWidth: CGFloat = 74

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let ringRadius = size * 0.30
            let labelRadius = size * 0.385

            ZStack {
                innerRings(center: center, ringRadius: ringRadius)
                dashedRing(center: center, radius: ringRadius)
                centrepiece(center: center, ringRadius: ringRadius)

                ForEach(Array(nodes.enumerated()), id: \.element.id) { offset, node in
                    let angle = angleRadians(for: offset)
                    let isActive = offset == activeNodeIndex
                    let appeared = revealProgress >= nodeThreshold(offset)

                    nodeDot(isActive: isActive)
                        .position(
                            x: center.x + cos(angle) * ringRadius,
                            y: center.y + sin(angle) * ringRadius
                        )
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.5)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: appeared)

                    nodeLabel(node.label, isActive: isActive)
                        .position(
                            x: clampedLabelX(
                                center.x + cos(angle) * labelRadius,
                                containerWidth: proxy.size.width
                            ),
                            y: center.y + sin(angle) * labelRadius
                        )
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.35), value: appeared)
                }
            }
        }
        .dynamicTypeSize(.xSmall ... .large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "A loop diagram of twelve linked problems with a hesitant person at the centre thinking tomorrow will be better."
        )
    }

    // MARK: - Ring

    private func dashedRing(center: CGPoint, radius: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: revealProgress)
            .stroke(
                Theme.inkTertiary.opacity(0.55),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 7])
            )
            .rotationEffect(.degrees(-90))
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
    }

    private func innerRings(center: CGPoint, ringRadius: CGFloat) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.border, lineWidth: 1)
                .frame(width: ringRadius * 1.42, height: ringRadius * 1.42)
            Circle()
                .strokeBorder(Theme.border.opacity(0.6), lineWidth: 1)
                .frame(width: ringRadius * 1.62, height: ringRadius * 1.62)
        }
        .position(center)
        .opacity(revealProgress > 0.5 ? 1 : 0)
        .animation(.easeOut(duration: 0.5), value: revealProgress > 0.5)
    }

    // MARK: - Nodes

    private func nodeDot(isActive: Bool) -> some View {
        Circle()
            .fill(isActive ? Theme.accent : Theme.canvas)
            .frame(width: isActive ? 17 : 13, height: isActive ? 17 : 13)
            .overlay {
                Circle().strokeBorder(Theme.accent, lineWidth: 2.5)
            }
            .overlay {
                Circle()
                    .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 6)
                    .scaleEffect(isActive ? 1.9 : 1)
                    .opacity(isActive ? 1 : 0)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }

    private func nodeLabel(_ text: String, isActive: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: isActive ? .bold : .medium))
            .foregroundStyle(isActive ? Theme.accent : Theme.inkSecondary)
            .multilineTextAlignment(.center)
            .lineSpacing(1)
            .frame(width: labelWidth)
            .animation(Theme.stateChange, value: isActive)
    }

    // MARK: - Centre

    private func centrepiece(center: CGPoint, ringRadius: CGFloat) -> some View {
        ZStack {
            Image("person_thinking_pose")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: ringRadius * 1.14, height: ringRadius * 1.14)
                .offset(y: ringRadius * 0.16)

            thoughtBubble
                .offset(x: ringRadius * 0.40, y: -ringRadius * 0.54)
        }
        .position(center)
        .opacity(revealProgress > 0.25 ? 1 : 0)
        .animation(.easeOut(duration: 0.6), value: revealProgress > 0.25)
    }

    private var thoughtBubble: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Tomorrow\nwill be better!")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.surface, in: .rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }

            HStack(spacing: 3) {
                Circle().fill(Theme.surface).frame(width: 7, height: 7)
                    .overlay { Circle().strokeBorder(Theme.border, lineWidth: 1) }
                Circle().fill(Theme.surface).frame(width: 4, height: 4)
                    .overlay { Circle().strokeBorder(Theme.border, lineWidth: 1) }
            }
            .padding(.leading, 6)
        }
    }

    // MARK: - Maths

    /// Node 0 sits at the top, the rest run clockwise.
    private func angleRadians(for index: Int) -> CGFloat {
        let degrees = -90.0 + (360.0 / Double(nodes.count)) * Double(index)
        return CGFloat(degrees * .pi / 180)
    }

    /// Staggers node appearance along the ring draw.
    private func nodeThreshold(_ index: Int) -> CGFloat {
        CGFloat(index) / CGFloat(nodes.count) * 0.92
    }

    /// Keeps side labels fully on screen regardless of ring geometry.
    private func clampedLabelX(_ proposed: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let inset = labelWidth / 2 + 2
        return min(max(proposed, inset), containerWidth - inset)
    }
}
