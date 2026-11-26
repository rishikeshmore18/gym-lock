//
//  CantTodaySun.swift
//  GymLock · the "can't today" screen
//
//  When the sun in the Ridge sky is up. It follows the real sun: it rises at sunrise, crosses
//  the arc at midday and sets at sunset, at the place the person trains (the saved gym, else the
//  last place the phone knew). Before sunrise and after sunset it is below the horizon and the
//  sky is night, so the clock and the sky always agree. If no place is known the sky uses a plain
//  6:00 am to 6:00 pm day, so it still reads right.
//

import CoreLocation
import Foundation

struct CantTodayDaylight: Equatable {
    /// Local minutes after midnight.
    let sunrise: Int
    let sunset: Int
    /// False for the plain 6:00 am to 6:00 pm day used when no place is known.
    let isReal: Bool

    static let fallback = CantTodayDaylight(sunrise: 6 * 60, sunset: 18 * 60, isReal: false)

    /// Sunrise and sunset for a place on a day (NOAA's solar equations, 90.833 degrees for the
    /// sun's edge and the air's bend). Nil near the poles, where the sun does not rise or set.
    static func make(
        latitude: Double,
        longitude: Double,
        on date: Date,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> CantTodayDaylight? {
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }
        let daysInYear = Double(calendar.range(of: .day, in: .year, for: date)?.count ?? 365)
        let g = 2 * Double.pi / daysInYear * Double(dayOfYear - 1)

        let equationOfTime = 229.18 * (0.000075
            + 0.001868 * cos(g) - 0.032077 * sin(g)
            - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let declination = 0.006918
            - 0.399912 * cos(g) + 0.070257 * sin(g)
            - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)

        let lat = latitude * Double.pi / 180
        let cosHourAngle = cos(90.833 * Double.pi / 180) / (cos(lat) * cos(declination))
            - tan(lat) * tan(declination)
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }
        let hourAngle = acos(cosHourAngle) * 180 / Double.pi

        // Minutes after midnight UTC, then into the local zone.
        let utcRise = 720 - 4 * (longitude + hourAngle) - equationOfTime
        let utcSet = 720 - 4 * (longitude - hourAngle) - equationOfTime
        let offset = Double(timeZone.secondsFromGMT(for: date)) / 60
        func local(_ m: Double) -> Int {
            let r = Int((m + offset).rounded())
            return ((r % 1440) + 1440) % 1440
        }
        let rise = local(utcRise)
        let set = local(utcSet)
        guard rise != set else { return nil }
        return CantTodayDaylight(sunrise: rise, sunset: set, isReal: true)
    }

    /// The saved gym first, then the last place the phone knew (no new location request), else the plain day.
    static func current(gym: GymLocation?, on date: Date = Date()) -> CantTodayDaylight {
        if let gym, let d = make(latitude: gym.latitude, longitude: gym.longitude, on: date) {
            return d
        }
        if let c = CLLocationManager().location?.coordinate,
           CLLocationCoordinate2DIsValid(c),
           let d = make(latitude: c.latitude, longitude: c.longitude, on: date) {
            return d
        }
        return .fallback
    }
}
