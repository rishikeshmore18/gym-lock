import CoreLocation
import MapKit
import Observation

/// Finds the user's gym on the map so they never type a coordinate.
///
/// Deliberately thin: one debounced local search, results as plain values, no
/// map view required. The picker screen is a list, because a list of named
/// branches is far easier to choose from at setup time than a pin on a map.
@Observable
@MainActor
final class GymSearchService {
    private(set) var results: [GymSearchResult] = []
    private(set) var isSearching = false
    private(set) var failureMessage: String?

    private var searchTask: Task<Void, Never>?
    private var currentSearch: MKLocalSearch?

    /// Searches near a coordinate when one is known, so "Planet Fitness"
    /// returns the branch down the road rather than one in another country.
    func search(_ term: String, near coordinate: CLLocationCoordinate2D?) {
        searchTask?.cancel()
        currentSearch?.cancel()

        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            failureMessage = nil
            return
        }

        searchTask = Task { [weak self] in
            // Debounce: a search per keystroke would be both slow and rude to
            // the service.
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            await self?.performSearch(trimmed, near: coordinate)
        }
    }

    func clear() {
        searchTask?.cancel()
        currentSearch?.cancel()
        results = []
        isSearching = false
        failureMessage = nil
    }

    // MARK: - Private

    private func performSearch(_ term: String, near coordinate: CLLocationCoordinate2D?) async {
        isSearching = true
        failureMessage = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        request.resultTypes = [.pointOfInterest]
        // Gyms are the overwhelmingly likely intent, and filtering keeps
        // unrelated shops out of a list the user has to scan while half awake.
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: [.fitnessCenter, .stadium, .university, .school]
        )

        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 40_000,
                longitudinalMeters: 40_000
            )
        }

        let search = MKLocalSearch(request: request)
        currentSearch = search

        do {
            let response = try await search.start()
            guard !Task.isCancelled else { return }

            let origin = coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }

            results = response.mapItems.compactMap { item in
                GymSearchResult(item: item, from: origin)
            }
            failureMessage = results.isEmpty ? "no gyms found for that." : nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            // `MKLocalSearch` reports cancellation as an error; treating that as
            // a failure would flash a message on every keystroke.
            let isCancellation = (error as NSError).code == MKError.loadingThrottled.rawValue
            failureMessage = isCancellation ? nil : "couldn't search just now. check your connection?"
        }

        isSearching = false
    }
}

/// One place the user could pick as their gym.
struct GymSearchResult: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
    /// Metres from the user, when their position is known.
    let distance: Double?

    init?(item: MKMapItem, from origin: CLLocation?) {
        guard let name = item.name else { return nil }

        let coordinate = item.placemark.coordinate
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        id = "\(name)-\(coordinate.latitude)-\(coordinate.longitude)"

        let placemark = item.placemark
        let parts = [placemark.thoroughfare, placemark.locality, placemark.postalCode]
        subtitle = parts.compactMap { $0 }.joined(separator: ", ")

        if let origin {
            distance = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ).distance(from: origin)
        } else {
            distance = nil
        }
    }

    /// Human distance, e.g. "1.2 km" or "450 m".
    var distanceLabel: String? {
        guard let distance else { return nil }
        let measurement = Measurement(value: distance, unit: UnitLength.meters)
        return measurement.formatted(
            .measurement(width: .abbreviated, usage: .road)
        )
    }

    func asGymLocation() -> GymLocation {
        GymLocation(
            name: name,
            subtitle: subtitle,
            latitude: latitude,
            longitude: longitude
        )
    }
}
