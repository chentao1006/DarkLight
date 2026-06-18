//
//  ViewController.swift
//  Dark Light
//
//  Created by 陈涛 on 2026/6/18.
//

import Cocoa
import SafariServices
import WebKit

let extensionBundleIdentifier = "com.ct106.darklight.Extension"
let safariBundleIdentifier = "com.apple.Safari"

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Avoid the default white WebKit paint before content is loaded.
        webView.setValue(false, forKey: "drawsBackground")
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "controller")

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
                self.webView.evaluateJavaScript("show(\(jsEnabledValue), \(usesSettingsLabel))")
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
