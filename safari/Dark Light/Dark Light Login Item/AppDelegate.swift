import AppKit

@main
final class LoginItemAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let helperURL = Bundle.main.bundleURL
        let mainAppURL = (0..<4).reduce(helperURL) { url, _ in
            url.deletingLastPathComponent()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.arguments = ["--darklight-login-item"]

        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration) { _, _ in
            NSApplication.shared.terminate(nil)
        }
    }
}
