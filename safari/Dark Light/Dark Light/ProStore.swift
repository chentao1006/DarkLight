import Foundation
import Combine
import StoreKit

let proProductIdentifier = "darklight.pro"
let iCloudSettingsKey = "darkLightSettings"
let iCloudSyncEnabledKey = "darkLightICloudSyncEnabled"

@MainActor
final class ProStore: ObservableObject {
    @Published var product: Product?
    @Published var isPro = false
    @Published var isLoading = false
    @Published var isPurchasing = false
    @Published var purchaseMessage: String?
    @Published var iCloudSyncEnabled: Bool {
        didSet {
            NSUbiquitousKeyValueStore.default.set(iCloudSyncEnabled, forKey: iCloudSyncEnabledKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        NSUbiquitousKeyValueStore.default.synchronize()
        iCloudSyncEnabled = NSUbiquitousKeyValueStore.default.bool(forKey: iCloudSyncEnabledKey)
        transactionUpdatesTask = listenForTransactionUpdates()
        Task {
            await refresh()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            product = try await Product.products(for: [proProductIdentifier]).first
        } catch {
            purchaseMessage = "Unable to load purchase information."
        }

        isPro = await Self.hasUnlockedPro()
    }

    func purchase() async {
        guard let product else {
            purchaseMessage = "Purchase is not available yet."
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refresh()
                purchaseMessage = "Dark Light Premium is unlocked."
            case .userCancelled:
                purchaseMessage = nil
            case .pending:
                purchaseMessage = "Purchase is pending."
            @unknown default:
                purchaseMessage = "Purchase did not complete."
            }
        } catch {
            purchaseMessage = "Purchase failed."
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refresh()
            purchaseMessage = isPro ? "Purchases restored." : "No Premium purchase was found."
        } catch {
            purchaseMessage = "Restore failed."
        }
    }

    static func hasUnlockedPro() async -> Bool {
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

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else {
                    continue
                }
                await transaction.finish()
                await self.refresh()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
