import CoreLocation
import MapKit
import Observation

/// The live geometry of one trip to the gym: where the user is, the route Apple
/// Maps gives from there to the gym, and how much of it is left.
///
/// Owned by `TripView` and alive only while the trip screen is on screen. It
/// keeps its own location manager because the session's departure monitor
/// stops listening the moment the user leaves home, and the map has to keep
/// following them after that. Nothing here is persisted: the session's
/// deadline, departure and arrival stay the only truth about the trip, and
/// this model only draws them.
///
/// Every number it exposes is real or absent. No route means no ETA, never a
/// guessed one.
@MainActor
@Observable
final class TripModel: NSObject {
    let gym: CLLocationCoordinate2D

    /// The latest fix, nil until the first one lands.
    private(set) var user: CLLocationCoordinate2D?
    /// Where the user was when the screen first got a fix. The Matrix board
    /// keeps a ring there, and the Ridge trail starts there.
    private(set) var origin: CLLocationCoordinate2D?
    /// Direction of travel in degrees from north, taken from the route where the
    /// user is on it (GPS course is too noisy at walking speed).
    private(set) var heading: CLLocationDirection = 0

    /// Apple's route, from the point it was asked for to the gym.
    private(set) var route: [CLLocationCoordinate2D] = []
    /// True when Apple returned no route and `route` is a straight line. The
    /// distance is still true; the time is unknown and hidden.
    private(set) var isRouteEstimated = false
    private(set) var routeDistance: CLLocationDistance = 0
    private(set) var routeTravelTime: TimeInterval = 0
    /// Metres along `route` to the point closest to the user.
    private(set) var along: CLLocationDistance = 0
    /// Index of the route vertex just behind the user, for splitting the line
    /// into travelled and ahead.
    private(set) var alongIndex = 0
    /// The user's position snapped onto the route.
    private(set) var snapped: CLLocationCoordinate2D?

    /// The longest the route has been this trip. Progress is measured against
    /// it, so a re-route from further along never jumps the climber backwards.
    @ObservationIgnored private var tripLength: CLLocationDistance = 0
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var cumulative: [CLLocationDistance] = []
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var lastRouteRequest: Date?
    @ObservationIgnored private var isRunning = false

    /// How far off the line counts as a new way, in metres.
    private static let offRouteMetres: CLLocationDistance = 60
    /// Never ask Apple for directions more often than this.
    private static let rerouteInterval: TimeInterval = 30
    /// Below this straight-line distance the route is asked for on foot.
    private static let walkingThreshold: CLLocationDistance = 1_600

    init(gym: CLLocationCoordinate2D) {
        self.gym = gym
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 4
        manager.activityType = .fitness
    }

    // MARK: - Derived

    /// Metres still to go, nil before there is a route.
    var remainingDistance: CLLocationDistance? {
        guard !route.isEmpty else { return nil }
        return max(0, routeDistance - along)
    }

    /// Seconds still to go by Apple's own estimate, nil when unknown.
    var remainingTime: TimeInterval? {
        guard !isRouteEstimated, routeDistance > 0, let remainingDistance else { return nil }
        return routeTravelTime * (remainingDistance / routeDistance)
    }

    /// 0 at the start of the trip, 1 at the gym.
    var progress: Double {
        guard tripLength > 0, let remainingDistance else { return 0 }
        return min(1, max(0, 1 - remainingDistance / tripLength))
    }

    /// The part of the route already behind the user, ending at their snapped position.
    var travelledPath: [CLLocationCoordinate2D] {
        guard !route.isEmpty else { return [] }
        var path = Array(route.prefix(alongIndex + 1))
        if let snapped { path.append(snapped) }
        return path
    }

    /// The part still ahead, starting at their snapped position.
    var remainingPath: [CLLocationCoordinate2D] {
        guard !route.isEmpty else { return [] }
        var path: [CLLocationCoordinate2D] = []
        if let snapped { path.append(snapped) }
        path.append(contentsOf: route.suffix(from: min(alongIndex + 1, route.count)))
        return path
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        #if DEBUG
        if TripSimulation.shared.isActive {
            TripSimulation.shared.attach(self)
            return
        }
        #endif
        if let last = manager.location { ingest(last.coordinate) }
        manager.startUpdatingLocation()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        routeTask?.cancel()
        routeTask = nil
    }

    // MARK: - Input

    /// Takes one position, from GPS or from the debug simulator.
    func ingest(_ coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        user = coordinate
        if origin == nil { origin = coordinate }

        if route.isEmpty {
            requestRoute(from: coordinate)
            return
        }

        let offRoute = project(coordinate)
        if offRoute > Self.offRouteMetres, canReroute {
            requestRoute(from: coordinate)
        }
    }

    private var canReroute: Bool {
        guard routeTask == nil else { return false }
        guard let lastRouteRequest else { return true }
        return Date().timeIntervalSince(lastRouteRequest) >= Self.rerouteInterval
    }

    // MARK: - Route

    private func requestRoute(from source: CLLocationCoordinate2D) {
        guard routeTask == nil else { return }
        lastRouteRequest = Date()

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: gym))
        let straight = Self.distance(source, gym)
        request.transportType = straight < Self.walkingThreshold ? .walking : .automobile

        routeTask = Task { [weak self] in
            let response = try? await MKDirections(request: request).calculate()
            guard let self, !Task.isCancelled else { return }
            self.routeTask = nil
            if let best = response?.routes.first {
                self.apply(best)
            } else if self.route.isEmpty {
                self.applyStraightLine(from: source)
            }
        }
    }

    private func apply(_ best: MKRoute) {
        let count = best.polyline.pointCount
        guard count >= 2 else { return }
        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
        best.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: count))
        setRoute(coordinates, distance: best.distance, time: best.expectedTravelTime, estimated: false)
    }

    private func applyStraightLine(from source: CLLocationCoordinate2D) {
        setRoute([source, gym], distance: Self.distance(source, gym), time: 0, estimated: true)
    }

    private func setRoute(_ coordinates: [CLLocationCoordinate2D], distance: CLLocationDistance, time: TimeInterval, estimated: Bool) {
        route = coordinates
        isRouteEstimated = estimated
        routeTravelTime = time

        var running: CLLocationDistance = 0
        var sums: [CLLocationDistance] = [0]
        for index in 1..<coordinates.count {
            running += Self.distance(coordinates[index - 1], coordinates[index])
            sums.append(running)
        }
        cumulative = sums
        // The polyline's own length, so `along` and the total agree exactly.
        routeDistance = max(running, 1)
        if estimated == false, distance > 0, abs(distance - running) / distance > 0.25 {
            // Apple's total and the drawn line disagree a lot: trust the line.
            routeTravelTime = time * (running / distance)
        }
        tripLength = max(tripLength, routeDistance)

        if let user { _ = project(user) }
    }

    /// Snaps the user onto the route and returns how far off it they are, in metres.
    @discardableResult
    private func project(_ point: CLLocationCoordinate2D) -> CLLocationDistance {
        guard route.count >= 2 else { return 0 }
        let reference = point
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        var bestAlong: CLLocationDistance = 0
        var bestIndex = 0
        var bestPoint = route[0]

        let p = Self.local(point, around: reference)
        for index in 0..<(route.count - 1) {
            let a = Self.local(route[index], around: reference)
            let b = Self.local(route[index + 1], around: reference)
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            var t = lengthSquared > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared : 0
            t = min(1, max(0, t))
            let cx = a.x + dx * t, cy = a.y + dy * t
            let d = hypot(p.x - cx, p.y - cy)
            if d < bestDistance {
                bestDistance = d
                bestIndex = index
                let segment = cumulative[index + 1] - cumulative[index]
                bestAlong = cumulative[index] + segment * t
                bestPoint = CLLocationCoordinate2D(
                    latitude: route[index].latitude + (route[index + 1].latitude - route[index].latitude) * t,
                    longitude: route[index].longitude + (route[index + 1].longitude - route[index].longitude) * t
                )
            }
        }

        along = bestAlong
        alongIndex = bestIndex
        snapped = bestPoint
        heading = Self.bearing(route[bestIndex], route[bestIndex + 1])
        return bestDistance
    }

    // MARK: - Geometry

    /// Metres east and north of `reference`. Accurate to well under a metre
    /// over the few kilometres of a trip to the gym.
    nonisolated static func local(_ c: CLLocationCoordinate2D, around reference: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let metresPerDegree = 111_320.0
        let x = (c.longitude - reference.longitude) * metresPerDegree * cos(reference.latitude * .pi / 180)
        let y = (c.latitude - reference.latitude) * metresPerDegree
        return (x, y)
    }

    nonisolated static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Degrees clockwise from north, from `a` towards `b`.
    nonisolated static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDirection {
        let v = local(b, around: a)
        guard v.x != 0 || v.y != 0 else { return 0 }
        let degrees = atan2(v.x, v.y) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}

// MARK: - Location updates

extension TripModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        // A fix worse than this would drag the dot through buildings.
        guard latest.horizontalAccuracy >= 0, latest.horizontalAccuracy <= 120 else { return }
        let coordinate = latest.coordinate
        Task { @MainActor in self.ingest(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
