import CoreLocation
import Foundation

/// The gym the user actually goes to.
///
/// Chosen once from a map search and then never thought about again. The user is
/// never asked for coordinates, never shown a radius slider, and never asked to
/// confirm they arrived — this record is the entire configuration burden for
/// automatic arrival detection.
struct GymLocation: Codable, Hashable, Identifiable {
    var id: UUID
    /// What the place is called, e.g. "PureGym Manchester Piccadilly".
    var name: String
    /// Street or locality line, purely to disambiguate two branches in a list.
    var subtitle: String
    var latitude: Double
    var longitude: Double
    /// Detection radius in metres.
    ///
    /// Not exposed in normal UI. It exists as a field rather than a constant
    /// only so a support case can widen it for a user whose gym sits inside a
    /// large mall or basement where fixes are poor.
    var radius: Double
    var addedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String,
        latitude: Double,
        longitude: Double,
        radius: Double = GymLocation.defaultRadius,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.addedAt = addedAt
    }

    /// Starting radius.
    ///
    /// Big enough to fire reliably through the poor GPS of a doorway or a
    /// basement gym, small enough that a neighbouring building does not trip it.
    /// Entering this radius is only ever a *candidate* — the dwell check is what
    /// turns it into an arrival.
    static let defaultRadius: Double = 175

    /// Region monitoring has a hard floor on iOS; anything smaller is silently
    /// clamped and produces erratic callbacks.
    static let minimumRadius: Double = 100
    static let maximumRadius: Double = 400

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Stable identifier for the monitored region.
    var regionIdentifier: String { "gymlock.gym.\(id.uuidString)" }

    func region() -> CLCircularRegion {
        let region = CLCircularRegion(
            center: coordinate,
            radius: min(max(radius, Self.minimumRadius), Self.maximumRadius),
            identifier: regionIdentifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        return region
    }

    func distance(from location: CLLocation) -> Double {
        location.distance(from: clLocation)
    }
}

// MARK: - Arrival tuning

/// Every threshold the arrival logic depends on, in one place.
///
/// These are engineering starting points for beta, not claims about anything.
/// Keeping them together means tuning after real-world testing is a single
/// edit rather than a hunt through three files.
enum ArrivalTuning {
    /// How long the phone must stay near the gym before arrival is accepted.
    ///
    /// This is the anti-drive-by check. Two minutes is long enough that traffic
    /// lights outside the gym do not unlock the user's apps, and short enough
    /// that it finishes while they are still finding a locker.
    static let dwellSeconds: TimeInterval = 120

    /// Worst horizontal accuracy, in metres, still worth acting on.
    ///
    /// A fix reported as accurate to 500 m says almost nothing about whether
    /// somebody is inside a building. Acting on it would mean unlocking apps
    /// for a user sitting at home two streets away.
    static let maximumAcceptableAccuracy: Double = 120

    /// How far outside the radius the user may drift mid-dwell before the
    /// candidate is abandoned. Absorbs normal GPS jitter indoors.
    static let dwellTolerance: Double = 90

    /// How long to keep asking for a better fix before giving up and telling
    /// the user honestly that it could not be confirmed.
    static let confirmationTimeout: TimeInterval = 180

    /// Interval between location samples while confirming.
    static let samplePeriod: TimeInterval = 15
}
