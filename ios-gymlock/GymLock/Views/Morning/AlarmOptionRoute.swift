import Foundation

/// The pages the Alarm screen pushes, after Apple's Edit Alarm: Sound, with
/// Haptics and your own song one level under it.
enum AlarmOptionRoute: Hashable {
    case sound
    case haptics
    case song
}
