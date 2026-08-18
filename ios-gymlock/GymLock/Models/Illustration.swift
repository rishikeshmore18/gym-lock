import CoreGraphics

/// The user-supplied illustration library.
///
/// Every asset ships with a light grey studio background around an organic
/// cream blob (or, for the loop diagrams, around the ring itself). `contentRect`
/// is the measured normalised region worth showing, so scenes can crop the dead
/// grey margin away instead of drawing a grey rectangle on the warm canvas.
///
/// See `.rork/skills/gymlock-illustrations/SKILL.md` for the character bible and
/// the meaning of each scene.
enum Illustration: String, CaseIterable {
    // Problem scenes
    case guiltCouch = "illo_guilt_couch"
    case excusesDesk = "illo_excuses_desk"
    case snoozeTopdown = "illo_snooze_topdown"

    // The six-state loop sequence
    case cycleOverview = "illo_cycle_overview"
    case cycle1Wants = "illo_cycle_1_wants"
    case cycle2Snooze = "illo_cycle_2_snooze"
    case cycle3Delays = "illo_cycle_3_delays"
    case cycle4Misses = "illo_cycle_4_misses"
    case cycle5Late = "illo_cycle_5_late"
    case cycle6Tired = "illo_cycle_6_tired"

    // Commitment gate
    case cautionSign = "illo_caution_sign"

    // Positive scenes
    case curlBench = "illo_curl_bench"
    case calendarMarking = "illo_calendar_marking"
    case celebrationJump = "illo_celebration_jump"

    /// Asset catalog name.
    var assetName: String { rawValue }

    /// True for the ring diagrams, which crossfade in place and therefore all
    /// share one crop so the geometry never shifts between states.
    var isLoopDiagram: Bool {
        switch self {
        case .cycleOverview, .cycle1Wants, .cycle2Snooze,
             .cycle3Delays, .cycle4Misses, .cycle5Late, .cycle6Tired:
            return true
        default:
            return false
        }
    }

    /// Pixel dimensions of the bundled file, used only to derive aspect ratio.
    var pixelSize: CGSize {
        switch self {
        case .guiltCouch, .excusesDesk:
            return CGSize(width: 1100, height: 880)
        case .curlBench, .snoozeTopdown:
            return CGSize(width: 825, height: 1100)
        case .cautionSign, .calendarMarking, .celebrationJump:
            return CGSize(width: 880, height: 1100)
        case .cycleOverview, .cycle1Wants, .cycle2Snooze,
             .cycle3Delays, .cycle4Misses, .cycle5Late, .cycle6Tired:
            return CGSize(width: 1100, height: 1100)
        }
    }

    /// Measured region of the image that actually carries the drawing,
    /// already trimmed slightly inwards so the grey studio edge never shows.
    var contentRect: CGRect {
        switch self {
        case .guiltCouch:
            return CGRect(x: 0.037, y: 0.083, width: 0.907, height: 0.859)
        case .excusesDesk:
            return CGRect(x: 0.105, y: 0.115, width: 0.790, height: 0.791)
        case .snoozeTopdown:
            return CGRect(x: 0.052, y: 0.112, width: 0.874, height: 0.755)
        case .cautionSign:
            return CGRect(x: 0.058, y: 0.121, width: 0.881, height: 0.776)
        case .curlBench:
            return CGRect(x: 0.133, y: 0.135, width: 0.750, height: 0.693)
        case .calendarMarking:
            return CGRect(x: 0.086, y: 0.114, width: 0.843, height: 0.806)
        case .celebrationJump:
            return CGRect(x: 0.138, y: 0.089, width: 0.734, height: 0.801)
        case .cycleOverview, .cycle1Wants, .cycle2Snooze,
             .cycle3Delays, .cycle4Misses, .cycle5Late, .cycle6Tired:
            // One shared crop for the whole sequence — see `isLoopDiagram`.
            return CGRect(x: 0.075, y: 0.038, width: 0.845, height: 0.914)
        }
    }

    /// Width / height of the cropped region.
    var croppedAspectRatio: CGFloat {
        let rect = contentRect
        let size = pixelSize
        return (rect.width * size.width) / (rect.height * size.height)
    }
}

// MARK: - The loop sequence

/// The six states of the miss-cycle, as pre-rendered by the illustrator, plus
/// the resting overview frame that opens the scene.
///
/// The diagram geometry is identical in every frame, so the scene keeps the
/// visual pinned and crossfades between states as the user swipes.
struct LoopState: Identifiable, Hashable {
    let id: Int
    let illustration: Illustration
    /// Short line shown beneath the pinned diagram for this state.
    let caption: String
    /// Node number as drawn in the artwork, or nil for the resting frame.
    let nodeNumber: Int?

    static let sequence: [LoopState] = [
        LoopState(
            id: 0,
            illustration: .cycleOverview,
            caption: "it always starts with one honest thought.",
            nodeNumber: nil
        ),
        LoopState(
            id: 1,
            illustration: .cycle1Wants,
            caption: "you genuinely want to go tomorrow.",
            nodeNumber: 1
        ),
        LoopState(
            id: 2,
            illustration: .cycle2Snooze,
            caption: "at 7am, the alarm becomes negotiable.",
            nodeNumber: 2
        ),
        LoopState(
            id: 3,
            illustration: .cycle3Delays,
            caption: "the phone quietly takes the morning.",
            nodeNumber: 3
        ),
        LoopState(
            id: 4,
            illustration: .cycle4Misses,
            caption: "the session disappears without a decision.",
            nodeNumber: 4
        ),
        LoopState(
            id: 5,
            illustration: .cycle5Late,
            caption: "guilt keeps you up past 1am.",
            nodeNumber: 5
        ),
        LoopState(
            id: 6,
            illustration: .cycle6Tired,
            caption: "so tomorrow begins already tired.",
            nodeNumber: 6
        ),
    ]
}
