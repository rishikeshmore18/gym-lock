import Foundation
import Observation

/// Remembers how the user framed and arranged a share.
///
/// Two small dictionaries in `UserDefaults`, keyed by photo ID and format for
/// the crop and by photo ID, frame and format for the element positions. The
/// values are normalized fractions, never pixels, so a layout saved on an SE
/// is the same layout on a Pro Max. Session shares (no photo) are keyed by
/// day, so re-opening the same morning restores the same arrangement.
///
/// Nothing here is a second source of truth about the photos themselves: a
/// photo that is deleted simply leaves an orphaned entry that nothing reads.
@Observable
@MainActor
final class StoryLayoutStore {
    private let defaults: UserDefaults
    private static let transformsKey = "gymlock.share.transforms"
    private static let elementsKey = "gymlock.share.elements"
    /// Enough for a long history of shares; older entries are dropped first.
    private static let limit = 400

    private var transforms: [String: PhotoTransform]
    private var elements: [String: StoryElementLayouts]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transforms = Self.load([String: PhotoTransform].self, from: defaults, key: Self.transformsKey) ?? [:]
        elements = Self.load([String: StoryElementLayouts].self, from: defaults, key: Self.elementsKey) ?? [:]
    }

    // MARK: Transform

    func transform(for origin: ShareOrigin, format: StoryFormat) -> PhotoTransform {
        transforms[Self.transformKey(origin, format)] ?? .default
    }

    func setTransform(_ transform: PhotoTransform, for origin: ShareOrigin, format: StoryFormat) {
        transforms[Self.transformKey(origin, format)] = transform
        trim(&transforms)
        persist(transforms, key: Self.transformsKey)
    }

    // MARK: Elements

    func layouts(for origin: ShareOrigin, frame: ShareFrame, format: StoryFormat) -> StoryElementLayouts {
        elements[Self.elementKey(origin, frame, format)] ?? .defaults(for: frame, format: format)
    }

    func setLayouts(
        _ layouts: StoryElementLayouts,
        for origin: ShareOrigin,
        frame: ShareFrame,
        format: StoryFormat
    ) {
        let key = Self.elementKey(origin, frame, format)
        // A layout back at its defaults is forgotten rather than stored, so
        // "Reset layout" leaves nothing behind.
        if layouts == .defaults(for: frame, format: format) {
            elements.removeValue(forKey: key)
        } else {
            elements[key] = layouts
        }
        trim(&elements)
        persist(elements, key: Self.elementsKey)
    }

    func resetLayouts(for origin: ShareOrigin, frame: ShareFrame, format: StoryFormat) {
        elements.removeValue(forKey: Self.elementKey(origin, frame, format))
        persist(elements, key: Self.elementsKey)
    }

    // MARK: Keys

    private static func transformKey(_ origin: ShareOrigin, _ format: StoryFormat) -> String {
        "\(origin.id)|\(format.rawValue)"
    }

    private static func elementKey(_ origin: ShareOrigin, _ frame: ShareFrame, _ format: StoryFormat) -> String {
        "\(origin.id)|\(frame.rawValue)|\(format.rawValue)"
    }

    // MARK: Persistence

    private func trim<Value>(_ dictionary: inout [String: Value]) {
        guard dictionary.count > Self.limit else { return }
        // Keys carry no order; drop an arbitrary surplus. This only fires
        // after hundreds of distinct shares.
        for key in dictionary.keys.sorted().prefix(dictionary.count - Self.limit) {
            dictionary.removeValue(forKey: key)
        }
    }

    private func persist<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<Value: Decodable>(
        _ type: Value.Type,
        from defaults: UserDefaults,
        key: String
    ) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
