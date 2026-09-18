import SwiftUI

/// The overlapping stack of progress photographs.
///
/// The arrangement is the instruction: cards sitting on top of one another,
/// with one clearly in front, is a shape people already understand from a hand
/// of photos or a deck of cards. That is why there is no "swipe to see your
/// progress" caption anywhere — a label explaining an interaction is usually a
/// sign the interaction does not look like one.
///
/// The stack is driven by one continuous `position` rather than by a selected
/// index. Whole numbers are settled arrangements and everything in between is
/// a real, drawable state, which is what lets a finger drag the deck through
/// several photographs in one movement instead of nudging it one notch at a
/// time.
struct ProgressPhotoStack: View {
    let slides: [ProgressPhotoSlide]
    /// The card currently in front.
    let focusedID: String
    /// Width available for the whole stack.
    let regionWidth: CGFloat
    let reduceMotion: Bool
    /// Called when a card should become the focused one.
    let onFocus: (ProgressPhotoSlide) -> Void
    /// Called to delete a real photograph. Absent while the demo stack shows.
    var onDelete: ((ProgressPhoto) -> Void)?
    /// Called to share a real photograph: from the context menu, or by tapping
    /// the card that is already in front. Absent while the demo stack shows.
    var onShare: ((ProgressPhoto) -> Void)?
    /// The zoom transition's source, so the card grows into the editor.
    var transitionNamespace: Namespace.ID?

    /// Continuous position while a finger is down. `nil` means settled, and
    /// the focused card is the source of truth again.
    @State private var dragPosition: CGFloat?
    /// Where the deck sat when the current gesture began.
    @State private var dragStart: CGFloat = 0
    /// Set once a drag has travelled far enough to be a drag rather than a tap.
    @State private var isDragging = false
    /// Whether the current gesture was judged vertical and handed to the page.
    @State private var isScrollingVertically = false
    /// Which photograph last came to the front mid-drag, for the tick.
    @State private var tickedSlot: Int?

    /// How much of the throw's projected travel counts towards the landing
    /// slot. A full projection sends a firm flick clean past the whole
    /// history; none at all makes a fast flick and a slow drag land in the
    /// same place, which is what makes a deck feel nailed down.
    private static let momentum: CGFloat = 0.72
    /// Resistance applied past the first and last photograph.
    private static let edgeResistance: CGFloat = 0.3
    /// Movement before a touch is judged a drag rather than a tap.
    ///
    /// Small on purpose. The gesture itself starts at zero distance so the deck
    /// answers the finger on the first frame; this only decides which way the
    /// gesture is going, and anything larger is felt as the deck hesitating
    /// before it moves.
    private static let axisThreshold: CGFloat = 5

    private var focusedSlot: Int {
        slides.firstIndex { $0.id == focusedID } ?? max(slides.count - 1, 0)
    }

    private var cardWidth: CGFloat {
        ProgressPhotoLayout.cardWidth(for: slides.count, in: regionWidth)
    }

    /// Finger travel that advances the deck by one photograph.
    ///
    /// Undamped on purpose: the deck moves with the hand at its own scale
    /// rather than lagging behind it at a fraction of the speed. Deliberately
    /// shorter than a card, so one comfortable thumb sweep crosses the whole
    /// history instead of advancing one photograph per swipe.
    private var slotTravel: CGFloat {
        max(cardWidth * 0.5, 1)
    }

    /// Where the deck is right now, settled or mid-drag.
    private var position: CGFloat {
        dragPosition ?? CGFloat(focusedSlot)
    }

    private var lastSlot: CGFloat {
        CGFloat(max(slides.count - 1, 0))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(slides.enumerated()), id: \.element.id) { index, slide in
                card(slide, at: index)
            }
        }
        .frame(
            width: regionWidth,
            height: ProgressPhotoMetrics.regionHeight(for: cardWidth),
            alignment: .leading
        )
        .contentShape(.rect)
        // Simultaneous, so the page's vertical ScrollView keeps its own pan.
        // An exclusive gesture at zero distance would swallow the scroll, and
        // a non-zero distance is exactly what made the deck wait before it
        // started moving.
        .simultaneousGesture(dragGesture)
        .accessibilityElement(children: .contain)
    }

    // MARK: Cards

    private func card(_ slide: ProgressPhotoSlide, at index: Int) -> some View {
        let geometry = ProgressPhotoLayout.geometry(
            index: index,
            position: position,
            count: slides.count,
            cardWidth: cardWidth,
            regionWidth: regionWidth
        )

        // Deliberately not a Button. A button installs its own gesture, and a
        // child's gesture outranks the container's, so the drag was only
        // delivered once the button's recogniser gave up — on finger lift.
        // That is what made the deck jump to its new arrangement after the
        // gesture instead of moving with the hand. Taps are handled by the one
        // container gesture below, which can tell a tap from a drag itself.
        return ProgressPhotoCard(
            slide: slide,
            dimming: geometry.opacity,
            // Only the ends are labelled, and a label on a card buried at
            // the back is just noise.
            showsMarker: slide.markerText != nil,
            width: cardWidth
        )
        .zoomTransitionSource(id: slide.id, in: transitionNamespace, isEnabled: slide.id == focusedID)
        .scaleEffect(geometry.scale)
        .offset(x: geometry.x)
        .zIndex(geometry.zIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: slide))
        .accessibilityAddTraits(slide.id == focusedID ? [.isButton, .isSelected] : .isButton)
        // Removing the button removed its accessibility action, so the card
        // brings its own — VoiceOver must still be able to activate it.
        .accessibilityAction {
            withAnimation(settle) { onFocus(slide) }
        }
        .photoContextMenu(slide: slide, onShare: onShare, onDelete: onDelete)
    }

    /// The spring for a tap, where travel is short and known.
    private var settle: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.38, dampingFraction: 0.86)
    }

    /// The spring for a release, stretched according to how far the deck still
    /// has to travel.
    ///
    /// A fixed spring makes a four-card glide look hurried and a small
    /// correction look sluggish, because both are given the same time. Letting
    /// the duration grow with the distance is what reads as the deck carrying
    /// its own weight.
    private func glide(slots: CGFloat) -> Animation {
        guard !reduceMotion else { return .easeInOut(duration: 0.18) }
        let response = min(0.36 + Double(slots) * 0.09, 0.7)
        // Slightly less damped the further it has to travel, so a long glide
        // arrives carrying a trace of momentum rather than stopping dead on
        // the slot the way a snapped index would.
        let damping = max(0.86 - Double(slots) * 0.03, 0.76)
        return .spring(response: response, dampingFraction: damping)
    }

    // MARK: Drag

    /// One gesture for the whole deck, tracking from the very first point.
    ///
    /// `minimumDistance: 0` is the heart of it. The deck has to redraw on the
    /// frame the finger moves, not once a threshold has been cleared and
    /// certainly not on release — the photographs are meant to move *with* the
    /// hand. Because there is no per-card button any more, this gesture also
    /// has to recognise a tap, which it does by measuring how far the touch
    /// travelled before it was lifted.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // The card sits inside a vertical ScrollView, so the axis is
                // decided once, as soon as there is enough movement to tell,
                // and honoured for the rest of the gesture. Without this a
                // finger travelling down the page would shuffle the photos.
                if !isDragging, !isScrollingVertically {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) >= Self.axisThreshold else { return }

                    isScrollingVertically = dy > dx
                    guard !isScrollingVertically else { return }

                    dragStart = CGFloat(focusedSlot)
                    tickedSlot = focusedSlot
                    isDragging = true
                }
                guard isDragging, !isScrollingVertically else { return }

                // Dragging left (negative) moves forward in time, matching the
                // left-to-right chronology of the stack. Written straight to
                // state with no animation: the finger is the animation, and a
                // spring here would put the deck behind the hand.
                let next = resisted(dragStart - value.translation.width / slotTravel)
                dragPosition = next

                // A tick as each photograph reaches the front, the way a
                // picker notches. Bounded by the number of photos, so a long
                // glide cannot buzz continuously.
                let nearest = Int(next.rounded().clamped(to: 0...lastSlot))
                if nearest != tickedSlot {
                    tickedSlot = nearest
                    Haptics.selection()
                }
            }
            .onEnded { value in
                let wasDragging = isDragging
                let wasVertical = isScrollingVertically
                isDragging = false
                isScrollingVertically = false
                tickedSlot = nil

                guard !wasVertical else {
                    dragPosition = nil
                    return
                }

                // Never moved far enough to be a drag, so it was a tap on
                // whichever card sits under the finger.
                guard wasDragging else {
                    dragPosition = nil
                    handleTap(at: value.startLocation)
                    return
                }

                // `predictedEndTranslation` is where the system thinks the
                // finger would coast to, so a throw keeps going after release
                // instead of stopping dead where contact was lost.
                let travelled = value.translation.width
                let projected = value.predictedEndTranslation.width
                let carried = travelled + (projected - travelled) * Self.momentum

                let landing = (dragStart - carried / slotTravel)
                    .clamped(to: 0...lastSlot)
                let target = Int(landing.rounded())
                let remaining = abs(position - CGFloat(target))

                withAnimation(glide(slots: remaining)) {
                    if let slide = slides[safe: target], slide.id != focusedID {
                        onFocus(slide)
                    }
                    dragPosition = nil
                }
            }
    }

    /// Brings the card under a tap to the front — or, if it is already in
    /// front, opens it in the Story editor.
    ///
    /// Two taps to share, never one: the first tap is always "look at this
    /// one", so a user browsing their history is never surprised by an
    /// editor appearing.
    private func handleTap(at location: CGPoint) {
        guard let index = slideIndex(at: location.x),
              let slide = slides[safe: index]
        else { return }

        if slide.id == focusedID {
            guard let onShare, case let .photo(photo) = slide.content else { return }
            Haptics.tap()
            onShare(photo)
            return
        }

        Haptics.selection()
        withAnimation(settle) { onFocus(slide) }
    }

    /// Which card is under a horizontal point, front-most first.
    ///
    /// The cards overlap, so the test walks them in drawing order and takes the
    /// nearest to the focus — tapping the visible sliver of Day 0 has to select
    /// Day 0, not the card lying on top of it.
    private func slideIndex(at x: CGFloat) -> Int? {
        let hits = slides.indices.filter { index in
            let geometry = ProgressPhotoLayout.geometry(
                index: index,
                position: position,
                count: slides.count,
                cardWidth: cardWidth,
                regionWidth: regionWidth
            )
            // `scaleEffect` scales about the centre, so the drawn edges move
            // in by half the difference.
            let inset = cardWidth * (1 - geometry.scale) / 2
            let left = geometry.x + inset
            return x >= left && x <= left + cardWidth * geometry.scale
        }
        return hits.max { first, second in
            abs(CGFloat(first) - position) > abs(CGFloat(second) - position)
        }
    }

    /// Softens travel past the ends, so the deck resists rather than stopping
    /// dead — the give is what tells the hand it has reached the beginning.
    private func resisted(_ value: CGFloat) -> CGFloat {
        if value < 0 { return value * Self.edgeResistance }
        if value > lastSlot { return lastSlot + (value - lastSlot) * Self.edgeResistance }
        return value
    }

    // MARK: Accessibility

    private func accessibilityLabel(for slide: ProgressPhotoSlide) -> String {
        var parts: [String] = []
        switch slide.marker {
        case .dayZero: parts.append("Day 0 progress photo")
        case .first: parts.append("First progress photo")
        case .latest: parts.append("Latest progress photo")
        case nil: parts.append("Progress photo")
        }
        if let date = slide.date {
            parts.append(date.formatted(.dateTime.month(.wide).day()))
        } else if slide.isDemo {
            parts.append("example")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Layout

/// The geometry of the stack, kept separate from the view so the arrangement
/// can be reasoned about (and previewed) as pure arithmetic.
enum ProgressPhotoLayout {
    struct CardGeometry {
        let x: CGFloat
        let scale: CGFloat
        let opacity: Double
        let zIndex: Double
    }

    /// How wide a single card is, given how many share the region.
    ///
    /// Fewer photos means bigger cards: with one photo the region is not a
    /// stack at all and a small print marooned on the left would look like a
    /// bug rather than a beginning.
    static func cardWidth(for count: Int, in regionWidth: CGFloat) -> CGFloat {
        guard regionWidth > 0 else { return ProgressPhotoMetrics.preferredCardWidth }
        let fraction: CGFloat = switch count {
        case 0, 1: 0.74
        case 2: 0.64
        case 3: 0.58
        default: 0.48
        }
        // Capped so the stack never outgrows the space it was given, and never
        // shrinks below something you could actually recognise a body in.
        return min(max(regionWidth * fraction, 62), regionWidth)
    }

    /// Relative widths of the gaps between cards when the newest photo leads,
    /// oldest first.
    ///
    /// Deliberately lopsided. The oldest photo gets by far the widest gap so it
    /// stays around two-thirds visible, because it is the card the newest one
    /// is being compared against — a Day 0 reduced to a sliver defeats the
    /// point of the whole component. The middle cards give up their space for
    /// it and sit tightly overlapped, which is also what makes the stack read
    /// as depth rather than as four evenly spaced thumbnails.
    private static func restWeights(count: Int) -> [CGFloat] {
        switch count {
        case ...1: []
        case 2: [1.0]
        case 3: [1.5, 0.8]
        default: [1.8, 0.66] + Array(repeating: 0.54, count: count - 3)
        }
    }

    /// The gaps for a given deck position, which is what makes a drag feel like
    /// a deck instead of a slideshow.
    ///
    /// The resting arrangement is built around the newest photo leading. Its
    /// mirror image is the arrangement for the oldest photo leading, and every
    /// position in between is a real blend of the two. So the space itself
    /// migrates from one end of the stack to the other as the finger moves:
    /// cards ahead of the focus close up and cards behind it fan open,
    /// continuously, at every intermediate frame.
    ///
    /// Without this the gaps were constant and only the scale changed, which is
    /// exactly what made the motion read as rigid — the photographs stayed put
    /// while the deck was supposedly being dragged through them.
    static func gapWeights(count: Int, position: CGFloat) -> [CGFloat] {
        let rest = restWeights(count: count)
        guard rest.count > 1 else { return rest }

        // 0 with the newest card in front, 1 with the oldest in front.
        let progress = 1 - (position / CGFloat(count - 1)).clamped(to: 0...1)
        return zip(rest, rest.reversed()).map { near, far in
            near * (1 - progress) + far * progress
        }
    }

    static func geometry(
        index: Int,
        position: CGFloat,
        count: Int,
        cardWidth: CGFloat,
        regionWidth: CGFloat
    ) -> CardGeometry {
        let delta = CGFloat(index) - position
        let depth = min(abs(delta), 3)

        // How far the focused card grows, and how far back the others sit.
        // Both interpolate continuously with `depth`, so a half-dragged deck
        // draws a genuine half-way state rather than snapping between looks.
        let scale: CGFloat = ProgressPhotoMetrics.focusScale - depth * 0.045
        let opacity: Double = 1 - Double(depth) * 0.07

        var x = baseX(
            index: index,
            position: position,
            count: count,
            cardWidth: cardWidth,
            regionWidth: regionWidth
        )
        // A last nudge away from whichever card is coming forward. Small now
        // that the gaps themselves travel — this only softens the moment a
        // card takes the front.
        x += delta.clamped(to: -2...2) * 3

        return CardGeometry(
            x: x,
            scale: scale,
            opacity: opacity,
            // Nearest to the focus draws on top.
            zIndex: Double(count) - Double(depth)
        )
    }

    /// Position of a card for the deck's current position.
    ///
    /// The gaps are normalised against the slack in the region, so the last
    /// card always lands flush with the right edge no matter how the space is
    /// currently distributed. The stack breathes internally without the deck as
    /// a whole drifting sideways.
    private static func baseX(
        index: Int,
        position: CGFloat,
        count: Int,
        cardWidth: CGFloat,
        regionWidth: CGFloat
    ) -> CGFloat {
        guard count > 1 else { return (regionWidth - cardWidth) / 2 }

        let slack = max(regionWidth - cardWidth, 0)
        let weights = gapWeights(count: count, position: position)
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }

        let gaps = weights.map { $0 / total * slack }
        return gaps.prefix(index).reduce(0, +)
    }
}

// MARK: - Context menu

private extension View {
    /// Long-press for Share and Delete, on real photographs only.
    ///
    /// A context menu rather than visible controls on every card: delete is
    /// destructive, and both should take a deliberate press rather than sit
    /// under the thumb that is busy dragging the deck. Long-press is also
    /// where iOS users already reach for both actions on a photo. Share sits
    /// above Delete, as the system puts the safe action first.
    ///
    /// Matching accessibility actions are attached alongside, because a long
    /// press is not a gesture VoiceOver users can rely on.
    @ViewBuilder
    func photoContextMenu(
        slide: ProgressPhotoSlide,
        onShare: ((ProgressPhoto) -> Void)?,
        onDelete: ((ProgressPhoto) -> Void)?
    ) -> some View {
        if case let .photo(photo) = slide.content, onShare != nil || onDelete != nil {
            contextMenu {
                if let onShare {
                    Button {
                        onShare(photo)
                    } label: {
                        Label("Share Photo", systemImage: "square.and.arrow.up")
                    }
                }
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete(photo)
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                    }
                }
            }
            .modifier(PhotoAccessibilityActions(photo: photo, onShare: onShare, onDelete: onDelete))
        } else {
            self
        }
    }

    /// Marks the focused card as the source of the zoom into the editor.
    ///
    /// Only the focused card is a source: registering the buried ones too
    /// would be wasted work on every drag frame.
    @ViewBuilder
    func zoomTransitionSource(id: String, in namespace: Namespace.ID?, isEnabled: Bool) -> some View {
        if let namespace, isEnabled {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

/// VoiceOver actions matching the context menu.
private struct PhotoAccessibilityActions: ViewModifier {
    let photo: ProgressPhoto
    let onShare: ((ProgressPhoto) -> Void)?
    let onDelete: ((ProgressPhoto) -> Void)?

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: "Share Photo") { onShare?(photo) }
            .accessibilityAction(named: "Delete Photo") { onDelete?(photo) }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Array {
    /// Bounds-checked lookup, for the landing slot of a throw.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
