//
//  BadgeGalleryView.swift
//  GymLock — Badges
//
//  The badges screen: title, unlocked count + progress bar, and the three sections
//  (Streak, Workout Days, Achievements) in a 3-column grid — exactly the approved layout.
//  Locked badges are gray with a padlock chip. Scrolls a badge into view when asked
//  (so the rank-up can fly into it).
//

import SwiftUI

struct BadgeGalleryView<Accessory: View>: View {
    let unlocked: Set<String>
    /// Each badge's real state, for locked progress and VoiceOver.
    var stateFor: (String) -> BadgeState = { _ in .locked(nil) }
    /// Per-badge pop delays (seconds) for badges that were just unlocked.
    var pops: [String: Double] = [:]
    /// When set, this badge is scrolled to the centre (instantly).
    var focusBadgeId: String? = nil
    var onTap: (BadgeDefinition) -> Void = { _ in }
    /// Optional content under the progress bar (e.g. demo controls).
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title3) private var sectionSize: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var subSize: CGFloat = 15

    /// Three across; two once accessibility sizes leave a third too narrow
    /// for its name.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 3)
    }

    private func card(_ b: BadgeDefinition) -> some View {
        let isUnlocked = unlocked.contains(b.id)
        let state = stateFor(b.id)
        // A badge waiting for its reveal reads as locked until it lands.
        let shown: BadgeState = isUnlocked ? state : (state.isEarned ? .locked(nil) : state)
        return BadgeCardView(
            badge: b,
            unlocked: isUnlocked,
            progress: BadgeCopy.cardProgress(shown.progress),
            accessibilityText: BadgeCopy.accessibilityLabel(b, state: shown),
            popDelay: pops[b.id]
        ) { onTap(b) }
    }

    var body: some View {
        let P = BadgePalette.of(scheme)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(P)
                    ForEach(BadgeGroup.allCases, id: \.self) { g in
                        Text(g.title)
                            .font(.system(size: sectionSize, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                            .tracking(-0.2)
                            .foregroundStyle(P.text)
                            .padding(.top, 24)
                            .padding(.bottom, 10)
                            .padding(.horizontal, 4)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(BadgeCatalog.badges(in: g)) { b in
                                card(b)
                                    .id(b.id)
                            }
                        }
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .background(P.bg.ignoresSafeArea())
            .onChange(of: focusBadgeId) { _, id in
                guard let id else { return }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .onAppear { BadgeImages.preloadAll() }
    }

    @ViewBuilder
    private func header(_ P: BadgePalette) -> some View {
        let count = unlocked.count
        let total = BadgeCatalog.all.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Badges")
                    .font(.system(size: titleSize, weight: .heavy))
                    .tracking(-0.68)
                    .foregroundStyle(P.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                (Text("\(count)").fontWeight(.bold).foregroundColor(P.text) + Text(" / \(total)").foregroundColor(P.sub))
                    .font(.system(size: subSize))
                    .monospacedDigit()
                    .accessibilityLabel(Text("\(count) of \(total) earned"))
            }
            Text("milestones from showing up.")
                .font(.system(size: subSize, weight: .medium))
                .foregroundStyle(P.sub)
                .padding(.top, 2)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(P.line)
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0xD6956A), Color(hex: 0xE6B64F), Color(hex: 0x7CC8FF), Color(hex: 0x9D7DFF)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(count) / CGFloat(total))
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8), value: count)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            .padding(.top, 10)
            .padding(.bottom, 12)
            accessory()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

extension BadgeGalleryView where Accessory == EmptyView {
    init(
        unlocked: Set<String>,
        stateFor: @escaping (String) -> BadgeState = { _ in .locked(nil) },
        pops: [String: Double] = [:],
        focusBadgeId: String? = nil,
        onTap: @escaping (BadgeDefinition) -> Void = { _ in }
    ) {
        self.init(unlocked: unlocked, stateFor: stateFor, pops: pops, focusBadgeId: focusBadgeId, onTap: onTap, accessory: { EmptyView() })
    }
}
