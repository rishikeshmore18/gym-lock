import Foundation

/// The pages the Alarm screen pushes, after Apple's Edit Alarm: Sound, and
/// Haptics one level under it.
enum AlarmOptionRoute: Hashable {
    case sound
    case haptics
}
