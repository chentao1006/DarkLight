//
//  SafariWebExtensionHandler.swift
//  Dark Light Extension
//
//  Created by 陈涛 on 2026/6/18.
//

import SafariServices
import os.log
import StoreKit
#if os(macOS)
import AppKit
#endif

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let proProductIdentifier = "darklight.pro"
    private let settingsKey = "darkLightSettings"
    private let iCloudSyncEnabledKey = "darkLightICloudSyncEnabled"

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(.default, "Received message from browser.runtime.sendNativeMessage: %@ (profile: %@)", String(describing: message), profile?.uuidString ?? "none")

        Task {
            let responseMessage = await handleMessage(message, context: context)
            let response = NSExtensionItem()
            if #available(iOS 15.0, macOS 11.0, *) {
                response.userInfo = [ SFExtensionMessageKey: responseMessage ]
            } else {
                response.userInfo = [ "message": responseMessage ]
            }

            context.completeRequest(returningItems: [ response ], completionHandler: nil)
        }
    }

    private func handleMessage(_ message: Any?, context: NSExtensionContext) async -> [String: Any] {
        guard let payload = message as? [String: Any],
              let action = payload["action"] as? String else {
            return ["ok": false, "error": "invalidMessage"]
        }

        switch action {
        case "getProState":
            return await proStateResponse()
        case "getCloudSettings":
            return await cloudSettingsResponse()
        case "setCloudSettings":
            return await setCloudSettingsResponse(payload)
        case "setICloudSyncEnabled":
            return await setICloudSyncEnabledResponse(payload)
        case "openPremium":
            return await openPremiumResponse(context: context)
        default:
            return ["ok": false, "error": "unknownAction"]
        }
    }

    private func proStateResponse() async -> [String: Any] {
        let isPro = await hasUnlockedPro()
        let syncEnabled = isICloudSyncEnabled()

        return [
            "ok": true,
            "isPro": isPro,
            "iCloudSyncEnabled": syncEnabled
        ]
    }

    private func cloudSettingsResponse() async -> [String: Any] {
        let isPro = await hasUnlockedPro()
        guard isPro && isICloudSyncEnabled() else {
            return [
                "ok": true,
                "isPro": isPro,
                "iCloudSyncEnabled": isICloudSyncEnabled(),
                "settings": NSNull()
            ]
        }

        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        return [
            "ok": true,
            "isPro": isPro,
            "iCloudSyncEnabled": true,
            "settings": store.dictionary(forKey: settingsKey) ?? NSNull()
        ]
    }

    private func setCloudSettingsResponse(_ payload: [String: Any]) async -> [String: Any] {
        let isPro = await hasUnlockedPro()
        guard isPro && isICloudSyncEnabled() else {
            return [
                "ok": false,
                "isPro": isPro,
                "iCloudSyncEnabled": isICloudSyncEnabled(),
                "error": "iCloudSyncUnavailable"
            ]
        }

        guard let settings = payload["settings"] as? [String: Any] else {
            return ["ok": false, "error": "invalidSettings"]
        }

        let store = NSUbiquitousKeyValueStore.default
        store.set(settings, forKey: settingsKey)
        store.synchronize()
        return [
            "ok": true,
            "isPro": true,
            "iCloudSyncEnabled": true
        ]
    }

    private func setICloudSyncEnabledResponse(_ payload: [String: Any]) async -> [String: Any] {
        let isPro = await hasUnlockedPro()
        guard isPro else {
            return ["ok": false, "isPro": false, "error": "proRequired"]
        }

        let enabled = payload["enabled"] as? Bool ?? false
        NSUbiquitousKeyValueStore.default.set(enabled, forKey: iCloudSyncEnabledKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        return [
            "ok": true,
            "isPro": true,
            "iCloudSyncEnabled": enabled
        ]
    }

    private func isICloudSyncEnabled() -> Bool {
        NSUbiquitousKeyValueStore.default.synchronize()
        return NSUbiquitousKeyValueStore.default.bool(forKey: iCloudSyncEnabledKey)
    }

    private func openPremiumResponse(context: NSExtensionContext) async -> [String: Any] {
        guard let url = URL(string: "darklight://premium") else {
            return ["ok": false, "error": "invalidURL"]
        }

        #if os(macOS)
        NSWorkspace.shared.open(url)
        return ["ok": true]
        #else
        return await withCheckedContinuation { continuation in
            context.open(url) { success in
                continuation.resume(returning: success ? ["ok": true] : ["ok": false, "error": "openURLFailed"])
            }
        }
        #endif
    }

    private func hasUnlockedPro() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }
            if transaction.productID == proProductIdentifier && transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }
}
