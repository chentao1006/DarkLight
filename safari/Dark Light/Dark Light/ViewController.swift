import Foundation
import SwiftUI
import Combine
import SafariServices
import StoreKit
import WebKit

let extensionBundleIdentifier = "com.ct106.darklight.Extension"
let safariBundleIdentifier = "com.apple.Safari" // only used on mac
let openPremiumNotification = Notification.Name("DarkLightOpenPremium")

enum PremiumDeepLink {
    private static var pendingOpenPremium = false

    static func handlesPremiumURL(_ urls: [URL]) -> Bool {
        urls.contains { $0.scheme == "darklight" && $0.host == "premium" }
    }

    static func requestOpenPremium() {
        DispatchQueue.main.async {
            pendingOpenPremium = true
            NotificationCenter.default.post(name: openPremiumNotification, object: nil)
        }
    }

    static func consumePendingOpenPremium() -> Bool {
        guard pendingOpenPremium else {
            return false
        }
        pendingOpenPremium = false
        return true
    }
}

// MARK: - Localization Strings
let localizedStrings: [String: [String: String]] = [
    "en": [
        "pageTitle": "Dark Light",
        "appIconAlt": "Dark Light Icon",
        "heroTitle": "Dark Light",
        "heroIntro": "Dark Light lets you decide how each website should \"look\": follow system, preserve site design, force dark, or force light.",
        "macUsageTitle": "How to enable on Mac",
        "macStep1": "Open Safari.",
        "macStep2": "Enable Dark Light in Safari Extensions Preferences.",
        "macStep3": "Click \"Always Allow on Every Website\".",
        "iphoneUsageTitle": "How to enable on iPhone",
        "ipadUsageTitle": "How to enable on iPad",
        "iosUsageTitle": "How to enable on iOS",
        "iosStep1": "Tap the button below to open App Settings.",
        "iosStep2": "In the list, find and tap Safari > Extensions.",
        "iosStep3": "Tap Dark Light and toggle it On.",
        "iosStep4": "Tap \"All Websites\" and select \"Allow\".",
        "statusUnknownSettings": "Dark Light is ready to be enabled.",
        "statusOnSettings": "Dark Light is enabled and ready to use in Safari.",
        "statusOffIOS": "Dark Light is currently disabled in Safari. You can turn it on in Settings.",
        "statusUnknownPreferences": "Dark Light is ready to be enabled.",
        "statusOnPreferences": "Dark Light is enabled and ready to use in Safari.",
        "statusOffMac": "Dark Light is currently disabled in Safari. You can turn it on in Preferences.",
        "proTitle": "Dark Light Premium",
        "proIntro": "Upgrade to unlock unlimited site rules, import and export, and iCloud sync.",
        "premiumFeatureRules": "Unlimited per-site rules",
        "premiumFeatureImportExport": "Import and export rule backups",
        "premiumFeatureICloud": "iCloud sync across Safari devices",
        "proUnlocked": "Premium is unlocked.",
        "proLocked": "Upgrade once to unlock Premium features.",
        "proPriceUnavailable": "Purchase unavailable",
        "buyPro": "Buy Premium",
        "restorePurchases": "Restore Purchases",
        "iCloudSync": "iCloud Sync",
        "iCloudSyncDetail": "Sync site rules across your Safari devices with iCloud.",
        "openingSafariExtensions": "Opening Safari extension settings...",
        "safariExtensionsOpenRequested": "Safari extension settings were requested. Check Safari Settings > Extensions.",
        "safariExtensionsOpenFailed": "Could not open Safari extension settings.",
        "openPreferencesIOS": "Open Apps Settings",
        "openPreferencesMac": "Open Safari Extensions",
        "openSafari": "Open Safari"
    ],
    "zh": [
        "pageTitle": "暗光",
        "appIconAlt": "暗光图标",
        "heroTitle": "暗光",
        "heroIntro": "暗光让你决定每个网站该如何显示：跟随系统外观、维持网站设计、强制深色或强制浅色。",
        "macUsageTitle": "在 Mac 上如何开启",
        "macStep1": "打开 Safari。",
        "macStep2": "在 Safari 的扩展偏好设置中勾选暗光。",
        "macStep3": "点击“在每个网站上始终允许”。",
        "iphoneUsageTitle": "在 iPhone 上如何开启",
        "ipadUsageTitle": "在 iPad 上如何开启",
        "iosUsageTitle": "在 iOS 上如何开启",
        "iosStep1": "点击下方按钮打开 Apps 设置。",
        "iosStep2": "在列表中找到并进入 Safari 浏览器 > 扩展。",
        "iosStep3": "点击“暗光”并将其开关打开。",
        "iosStep4": "点击“所有网站”，选择“允许”。",
        "statusUnknownSettings": "暗光已准备好开启。",
        "statusOnSettings": "暗光已在 Safari 中启用，可以直接使用。",
        "statusOffIOS": "暗光当前处于关闭状态。你可以在设置中启用它。",
        "statusUnknownPreferences": "暗光已准备好开启。",
        "statusOnPreferences": "暗光已在 Safari 中启用，可以直接使用。",
        "statusOffMac": "暗光当前处于关闭状态。你可以在偏好设置中启用它。",
        "proTitle": "暗光高级版",
        "proIntro": "升级后可解锁无限网站规则、导入导出和 iCloud 同步。",
        "premiumFeatureRules": "无限网站规则",
        "premiumFeatureImportExport": "导入和导出规则备份",
        "premiumFeatureICloud": "通过 iCloud 在 Safari 设备之间同步",
        "proUnlocked": "高级版已解锁。",
        "proLocked": "一次购买即可解锁高级版功能。",
        "proPriceUnavailable": "暂不可购买",
        "buyPro": "购买高级版",
        "restorePurchases": "恢复购买",
        "iCloudSync": "iCloud 同步",
        "iCloudSyncDetail": "通过 iCloud 在你的 Safari 设备之间同步网站规则。",
        "openingSafariExtensions": "正在打开 Safari 扩展设置...",
        "safariExtensionsOpenRequested": "已请求打开 Safari 扩展设置。请查看 Safari 设置 > 扩展。",
        "safariExtensionsOpenFailed": "无法打开 Safari 扩展设置。",
        "openPreferencesIOS": "打开 Apps 设置",
        "openPreferencesMac": "打开 Safari 扩展设置",
        "openSafari": "打开 Safari"
    ],
    "ja": [
        "pageTitle": "Dark Light",
        "appIconAlt": "Dark Light アイコン",
        "heroTitle": "Dark Light",
        "heroIntro": "Dark Lightでは、各ウェブサイトの表示方法（システムに従う、サイトのデザインを維持する、強制的にダーク、強制的にライト）を決定できます。",
        "macUsageTitle": "Macでの有効化方法",
        "macStep1": "Safariを開きます。",
        "macStep2": "Safariの機能拡張環境設定でDark Lightを有効にします。",
        "macStep3": "「すべてのWebサイトで常に許可」をクリックします。",
        "iphoneUsageTitle": "iPhoneでの有効化方法",
        "ipadUsageTitle": "iPadでの有効化方法",
        "iosUsageTitle": "iOSでの有効化方法",
        "iosStep1": "下のボタンをタップして「設定」アプリを開きます。",
        "iosStep2": "リストで「Safari」>「拡張機能」を見つけてタップします。",
        "iosStep3": "「Dark Light」をタップしてオンにします。",
        "iosStep4": "「すべてのWebサイト」をタップして「許可」を選択します。",
        "statusUnknownSettings": "Dark Lightを有効にする準備ができました。",
        "statusOnSettings": "Dark LightはSafariで有効になっており、すぐに使用できます。",
        "statusOffIOS": "Dark Lightは現在Safariで無効になっています。設定で有効にすることができます。",
        "statusUnknownPreferences": "Dark Lightを有効にする準備ができました。",
        "statusOnPreferences": "Dark LightはSafariで有効になっており、すぐに使用できます。",
        "statusOffMac": "Dark Lightは現在Safariで無効になっています。環境設定で有効にすることができます。",
        "proTitle": "Dark Light Premium",
        "proIntro": "アップグレードすると、無制限のサイトルール、インポートとエクスポート、iCloud同期を利用できます。",
        "premiumFeatureRules": "無制限のサイトルール",
        "premiumFeatureImportExport": "ルールバックアップのインポートとエクスポート",
        "premiumFeatureICloud": "Safariデバイス間のiCloud同期",
        "proUnlocked": "Premiumはロック解除済みです。",
        "proLocked": "一度の購入でPremium機能をロック解除できます。",
        "proPriceUnavailable": "購入できません",
        "buyPro": "Premiumを購入",
        "restorePurchases": "購入を復元",
        "iCloudSync": "iCloud同期",
        "iCloudSyncDetail": "iCloudでSafariデバイス間のサイトルールを同期します。",
        "openPreferencesIOS": "設定アプリを開く",
        "openPreferencesMac": "Safari機能拡張を開く",
        "openSafari": "Safariを開く"
    ],
    "ko": [
        "pageTitle": "Dark Light",
        "appIconAlt": "Dark Light 아이콘",
        "heroTitle": "Dark Light",
        "heroIntro": "Dark Light를 사용하면 각 웹사이트의 표시 방법(시스템 따르기, 사이트 디자인 유지, 강제 다크, 강제 라이트)을 결정할 수 있습니다.",
        "macUsageTitle": "Mac에서 활성화하는 방법",
        "macStep1": "Safari를 엽니다.",
        "macStep2": "Safari 확장 프로그램 환경설정에서 Dark Light를 활성화합니다.",
        "macStep3": "\"모든 웹사이트에서 항상 허용\"을 클릭합니다.",
        "iphoneUsageTitle": "iPhone에서 활성화하는 방법",
        "ipadUsageTitle": "iPad에서 활성화하는 방법",
        "iosUsageTitle": "iOS에서 활성화하는 방법",
        "iosStep1": "아래 버튼을 탭하여 설정 앱을 엽니다.",
        "iosStep2": "목록에서 Safari > 확장 프로그램을 찾아 탭합니다.",
        "iosStep3": "Dark Light를 탭하고 켭니다.",
        "iosStep4": "\"모든 웹사이트\"를 탭하고 \"허용\"을 선택합니다.",
        "statusUnknownSettings": "Dark Light를 활성화할 준비가 되었습니다.",
        "statusOnSettings": "Dark Light가 Safari에서 활성화되어 바로 사용할 수 있습니다.",
        "statusOffIOS": "Dark Light가 현재 Safari에서 비활성화되어 있습니다. 설정에서 켤 수 있습니다.",
        "statusUnknownPreferences": "Dark Light를 활성화할 준비가 되었습니다.",
        "statusOnPreferences": "Dark Light가 Safari에서 활성화되어 바로 사용할 수 있습니다.",
        "statusOffMac": "Dark Light가 현재 Safari에서 비활성화되어 있습니다. 환경설정에서 켤 수 있습니다.",
        "proTitle": "Dark Light Premium",
        "proIntro": "업그레이드하면 무제한 사이트 규칙, 가져오기와 내보내기, iCloud 동기화를 사용할 수 있습니다.",
        "premiumFeatureRules": "무제한 사이트 규칙",
        "premiumFeatureImportExport": "규칙 백업 가져오기 및 내보내기",
        "premiumFeatureICloud": "Safari 기기 간 iCloud 동기화",
        "proUnlocked": "Premium이 잠금 해제되었습니다.",
        "proLocked": "한 번 구매하면 Premium 기능을 잠금 해제할 수 있습니다.",
        "proPriceUnavailable": "구매할 수 없음",
        "buyPro": "Premium 구매",
        "restorePurchases": "구매 복원",
        "iCloudSync": "iCloud 동기화",
        "iCloudSyncDetail": "iCloud로 Safari 기기 간 사이트 규칙을 동기화합니다.",
        "openPreferencesIOS": "설정 앱 열기",
        "openPreferencesMac": "Safari 확장 프로그램 열기",
        "openSafari": "Safari 열기"
    ],
    "es": [
        "pageTitle": "Dark Light",
        "appIconAlt": "Icono de Dark Light",
        "heroTitle": "Dark Light",
        "heroIntro": "Dark Light te permite decidir cómo debe verse cada sitio \"web\": seguir el sistema, conservar el diseño del sitio, forzar oscuro o forzar claro.",
        "macUsageTitle": "Cómo habilitar en Mac",
        "macStep1": "Abre Safari.",
        "macStep2": "Habilita Dark Light en las Preferencias de Extensiones de Safari.",
        "macStep3": "Haz clic en \"Permitir siempre en todos los sitios web\".",
        "iphoneUsageTitle": "Cómo habilitar en iPhone",
        "ipadUsageTitle": "Cómo habilitar en iPad",
        "iosUsageTitle": "Cómo habilitar en iOS",
        "iosStep1": "Toca el botón a continuación para abrir Configuración.",
        "iosStep2": "En la lista, busca y toca Safari > Extensiones.",
        "iosStep3": "Toca Dark Light y actívalo.",
        "iosStep4": "Toca \"Todos los sitios web\" y selecciona \"Permitir\".",
        "statusUnknownSettings": "Dark Light está listo para ser habilitado.",
        "statusOnSettings": "Dark Light está habilitado y listo para usarse en Safari.",
        "statusOffIOS": "Dark Light está actualmente deshabilitado en Safari. Puedes activarlo en Configuración.",
        "statusUnknownPreferences": "Dark Light está listo para ser habilitado.",
        "statusOnPreferences": "Dark Light está habilitado y listo para usarse en Safari.",
        "statusOffMac": "Dark Light está actualmente deshabilitado en Safari. Puedes activarlo en Preferencias.",
        "proTitle": "Dark Light Premium",
        "proIntro": "Actualiza para desbloquear reglas ilimitadas por sitio, importación y exportación y sincronización con iCloud.",
        "premiumFeatureRules": "Reglas ilimitadas por sitio",
        "premiumFeatureImportExport": "Importar y exportar copias de seguridad de reglas",
        "premiumFeatureICloud": "Sincronización de iCloud entre dispositivos Safari",
        "proUnlocked": "Premium está desbloqueado.",
        "proLocked": "Actualiza una vez para desbloquear las funciones Premium.",
        "proPriceUnavailable": "Compra no disponible",
        "buyPro": "Comprar Premium",
        "restorePurchases": "Restaurar compras",
        "iCloudSync": "Sincronización de iCloud",
        "iCloudSyncDetail": "Sincroniza reglas de sitios entre tus dispositivos Safari con iCloud.",
        "openPreferencesIOS": "Abrir Configuración",
        "openPreferencesMac": "Abrir extensiones de Safari",
        "openSafari": "Abrir Safari"
    ],
    "fr": [
        "pageTitle": "Dark Light",
        "appIconAlt": "Icône Dark Light",
        "heroTitle": "Dark Light",
        "heroIntro": "Dark Light vous permet de décider de l\'apparence de chaque site Web : suivre le système, conserver la conception du site, forcer le mode sombre ou forcer le mode clair.",
        "macUsageTitle": "Comment activer sur Mac",
        "macStep1": "Ouvrez Safari.",
        "macStep2": "Activez Dark Light dans les Préférences des extensions Safari.",
        "macStep3": "Cliquez sur \"Toujours autoriser sur tous les sites Web\".",
        "iphoneUsageTitle": "Comment activer sur iPhone",
        "ipadUsageTitle": "Comment activer sur iPad",
        "iosUsageTitle": "Comment activer sur iOS",
        "iosStep1": "Touchez le bouton ci-dessous pour ouvrir les Réglages.",
        "iosStep2": "Dans la liste, trouvez et touchez Safari > Extensions.",
        "iosStep3": "Touchez Dark Light et activez-le.",
        "iosStep4": "Touchez \"Tous les sites Web\" et sélectionnez \"Autoriser\".",
        "statusUnknownSettings": "Dark Light est prêt à être activé.",
        "statusOnSettings": "Dark Light est activé et prêt à être utilisé dans Safari.",
        "statusOffIOS": "Dark Light est actuellement désactivé dans Safari. Vous pouvez l\'activer dans les Réglages.",
        "statusUnknownPreferences": "Dark Light est prêt à être activé.",
        "statusOnPreferences": "Dark Light est activé et prêt à être utilisé dans Safari.",
        "statusOffMac": "Dark Light est actuellement désactivé dans Safari. Vous pouvez l\'activer dans les Préférences.",
        "proTitle": "Dark Light Premium",
        "proIntro": "Passez à Premium pour débloquer des règles de site illimitées, l'importation et l'exportation, et la synchronisation iCloud.",
        "premiumFeatureRules": "Règles de site illimitées",
        "premiumFeatureImportExport": "Importation et exportation des sauvegardes de règles",
        "premiumFeatureICloud": "Synchronisation iCloud entre appareils Safari",
        "proUnlocked": "Premium est débloqué.",
        "proLocked": "Achetez une fois pour débloquer les fonctions Premium.",
        "proPriceUnavailable": "Achat indisponible",
        "buyPro": "Acheter Premium",
        "restorePurchases": "Restaurer les achats",
        "iCloudSync": "Synchronisation iCloud",
        "iCloudSyncDetail": "Synchronisez les règles de site entre vos appareils Safari avec iCloud.",
        "openPreferencesIOS": "Ouvrir les Réglages",
        "openPreferencesMac": "Ouvrir les extensions Safari",
        "openSafari": "Ouvrir Safari"
    ],
    "de": [
        "pageTitle": "Dark Light",
        "appIconAlt": "Dark Light Symbol",
        "heroTitle": "Dark Light",
        "heroIntro": "Mit Dark Light können Sie entscheiden, wie jede Website aussehen \"soll\": System folgen, Site-Design beibehalten, Dunkel erzwingen oder Hell erzwingen.",
        "macUsageTitle": "Wie man es auf dem Mac aktiviert",
        "macStep1": "Öffnen Sie Safari.",
        "macStep2": "Aktivieren Sie Dark Light in den Safari-Erweiterungseinstellungen.",
        "macStep3": "Klicken Sie auf \"Auf jeder Website immer zulassen\".",
        "iphoneUsageTitle": "Wie man es auf dem iPhone aktiviert",
        "ipadUsageTitle": "Wie man es auf dem iPad aktiviert",
        "iosUsageTitle": "Wie man es auf iOS aktiviert",
        "iosStep1": "Tippen Sie auf die Schaltfläche unten, um die Einstellungen zu öffnen.",
        "iosStep2": "Suchen und tippen Sie in der Liste auf Safari > Erweiterungen.",
        "iosStep3": "Tippen Sie auf Dark Light und schalten Sie es ein.",
        "iosStep4": "Tippen Sie auf \"Alle Websites\" und wählen Sie \"Zulassen\".",
        "statusUnknownSettings": "Dark Light kann jetzt aktiviert werden.",
        "statusOnSettings": "Dark Light ist in Safari aktiviert und einsatzbereit.",
        "statusOffIOS": "Dark Light ist derzeit in Safari deaktiviert. Sie können es in den Einstellungen einschalten.",
        "statusUnknownPreferences": "Dark Light kann jetzt aktiviert werden.",
        "statusOnPreferences": "Dark Light ist in Safari aktiviert und einsatzbereit.",
        "statusOffMac": "Dark Light ist derzeit in Safari deaktiviert. Sie können es in den Einstellungen einschalten.",
        "proTitle": "Dark Light Premium",
        "proIntro": "Mit dem Upgrade schalten Sie unbegrenzte Website-Regeln, Import und Export sowie iCloud-Sync frei.",
        "premiumFeatureRules": "Unbegrenzte Website-Regeln",
        "premiumFeatureImportExport": "Regelsicherungen importieren und exportieren",
        "premiumFeatureICloud": "iCloud-Sync zwischen Safari-Geräten",
        "proUnlocked": "Premium ist freigeschaltet.",
        "proLocked": "Einmal upgraden, um Premium-Funktionen freizuschalten.",
        "proPriceUnavailable": "Kauf nicht verfügbar",
        "buyPro": "Premium kaufen",
        "restorePurchases": "Käufe wiederherstellen",
        "iCloudSync": "iCloud-Sync",
        "iCloudSyncDetail": "Synchronisieren Sie Website-Regeln per iCloud zwischen Ihren Safari-Geräten.",
        "openPreferencesIOS": "Einstellungen öffnen",
        "openPreferencesMac": "Safari-Erweiterungen öffnen",
        "openSafari": "Safari öffnen"
    ]
]

class SetupViewModel: ObservableObject {
    @Published var isEnabled: Bool? = nil
    @Published var currentLanguage: String = "en"
    @Published var preferencesMessage: String? = nil
    
    init() {
        let locale = Locale.current.languageCode ?? "en"
        if localizedStrings.keys.contains(locale) {
            currentLanguage = locale
        } else if locale.starts(with: "zh") {
            currentLanguage = "zh"
        }
        refreshExtensionState()
        
        #if os(macOS)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshExtensionState()
        }
        #else
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshExtensionState()
        }
        #endif
    }
    
    func refreshExtensionState() {
        #if os(macOS)
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            DispatchQueue.main.async {
                if error != nil {
                    self.isEnabled = nil
                } else {
                    self.isEnabled = state?.isEnabled
                }
            }
        }
        #else
        if #available(iOS 26.2, *) {
            SFSafariExtensionManager.getStateOfExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
                DispatchQueue.main.async {
                    if error != nil {
                        self.isEnabled = nil
                    } else {
                        self.isEnabled = state?.isEnabled
                    }
                }
            }
        } else {
            // getStateOfExtension is not available on iOS < 26.2
            // Fall back to unknown state; the UI will prompt the user to open Settings
            self.isEnabled = nil
        }
        #endif
    }
    
    func t(_ key: String) -> String {
        return localizedStrings[currentLanguage]?[key] ?? localizedStrings["en"]?[key] ?? ""
    }
    
    func openPreferences() {
        #if os(macOS)
        preferencesMessage = t("openingSafariExtensions")
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
            DispatchQueue.main.async {
                if let error {
                    self.preferencesMessage = "\(self.t("safariExtensionsOpenFailed")) \(error.localizedDescription)"
                    self.activateSafari()
                    return
                }
                self.preferencesMessage = self.t("safariExtensionsOpenRequested")
                self.refreshExtensionState()
            }
        }
        #else
        let urls = [
            "App-Prefs:root=SAFARI&path=WEB_EXTENSIONS",
            "App-Prefs:root=SAFARI",
            "prefs:root=SAFARI",
            "App-Prefs:root=APPS",
            "App-Prefs:"
        ].compactMap { URL(string: $0) }
        
        func tryOpenURL(at index: Int) {
            guard index < urls.count else { 
                exit(0)
            }
            UIApplication.shared.open(urls[index], options: [:]) { success in
                if !success {
                    tryOpenURL(at: index + 1)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        exit(0)
                    }
                }
            }
        }
        tryOpenURL(at: 0)
        #endif
    }
    
    func openSafari() {
        #if os(macOS)
        activateSafari {
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
        #else
        if let url = URL(string: "x-web-search://") {
            UIApplication.shared.open(url, options: [:]) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    exit(0)
                }
            }
        } else {
            exit(0)
        }
        #endif
    }
    
    #if os(macOS)
    private func activateSafari(completion: (() -> Void)? = nil) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: safariBundleIdentifier) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                completion?()
            }
        } else {
            completion?()
        }
    }
    #endif
}

struct SetupView: View {
    @StateObject var viewModel = SetupViewModel()
    @StateObject var proStore = ProStore()
    @State private var showingPremiumDetails = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background Blobs
            GeometryReader { geo in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .opacity(0.4)
                    .offset(x: -100, y: -50)
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 250, height: 250)
                    .blur(radius: 100)
                    .opacity(0.4)
                    .offset(x: geo.size.width - 150, y: geo.size.height - 150)
            }
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 10) {
                        #if os(macOS)
                        Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                            .resizable()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 10)
                            .padding(.bottom, 6)
                        #else
                        Image(uiImage: UIImage(named: "AppIconImage") ?? UIImage())
                            .resizable()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 10)
                            .padding(.bottom, 6)
                        #endif
                        
                        Text(viewModel.t("heroTitle"))
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    // Usage Card
                    VStack(alignment: .leading, spacing: 12) {
                        #if os(macOS)
                        Text(viewModel.t("macUsageTitle"))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) { Text("1.").foregroundColor(.secondary); Text(viewModel.t("macStep1")).foregroundColor(.secondary) }
                            HStack(alignment: .top) { Text("2.").foregroundColor(.secondary); Text(viewModel.t("macStep2")).foregroundColor(.secondary) }
                            HStack(alignment: .top) { Text("3.").foregroundColor(.secondary); Text(viewModel.t("macStep3")).foregroundColor(.secondary) }
                        }
                        .font(.subheadline)
                        #else
                        Text(viewModel.t("iosUsageTitle"))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) { Text("1.").foregroundColor(.secondary); Text(viewModel.t("iosStep1")).foregroundColor(.secondary) }
                            HStack(alignment: .top) { Text("2.").foregroundColor(.secondary); Text(viewModel.t("iosStep2")).foregroundColor(.secondary) }
                            HStack(alignment: .top) { Text("3.").foregroundColor(.secondary); Text(viewModel.t("iosStep3")).foregroundColor(.secondary) }
                            if !viewModel.t("iosStep4").isEmpty {
                                HStack(alignment: .top) { Text("4.").foregroundColor(.secondary); Text(viewModel.t("iosStep4")).foregroundColor(.secondary) }
                            }
                        }
                        .font(.subheadline)
                        #endif
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(macOS)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    #else
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                    #endif
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
                    
                    // Status Banner
                    HStack {
                        Text(statusText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    #if os(macOS)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
                    #else
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                    #endif
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .overlay(
                        Rectangle()
                            .fill(statusColor)
                            .frame(width: 4)
                            .padding(.vertical, 1),
                        alignment: .leading
                    )

                    // Actions
                    HStack(spacing: 16) {
                        if viewModel.isEnabled != true {
                            Button(action: {
                                viewModel.openPreferences()
                            }) {
                                #if os(macOS)
                                Text(viewModel.t("openPreferencesMac"))
                                #else
                                Text(viewModel.t("openPreferencesIOS"))
                                #endif
                            }
                        }
                        
                        Button(action: {
                            viewModel.openSafari()
                        }) {
                            Text(viewModel.t("openSafari"))
                        }
                    }
                    .padding(.top, 10)
                    
                    if let preferencesMessage = viewModel.preferencesMessage {
                        Text(preferencesMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            
            // Top Controls
            VStack {
                HStack {
                    Button(action: {
                        showingPremiumDetails = true
                    }) {
                        Label(viewModel.t("proTitle"), systemImage: "star.circle")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Picker("", selection: $viewModel.currentLanguage) {
                        Text("English").tag("en")
                        Text("简体中文").tag("zh")
                        Text("日本語").tag("ja")
                        Text("한국어").tag("ko")
                        Text("Español").tag("es")
                        Text("Français").tag("fr")
                        Text("Deutsch").tag("de")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .padding()
                Spacer()
            }
        }
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(UIColor.systemBackground))
        #endif
        .sheet(isPresented: $showingPremiumDetails) {
            PremiumDetailsView(viewModel: viewModel, proStore: proStore)
        }
        .onAppear {
            if PremiumDeepLink.consumePendingOpenPremium() {
                showingPremiumDetails = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: openPremiumNotification)) { _ in
            showingPremiumDetails = true
        }
    }
    
    var statusText: String {
        if viewModel.isEnabled == true {
            #if os(macOS)
            return viewModel.t("statusOnPreferences")
            #else
            return viewModel.t("statusOnSettings")
            #endif
        } else if viewModel.isEnabled == false {
            #if os(macOS)
            return viewModel.t("statusOffMac")
            #else
            return viewModel.t("statusOffIOS")
            #endif
        } else {
            #if os(macOS)
            return viewModel.t("statusUnknownPreferences")
            #else
            return viewModel.t("statusUnknownSettings")
            #endif
        }
    }
    
    var statusColor: Color {
        if viewModel.isEnabled == true {
            return .green
        } else if viewModel.isEnabled == false {
            return .orange
        } else {
            return .clear
        }
    }
}

struct PremiumDetailsView: View {
    @ObservedObject var viewModel: SetupViewModel
    @ObservedObject var proStore: ProStore
    @Environment(\.dismiss) private var dismiss
    
    private var featureKeys: [String] {
        [
            "premiumFeatureRules",
            "premiumFeatureImportExport",
            "premiumFeatureICloud"
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.t("proTitle"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(proStore.isPro ? viewModel.t("proUnlocked") : viewModel.t("proLocked"))
                        .font(.subheadline)
                        .foregroundColor(proStore.isPro ? .green : .secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            
            Text(viewModel.t("proIntro"))
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(featureKeys, id: \.self) { key in
                    Label(viewModel.t(key), systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            
            Divider()
            
            if proStore.isPro {
                Toggle(isOn: $proStore.iCloudSyncEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.t("iCloudSync"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(viewModel.t("iCloudSyncDetail"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } else {
                HStack(spacing: 12) {
                    Button(action: {
                        Task { await proStore.purchase() }
                    }) {
                        Text(proStore.product == nil ? viewModel.t("proPriceUnavailable") : "\(viewModel.t("buyPro")) \(proStore.product?.displayPrice ?? "")")
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(proStore.product == nil || proStore.isPurchasing)
                    
                    Button(action: {
                        Task { await proStore.restore() }
                    }) {
                        Text(viewModel.t("restorePurchases"))
                    }
                    .disabled(proStore.isPurchasing)
                }
            }
            
            if let message = proStore.purchaseMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 460, alignment: .leading)
        #else
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

#if os(macOS)
import Cocoa

class ViewController: NSViewController {
    @IBOutlet var webView: WKWebView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        webView?.isHidden = true
        webView?.removeFromSuperview()
        
        let setupView = SetupView()
        let hostingView = NSHostingView(rootView: setupView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
#endif

#if os(iOS)
import UIKit

class ViewController: UIViewController {
    var webView: WKWebView?
    
    override func loadView() {
        super.loadView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        webView?.isHidden = true
        webView?.removeFromSuperview()
        
        let setupView = SetupView()
        let hostingController = UIHostingController(rootView: setupView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
#endif
