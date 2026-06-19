//
//  ViewController.swift
//  Dark Light
//
//  Created by 陈涛 on 2026/6/18.
//

#if os(macOS)
import Cocoa
import SafariServices
import WebKit

let extensionBundleIdentifier = "com.ct106.darklight.Extension"
let safariBundleIdentifier = "com.apple.Safari"

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    private var titleObservation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Avoid the default white WebKit paint before content is loaded.
        webView.setValue(false, forKey: "drawsBackground")
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "controller")

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] (webView, change) in
            if let title = change.newValue as? String, !title.isEmpty {
                self?.view.window?.title = title
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        if let htmlURL = Bundle.main.url(forResource: "Main", withExtension: "html"),
           let resourceURL = Bundle.main.resourceURL {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceURL)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "controller")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshExtensionState()
    }

    @objc private func applicationDidBecomeActive() {
        refreshExtensionState()
    }

    private func refreshExtensionState() {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            DispatchQueue.main.async {
                let usesSettingsLabel: Bool
                if #available(macOS 13, *) {
                    usesSettingsLabel = true
                } else {
                    usesSettingsLabel = false
                }

                // Treat lookup errors as unknown, not disabled, to avoid false "off" status.
                let enabledState: Bool?
                if error != nil {
                    enabledState = nil
                } else {
                    enabledState = state?.isEnabled
                }

                let jsEnabledValue = enabledState.map { $0 ? "true" : "false" } ?? "null"
                self.webView.evaluateJavaScript("show(\(jsEnabledValue), \(usesSettingsLabel), 'macOS')")
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let action = message.body as? String else {
            return
        }

        if action == "open-safari" {
            openSafari()
            return
        }

        if action != "open-preferences" {
            return
        }

        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { _ in
            DispatchQueue.main.async {
                self.openSafari()
            }
        }
    }

    private func openSafari() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: safariBundleIdentifier) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

}
#endif

#if os(iOS)
import UIKit
import SafariServices
import WebKit

let extensionBundleIdentifier = "com.ct106.darklight.Extension"

class ViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {

    var webView: WKWebView!

    override func loadView() {
        view = UIView()
        view.backgroundColor = .systemBackground
        
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "controller")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        if let htmlURL = Bundle.main.url(forResource: "Main", withExtension: "html"),
           let resourceURL = Bundle.main.resourceURL {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceURL)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "controller")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshExtensionState()
    }

    @objc private func applicationDidBecomeActive() {
        refreshExtensionState()
    }

    private func refreshExtensionState() {
        if #available(iOS 26.2, *) {
            SFSafariExtensionManager.getStateOfExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
                DispatchQueue.main.async {
                    let usesSettingsLabel = true
                    let enabledState: Bool?
                    if error != nil {
                        enabledState = nil
                    } else {
                        enabledState = state?.isEnabled
                    }
                    let jsEnabledValue = enabledState.map { $0 ? "true" : "false" } ?? "null"
                    let platformName = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
                    self.webView.evaluateJavaScript("show(\(jsEnabledValue), \(usesSettingsLabel), '\(platformName)')")
                }
            }
        } else {
            DispatchQueue.main.async {
                let usesSettingsLabel = true
                let platformName = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
                self.webView.evaluateJavaScript("show(null, \(usesSettingsLabel), '\(platformName)')")
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let action = message.body as? String else {
            return
        }

        if action == "open-safari" {
            openSafari()
            return
        }

        if action == "open-preferences" {
            openPreferences()
            return
        }
    }

    private func openSafari() {
        if let url = URL(string: "x-web-search://") {
            UIApplication.shared.open(url)
        }
    }

    private func openPreferences() {
        let urls = [
            "App-Prefs:root=SAFARI&path=WEB_EXTENSIONS",
            "App-Prefs:root=SAFARI",
            "prefs:root=SAFARI",
            "App-Prefs:root=APPS",
            "App-Prefs:"
        ].compactMap { URL(string: $0) }
        
        func tryOpenURL(at index: Int) {
            guard index < urls.count else { return }
            
            UIApplication.shared.open(urls[index], options: [:]) { success in
                if !success {
                    tryOpenURL(at: index + 1)
                }
            }
        }
        
        tryOpenURL(at: 0)
    }
}
#endif
