//
//  AppDelegate.swift
//  Dark Light
//
//  Created by 陈涛 on 2026/6/18.
//

#if os(macOS)
import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if PremiumDeepLink.handlesPremiumURL(urls) {
            PremiumDeepLink.requestOpenPremium()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

}
#endif

#if os(iOS)
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
