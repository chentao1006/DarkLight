//
//  AppDelegate.swift
//  Dark Light
//
//  Created by 陈涛 on 2026/6/18.
//

#if os(macOS)
import Cocoa
import SwiftUI

@main
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var appThemeControlWindow: NSWindow?
    private let appThemeControlProStore = ProStore()
    private var launchedAsLoginItem = false
    private var selectedInterfaceLanguage: String?

    private enum AppThemeControlRecommendation {
        static let hasBeenPresentedDefaultsKey = "DarkLight.appThemeControlRecommendationHasBeenPresented"
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAsLoginItem = Self.isLaunchedAsLoginItem
        let iCloudStore = NSUbiquitousKeyValueStore.default
        iCloudStore.synchronize()
        if let language = iCloudStore.string(forKey: "darkLightInterfaceLanguage"),
           localizedStrings.keys.contains(language) {
            selectedInterfaceLanguage = language
            UserDefaults.standard.set(language, forKey: interfaceLanguageDefaultsKey)
        } else {
            selectedInterfaceLanguage = UserDefaults.standard.string(forKey: interfaceLanguageDefaultsKey)
        }
        if launchedAsLoginItem {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchedAsLoginItem = launchedAsLoginItem || Self.isLaunchedAsLoginItem
        if launchedAsLoginItem {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        DailyCheckInScheduler.shared.start()
        AppAppearanceController.shared.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interfaceLanguageStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        installStatusItem()
        if launchedAsLoginItem {
            NSApplication.shared.windows.forEach { $0.orderOut(nil) }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.presentAppThemeControlRecommendationIfNeeded()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if PremiumDeepLink.handlesPremiumURL(urls) {
            PremiumDeepLink.requestOpenPremium()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep applying saved app themes without leaving a redundant running
        // indicator in the Dock. The menu-bar item remains the background
        // service's entry point.
        guard AppAppearanceController.shared.hasActiveFilterRules else {
            return true
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        openMainWindow()
        return false
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = statusBarImage()

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildStatusMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let controller = AppAppearanceController.shared

        if let app = controller.focusedApplication() {
            let header = NSMenuItem(title: menuText("currentApp", app.appName), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let enabledRule = controller.enabledRule(for: app)
            for mode in AppAppearanceMode.allCases {
                let modeItem = addMenuItem(
                    to: menu,
                    title: mode.title(language: menuLanguage),
                    action: #selector(setFocusedAppStrategy(_:))
                )
                modeItem.tag = mode.menuTag
                modeItem.state = (enabledRule?.mode ?? .preserveApp) == mode ? .on : .off
            }

            menu.addItem(.separator())
        }

        addMenuItem(to: menu, title: menuText("open"), action: #selector(openMainWindow))
        addMenuItem(to: menu, title: menuText("openAppThemeControl"), action: #selector(openAppThemeControl))
        menu.addItem(.separator())
        let quitItem = addMenuItem(to: menu, title: menuText("quit"), action: #selector(quit))
        quitItem.keyEquivalent = "q"
    }

    @discardableResult
    private func addMenuItem(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func openMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first(where: { $0.contentViewController is ViewController }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showAppThemeControl() {
        if let appThemeControlWindow {
            appThemeControlWindow.title = localizedProductTitle
            NSApplication.shared.setActivationPolicy(.regular)
            appThemeControlWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = localizedProductTitle
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 620)
        window.center()
        window.contentView = NSHostingView(rootView: appThemeControlContent(language: menuLanguage))
        appThemeControlWindow = window
        NSApplication.shared.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func presentAppThemeControlRecommendationIfNeeded() {
        guard #available(macOS 12.3, *),
              !launchedAsLoginItem,
              !UserDefaults.standard.bool(forKey: AppThemeControlRecommendation.hasBeenPresentedDefaultsKey),
              let window = NSApplication.shared.windows.first(where: { $0.contentViewController is ViewController }) else {
            return
        }

    let alert = NSAlert()
        alert.messageText = appThemeControlRecommendationText("title")
        alert.informativeText = appThemeControlRecommendationText("message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: appThemeControlRecommendationText("tryNow"))
        alert.addButton(withTitle: appThemeControlRecommendationText("dontRemind"))
    alert.beginSheetModal(for: window) { [weak self] response in
        switch response {
        case .alertFirstButtonReturn:
            UserDefaults.standard.set(true, forKey: AppThemeControlRecommendation.hasBeenPresentedDefaultsKey)
            AppAppearanceController.shared.requestScreenCapturePermission()
            self?.showAppThemeControl()
        case .alertSecondButtonReturn:
            UserDefaults.standard.set(true, forKey: AppThemeControlRecommendation.hasBeenPresentedDefaultsKey)
        default:
            break
        }
    }
}

    func updateInterfaceLanguage(_ language: String) {
        selectedInterfaceLanguage = language
        UserDefaults.standard.set(language, forKey: interfaceLanguageDefaultsKey)
        let iCloudStore = NSUbiquitousKeyValueStore.default
        if iCloudStore.string(forKey: "darkLightInterfaceLanguage") != language
            || iCloudStore.double(forKey: "darkLightInterfaceLanguageRevision") == 0 {
            iCloudStore.set(language, forKey: "darkLightInterfaceLanguage")
            iCloudStore.set(Date().timeIntervalSince1970, forKey: "darkLightInterfaceLanguageRevision")
            iCloudStore.synchronize()
        }

        refreshInterfaceLanguageViews()
    }

    @objc private func interfaceLanguageStoreDidChange(_ notification: Notification) {
        let iCloudStore = NSUbiquitousKeyValueStore.default
        iCloudStore.synchronize()
        guard let language = iCloudStore.string(forKey: "darkLightInterfaceLanguage"),
              localizedStrings.keys.contains(language),
              language != selectedInterfaceLanguage else {
            return
        }

        selectedInterfaceLanguage = language
        UserDefaults.standard.set(language, forKey: interfaceLanguageDefaultsKey)
        refreshInterfaceLanguageViews()
        NotificationCenter.default.post(
            name: interfaceLanguageDidChangeNotification,
            object: nil,
            userInfo: ["language": language]
        )
    }

    private func refreshInterfaceLanguageViews() {
        if let appThemeControlWindow {
            appThemeControlWindow.title = localizedProductTitle
            appThemeControlWindow.contentView = NSHostingView(
                rootView: appThemeControlContent(language: menuLanguage)
            )
        }

        if let menu = statusItem?.menu {
            rebuildStatusMenu(menu)
        }
    }

    private func appThemeControlContent(language: String) -> AppAppearanceView {
        AppAppearanceView(
            controller: .shared,
            proStore: appThemeControlProStore,
            language: language,
            showPremium: { [weak self] in
                self?.appThemeControlWindow?.orderOut(nil)
                self?.openMainWindow()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: openPremiumNotification, object: nil)
                }
            }
        )
    }

    @objc private func openAppThemeControl() {
        showAppThemeControl()
    }

    @objc private func setFocusedAppStrategy(_ sender: NSMenuItem) {
        guard let mode = AppAppearanceMode(menuTag: sender.tag) else { return }
        AppAppearanceController.shared.setAppearance(mode, forFocusedApplication: AppAppearanceController.shared.focusedApplication())
    }

    @objc private func stopFilteringFocusedApp() {
        AppAppearanceController.shared.stopFilteringFocusedApplication(AppAppearanceController.shared.focusedApplication())
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func menuText(_ key: String, _ appName: String? = nil) -> String {
        let language = menuLanguage
        let text: String
        switch (language, key) {
        case ("zh", "currentApp"): text = "当前应用：%@"
        case ("zh", "makeDark"): text = "让 %@ 显示为深色"
        case ("zh", "makeLight"): text = "让 %@ 显示为浅色"
        case ("zh", "stopFiltering"): text = "停止处理 %@"
        case ("zh", "open"): text = "打开暗光"
        case ("zh", "openAppThemeControl"): text = "打开应用主题控制"
        case ("zh", "quit"): text = "退出暗光"

        case ("ja", "currentApp"): text = "現在のアプリ：%@"
        case ("ja", "makeDark"): text = "%@ をダーク表示にする"
        case ("ja", "makeLight"): text = "%@ をライト表示にする"
        case ("ja", "stopFiltering"): text = "%@ のフィルタを停止"
        case ("ja", "open"): text = "Dark Light を開く"
        case ("ja", "openAppThemeControl"): text = "アプリテーマ管理を開く"
        case ("ja", "quit"): text = "Dark Light を終了"

        case ("ko", "currentApp"): text = "현재 앱: %@"
        case ("ko", "makeDark"): text = "%@을(를) 어둡게 표시"
        case ("ko", "makeLight"): text = "%@을(를) 밝게 표시"
        case ("ko", "stopFiltering"): text = "%@ 필터 중지"
        case ("ko", "open"): text = "Dark Light 열기"
        case ("ko", "openAppThemeControl"): text = "앱 테마 제어 열기"
        case ("ko", "quit"): text = "Dark Light 종료"

        case ("es", "currentApp"): text = "App actual: %@"
        case ("es", "makeDark"): text = "Mostrar %@ en oscuro"
        case ("es", "makeLight"): text = "Mostrar %@ en claro"
        case ("es", "stopFiltering"): text = "Dejar de filtrar %@"
        case ("es", "open"): text = "Abrir Dark Light"
        case ("es", "openAppThemeControl"): text = "Abrir el control de tema de apps"
        case ("es", "quit"): text = "Salir de Dark Light"

        case ("fr", "currentApp"): text = "App active : %@"
        case ("fr", "makeDark"): text = "Afficher %@ en sombre"
        case ("fr", "makeLight"): text = "Afficher %@ en clair"
        case ("fr", "stopFiltering"): text = "Arrêter le filtre de %@"
        case ("fr", "open"): text = "Ouvrir Dark Light"
        case ("fr", "openAppThemeControl"): text = "Ouvrir le contrôle du thème des apps"
        case ("fr", "quit"): text = "Quitter Dark Light"

        case ("de", "currentApp"): text = "Aktuelle App: %@"
        case ("de", "makeDark"): text = "%@ dunkel anzeigen"
        case ("de", "makeLight"): text = "%@ hell anzeigen"
        case ("de", "stopFiltering"): text = "Filter für %@ beenden"
        case ("de", "open"): text = "Dark Light öffnen"
        case ("de", "openAppThemeControl"): text = "App-Themensteuerung öffnen"
        case ("de", "quit"): text = "Dark Light beenden"

        default:
            switch key {
            case "currentApp": text = "Current app: %@"
            case "makeDark": text = "Show %@ in dark"
            case "makeLight": text = "Show %@ in light"
            case "stopFiltering": text = "Stop filtering %@"
            case "open": text = "Open Dark Light"
            case "openAppThemeControl": text = "Open App Theme Control"
            default: text = "Quit Dark Light"
            }
        }
        guard let appName else { return text }
        return String(format: text, appName)
    }

    private func appThemeControlRecommendationText(_ key: String) -> String {
        let texts: [String: [String: String]] = [
            "zh": [
                "title": "试试应用主题控制",
                "message": "这是实验性功能，适合没有自动适配深浅色主题的 Mac 应用。",
                "tryNow": "立即尝试",
                "dontRemind": "不再提示"
            ],
            "ja": [
                "title": "アプリテーマ管理を試す",
                "message": "実験的機能です。ライト／ダーク表示に自動対応しない Mac アプリ向けです。",
                "tryNow": "今すぐ試す",
                "dontRemind": "今後表示しない"
            ],
            "ko": [
                "title": "앱 테마 제어 사용해 보기",
                "message": "밝은색과 어두운색 테마에 자동으로 맞춰 전환되지 않는 Mac 앱을 위한 실험 기능입니다.",
                "tryNow": "지금 사용해 보기",
                "dontRemind": "다시 표시 안 함"
            ],
            "es": [
                "title": "Prueba el control de tema de apps",
                "message": "Esta función experimental está pensada para apps Mac que no se adaptan automáticamente a los temas claro y oscuro.",
                "tryNow": "Probar ahora",
                "dontRemind": "No volver a mostrar"
            ],
            "fr": [
                "title": "Essayer le contrôle du thème des apps",
                "message": "Cette fonction expérimentale est conçue pour les apps Mac qui ne s’adaptent pas automatiquement aux thèmes clair et sombre.",
                "tryNow": "Essayer maintenant",
                "dontRemind": "Ne plus afficher"
            ],
            "de": [
                "title": "App-Themensteuerung ausprobieren",
                "message": "Diese experimentelle Funktion ist für Mac-Apps gedacht, die sich nicht automatisch an helle und dunkle Themes anpassen.",
                "tryNow": "Jetzt ausprobieren",
                "dontRemind": "Nicht mehr anzeigen"
            ],
            "en": [
                "title": "Try App Theme Control",
                "message": "This experimental feature is for Mac apps that do not automatically adapt to light and dark themes.",
                "tryNow": "Try it now",
                "dontRemind": "Don't remind me again"
            ]
        ]

        return texts[menuLanguage]?[key] ?? texts["en"]?[key] ?? ""
    }

    private var menuLanguage: String {
        if let selectedInterfaceLanguage {
            return selectedInterfaceLanguage
        }
        switch Locale.current.languageCode {
        case "zh": return "zh"
        case "ja": return "ja"
        case "ko": return "ko"
        case "es": return "es"
        case "fr": return "fr"
        case "de": return "de"
        default: return "en"
        }
    }

    private var localizedProductTitle: String {
        localizedStrings[menuLanguage]?["pageTitle"] ?? "Dark Light"
    }

    private func statusBarImage() -> NSImage {
        if let symbol = NSImage(
            systemSymbolName: "circle.bottomrighthalf.pattern.checkered",
            accessibilityDescription: "Dark Light"
        )?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium)) {
            symbol.isTemplate = true
            return symbol
        }

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let circle = NSRect(x: rect.midX - 6, y: rect.midY - 6, width: 12, height: 12)
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let half = NSBezierPath()
            half.move(to: NSPoint(x: circle.midX, y: circle.maxY))
            half.appendArc(withCenter: NSPoint(x: circle.midX, y: circle.midY),
                           radius: circle.width / 2, startAngle: 90, endAngle: 270)
            half.close()
            half.fill()

            let outline = NSBezierPath(ovalIn: circle)
            outline.lineWidth = 1.5
            outline.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static var isLaunchedAsLoginItem: Bool {
        if ProcessInfo.processInfo.arguments.contains(darkLightLoginItemLaunchArgument) {
            return true
        }

        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else {
            return false
        }

        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
            || event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }

}
#endif

#if os(iOS)
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DailyCheckInScheduler.shared.start()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window

        if let url = launchOptions?[.url] as? URL, PremiumDeepLink.handlesPremiumURL([url]) {
            PremiumDeepLink.requestOpenPremium()
        }
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard PremiumDeepLink.handlesPremiumURL([url]) else {
            return false
        }
        PremiumDeepLink.requestOpenPremium()
        return true
    }
}
#endif
