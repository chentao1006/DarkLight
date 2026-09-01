//
//  AptabaseAnalytics.swift
//  Dark Light
//

import Foundation

/// Sends the small, anonymous event set used by Dark Light without collecting
/// account, browsing, screen, or device-identifying data.
final class AptabaseAnalytics {
    static let shared = AptabaseAnalytics()

    private static let appKey = "A-US-3733627961"
    private static let eventsURL = URL(string: "https://us.aptabase.com/api/v0/events")!

    private let sessionID: String
    private let urlSession: URLSession

    private init() {
        let epochSeconds = Int(Date().timeIntervalSince1970)
        let randomSuffix = String(format: "%08d", Int.random(in: 0...99_999_999))
        sessionID = "\(epochSeconds)\(randomSuffix)"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        urlSession = URLSession(configuration: configuration)
    }

    func trackEvent(_ eventName: String) {
        let event: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "sessionId": sessionID,
            "eventName": eventName,
            "systemProps": [
                "locale": Locale.current.identifier,
                "osName": operatingSystemName,
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
                "deviceModel": deviceFamily,
                "isDebug": isDebugBuild,
                "appVersion": appVersion,
                "sdkVersion": "dark-light@1.0.15"
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: [event]) else {
            return
        }

        var request = URLRequest(url: Self.eventsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.appKey, forHTTPHeaderField: "App-Key")
        request.httpBody = body

        urlSession.dataTask(with: request).resume()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var operatingSystemName: String {
        #if os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #else
        "Apple"
        #endif
    }

    private var deviceFamily: String {
        #if os(macOS)
        "Mac"
        #elseif os(iOS)
        "iPhone/iPad"
        #else
        "Apple device"
        #endif
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

@MainActor
final class DailyCheckInScheduler {
    static let shared = DailyCheckInScheduler()

    private var timer: Timer?

    private init() {}

    func start() {
        AptabaseAnalytics.shared.trackEvent("app_started")
        scheduleNextCheckIn()
    }

    private func scheduleNextCheckIn() {
        timer?.invalidate()

        let now = Date()
        guard let nextMidnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else {
            return
        }

        timer = Timer(fire: nextMidnight, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                AptabaseAnalytics.shared.trackEvent("daily_check_in")
                self?.scheduleNextCheckIn()
            }
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
