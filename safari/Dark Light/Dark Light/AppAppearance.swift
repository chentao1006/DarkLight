#if os(macOS)
import AppKit
import Combine
import CoreGraphics
import CoreMedia
import CoreVideo
import MetalKit
import ScreenCaptureKit
import ServiceManagement
import SwiftUI

let darkLightLoginItemLaunchArgument = "--darklight-login-item"

@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()
    private static let legacyHelperBundleIdentifier = "com.ct106.darklight.LoginItem"
    private static let legacyEnabledDefaultsKey = "darkLight.legacyLoginItemEnabled"

    @Published private(set) var isAvailable = false
    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?

    private init() {
        refresh()
    }

    func refresh() {
        guard #available(macOS 13.0, *) else {
            isAvailable = true
            isEnabled = UserDefaults.standard.bool(forKey: Self.legacyEnabledDefaultsKey)
            return
        }
        isAvailable = true
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            let didUpdate = SMLoginItemSetEnabled(Self.legacyHelperBundleIdentifier as CFString, enabled)
            if didUpdate {
                UserDefaults.standard.set(enabled, forKey: Self.legacyEnabledDefaultsKey)
                errorMessage = nil
            } else {
                errorMessage = "macOS could not update the login item."
            }
            refresh()
            return
        }

        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}

/// A visual preference for an app window. The original app is never changed;
/// Dark Light only renders a real-time, GPU-filtered mirror above it.
enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case followSystem
    case forceDark
    case forceLight
    case timeBased
    case preserveApp = "preserveSite"

    var id: String { rawValue }

    var menuTag: Int {
        switch self {
        case .followSystem: return 1
        case .forceDark: return 2
        case .forceLight: return 3
        case .timeBased: return 4
        case .preserveApp: return 5
        }
    }

    init?(menuTag: Int) {
        switch menuTag {
        case 1: self = .followSystem
        case 2: self = .forceDark
        case 3: self = .forceLight
        case 4: self = .timeBased
        case 5: self = .preserveApp
        default: return nil
        }
    }

    func title(language: String) -> String {
        switch language {
        case "zh":
            switch self {
            case .followSystem: return "跟随系统外观"
            case .forceDark: return "强制深色"
            case .forceLight: return "强制浅色"
            case .timeBased: return "根据时间段改变"
            case .preserveApp: return "保持应用原样"
            }
        case "ja":
            switch self {
            case .followSystem: return "システムに従う"
            case .forceDark: return "強制的にダーク"
            case .forceLight: return "強制的にライト"
            case .timeBased: return "時間帯で切り替え"
            case .preserveApp: return "アプリの表示をそのまま使う"
            }
        case "ko":
            switch self {
            case .followSystem: return "시스템 따르기"
            case .forceDark: return "강제 다크"
            case .forceLight: return "강제 라이트"
            case .timeBased: return "시간대에 따라 변경"
            case .preserveApp: return "앱 모양 유지"
            }
        case "es":
            switch self {
            case .followSystem: return "Seguir al sistema"
            case .forceDark: return "Forzar oscuro"
            case .forceLight: return "Forzar claro"
            case .timeBased: return "Cambiar según horario"
            case .preserveApp: return "Mantener apariencia de la app"
            }
        case "fr":
            switch self {
            case .followSystem: return "Suivre le système"
            case .forceDark: return "Forcer le mode sombre"
            case .forceLight: return "Forcer le mode clair"
            case .timeBased: return "Changer selon l’horaire"
            case .preserveApp: return "Conserver l’apparence de l’app"
            }
        case "de":
            switch self {
            case .followSystem: return "System folgen"
            case .forceDark: return "Dunkel erzwingen"
            case .forceLight: return "Hell erzwingen"
            case .timeBased: return "Nach Zeitplan wechseln"
            case .preserveApp: return "App-Erscheinungsbild beibehalten"
            }
        default:
            switch self {
            case .followSystem: return "Follow System"
            case .forceDark: return "Force Dark"
            case .forceLight: return "Force Light"
            case .timeBased: return "Change by Time"
            case .preserveApp: return "Keep App Appearance"
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        // Migration from the first App Filters preview.
        case "dark": self = .forceDark
        case "light": self = .forceLight
        default:
            guard let mode = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown app appearance mode: \(rawValue)")
            }
            self = mode
        }
    }
}

private struct AppAppearanceSchedule: Codable, Equatable {
    var darkStartMinutes = 19 * 60
    var darkEndMinutes = 7 * 60
}

struct AppAppearanceRule: Codable, Identifiable, Equatable {
    let bundleIdentifier: String
    var appName: String
    var mode: AppAppearanceMode
    var isEnabled: Bool

    var id: String { bundleIdentifier }
}

struct AppAppearanceCandidate: Identifiable {
    let bundleIdentifier: String
    let appName: String
    let icon: NSImage

    var id: String { bundleIdentifier }
}

private struct TrackedWindow: Equatable {
    let windowID: CGWindowID
    let frame: CGRect
}

private struct FilterTarget {
    let window: TrackedWindow
    let rule: AppAppearanceRule
    let resolvedMode: AppAppearanceMode
    let isFrontmost: Bool
}

@MainActor
final class AppAppearanceController: NSObject, ObservableObject {
    static let shared = AppAppearanceController()
    static let freeAppRuleLimit = 3

    @Published private(set) var rules: [AppAppearanceRule] = []
    @Published private(set) var activeAppName: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var hasScreenCapturePermission = false
    @Published private(set) var isFiltering = false
    @Published private(set) var hasPremiumAccess = false
    @Published private var schedule = AppAppearanceSchedule()

    private let storageKey = "DarkLight.appAppearanceRules.v1"
    private let scheduleStorageKey = "DarkLight.appAppearanceSchedule.v1"
    private var workspaceObservers: [NSObjectProtocol] = []
    private var trackingTimer: Timer?
    private var trackingInterval: TimeInterval?
    private var captureSessions: [CGWindowID: WindowCaptureSessionProtocol] = [:]
    private var desiredWindowIDs: Set<CGWindowID> = []
    private var pendingCaptureWindowIDs: Set<CGWindowID> = []
    private var didStart = false
    private var permissionProbeInFlight = false
    private var didProbeScreenCapturePermission = false

    private override init() {
        super.init()
        loadRules()
        loadSchedule()
        // Cheap, side-effect-free read only. Do not call refreshScreenCapturePermission()
        // here: its SCShareableContent fallback triggers the system Screen Recording
        // prompt as a side effect, which must never fire before the user has actually
        // opted into App Theme Control.
        hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
    }

    deinit {
        trackingTimer?.invalidate()
        workspaceObservers.forEach(NotificationCenter.default.removeObserver)
    }

    var hasActiveFilterRules: Bool {
        rules.contains { $0.isEnabled && $0.mode != .preserveApp }
    }

    var canAddAnotherApp: Bool {
        hasPremiumAccess || rules.count < Self.freeAppRuleLimit
    }

    func setPremiumAccess(_ hasPremiumAccess: Bool) {
        self.hasPremiumAccess = hasPremiumAccess
    }

    func start() {
        refreshPremiumAccess()
        guard !didStart else { return }
        didStart = true
        rememberExternalFrontmostApplication()

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                let processIdentifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                // This observer is explicitly delivered on the main queue.
                // Do not enqueue another Task: when the source application is
                // activated, that extra turn lets its light window rise above
                // the normal-level panel for one visible frame.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rememberExternalFrontmostApplication(processIdentifier: processIdentifier)
                    self.refreshNow()
                }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [self] in self.refreshNow() }
            },
            center.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [self] in self.refreshNow() }
            }
        ]

        updateTrackingState()
        refreshNow()
    }

    private func refreshPremiumAccess() {
        Task { [weak self] in
            let hasPremiumAccess = await ProStore.hasUnlockedPro()
            self?.setPremiumAccess(hasPremiumAccess)
        }
    }

    func refreshNow() {
        guard hasActiveFilterRules else {
            stopFiltering(message: nil)
            return
        }
        // Only probe permission (which can trigger the system prompt as a side
        // effect) once there is actually something to filter.
        refreshScreenCapturePermission()
        guard hasScreenCapturePermission else {
            stopFiltering(message: screenCapturePermissionMessage)
            return
        }
        let targets = visibleTargets()
        desiredWindowIDs = Set(targets.map(\.window.windowID))
        let targetNames = targets.filter(\.isFrontmost).map(\.rule.appName)
        activeAppName = targetNames.first

        // A window absent from the active Space must disappear immediately.
        // Retaining the last capture through a grace period makes its mirror
        // visibly travel to a Space where the source window does not exist.
        let obsoleteWindowIDs = captureSessions.keys.filter { !desiredWindowIDs.contains($0) }
        for windowID in obsoleteWindowIDs {
            captureSessions[windowID]?.stop()
            captureSessions.removeValue(forKey: windowID)
        }

        for target in targets {
            // A foreground mirror needs one captured frame per display frame
            // where possible. Background windows retain the low-power rate.
            let rate: Int32 = target.isFrontmost ? 60 : 5
            if let session = captureSessions[target.window.windowID] {
                session.update(
                    frame: cocoaFrame(from: target.window.frame),
                    mode: target.resolvedMode,
                    frameRate: rate,
                    isFrontmost: target.isFrontmost
                )
            } else if !pendingCaptureWindowIDs.contains(target.window.windowID) {
                beginCapture(target, frameRate: rate)
            }
        }
        isFiltering = !captureSessions.isEmpty
        updateTrackingState()
        if targets.isEmpty {
            statusMessage = nil
        }
    }

    func requestScreenCapturePermission() {
        guard !CGPreflightScreenCaptureAccess() else {
            refreshScreenCapturePermission(force: true)
            return
        }
        // This is the system-owned prompt. Dark Light never reads or stores
        // captured pixels outside of the short-lived GPU texture.
        let requestWasAccepted = CGRequestScreenCaptureAccess()
        if !requestWasAccepted {
            statusMessage = screenCaptureRequestPendingMessage
            // TCC only presents the system consent prompt once. After a prior
            // denial, the user must change the permission in System Settings.
            openScreenRecordingSettings()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshScreenCapturePermission(force: true)
        }
    }

    func refreshScreenCapturePermission(force: Bool = false) {
        // CGPreflight is fast but can remain stale immediately after a user
        // changes the Privacy & Security switch. Probe the public
        // ScreenCaptureKit source list as the authoritative fallback.
        let preflightGranted = CGPreflightScreenCaptureAccess()
        if preflightGranted {
            hasScreenCapturePermission = true
            return
        }
        guard #available(macOS 12.3, *) else {
            hasScreenCapturePermission = false
            return
        }
        guard force || !didProbeScreenCapturePermission else { return }
        guard !permissionProbeInFlight else { return }
        didProbeScreenCapturePermission = true
        permissionProbeInFlight = true
        Task { [weak self] in
            defer { self?.permissionProbeInFlight = false }
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                self?.hasScreenCapturePermission = true
                self?.statusMessage = nil
                self?.refreshNow()
            } catch {
                self?.hasScreenCapturePermission = false
                self?.statusMessage = self?.screenCaptureProbeFailureMessage(error)
            }
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func availableApplications() -> [AppAppearanceCandidate] {
        NSWorkspace.shared.runningApplications
            .compactMap { app -> AppAppearanceCandidate? in
                guard app.activationPolicy == .regular,
                      let bundleIdentifier = app.bundleIdentifier,
                      bundleIdentifier != Bundle.main.bundleIdentifier else {
                    return nil
                }
                return AppAppearanceCandidate(
                    bundleIdentifier: bundleIdentifier,
                    appName: app.localizedName ?? bundleIdentifier,
                    icon: app.icon ?? NSImage()
                )
            }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    func applicationCandidate(at url: URL) -> AppAppearanceCandidate? {
        guard url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        let appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return AppAppearanceCandidate(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            icon: NSWorkspace.shared.icon(forFile: url.path)
        )
    }

    /// The menu bar does not always become the frontmost regular application.
    /// Remembering the last external app lets its menu operate on the app the
    /// user was working in immediately before opening Dark Light's menu.
    func focusedApplication() -> AppAppearanceCandidate? {
        rememberExternalFrontmostApplication()
        guard let app = lastExternalFrontmostApplication else { return nil }
        return candidate(for: app)
    }

    func enabledRule(for application: AppAppearanceCandidate) -> AppAppearanceRule? {
        rules.first { $0.bundleIdentifier == application.bundleIdentifier && $0.isEnabled }
    }

    func setAppearance(_ mode: AppAppearanceMode, forFocusedApplication application: AppAppearanceCandidate? = nil) {
        guard let application = application ?? focusedApplication() else { return }
        addRule(for: application, mode: mode)
    }

    func stopFilteringFocusedApplication(_ application: AppAppearanceCandidate? = nil) {
        guard let application = application ?? focusedApplication(),
              let rule = rules.first(where: { $0.bundleIdentifier == application.bundleIdentifier }) else {
            return
        }
        remove(rule)
    }

    @discardableResult
    func addRule(for app: AppAppearanceCandidate, mode: AppAppearanceMode) -> Bool {
        if mode == .preserveApp {
            if let existingRule = rules.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                remove(existingRule)
            }
            return true
        }
        if let index = rules.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            rules[index].appName = app.appName
            rules[index].mode = mode
            rules[index].isEnabled = true
        } else {
            guard canAddAnotherApp else { return false }
            rules.append(AppAppearanceRule(bundleIdentifier: app.bundleIdentifier, appName: app.appName, mode: mode, isEnabled: true))
        }
        persistRules()
        updateTrackingState()
        refreshNow()
        return true
    }

    func setEnabled(_ enabled: Bool, for rule: AppAppearanceRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].isEnabled = enabled
        persistRules()
        updateTrackingState()
        refreshNow()
    }

    func setMode(_ mode: AppAppearanceMode, for rule: AppAppearanceRule) {
        if mode == .preserveApp {
            remove(rule)
            return
        }
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index].mode = mode
        rules[index].isEnabled = true
        persistRules()
        updateTrackingState()
        refreshNow()
    }

    func setScheduleTime(_ date: Date, isStart: Bool) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if isStart {
            schedule.darkStartMinutes = minutes
        } else {
            schedule.darkEndMinutes = minutes
        }
        persistSchedule()
        refreshNow()
    }

    func scheduleDate(isStart: Bool) -> Date {
        let minutes = isStart ? schedule.darkStartMinutes : schedule.darkEndMinutes
        return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    func remove(_ rule: AppAppearanceRule) {
        rules.removeAll { $0.id == rule.id }
        persistRules()
        updateTrackingState()
        refreshNow()
    }

    func pause() {
        rules = rules.map { rule in
            var changed = rule
            changed.isEnabled = false
            return changed
        }
        persistRules()
        updateTrackingState()
        stopFiltering(message: nil)
    }

    private func updateTrackingState() {
        guard hasActiveFilterRules else {
            trackingTimer?.invalidate()
            trackingTimer = nil
            trackingInterval = nil
            return
        }

        // A source window comes to the front above normal-level panels. Keep
        // the overlay ordered above it at display cadence while it is active,
        // so an app switch or a drag never leaves the unfiltered source exposed.
        // Background windows deliberately use a much cheaper poll because their
        // capture streams themselves run at 5 fps.
        let desiredInterval: TimeInterval
        if captureSessions.isEmpty {
            desiredInterval = 1.5
        } else if activeAppName != nil {
            desiredInterval = 1.0 / 60.0
        } else {
            desiredInterval = 0.2
        }
        guard trackingTimer == nil || trackingInterval != desiredInterval else { return }
        trackingTimer?.invalidate()
        trackingInterval = desiredInterval
        let timer = Timer(timeInterval: desiredInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.refreshNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func beginCapture(_ target: FilterTarget, frameRate: Int32) {
        guard #available(macOS 12.3, *) else {
            stopFiltering(message: "App Theme Control requires macOS 12.3 or later.")
            return
        }

        let expectedWindowID = target.window.windowID
        let expectedFrame = cocoaFrame(from: target.window.frame)
        let mode = target.resolvedMode
        pendingCaptureWindowIDs.insert(expectedWindowID)

        Task { [weak self] in
            defer { self?.pendingCaptureWindowIDs.remove(expectedWindowID) }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let self,
                      self.desiredWindowIDs.contains(expectedWindowID),
                      let sourceWindow = content.windows.first(where: { $0.windowID == expectedWindowID }) else {
                    return
                }

                let session = WindowCaptureSession(
                    window: sourceWindow,
                    frame: expectedFrame,
                    mode: mode,
                    frameRate: frameRate,
                    isFrontmost: target.isFrontmost
                )
                self.captureSessions[expectedWindowID] = session
                self.isFiltering = true
                self.updateTrackingState()
                self.statusMessage = nil
                session.start { [weak self] error in
                    guard let self else { return }
                    if let error {
                        self.captureSessions.removeValue(forKey: expectedWindowID)
                        self.isFiltering = !self.captureSessions.isEmpty
                        self.updateTrackingState()
                        self.statusMessage = error.localizedDescription
                    }
                }
            } catch {
                self?.statusMessage = error.localizedDescription
            }
        }
    }

    private func stopFiltering(message: String?) {
        captureSessions.values.forEach { $0.stop() }
        captureSessions.removeAll()
        desiredWindowIDs.removeAll()
        pendingCaptureWindowIDs.removeAll()
        activeAppName = nil
        isFiltering = false
        statusMessage = message
        updateTrackingState()
    }

    private func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AppAppearanceRule].self, from: data) else {
            return
        }
        rules = decoded
    }

    private func loadSchedule() {
        guard let data = UserDefaults.standard.data(forKey: scheduleStorageKey),
              let decoded = try? JSONDecoder().decode(AppAppearanceSchedule.self, from: data) else {
            return
        }
        schedule = decoded
    }

    private func persistRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func persistSchedule() {
        if let data = try? JSONEncoder().encode(schedule) {
            UserDefaults.standard.set(data, forKey: scheduleStorageKey)
        }
    }

    private func visibleTargets() -> [FilterTarget] {
        let enabledRules = Dictionary(uniqueKeysWithValues: rules.filter(\.isEnabled).map { ($0.bundleIdentifier, $0) })
        let applicationsByPID = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String)? in
            guard let bundleIdentifier = app.bundleIdentifier else { return nil }
            return (app.processIdentifier, bundleIdentifier)
        })
        // Keep the cached external app for the status-menu action, but never
        // use that cache to decide z-order. When Dark Light itself becomes
        // frontmost, the cached app is stale and would leave its panel floating
        // above our own preferences window.
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostPID: pid_t?
        if let frontmostApplication,
           frontmostApplication.activationPolicy == .regular,
           frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalFrontmostApplication = frontmostApplication
            frontmostPID = frontmostApplication.processIdentifier
        } else {
            frontmostPID = nil
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var targets: [FilterTarget] = []
        for info in windows {
            guard let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }
            let ownerPID = pid_t(ownerPIDNumber.int32Value)
            guard let bundleIdentifier = applicationsByPID[ownerPID],
                  let rule = enabledRules[bundleIdentifier],
                  let resolvedMode = resolvedFilterMode(for: rule) else {
                continue
            }
            var frame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds, &frame),
                  frame.width >= 120,
                  frame.height >= 80 else {
                continue
            }
            targets.append(FilterTarget(
                window: TrackedWindow(windowID: CGWindowID(number.uint32Value), frame: frame.integral),
                rule: rule,
                resolvedMode: resolvedMode,
                isFrontmost: ownerPID == frontmostPID
            ))
        }
        return targets
    }

    private func cocoaFrame(from quartzFrame: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { screen in
            screen.frame.intersects(CGRect(x: quartzFrame.minX, y: screen.frame.minY, width: quartzFrame.width, height: quartzFrame.height))
        } ?? NSScreen.main
        guard let screen else { return quartzFrame }
        return CGRect(
            x: quartzFrame.minX,
            y: screen.frame.maxY - quartzFrame.maxY,
            width: quartzFrame.width,
            height: quartzFrame.height
        ).integral
    }

    private var lastExternalFrontmostApplication: NSRunningApplication?

    private func rememberExternalFrontmostApplication(processIdentifier: pid_t? = nil) {
        let application = processIdentifier.flatMap { processIdentifier in
            NSWorkspace.shared.runningApplications.first { $0.processIdentifier == processIdentifier }
        } ?? NSWorkspace.shared.frontmostApplication
        guard let application,
              application.activationPolicy == .regular,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        lastExternalFrontmostApplication = application
    }

    private func candidate(for app: NSRunningApplication) -> AppAppearanceCandidate? {
        guard app.activationPolicy == .regular,
              let bundleIdentifier = app.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        return AppAppearanceCandidate(
            bundleIdentifier: bundleIdentifier,
            appName: app.localizedName ?? bundleIdentifier,
            icon: app.icon ?? NSImage()
        )
    }

    private func resolvedFilterMode(for rule: AppAppearanceRule) -> AppAppearanceMode? {
        switch rule.mode {
        case .forceDark:
            return .forceDark
        case .forceLight:
            return .forceLight
        case .followSystem:
            return systemUsesDarkAppearance ? .forceDark : .forceLight
        case .timeBased:
            return isWithinDarkSchedule ? .forceDark : .forceLight
        case .preserveApp:
            return nil
        }
    }

    private var systemUsesDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var isWithinDarkSchedule: Bool {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let start = schedule.darkStartMinutes
        let end = schedule.darkEndMinutes
        if start == end { return false }
        return start < end ? minutes >= start && minutes < end : minutes >= start || minutes < end
    }

    private var usesChinese: Bool {
        Locale.current.languageCode?.hasPrefix("zh") == true
    }

    private var screenCapturePermissionMessage: String {
        usesChinese
            ? "仍需要“屏幕与系统音频录制”权限；请确认系统设置里勾选的是当前安装的“暗光”。"
            : "Screen & System Audio Recording permission is still needed. Make sure the currently installed Dark Light is enabled in System Settings."
    }

    private var screenCaptureRequestPendingMessage: String {
        usesChinese
            ? "macOS 未再次显示授权提示。请在已打开的系统设置中允许“暗光”，然后完全退出并重新打开暗光。"
            : "macOS did not show the permission prompt again. Allow Dark Light in the opened System Settings pane, then fully quit and reopen Dark Light."
    }

    private func screenCaptureProbeFailureMessage(_ error: Error) -> String {
        let detail = (error as NSError).localizedDescription
        if usesChinese {
            return "屏幕录制仍不可用：\(detail)"
        }
        return "Screen capture is still unavailable: \(detail)"
    }
}

private protocol WindowCaptureSessionProtocol: AnyObject {
    func update(frame: CGRect, mode: AppAppearanceMode, frameRate: Int32, isFrontmost: Bool)
    func stop()
}

private let windowOverlayEdgeBleed: CGFloat = 2

@available(macOS 12.3, *)
private func streamMetadataRect(_ metadata: [SCStreamFrameInfo: Any]?, for key: SCStreamFrameInfo) -> CGRect? {
    guard let value = metadata?[key] else { return nil }
    if let rect = value as? CGRect { return rect }
    guard let dictionary = value as? NSDictionary else { return nil }
    var rect = CGRect.zero
    return CGRectMakeWithDictionaryRepresentation(dictionary, &rect) ? rect : nil
}

@available(macOS 12.3, *)
private final class WindowCaptureSession: NSObject, WindowCaptureSessionProtocol, SCStreamOutput, SCStreamDelegate {
    private let sourceWindow: SCWindow
    private let renderer: WindowFilterRenderer
    private let panel: NSPanel
    private let contentContainer: NSView
    private let captureQueue = DispatchQueue(label: "com.ct106.darklight.window-capture", qos: .userInteractive)
    private var stream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?
    private var currentFrame: CGRect
    private var currentMode: AppAppearanceMode
    private var currentFrameRate: Int32
    private var isSourceFrontmost: Bool
    private var pendingGeometryCorrection: DispatchWorkItem?
    private var stopped = false
    private var isFilterNeeded = false
    private var onFailure: ((Error?) -> Void)?

    // The system's window-capture affordance is attached to the top-leading
    // corner of the presenting panel. Give it room above the mirrored content
    // rather than letting it sit on the source window's traffic-light area.
    private let captureAffordanceClearance: CGFloat = 42
    // Window decoration is not part of every ScreenCaptureKit surface. Draw a
    // tiny amount past the reported frame so the filtered edge covers the
    // native light border that is otherwise visible after deactivation.
    private static let edgeBleed = windowOverlayEdgeBleed

    init(window: SCWindow, frame: CGRect, mode: AppAppearanceMode, frameRate: Int32, isFrontmost: Bool) {
        sourceWindow = window
        currentFrame = frame
        currentMode = mode
        currentFrameRate = frameRate
        isSourceFrontmost = isFrontmost
        renderer = WindowFilterRenderer(mode: mode)
        contentContainer = NSView(frame: NSRect(origin: .zero, size: Self.overlayFrame(for: frame, extraTop: 42).size))
        panel = NSPanel(
            contentRect: Self.overlayFrame(for: frame, extraTop: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        // Keep the overlay immediately above its source window instead of at
        // a global floating level. This preserves the normal z-order when
        // another app overlaps an inactive filtered window.
        panel.level = isFrontmost ? .floating : .normal
        // The captured app may have rounded corners. A normal opaque panel
        // paints its rectangular backing store into those four corner pixels.
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // The mirror belongs only to the source window's current Space.
        // `moveToActiveSpace` incorrectly carries a captured image of that
        // window onto every Space/display the user visits, making the source
        // appear to teleport. Keep the default managed-Space behavior instead.
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        contentContainer.wantsLayer = true
        contentContainer.layer?.isOpaque = false
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        contentContainer.addSubview(renderer.view)
        panel.contentView = contentContainer
        updatePanelGeometry(for: frame)
        // Leave an already-matching app window untouched. Only show the
        // mirror after a captured frame proves that inversion is needed.
        renderer.onFilterNeededChange = { [weak self] isNeeded in
            guard let self, !self.stopped else { return }
            self.isFilterNeeded = isNeeded
            if isNeeded {
                self.panel.order(.above, relativeTo: Int(window.windowID))
            } else {
                self.panel.orderOut(nil)
            }
        }
    }

    func start(completion: @escaping (Error?) -> Void) {
        onFailure = completion
        let filter = SCContentFilter(desktopIndependentWindow: sourceWindow)
        let configuration = SCStreamConfiguration()
        applyOutputSize(to: configuration, frameRate: currentFrameRate)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: currentFrameRate)
        configuration.showsCursor = false
        if #available(macOS 14.0, *) {
            // Preserve the captured window's native alpha edge. Forcing
            // transparency opaque produces the white halo seen around some
            // third-party window corners.
            configuration.shouldBeOpaque = false
            // This stream is only rendered locally as a visual filter; it
            // does not use Presenter Overlay. Avoid a system-injected
            // Presenter Overlay privacy pill covering the source title bar.
            configuration.presenterOverlayPrivacyAlertSetting = .never
        }
        if #available(macOS 13.0, *) {
            configuration.capturesAudio = false
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        streamConfiguration = configuration
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        } catch {
            completion(error)
            return
        }

        Task {
            do {
                try await stream.startCapture()
            } catch {
                completion(error)
            }
        }
    }

    func update(frame: CGRect, mode: AppAppearanceMode, frameRate: Int32, isFrontmost: Bool) {
        currentMode = mode
        renderer.mode = mode
        if isSourceFrontmost != isFrontmost {
            isSourceFrontmost = isFrontmost
            // While the source is active its normal-level window can be
            // raised by every mouse-down. Floating prevents even a one-frame
            // glimpse of the original light UI; inactive overlays go back to
            // normal level so they continue to respect other apps' z-order.
            panel.level = isFrontmost ? .floating : .normal
        }
        if frame != currentFrame {
            let previousFrame = currentFrame
            currentFrame = frame
            let sizeChanged = frame.size != previousFrame.size
            // A normal window drag holds a mouse button; a Space swipe does
            // not. Keep drag/resize tracking smooth. During a Space swipe,
            // WindowServer supplies the transform, then correct exactly once
            // after CGWindowList's final geometry has settled.
            if sizeChanged || NSEvent.pressedMouseButtons != 0 {
                pendingGeometryCorrection?.cancel()
                pendingGeometryCorrection = nil
                updatePanelGeometry(for: frame)
            } else {
                scheduleSettledGeometryCorrection(for: frame)
            }
        }
        // Activating the source application can reorder it above this panel
        // without changing its frame. Reasserting the relative order here is
        // intentionally cheap and makes the overlay survive focus changes.
        if isFilterNeeded {
            panel.order(.above, relativeTo: Int(sourceWindow.windowID))
        }
        guard frameRate != currentFrameRate else { return }
        currentFrameRate = frameRate
        guard let stream else { return }
        guard let configuration = streamConfiguration else { return }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: frameRate)
        // A background window is intentionally cheap (about 720p), while a
        // window that becomes active returns to the full 1440p texture budget.
        applyOutputSize(to: configuration, frameRate: frameRate)
        Task {
            try? await stream.updateConfiguration(configuration)
        }
    }

    private func applyOutputSize(to configuration: SCStreamConfiguration, frameRate: Int32) {
        let scale = max(1, NSScreen.main?.backingScaleFactor ?? 1)
        let requestedWidth = max(1, Int(currentFrame.width * scale))
        let requestedHeight = max(1, Int(currentFrame.height * scale))
        let maximumPixels = frameRate >= 30 ? 3_686_400 : 921_600
        let requestedPixels = requestedWidth * requestedHeight
        let downscale = requestedPixels > maximumPixels ? sqrt(Double(maximumPixels) / Double(requestedPixels)) : 1
        configuration.width = max(1, Int(Double(requestedWidth) * downscale))
        configuration.height = max(1, Int(Double(requestedHeight) * downscale))
    }

    private static func overlayFrame(for contentFrame: CGRect, extraTop: CGFloat) -> CGRect {
        CGRect(
            x: contentFrame.minX - edgeBleed,
            y: contentFrame.minY - edgeBleed,
            width: contentFrame.width + edgeBleed * 2,
            height: contentFrame.height + edgeBleed * 2 + extraTop
        )
    }

    private func updatePanelGeometry(for contentFrame: CGRect) {
        let overlayFrame = Self.overlayFrame(for: contentFrame, extraTop: captureAffordanceClearance)
        panel.setFrame(overlayFrame, display: false, animate: false)
        // AppKit coordinates start at the panel's lower edge. The renderer
        // extends two points beyond the source on every edge, while the rest
        // of the top clearance remains transparent.
        renderer.view.frame = NSRect(
            x: 0,
            y: 0,
            width: contentFrame.width + Self.edgeBleed * 2,
            height: contentFrame.height + Self.edgeBleed * 2
        )
        renderer.view.autoresizingMask = [.width]
    }

    private func scheduleSettledGeometryCorrection(for frame: CGRect) {
        pendingGeometryCorrection?.cancel()
        let expectedFrame = frame
        let correction = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.stopped,
                  self.currentFrame == expectedFrame,
                  NSEvent.pressedMouseButtons == 0 else {
                return
            }
            self.updatePanelGeometry(for: expectedFrame)
            if self.isFilterNeeded {
                self.panel.order(.above, relativeTo: Int(self.sourceWindow.windowID))
            }
        }
        pendingGeometryCorrection = correction
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: correction)
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        pendingGeometryCorrection?.cancel()
        pendingGeometryCorrection = nil
        panel.orderOut(nil)
        let stream = stream
        self.stream = nil
        Task {
            try? await stream?.stopCapture()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard !stopped,
              outputType == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        let metadata = attachments?.first
        let scaleFactor = metadata?[.scaleFactor] as? Double ?? 1
        // `contentRect` is the actual captured content within an IOSurface
        // which may also include transparent framing/shadow pixels. Convert it
        // to IOSurface pixels before handing it to Metal for cropping.
        let contentRect = streamMetadataRect(metadata, for: .contentRect).map {
            $0.applying(CGAffineTransform(scaleX: scaleFactor, y: scaleFactor))
        }
        renderer.submit(pixelBuffer, contentRect: contentRect)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard !stopped else { return }
        stopped = true
        DispatchQueue.main.async { [weak self] in
            self?.panel.orderOut(nil)
            self?.onFailure?(error)
        }
    }
}

private final class WindowFilterRenderer: NSObject, MTKViewDelegate {
    private struct FilterUniforms {
        var inversionAndBleed: SIMD4<Float>
        var sourceUVRect: SIMD4<Float>
    }

    let view: MTKView

    var mode: AppAppearanceMode {
        didSet {
            lock.lock()
            if desiredMode != mode { needsAppearanceCheck = true }
            desiredMode = mode
            lock.unlock()
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?
    private var desiredMode: AppAppearanceMode
    private var invertAmount: Float = 0
    private var sourceUVRect = SIMD4<Float>(0, 0, 1, 1)
    private var frameCount = 0
    private var drawScheduled = false
    private var needsAppearanceCheck = true
    private var presentedFilterState: Bool?
    var onFilterNeededChange: ((Bool) -> Void)?

    init(mode: AppAppearanceMode) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Dark Light needs a Metal-capable Mac.")
        }
        self.device = device
        self.commandQueue = commandQueue
        self.mode = mode
        desiredMode = mode

        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        self.view = view

        let pipelineState: MTLRenderPipelineState?
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            if let vertex = library.makeFunction(name: "darkLightVertex"),
               let fragment = library.makeFunction(name: "darkLightFragment") {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertex
                descriptor.fragmentFunction = fragment
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            } else {
                NSLog("Dark Light: GPU filter functions are unavailable.")
                pipelineState = nil
            }
        } catch {
            // A dynamically compiled MSL program can fail on a future GPU or
            // OS. A failed visual filter must never terminate the host app.
            NSLog("Dark Light: GPU filter is unavailable: \(error.localizedDescription)")
            pipelineState = nil
        }
        pipeline = pipelineState

        super.init()
        view.delegate = self
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    func submit(_ pixelBuffer: CVPixelBuffer, contentRect: CGRect?) {
        let sourceRect = normalizedSourceUVRect(contentRect, pixelBuffer: pixelBuffer)
        lock.lock()
        latestPixelBuffer = pixelBuffer
        sourceUVRect = sourceRect
        frameCount += 1
        if needsAppearanceCheck || frameCount % 60 == 0 {
            needsAppearanceCheck = false
            let luminance = estimateLuminance(pixelBuffer)
            switch desiredMode {
            case .forceDark:
                if luminance > 0.58 { invertAmount = 1 }
                if luminance < 0.42 { invertAmount = 0 }
            case .forceLight:
                if luminance < 0.42 { invertAmount = 1 }
                if luminance > 0.58 { invertAmount = 0 }
            case .followSystem, .timeBased, .preserveApp:
                // Sessions only receive resolved force modes. Keep a safe
                // no-op fallback if that invariant is ever broken.
                invertAmount = 0
            }
        }
        let shouldScheduleDraw = !drawScheduled
        drawScheduled = true
        lock.unlock()

        guard shouldScheduleDraw else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let isFilterNeeded = self.invertAmount > 0
            self.lock.unlock()
            if isFilterNeeded {
                self.view.draw()
            }
            if self.presentedFilterState != isFilterNeeded {
                self.presentedFilterState = isFilterNeeded
                self.onFilterNeededChange?(isFilterNeeded)
            }
            self.lock.lock()
            self.drawScheduled = false
            self.lock.unlock()
        }
    }

    func draw(in view: MTKView) {
        lock.lock()
        let pixelBuffer = latestPixelBuffer
        let inversion = invertAmount
        let sourceRect = sourceUVRect
        lock.unlock()

        guard let pipeline,
              let pixelBuffer,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let texture = makeTexture(from: pixelBuffer),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        // The captured surface can have transparent decoration pixels around
        // its edge. Expand the actual alpha silhouette by the same two points
        // used by the panel's edge bleed, instead of guessing a corner radius.
        let bleedU = Float(windowOverlayEdgeBleed / max(view.bounds.width, 1))
        let bleedV = Float(windowOverlayEdgeBleed / max(view.bounds.height, 1))
        var uniforms = FilterUniforms(
            inversionAndBleed: SIMD4<Float>(inversion, bleedU, bleedV, 0),
            sourceUVRect: sourceRect
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<FilterUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else { return nil }
        var metalTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0,
            &metalTexture
        )
        guard result == kCVReturnSuccess, let metalTexture else { return nil }
        return CVMetalTextureGetTexture(metalTexture)
    }

    private func normalizedSourceUVRect(_ contentRect: CGRect?, pixelBuffer: CVPixelBuffer) -> SIMD4<Float> {
        guard let contentRect else { return SIMD4<Float>(0, 0, 1, 1) }
        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        let visibleRect = contentRect.integral.intersection(imageBounds)
        guard visibleRect.width >= 1, visibleRect.height >= 1 else {
            return SIMD4<Float>(0, 0, 1, 1)
        }
        return SIMD4<Float>(
            Float(visibleRect.minX / imageBounds.width),
            Float(visibleRect.minY / imageBounds.height),
            Float(visibleRect.width / imageBounds.width),
            Float(visibleRect.height / imageBounds.height)
        )
    }

    private func estimateLuminance(_ pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let bytes = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0.5 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let stepX = max(1, width / 32)
        let stepY = max(1, height / 18)
        var sum: Float = 0
        var count: Float = 0
        for y in stride(from: stepY / 2, to: height, by: stepY) {
            let row = bytes.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: stepX / 2, to: width, by: stepX) {
                let pixel = row.advanced(by: x * 4)
                // ScreenCaptureKit outputs the requested BGRA format.
                sum += (0.2126 * Float(pixel[2]) + 0.7152 * Float(pixel[1]) + 0.0722 * Float(pixel[0])) / 255
                count += 1
            }
        }
        return count > 0 ? sum / count : 0.5
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct RasterizerData {
        float4 position [[position]];
        float2 uv;
    };

    struct FilterUniforms {
        float4 inversionAndBleed;
        float4 sourceUVRect;
    };

    vertex RasterizerData darkLightVertex(uint vertexID [[vertex_id]]) {
        constexpr float2 positions[] = {
            float2(-1.0, -1.0), float2(1.0, -1.0),
            float2(-1.0, 1.0), float2(1.0, 1.0)
        };
        constexpr float2 uvs[] = {
            float2(0.0, 1.0), float2(1.0, 1.0),
            float2(0.0, 0.0), float2(1.0, 0.0)
        };
        RasterizerData out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = uvs[vertexID];
        return out;
    }

    fragment float4 darkLightFragment(RasterizerData in [[stage_in]],
                                      texture2d<float> source [[texture(0)]],
                                      constant FilterUniforms &uniforms [[buffer(0)]]) {
        constexpr sampler linearSampler(mag_filter::linear, min_filter::linear);
        float2 sourceUV = uniforms.sourceUVRect.xy + in.uv * uniforms.sourceUVRect.zw;
        float4 color = source.sample(linearSampler, sourceUV);
        // The stream's transparent fringe would otherwise reveal the original
        // light window underneath. Select the nearest opaque captured pixel in
        // a two-point neighbourhood to dilate the *real* alpha silhouette.
        // This follows each window's native corner curve instead of using a
        // fixed rounded-rectangle mask.
        if (color.a < 0.999) {
            for (int y = -1; y <= 1; y++) {
                for (int x = -1; x <= 1; x++) {
                    float2 offset = float2(
                        float(x) * uniforms.inversionAndBleed.y * uniforms.sourceUVRect.z,
                        float(y) * uniforms.inversionAndBleed.z * uniforms.sourceUVRect.w
                    );
                    float4 candidate = source.sample(linearSampler, sourceUV + offset);
                    if (candidate.a > color.a) {
                        color = candidate;
                    }
                }
            }
        }
        float invertAmount = uniforms.inversionAndBleed.x;
        // A raw RGB inversion turns red into cyan and is unpleasant for UI
        // accents. Instead, reverse the brightness of neutral pixels while
        // progressively preserving high-saturation colours.
        float sourceLuminance = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
        float channelMin = min(color.r, min(color.g, color.b));
        float channelMax = max(color.r, max(color.g, color.b));
        float saturation = channelMax - channelMin;
        float colourPreservation = smoothstep(0.18, 0.58, saturation);
        float neutralLuminance = clamp(0.12 + 0.84 * (1.0 - sourceLuminance), 0.0, 1.0);
        float colourfulLuminance = clamp(sourceLuminance, 0.12, 0.78);
        float transformedLuminance = mix(neutralLuminance, colourfulLuminance, colourPreservation);
        float targetLuminance = mix(sourceLuminance, transformedLuminance, invertAmount);
        color.rgb = clamp(color.rgb + (targetLuminance - sourceLuminance), 0.0, 1.0);
        return color;
    }
    """
}

enum AppThemeControlStrings {
    static func text(_ key: String, language: String) -> String {
        let localized: [String: [String: String]] = [
            "zh": [
                "title": "应用主题控制",
                "description": "为不能自动适配深浅色主题的 App 设置显示主题。可跟随系统、固定深色或浅色，也可按时间自动切换。",
                "permissionGranted": "已获得屏幕录制权限。暗光不会保存屏幕内容。",
                "capturePillTitle": "关于窗口左上角的系统提示",
                "capturePillDetail": "这是 macOS 在屏幕录制时产生的系统提示，会遮挡窗口左上角，导致无法显示红黄绿窗口控制按钮。该限制无法由暗光解决。",
                "launchAtLogin": "开机启动",
                "launchAtLoginDetail": "登录 Mac 后静默启动，仅在菜单栏显示暗光图标。",
                "launchAtLoginError": "无法更新开机启动：",
                "rules": "应用规则",
                "addApp": "添加应用",
                "noRules": "还没有应用规则",
                "noRulesDetail": "添加一个正在运行的 App；它所有可见窗口都会自动生效。",
                "remove": "移除",
                "removeTitle": "移除 %@？",
                "removeDetail": "将停止处理此 App。",
                "cancel": "取消",
                "permissionNeeded": "需要屏幕录制权限",
                "permissionDetail": "用于在本机转换你选定且不能自动适配深浅色主题的 App；不会录制或上传。若刚在系统设置中授权，请完全退出后重新打开暗光，再点“重新检查”。",
                "continueAllow": "继续并授权",
                "checkAgain": "重新检查",
                "openSettings": "打开系统设置",
                "schedule": "按时间切换",
                "darkStarts": "深色开始",
                "ends": "结束",
                "scheduleDetail": "此时间段内应用显示为深色，其余时间显示为浅色。开始和结束时间相同会停用该策略。",
                "addRunning": "添加应用",
                "addRunningDetail": "从正在运行的应用中选择，或浏览选择其他应用；暗光会自动处理它的所有可见窗口。",
                "browse": "浏览应用…",
                "chooseApplication": "选择应用",
                "strategy": "策略",
                "limitTitle": "免费版最多 3 个应用",
                "limitDetail": "升级高级版即可为不限数量的应用设置主题。",
                "upgrade": "了解高级版"
            ],
            "ja": [
                "title": "アプリテーマ管理",
                "description": "ライト／ダーク表示に自動対応しないアプリの表示テーマを設定します。システムに従う、常にダーク／ライトにする、時間で自動的に切り替えることができます。",
                "permissionGranted": "画面収録が許可されています。Dark Light は画面内容を保存しません。",
                "capturePillTitle": "ウインドウ左上のシステム表示について",
                "capturePillDetail": "これは画面収録中に macOS が表示するシステム表示です。ウインドウ左上に重なるため、赤・黄・緑のウインドウボタンは表示できません。この制限は Dark Light では解消できません。",
                "launchAtLogin": "ログイン時に起動",
                "launchAtLoginDetail": "ログイン時はウインドウを表示せず、メニューバーのアイコンのみを表示します。",
                "launchAtLoginError": "ログイン時に起動を更新できませんでした：",
                "rules": "アプリのルール",
                "addApp": "アプリを追加",
                "noRules": "アプリのルールはまだありません",
                "noRulesDetail": "起動中のアプリを追加すると、表示中のすべてのウインドウに自動的に適用されます。",
                "remove": "削除",
                "removeTitle": "%@ を削除しますか？",
                "removeDetail": "このアプリは処理されなくなります。",
                "cancel": "キャンセル",
                "permissionNeeded": "画面収録の許可が必要です",
                "permissionDetail": "選択した、ライト／ダーク表示に自動対応しないアプリのテーマをこの Mac 上で変換するために使用します。画面内容の録画・保存・送信は行いません。システム設定で許可した直後は、Dark Light を完全に終了して開き直し、「再確認」を押してください。",
                "continueAllow": "続けて許可",
                "checkAgain": "再確認",
                "openSettings": "システム設定を開く",
                "schedule": "時間で切り替え",
                "darkStarts": "ダーク開始",
                "ends": "終了",
                "scheduleDetail": "この時間帯はダーク、それ以外はライトで表示します。開始と終了が同じ場合、この設定は無効になります。",
                "addRunning": "アプリを追加",
                "addRunningDetail": "起動中のアプリから選ぶか、ほかのアプリを参照して選択します。Dark Light が表示中のすべてのウインドウに自動的に適用します。",
                "browse": "アプリを参照…",
                "chooseApplication": "アプリを選択",
                "strategy": "テーマ",
                "limitTitle": "無料版はアプリ 3 個まで",
                "limitDetail": "Premium にアップグレードすると、無制限のアプリにテーマを設定できます。",
                "upgrade": "Premium を見る"
            ],
            "ko": [
                "title": "앱 테마 제어",
                "description": "밝은색과 어두운색 테마에 자동으로 맞춰 전환되지 않는 앱의 표시 테마를 설정합니다. 시스템을 따르거나, 항상 어둡게 또는 밝게 표시하거나, 시간에 따라 자동으로 전환할 수 있습니다.",
                "permissionGranted": "화면 기록 권한이 허용되었습니다. Dark Light는 화면 내용을 저장하지 않습니다.",
                "capturePillTitle": "창 왼쪽 위 시스템 표시 안내",
                "capturePillDetail": "화면 기록 중 macOS가 표시하는 시스템 표시입니다. 창의 왼쪽 위를 가리므로 빨강, 노랑, 초록 창 제어 버튼을 표시할 수 없습니다. Dark Light로는 이 제한을 해결할 수 없습니다.",
                "launchAtLogin": "로그인 시 실행",
                "launchAtLoginDetail": "로그인 시 창을 열지 않고 메뉴 막대 아이콘으로만 실행합니다.",
                "launchAtLoginError": "로그인 시 실행을 업데이트할 수 없음:",
                "rules": "앱 규칙",
                "addApp": "앱 추가",
                "noRules": "아직 앱 규칙이 없습니다",
                "noRulesDetail": "실행 중인 앱을 추가하면 모든 보이는 창에 자동으로 적용됩니다.",
                "remove": "제거",
                "removeTitle": "%@을(를) 제거할까요?",
                "removeDetail": "이 앱은 더 이상 처리되지 않습니다.",
                "cancel": "취소",
                "permissionNeeded": "화면 기록 권한이 필요합니다",
                "permissionDetail": "밝은색과 어두운색 테마에 자동으로 맞춰 전환되지 않는 선택한 앱의 테마를 이 Mac에서 변환하는 데 사용합니다. 화면 내용은 기록, 저장 또는 전송하지 않습니다. 시스템 설정에서 권한을 막 허용했다면 Dark Light를 완전히 종료한 뒤 다시 열고 ‘다시 확인’을 누르세요.",
                "continueAllow": "계속하여 허용",
                "checkAgain": "다시 확인",
                "openSettings": "시스템 설정 열기",
                "schedule": "시간별 전환",
                "darkStarts": "어두운 모드 시작",
                "ends": "종료",
                "scheduleDetail": "이 시간에는 어둡게, 그 외에는 밝게 표시합니다. 시작과 종료 시간이 같으면 이 설정은 비활성화됩니다.",
                "addRunning": "앱 추가",
                "addRunningDetail": "실행 중인 앱에서 선택하거나 다른 앱을 찾아 선택하세요. Dark Light가 모든 보이는 창에 자동으로 적용합니다.",
                "browse": "앱 찾아보기…",
                "chooseApplication": "앱 선택",
                "strategy": "테마",
                "limitTitle": "무료 버전은 앱 3개까지",
                "limitDetail": "Premium으로 업그레이드하면 앱 수 제한 없이 테마를 설정할 수 있습니다.",
                "upgrade": "Premium 알아보기"
            ],
            "es": [
                "title": "Control de tema de apps",
                "description": "Define un tema de visualización para apps que no se adaptan automáticamente a los temas claro y oscuro. Sigue el sistema, mantenlas claras u oscuras, o cambia automáticamente por horario.",
                "permissionGranted": "La grabación de pantalla está activada. Dark Light nunca guarda el contenido de la pantalla.",
                "capturePillTitle": "Sobre el indicador del sistema en la esquina superior izquierda",
                "capturePillDetail": "Es un indicador del sistema que macOS muestra durante la grabación de pantalla. Cubre la esquina superior izquierda de la ventana, por lo que no se pueden mostrar los botones rojo, amarillo y verde. Dark Light no puede eliminar esta limitación.",
                "launchAtLogin": "Abrir al iniciar sesión",
                "launchAtLoginDetail": "Se inicia en silencio al iniciar sesión y solo aparece en la barra de menús.",
                "launchAtLoginError": "No se pudo actualizar el inicio de sesión:",
                "rules": "Reglas de apps",
                "addApp": "Añadir app",
                "noRules": "Aún no hay reglas de apps",
                "noRulesDetail": "Añade una app en ejecución y se aplicará automáticamente a todas sus ventanas visibles.",
                "remove": "Eliminar",
                "removeTitle": "¿Eliminar %@?",
                "removeDetail": "Esta app dejará de procesarse.",
                "cancel": "Cancelar",
                "permissionNeeded": "Se necesita grabación de pantalla",
                "permissionDetail": "Se utiliza para transformar localmente el tema de las apps seleccionadas que no se adaptan automáticamente a los temas claro y oscuro. No se graba, guarda ni envía el contenido de la pantalla. Si acabas de autorizarlo en Ajustes del Sistema, cierra Dark Light por completo, ábrelo de nuevo y pulsa «Comprobar de nuevo».",
                "continueAllow": "Continuar y permitir",
                "checkAgain": "Comprobar de nuevo",
                "openSettings": "Abrir Ajustes del Sistema",
                "schedule": "Cambiar por horario",
                "darkStarts": "Inicio oscuro",
                "ends": "Fin",
                "scheduleDetail": "Las apps se muestran oscuras durante este periodo y claras fuera de él. Si las horas coinciden, esta opción se desactiva.",
                "addRunning": "Añadir app",
                "addRunningDetail": "Elige una app en ejecución o busca otra app. Dark Light se aplicará automáticamente a todas sus ventanas visibles.",
                "browse": "Buscar app…",
                "chooseApplication": "Elegir una app",
                "strategy": "Tema",
                "limitTitle": "La versión gratuita permite 3 apps",
                "limitDetail": "Actualiza a Premium para configurar temas en un número ilimitado de apps.",
                "upgrade": "Ver Premium"
            ],
            "fr": [
                "title": "Contrôle du thème des apps",
                "description": "Définissez un thème d’affichage pour les apps qui ne s’adaptent pas automatiquement aux thèmes clair et sombre. Suivez le système, gardez-les claires ou sombres, ou changez automatiquement selon l’heure.",
                "permissionGranted": "L’enregistrement de l’écran est activé. Dark Light n’enregistre jamais le contenu de l’écran.",
                "capturePillTitle": "À propos de l’indicateur système en haut à gauche",
                "capturePillDetail": "C’est un indicateur système affiché par macOS pendant l’enregistrement de l’écran. Il recouvre le coin supérieur gauche de la fenêtre, ce qui empêche l’affichage des boutons rouge, jaune et vert. Dark Light ne peut pas supprimer cette limitation.",
                "launchAtLogin": "Ouvrir à la connexion",
                "launchAtLoginDetail": "Démarre discrètement à la connexion et reste accessible uniquement depuis la barre des menus.",
                "launchAtLoginError": "Impossible de mettre à jour l’ouverture à la connexion :",
                "rules": "Règles des apps",
                "addApp": "Ajouter une app",
                "noRules": "Aucune règle d’app pour le moment",
                "noRulesDetail": "Ajoutez une app en cours d’exécution ; toutes ses fenêtres visibles seront appliquées automatiquement.",
                "remove": "Supprimer",
                "removeTitle": "Supprimer %@ ?",
                "removeDetail": "Cette app ne sera plus traitée.",
                "cancel": "Annuler",
                "permissionNeeded": "L’enregistrement de l’écran est requis",
                "permissionDetail": "Il sert à transformer localement le thème des apps sélectionnées qui ne s’adaptent pas automatiquement aux thèmes clair et sombre. Le contenu de l’écran n’est ni enregistré, ni conservé, ni envoyé. Si vous venez de l’autoriser dans Réglages Système, quittez entièrement Dark Light, relancez-le, puis cliquez sur « Vérifier à nouveau ».",
                "continueAllow": "Continuer et autoriser",
                "checkAgain": "Vérifier à nouveau",
                "openSettings": "Ouvrir Réglages Système",
                "schedule": "Changer selon l’heure",
                "darkStarts": "Début sombre",
                "ends": "Fin",
                "scheduleDetail": "Les apps sont sombres pendant cette période et claires le reste du temps. Des heures identiques désactivent cette option.",
                "addRunning": "Ajouter une app",
                "addRunningDetail": "Choisissez une app en cours d’exécution ou parcourez les autres apps. Dark Light s’appliquera automatiquement à toutes ses fenêtres visibles.",
                "browse": "Parcourir les apps…",
                "chooseApplication": "Choisir une app",
                "strategy": "Thème",
                "limitTitle": "La version gratuite permet 3 apps",
                "limitDetail": "Passez à Premium pour définir un thème pour un nombre illimité d’apps.",
                "upgrade": "Voir Premium"
            ],
            "de": [
                "title": "App-Themensteuerung",
                "description": "Legen Sie ein Darstellungsthema für Apps fest, die sich nicht automatisch an helle und dunkle Themes anpassen. Folgen Sie dem System, halten Sie Apps hell oder dunkel oder wechseln Sie automatisch nach Zeitplan.",
                "permissionGranted": "Bildschirmaufnahme ist aktiviert. Dark Light speichert keine Bildschirminhalte.",
                "capturePillTitle": "Hinweis zur Systemanzeige oben links",
                "capturePillDetail": "Dies ist eine macOS-Systemanzeige während der Bildschirmaufnahme. Sie verdeckt die obere linke Fensterecke, daher können die roten, gelben und grünen Fensterknöpfe nicht angezeigt werden. Dark Light kann diese Einschränkung nicht aufheben.",
                "launchAtLogin": "Beim Anmelden öffnen",
                "launchAtLoginDetail": "Startet bei der Anmeldung unauffällig und ist nur über die Menüleiste verfügbar.",
                "launchAtLoginError": "Anmeldung beim Start konnte nicht aktualisiert werden:",
                "rules": "App-Regeln",
                "addApp": "App hinzufügen",
                "noRules": "Noch keine App-Regeln",
                "noRulesDetail": "Fügen Sie eine laufende App hinzu. Die Einstellung wird automatisch auf alle sichtbaren Fenster angewendet.",
                "remove": "Entfernen",
                "removeTitle": "%@ entfernen?",
                "removeDetail": "Diese App wird nicht mehr verarbeitet.",
                "cancel": "Abbrechen",
                "permissionNeeded": "Bildschirmaufnahme ist erforderlich",
                "permissionDetail": "Sie wird verwendet, um das Thema ausgewählter Apps, die sich nicht automatisch an helle und dunkle Themes anpassen, lokal zu verändern. Bildschirminhalte werden nicht aufgezeichnet, gespeichert oder übertragen. Wenn Sie die Berechtigung gerade in den Systemeinstellungen erteilt haben, beenden Sie Dark Light vollständig, öffnen Sie es erneut und klicken Sie auf „Erneut prüfen“.",
                "continueAllow": "Fortfahren und erlauben",
                "checkAgain": "Erneut prüfen",
                "openSettings": "Systemeinstellungen öffnen",
                "schedule": "Nach Zeitplan wechseln",
                "darkStarts": "Dunkel beginnt",
                "ends": "Ende",
                "scheduleDetail": "Apps werden in diesem Zeitraum dunkel und außerhalb davon hell angezeigt. Gleiche Zeiten deaktivieren diese Einstellung.",
                "addRunning": "App hinzufügen",
                "addRunningDetail": "Wählen Sie eine laufende App oder durchsuchen Sie andere Apps. Dark Light wendet die Einstellung automatisch auf alle sichtbaren Fenster an.",
                "browse": "Apps durchsuchen…",
                "chooseApplication": "App auswählen",
                "strategy": "Thema",
                "limitTitle": "Die kostenlose Version erlaubt 3 Apps",
                "limitDetail": "Mit Premium können Sie für unbegrenzt viele Apps Themen festlegen.",
                "upgrade": "Premium ansehen"
            ],
            "en": [
                "title": "App Theme Control",
                "description": "Set a display theme for apps that do not automatically adapt to light and dark appearance. Follow the system, keep an app dark or light, or switch automatically by time.",
                "permissionGranted": "Screen Recording is enabled. Dark Light never saves screen contents.",
                "capturePillTitle": "About the system indicator at the window’s top-left",
                "capturePillDetail": "macOS shows this system indicator during Screen Recording. It covers the window’s top-left corner, so the red, yellow, and green window controls cannot be shown. Dark Light cannot remove this system limitation.",
                "launchAtLogin": "Launch at login",
                "launchAtLoginDetail": "Start silently when you log in. Dark Light will be available from the menu bar only.",
                "launchAtLoginError": "Could not update Launch at Login:",
                "rules": "App rules",
                "addApp": "Add app",
                "noRules": "No app rules yet",
                "noRulesDetail": "Add a running app and it will be applied automatically to all of its visible windows.",
                "remove": "Remove",
                "removeTitle": "Remove %@?",
                "removeDetail": "Dark Light will stop processing this app.",
                "cancel": "Cancel",
                "permissionNeeded": "Screen Recording is needed",
                "permissionDetail": "This lets Dark Light transform selected apps that do not automatically adapt to light and dark appearance. Nothing is recorded, saved, or uploaded. If you just enabled it in System Settings, fully quit and reopen Dark Light, then click Check again.",
                "continueAllow": "Continue and allow",
                "checkAgain": "Check again",
                "openSettings": "Open System Settings",
                "schedule": "Change by time",
                "darkStarts": "Dark starts",
                "ends": "Ends",
                "scheduleDetail": "Apps use dark appearance during this range and light appearance outside it. Matching times disable this option.",
                "addRunning": "Add an app",
                "addRunningDetail": "Choose a running app or browse for another app. Dark Light automatically applies to all of its visible windows.",
                "browse": "Browse Apps…",
                "chooseApplication": "Choose an app",
                "strategy": "Theme",
                "limitTitle": "Free includes 3 apps",
                "limitDetail": "Upgrade to Premium to set themes for unlimited apps.",
                "upgrade": "View Premium"
            ]
        ]
        return localized[language]?[key] ?? localized["en"]![key]!
    }
}

struct AppAppearanceView: View {
    @ObservedObject var controller: AppAppearanceController
    @ObservedObject var proStore: ProStore
    let language: String
    let showPremium: () -> Void
    @State private var showingFreeLimitAlert = false
    @State private var rulePendingRemoval: AppAppearanceRule?
    @StateObject private var launchAtLogin = LaunchAtLoginController.shared

    private func text(_ key: String) -> String { AppThemeControlStrings.text(key, language: language) }
    private var pendingRemovalName: String { rulePendingRemoval?.appName ?? "" }
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(text("title")).font(.title2).fontWeight(.semibold)
                Text(text("description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !controller.hasScreenCapturePermission {
                permissionCard
            } else {
                Label(text("permissionGranted"), systemImage: "checkmark.shield.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if launchAtLogin.isAvailable {
                launchAtLoginSection
            }

            HStack {
                Text(text("rules")).font(.headline)
                Spacer()
                Button(action: {
                    if controller.canAddAnotherApp {
                        browseForApplication()
                    } else {
                        showingFreeLimitAlert = true
                    }
                }) {
                    Label(text("addApp"), systemImage: "plus")
                }
            }

            if controller.rules.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(text("noRules"))
                        .font(.subheadline.weight(.medium))
                    Text(text("noRulesDetail"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                List {
                    ForEach(controller.rules) { rule in
                        HStack(spacing: 12) {
                            Image(nsImage: installedAppIcon(for: rule.bundleIdentifier))
                                .resizable()
                                .frame(width: 26, height: 26)
                            VStack(alignment: .leading) {
                                Text(rule.appName).font(.body.weight(.medium))
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { rule.mode },
                                set: { controller.setMode($0, for: rule) }
                            )) {
                                ForEach(AppAppearanceMode.allCases.filter { $0 != .preserveApp }) { mode in
                                    Text(mode.title(language: language)).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 130, alignment: .trailing)
                            Button(text("remove"), role: .destructive) {
                                rulePendingRemoval = rule
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 150, maxHeight: 280)
            }

            if controller.rules.contains(where: { $0.mode == .timeBased }) {
                AppAppearanceScheduleEditor(controller: controller, language: language)
            }

            if let status = controller.statusMessage {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            screenCapturePillNotice

        }
        .padding(24)
        .frame(width: 530, alignment: .leading)
        .onAppear {
            controller.setPremiumAccess(proStore.isPro)
            controller.start()
            launchAtLogin.refresh()
        }
        .onChange(of: proStore.isPro) { isPro in
            controller.setPremiumAccess(isPro)
        }
        .confirmationDialog(
            String(format: text("removeTitle"), pendingRemovalName),
            isPresented: Binding(
                get: { rulePendingRemoval != nil },
                set: { if !$0 { rulePendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let rule = rulePendingRemoval {
                Button(text("remove"), role: .destructive) {
                    controller.remove(rule)
                    rulePendingRemoval = nil
                }
            }
            Button(text("cancel"), role: .cancel) {
                rulePendingRemoval = nil
            }
        } message: {
            Text(text("removeDetail"))
        }
        .alert(text("limitTitle"), isPresented: $showingFreeLimitAlert) {
            Button(text("upgrade")) {
                showPremium()
            }
            Button(text("cancel"), role: .cancel) {}
        } message: {
            Text(text("limitDetail"))
        }
    }

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.badge.gearshape")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(text("permissionNeeded")).font(.subheadline.weight(.semibold))
                Text(text("permissionDetail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(text("continueAllow")) {
                        controller.requestScreenCapturePermission()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(text("checkAgain")) {
                        controller.refreshScreenCapturePermission(force: true)
                    }
                    Button(text("openSettings")) {
                        controller.openScreenRecordingSettings()
                    }
                }
            }
        }
        .padding(14)
        .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private var screenCapturePillNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(text("capturePillTitle")).font(.caption.weight(.semibold))
                Text(text("capturePillDetail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var launchAtLoginSection: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(text("launchAtLogin"))
                    .font(.body)
                Text(text("launchAtLoginDetail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage = launchAtLogin.errorMessage {
                    Text("\(text("launchAtLoginError")) \(errorMessage)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer(minLength: 16)
            Toggle("", isOn: launchAtLoginBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .accessibilityLabel(text("launchAtLogin"))
        }
        .padding(.vertical, 4)
    }

    private func browseForApplication() {
        let panel = NSOpenPanel()
        panel.title = text("chooseApplication")
        panel.prompt = text("chooseApplication")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedFileTypes = ["app"]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let app = controller.applicationCandidate(at: url) else { return }
                if !controller.addRule(for: app, mode: .followSystem) {
                    showingFreeLimitAlert = true
                }
            }
        }
    }
}

private struct AppAppearanceScheduleEditor: View {
    @ObservedObject var controller: AppAppearanceController
    let language: String

    private func text(_ key: String) -> String { AppThemeControlStrings.text(key, language: language) }

    private var startBinding: Binding<Date> {
        Binding(
            get: { controller.scheduleDate(isStart: true) },
            set: { controller.setScheduleTime($0, isStart: true) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { controller.scheduleDate(isStart: false) },
            set: { controller.setScheduleTime($0, isStart: false) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text("schedule"))
                .font(.headline)
            HStack {
                DatePicker(text("darkStarts"), selection: startBinding, displayedComponents: .hourAndMinute)
                DatePicker(text("ends"), selection: endBinding, displayedComponents: .hourAndMinute)
            }
            Text(text("scheduleDetail"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct AppPickerView: View {
    @ObservedObject var controller: AppAppearanceController
    let language: String
    let showPremium: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMode: AppAppearanceMode = .followSystem
    @State private var showingFreeLimitAlert = false

    private func text(_ key: String) -> String { AppThemeControlStrings.text(key, language: language) }
    private var apps: [AppAppearanceCandidate] { controller.availableApplications() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(text("addRunning"))
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            Text(text("addRunningDetail"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker(text("strategy"), selection: $selectedMode) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.title(language: language)).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if selectedMode == .timeBased {
                AppAppearanceScheduleEditor(controller: controller, language: language)
            }

            List(apps) { app in
                Button {
                    add(app)
                } label: {
                    HStack(spacing: 12) {
                        Image(nsImage: app.icon).resizable().frame(width: 30, height: 30)
                        Text(app.appName).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 280)

            HStack {
                Button(text("browse")) {
                    browseForApplication()
                }
                Spacer()
                Button(text("cancel")) { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .alert(text("limitTitle"), isPresented: $showingFreeLimitAlert) {
            Button(text("upgrade")) {
                dismiss()
                showPremium()
            }
            Button(text("cancel"), role: .cancel) {}
        } message: {
            Text(text("limitDetail"))
        }
    }

    private func add(_ app: AppAppearanceCandidate) {
        if controller.addRule(for: app, mode: selectedMode) {
            dismiss()
        } else {
            showingFreeLimitAlert = true
        }
    }

    private func browseForApplication() {
        let panel = NSOpenPanel()
        panel.title = text("chooseApplication")
        panel.prompt = text("chooseApplication")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedFileTypes = ["app"]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let app = controller.applicationCandidate(at: url) else { return }
                add(app)
            }
        }
    }
}

private func installedAppIcon(for bundleIdentifier: String) -> NSImage {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
        return NSImage()
    }
    return NSWorkspace.shared.icon(forFile: url.path)
}
#endif
