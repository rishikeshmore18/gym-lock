#if DEBUG
import SwiftUI

/// Previews for the Progress Photos card.
///
/// The photo-count states are the whole risk surface of this component — the
/// layout has to hold at one photo and at a hundred — so each one gets its own
/// preview rather than being reasoned about in the abstract.
///
/// Stacks are previewed with demonstration artwork so they render without any
/// files on disk; the card itself is previewed against a real store backed by
/// a throwaway defaults suite, so previewing can never touch the user's own
/// photo history.

// MARK: - Fixtures

private enum PhotoFixture {
    /// A store with no photos, which is what a new user sees.
    static func emptyStore() -> ProgressPhotoStore {
        ProgressPhotoStore(defaults: scratchDefaults())
    }

    /// Metadata-only photos, spread across twelve weeks.
    ///
    /// The files deliberately do not exist: this doubles as the missing-file
    /// case, proving the card degrades to a placeholder rather than crashing.
    ///
    /// `startedOnInstallDay` is what decides whether the opening card reads
    /// "Day 0" or "1st", so both are previewable without waiting for a real
    /// install to age.
    static func store(count: Int, startedOnInstallDay: Bool = true) -> ProgressPhotoStore {
        let defaults = scratchDefaults()
        let now = Date()
        let photos = (0..<count).map { index -> ProgressPhoto in
            let daysAgo = Double(count - 1 - index) * (84.0 / Double(max(count - 1, 1)))
            return ProgressPhoto(
                id: UUID(),
                createdAt: now.addingTimeInterval(-daysAgo * 86_400),
                fileName: "preview-\(index).jpg",
                thumbnailName: "preview-\(index)-thumb.jpg",
                source: .camera
            )
        }
        if let data = try? JSONEncoder().encode(photos) {
            defaults.set(data, forKey: "gymlock.progressPhotos")
        }
        // Installed either on the day of the oldest photo, or long before it.
        let install = startedOnInstallDay
            ? (photos.first?.createdAt ?? now)
            : now.addingTimeInterval(-200 * 86_400)
        defaults.set(install, forKey: AppInstallDate.key)
        return ProgressPhotoStore(defaults: defaults)
    }

    /// An isolated defaults suite so previews never write to the real app.
    private static func scratchDefaults() -> UserDefaults {
        UserDefaults(suiteName: "gymlock.preview.\(UUID().uuidString)") ?? .standard
    }

    /// Demonstration slides trimmed to a given count, with the end labels
    /// recomputed so a two-card stack still reads Day 0 → Latest.
    static func slides(
        _ count: Int,
        opening: ProgressPhotoSlide.Marker = .dayZero
    ) -> [ProgressPhotoSlide] {
        let clamped = min(max(count, 1), ProgressPhotoDemoArtwork.frameCount)
        return (0..<clamped).map { index in
            ProgressPhotoSlide(
                id: "demo-\(index)",
                content: .demo(index: index),
                marker: index == 0 ? opening : (index == clamped - 1 ? .latest : nil),
                date: nil
            )
        }
    }
}

/// Hosts a stack on the card surface at a realistic width.
private struct StackStage: View {
    let slides: [ProgressPhotoSlide]
    var focusedIndex: Int?
    var reduceMotion = false

    @State private var focused: String?

    private var activeID: String {
        focused ?? slides[min(focusedIndex ?? slides.count - 1, slides.count - 1)].id
    }

    var body: some View {
        GeometryReader { proxy in
            ProgressPhotoStack(
                slides: slides,
                focusedID: activeID,
                regionWidth: proxy.size.width,
                reduceMotion: reduceMotion,
                onFocus: { focused = $0.id }
            )
        }
        .frame(height: 210)
        .padding(18)
        .background(Theme.surface, in: .rect(cornerRadius: ProgressCardMetrics.cornerRadius))
        .padding(20)
        .background(Theme.canvas)
    }
}

/// Hosts a stack resting on its oldest card, with a button that fires the
/// progress reveal. Grab the deck mid-glide to check the hand wins.
private struct RevealStage: View {
    var reduceMotion = false

    @State private var focused = "demo-0"
    @State private var isRevealRequested = false

    var body: some View {
        VStack(spacing: 16) {
            GeometryReader { proxy in
                ProgressPhotoStack(
                    slides: ProgressPhotoSlide.demoSlides,
                    focusedID: focused,
                    regionWidth: proxy.size.width,
                    reduceMotion: reduceMotion,
                    onFocus: { focused = $0.id },
                    isRevealRequested: isRevealRequested
                )
            }
            .frame(height: 210)

            HStack(spacing: 20) {
                Button("Play reveal") { isRevealRequested = true }
                Button("Reset") {
                    isRevealRequested = false
                    focused = "demo-0"
                }
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .padding(18)
        .background(Theme.surface, in: .rect(cornerRadius: ProgressCardMetrics.cornerRadius))
        .padding(20)
        .background(Theme.canvas)
    }
}

// MARK: - Progress reveal

#Preview("Reveal · demo stack, oldest to Latest") {
    RevealStage()
}

/// Tap Play, then drag or tap the deck while it is still moving.
#Preview("Reveal · drag during the glide") {
    RevealStage()
}

#Preview("Reveal · reduce motion (short fade, no glide)") {
    RevealStage(reduceMotion: true)
}

/// Scroll down: the card rests on Day 0 and the deck travels once it is
/// fully on screen. Scrolling away and back does not replay it.
#Preview("Reveal · card below the fold, no photos") {
    ScrollView {
        VStack(spacing: 20) {
            Color.clear.frame(height: 900)
            ProgressPhotosCard(store: PhotoFixture.emptyStore(), appearanceDelay: 0)
        }
        .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Reveal · card below the fold, four real photos") {
    ScrollView {
        VStack(spacing: 20) {
            Color.clear.frame(height: 900)
            ProgressPhotosCard(store: PhotoFixture.store(count: 4), appearanceDelay: 0)
        }
        .padding(20)
    }
    .background(Theme.canvas)
}

// MARK: - Photo counts

#Preview("Stack · 1 photo") {
    StackStage(slides: PhotoFixture.slides(1))
}

#Preview("Stack · 2 photos") {
    StackStage(slides: PhotoFixture.slides(2))
}

#Preview("Stack · 3 photos") {
    StackStage(slides: PhotoFixture.slides(3))
}

#Preview("Stack · 4 photos") {
    StackStage(slides: PhotoFixture.slides(4))
}

#Preview("Stack · focus on Day 0") {
    StackStage(slides: PhotoFixture.slides(4), focusedIndex: 0)
}

#Preview("Stack · focus on a middle card") {
    StackStage(slides: PhotoFixture.slides(4), focusedIndex: 1)
}

#Preview("Stack · reduce motion") {
    StackStage(slides: PhotoFixture.slides(4), reduceMotion: true)
}

/// A user who started photographing themselves after installing, so the oldest
/// photo is honestly "1st" rather than a Day 0 they never took.
#Preview("Stack · no genuine Day 0") {
    StackStage(slides: PhotoFixture.slides(4, opening: .first))
}

// MARK: - The whole card

#Preview("Card · no photos (demo stack)") {
    ScrollView {
        ProgressPhotosCard(store: PhotoFixture.emptyStore(), appearanceDelay: 0)
            .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Card · one real photo") {
    ScrollView {
        ProgressPhotosCard(store: PhotoFixture.store(count: 1), appearanceDelay: 0)
            .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Card · two real photos") {
    ScrollView {
        ProgressPhotosCard(store: PhotoFixture.store(count: 2), appearanceDelay: 0)
            .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Card · three real photos") {
    ScrollView {
        ProgressPhotosCard(store: PhotoFixture.store(count: 3), appearanceDelay: 0)
            .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Card · four real photos (reveals)") {
    ScrollView {
        ProgressPhotosCard(store: PhotoFixture.store(count: 4), appearanceDelay: 0)
            .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Card · five real photos (no reveal)") {
    ScrollView {
        ProgressPhotosCard(store: PhotoFixture.store(count: 5), appearanceDelay: 0)
            .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Card · many photos (sampled)") {
    ScrollView {
        ProgressPhotosCard(store: PhotoFixture.store(count: 24), appearanceDelay: 0)
            .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Card · started after install (1st)") {
    ScrollView {
        ProgressPhotosCard(
            store: PhotoFixture.store(count: 6, startedOnInstallDay: false),
            appearanceDelay: 0
        )
        .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Card · accessibility text size") {
    ScrollView {
        ProgressPhotosCard(store: PhotoFixture.emptyStore(), appearanceDelay: 0)
            .padding(20)
    }
    .background(Theme.canvas)
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Card · narrow device") {
    ScrollView {
        ProgressPhotosCard(store: PhotoFixture.emptyStore(), appearanceDelay: 0)
            .padding(20)
    }
    .background(Theme.canvas)
    .frame(width: 320)
}

// MARK: - Selection maths

/// Shows which positions the sampler picks out of a long history, so the
/// spread can be checked by eye rather than trusted.
#Preview("Sampling · picked positions") {
    let now = Date()
    let photos = (0..<30).map { index in
        ProgressPhoto(
            id: UUID(),
            createdAt: now.addingTimeInterval(-Double(29 - index) * 3 * 86_400),
            fileName: "s-\(index).jpg",
            thumbnailName: "s-\(index)-thumb.jpg",
            source: .camera
        )
    }
    let picked = Set(ProgressPhotoSelection.representativeIndices(in: photos))

    return VStack(alignment: .leading, spacing: 12) {
        Text("30 photos over 90 days")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.ink)

        HStack(spacing: 3) {
            ForEach(0..<photos.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(picked.contains(index) ? Theme.ink : Theme.border)
                    .frame(height: picked.contains(index) ? 34 : 16)
            }
        }
        .frame(height: 34, alignment: .bottom)

        Text(picked.sorted().map(String.init).joined(separator: ", "))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.inkSecondary)
    }
    .padding(20)
    .background(Theme.canvas)
}
#endif
