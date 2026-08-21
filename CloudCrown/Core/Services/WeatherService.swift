//
//  WeatherService.swift
//  CloudCrown
//
//  Fetches real conditions from Open-Meteo (no API key, CC BY 4.0).
//  Every value returned carries its unit, origin, timestamp and confidence.
//  Missing fields stay nil — they are never coerced to zero.
//

import Foundation

enum WeatherServiceError: LocalizedError {
    case offline
    case badResponse(Int)
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .offline: return "No connection to the forecast service."
        case .badResponse(let code): return "The forecast service replied with status \(code)."
        case .decoding(let d): return "The forecast response could not be read. \(d)"
        case .cancelled: return "The request was cancelled."
        }
    }

    var isOffline: Bool { if case .offline = self { return true }; return false }
}

protocol WeatherFetching {
    func fetchSnapshot(for place: Place, precision: LocationPrecision, forecastDays: Int) async throws -> ConditionSnapshot
}

final class WeatherService: WeatherFetching {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private static let hourlyForecastFields = [
        "temperature_2m", "apparent_temperature", "precipitation_probability", "precipitation",
        "wind_speed_10m", "wind_gusts_10m", "uv_index", "visibility",
        "relative_humidity_2m", "cloud_cover"
    ]

    private static let hourlyAirFields = [
        "us_aqi", "european_aqi", "alder_pollen", "birch_pollen", "grass_pollen",
        "mugwort_pollen", "olive_pollen", "ragweed_pollen"
    ]

    func fetchSnapshot(for place: Place, precision: LocationPrecision, forecastDays: Int = 7) async throws -> ConditionSnapshot {
        let coord = place.transmittedCoordinate(precision: precision)
        let days = min(max(forecastDays, 1), 10)

        async let forecast = fetchForecast(lat: coord.lat, lon: coord.lon, days: days)
        async let air = fetchAirQuality(lat: coord.lat, lon: coord.lon, days: min(days, 5))

        let forecastResponse = try await forecast
        // Air quality is optional: if it fails, those metrics become Unknown
        // rather than blocking the whole snapshot.
        let airResponse = try? await air

        let now = Date()
        var sources = [DataSource.openMeteoForecast(fetchedAt: now)]
        if airResponse != nil { sources.append(.openMeteoAir(fetchedAt: now)) }

        let timeZoneID = forecastResponse.timezone ?? place.timeZoneIdentifier
        let timeZone = TimeZone(identifier: timeZoneID) ?? place.timeZone

        let hours = buildHours(forecast: forecastResponse, air: airResponse, timeZone: timeZone, now: now)
        let days_ = buildDays(forecast: forecastResponse, timeZone: timeZone)

        var unavailable: [MetricKind] = []
        if airResponse == nil { unavailable.append(contentsOf: [.airQuality, .pollen]) }
        for metric in [MetricKind.visibility, .uvIndex] {
            if hours.allSatisfy({ $0.value(metric) == nil }) { unavailable.append(metric) }
        }

        return ConditionSnapshot(
            placeID: place.id,
            capturedAt: now,
            timeZoneIdentifier: timeZoneID,
            sources: sources,
            hours: hours,
            days: days_,
            unavailableMetrics: Array(Set(unavailable))
        )
    }

    // MARK: - Building samples

    private func buildHours(forecast: OpenMeteoForecastResponse,
                            air: OpenMeteoAirResponse?,
                            timeZone: TimeZone,
                            now: Date) -> [HourlyConditions] {
        guard let times = forecast.hourly?.time else { return [] }
        let parser = Self.makeDateParser(timeZone: timeZone)
        let h = forecast.hourly

        // Air-quality timestamps are aligned by string key, not by index,
        // because the two endpoints can return different horizons.
        var airIndex: [String: Int] = [:]
        if let airTimes = air?.hourly?.time {
            for (i, t) in airTimes.enumerated() { airIndex[t] = i }
        }

        let forecastSourceID = DataSource.openMeteoForecast(fetchedAt: now).id
        let airSourceID = DataSource.openMeteoAir(fetchedAt: now).id

        return times.enumerated().compactMap { index, timeString in
            guard let date = parser.date(from: timeString) else { return nil }
            let lead = date.timeIntervalSince(now)
            let observation: ObservationKind = lead < -1800 ? .observed : .forecast
            let confidence = observation == .observed ? Confidence.high : Confidence.forForecast(leadTime: max(0, lead))

            func make(_ kind: MetricKind, _ raw: Double?, source: String, transform: ((Double) -> Double)? = nil) -> MetricSample {
                let converted = raw.map { transform?($0) ?? $0 }
                return MetricSample(
                    kind: kind,
                    value: MetricValue(value: converted,
                                       unit: kind.canonicalUnit,
                                       observation: observation,
                                       updatedAt: now,
                                       confidence: converted == nil ? .unknown : confidence,
                                       sourceID: source)
                )
            }

            // Built with explicit appends: a single large array literal pushes
            // the type checker past its budget.
            var samples: [MetricSample] = []
            let temperature: Double? = h?.temperature_2m?[safe: index] ?? nil
            let apparent: Double? = h?.apparent_temperature?[safe: index] ?? nil
            let precipProbability: Double? = h?.precipitation_probability?[safe: index] ?? nil
            let precipAmount: Double? = h?.precipitation?[safe: index] ?? nil
            let wind: Double? = h?.wind_speed_10m?[safe: index] ?? nil
            let gust: Double? = h?.wind_gusts_10m?[safe: index] ?? nil
            let uv: Double? = h?.uv_index?[safe: index] ?? nil
            let humidity: Double? = h?.relative_humidity_2m?[safe: index] ?? nil
            let cloud: Double? = h?.cloud_cover?[safe: index] ?? nil
            let visibilityMetres: Double? = h?.visibility?[safe: index] ?? nil

            samples.append(make(.temperature, temperature, source: forecastSourceID))
            samples.append(make(.apparentTemperature, apparent, source: forecastSourceID))
            samples.append(make(.precipitationProbability, precipProbability, source: forecastSourceID))
            samples.append(make(.precipitationAmount, precipAmount, source: forecastSourceID))
            samples.append(make(.windSpeed, wind, source: forecastSourceID))
            samples.append(make(.windGust, gust, source: forecastSourceID))
            samples.append(make(.uvIndex, uv, source: forecastSourceID))
            samples.append(make(.humidity, humidity, source: forecastSourceID))
            samples.append(make(.cloudCover, cloud, source: forecastSourceID))
            // Open-Meteo reports visibility in metres; the app stores kilometres.
            samples.append(make(.visibility, visibilityMetres, source: forecastSourceID) { $0 / 1000 })

            if let ai = airIndex[timeString], let a = air?.hourly {
                let aqi: Double? = a.us_aqi?[safe: ai] ?? nil
                samples.append(make(.airQuality, aqi, source: airSourceID))
                var pollenReadings: [Double?] = []
                pollenReadings.append(a.alder_pollen?[safe: ai] ?? nil)
                pollenReadings.append(a.birch_pollen?[safe: ai] ?? nil)
                pollenReadings.append(a.grass_pollen?[safe: ai] ?? nil)
                pollenReadings.append(a.mugwort_pollen?[safe: ai] ?? nil)
                pollenReadings.append(a.olive_pollen?[safe: ai] ?? nil)
                pollenReadings.append(a.ragweed_pollen?[safe: ai] ?? nil)
                let pollens = pollenReadings.compactMap { $0 }
                // The dominant pollen drives the reading; no data means Unknown.
                samples.append(make(.pollen, pollens.isEmpty ? nil : pollens.max(), source: airSourceID))
            } else {
                samples.append(MetricSample(kind: .airQuality, value: .unknown(unit: MetricKind.airQuality.canonicalUnit, sourceID: airSourceID, updatedAt: now)))
                samples.append(MetricSample(kind: .pollen, value: .unknown(unit: MetricKind.pollen.canonicalUnit, sourceID: airSourceID, updatedAt: now)))
            }

            return HourlyConditions(date: date, samples: samples)
        }
    }

    private func buildDays(forecast: OpenMeteoForecastResponse, timeZone: TimeZone) -> [DailyConditions] {
        guard let times = forecast.daily?.time else { return [] }
        let dayParser = Self.makeDayParser(timeZone: timeZone)
        let dateTimeParser = Self.makeDateParser(timeZone: timeZone)
        let d = forecast.daily

        return times.enumerated().compactMap { index, dayString in
            guard let date = dayParser.date(from: dayString) else { return nil }
            let sunrise = (d?.sunrise?[safe: index] ?? nil).flatMap { dateTimeParser.date(from: $0) }
            let sunset = (d?.sunset?[safe: index] ?? nil).flatMap { dateTimeParser.date(from: $0) }
            let daylight: Double? = {
                if let seconds = d?.daylight_duration?[safe: index] ?? nil { return seconds / 60 }
                guard let sunrise = sunrise, let sunset = sunset else { return nil }
                return sunset.timeIntervalSince(sunrise) / 60
            }()
            return DailyConditions(
                date: date,
                sunrise: sunrise,
                sunset: sunset,
                daylightMinutes: daylight,
                maxUV: d?.uv_index_max?[safe: index] ?? nil,
                precipitationSum: d?.precipitation_sum?[safe: index] ?? nil
            )
        }
    }

    // MARK: - Requests

    private func fetchForecast(lat: Double, lon: Double, days: Int) async throws -> OpenMeteoForecastResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "hourly", value: Self.hourlyForecastFields.joined(separator: ",")),
            URLQueryItem(name: "daily", value: "sunrise,sunset,daylight_duration,uv_index_max,precipitation_sum"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(days)),
            URLQueryItem(name: "past_hours", value: "3")
        ]
        return try await perform(components.url!, as: OpenMeteoForecastResponse.self)
    }

    private func fetchAirQuality(lat: Double, lon: Double, days: Int) async throws -> OpenMeteoAirResponse {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "hourly", value: Self.hourlyAirFields.joined(separator: ",")),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(days))
        ]
        return try await perform(components.url!, as: OpenMeteoAirResponse.self)
    }

    private func perform<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadRevalidatingCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WeatherServiceError.badResponse(-1) }
            guard (200...299).contains(http.statusCode) else { throw WeatherServiceError.badResponse(http.statusCode) }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw WeatherServiceError.decoding(error.localizedDescription)
            }
        } catch let error as WeatherServiceError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .timedOut:
                throw WeatherServiceError.offline
            case .cancelled:
                throw WeatherServiceError.cancelled
            default:
                throw WeatherServiceError.offline
            }
        }
    }

    // MARK: - Parsers

    private static func makeDateParser(timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    private static func makeDayParser(timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }
}

// MARK: - Wire format

struct OpenMeteoForecastResponse: Decodable {
    var timezone: String?
    var hourly: Hourly?
    var daily: Daily?

    struct Hourly: Decodable {
        var time: [String]?
        var temperature_2m: [Double?]?
        var apparent_temperature: [Double?]?
        var precipitation_probability: [Double?]?
        var precipitation: [Double?]?
        var wind_speed_10m: [Double?]?
        var wind_gusts_10m: [Double?]?
        var uv_index: [Double?]?
        var visibility: [Double?]?
        var relative_humidity_2m: [Double?]?
        var cloud_cover: [Double?]?
    }

    struct Daily: Decodable {
        var time: [String]?
        var sunrise: [String?]?
        var sunset: [String?]?
        var daylight_duration: [Double?]?
        var uv_index_max: [Double?]?
        var precipitation_sum: [Double?]?
    }
}

struct OpenMeteoAirResponse: Decodable {
    var hourly: Hourly?

    struct Hourly: Decodable {
        var time: [String]?
        var us_aqi: [Double?]?
        var european_aqi: [Double?]?
        var alder_pollen: [Double?]?
        var birch_pollen: [Double?]?
        var grass_pollen: [Double?]?
        var mugwort_pollen: [Double?]?
        var olive_pollen: [Double?]?
        var ragweed_pollen: [Double?]?
    }
}

extension Array {
    /// Bounds-safe lookup: the two endpoints can disagree on array lengths.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
