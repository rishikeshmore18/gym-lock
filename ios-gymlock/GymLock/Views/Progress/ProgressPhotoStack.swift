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

    /// Continuous position while a finger is down. `nil` means settled, and
    /// the focused card is the source of truth again.
    @State private var dragPosition: CGFloat?
    /// Where the deck sat when the current gesture began.
    @State private var dragStart: CGFloat = 0
    /// Set once a drag has travelled far enough to be a drag rather than a tap.
    @State private var isDragging = false
    /// Whether the current gesture was judged vertical and handed to the page.
    @State private var isScrollingVertically = false

    /// How much of the throw's projected travel counts towards the landing
    /// slot. A full projection sends a firm flick clean past the whole
    /// history; none at all makes a fast flick and a slow drag land in the
    /// same place, which is what makes a deck feel nailed down.
    private static let momentum: CGFloat = 0.55
    /// Resistance applied past the first and last photograph.
    private static let edgeResistance: CGFloat = 0.3

    private var focusedSlot: Int {
        slides.firstIndex { $0.id == focusedID } ?? max(slides.count - 1, 0)
    }

    private var cardWidth: CGFloat {
        ProgressPhotoLayout.cardWidth(for: slides.count, in: regionWidth)
    }

    /// Finger travel that advances the deck by one photograph.
    ///
    /// Undamped on purpose: the deck moves with the hand at its own scale
    /// rather than lagging behind it at a fraction of the speed.
    private var slotTravel: CGFloat {
        max(cardWidth * 0.58, 1)
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
        .gesture(dragGesture)
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

        return Button {
            guard !isDragging else { return }
            withAnimation(settle) { onFocus(slide) }
        } label: {
            ProgressPhotoCard(
                slide: slide,
                dimming: geometry.opacity,
                // Only the ends are labelled, and a label on a card buried at
                // the back is just noise.
                showsMarker: slide.markerText != nil,
                width: cardWidth
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(geometry.scale)
        .offset(x: geometry.x)
        .zIndex(geometry.zIndex)
        .accessibilityLabel(accessibilityLabel(for: slide))
        .accessibilityAddTraits(slide.id == focusedID ? [.isButton, .isSelected] : .isButton)
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
        let response = min(0.34 + Double(slots) * 0.08, 0.66)
        return .spring(response: response, dampingFraction: 0.84)
    }

    // MARK: Drag

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // The card sits inside a vertical ScrollView, so the axis is
                // decided once at the start of the gesture and honoured for
                // the rest of it. Without this, a finger travelling down the
                // page would also shuffle the photographs.
                if !isDragging, !isScrollingVertically {
                    isScrollingVertically =
                        abs(value.translation.height) > abs(value.translation.width)
                    if !isScrollingVertically { dragStart = CGFloat(focusedSlot) }
                }
                guard !isScrollingVertically else { return }

                isDragging = true
                // Dragging left (negative) moves forward in time, matching the
                // left-to-right chronology of the stack.
                dragPosition = resisted(dragStart - value.translation.width / slotTravel)
            }
            .onEnded { value in
                defer {
                    // Cleared after the gesture resolves so the tap that ends
                    // a drag cannot also select a card.
                    Task { @MainActor in
                        isDragging = false
                        isScrollingVertically = false
                    }
                }
                guard !isScrollingVertically else {
                    dragPosition = nil
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
        case 2: 0.62
        case 3: 0.56
        default: 0.44
        }
        // Capped so the stack never outgrows the space it was given, and never
        // shrinks below something you could actually recognise a body in.
        return min(max(regionWidth * fraction, 62), regionWidth)
    }

    /// Relative widths of the gaps between cards, oldest first.
    ///
    /// Deliberately lopsided. The oldest photo gets by far the widest gap so it
    /// stays around three-quarters visible, because it is the card the newest
    /// one is being compared against — a Day 0 reduced to a sliver defeats the
    /// point of the whole component. The middle two give up their space for it
    /// and sit tightly overlapped, which is also what makes the stack read as
    /// depth rather than as four evenly spaced thumbnails.
    private static let gapWeights: [CGFloat] = [1.8, 0.66, 0.54]

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

        var x = baseX(index: index, count: count, cardWidth: cardWidth, regionWidth: regionWidth)
        // Cards ease away from whichever one is coming forward, so the stack
        // opens around the focus instead of every card sliding as a block.
        x += delta.clamped(to: -2...2) * 4.5

        return CardGeometry(
            x: x,
            scale: scale,
            opacity: opacity,
            // Nearest to the focus draws on top.
            zIndex: Double(count) - Double(depth)
        )
    }

    /// Resting position of a card before any focus adjustment.
    private static func baseX(
        index: Int,
        count: Int,
        cardWidth: CGFloat,
        regionWidth: CGFloat
    ) -> CGFloat {
        guard count > 1 else { return (regionWidth - cardWidth) / 2 }

        let slack = max(regionWidth - cardWidth, 0)
        let weights = Array(gapWeights.prefix(count - 1))
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }

        let gaps = weights.map { $0 / total * slack }
        return gaps.prefix(index).reduce(0, +)
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
