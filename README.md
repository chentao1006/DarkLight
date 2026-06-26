# Dark Light

**You control website appearance: dark mode and light mode in one extension.**

**English** | [简体中文](./README_CN.md)

---

Dark Light is a lightweight browser extension that gives you bidirectional control over website appearance. Unlike typical dark-mode extensions, Dark Light provides both Force Dark mode for bright pages and a reliable Force Light mode to turn dark sites back to light, letting you customize your reading environment exactly how you want.

## Why Use Dark Light?

* **True Bidirectional Control:** Force dark mode on bright websites, or force light mode on dark websites to match your reading environment.
* **Follow your real preference:** Choose Follow System, Preserve Site Design, Force Dark, or Force Light as the default behavior.
* **Per-site rules:** Set a different mode for any domain, with optional subdomain matching.
* **Better dark mode:** Turn light-heavy websites into comfortable dark reading spaces.
* **Reliable light mode:** Turn dark websites back to light when you want daytime readability.
* **Local and private:** Settings and style changes stay in your browser.

## Features

* **Global default mode:** Follow System, Preserve Site Design, Force Dark, or Force Light.
* **Current-site popup controls:** Change the current domain in seconds.
* **Rules manager:** Add, edit, disable, and remove all site rules from the options page.
* **Visual badge:** The toolbar badge shows mode at a glance: `A` (Follow System), `🌙` (Force Dark), `☀️` (Force Light), empty for Preserve Site.
* **Safari app included:** A native macOS host app and Safari Web Extension project are included under `safari/`.

## Installation

[![Download on the App Store](assets/app_store.png)](https://apps.apple.com/us/app/dark-light-for-webpages/id6781749180)
[![Available in the Chrome Web Store](assets/chrome-web-store-badge.png)](https://chromewebstore.google.com/detail/dark-light/jmckaadolajjpcmlciacmdenlfkolnhf)
[![Get the Firefox Add-on](assets/firefox.png)](https://addons.mozilla.org/zh-CN/firefox/addon/dark-light-web-mode/)

## Screenshots

### Safari (iOS / iPadOS)

| Popup | Rules Manager | App Setup |
|-------|---------------|-----------|
| ![Safari iOS popup](assets/000001.jpg) | ![Safari iOS rules](assets/000004.jpg) | ![Safari iPhone app](assets/000003.jpg) |

| iPad App |
|----------|
| ![Safari iPad app](assets/000002.jpg) |

### Chrome

| Popup (compact) | Popup (wide) | Options Page |
|-----------------|--------------|--------------|
| ![Chrome popup compact](assets/000007.jpg) | ![Chrome popup wide](assets/000008.jpg) | ![Chrome options](assets/000010.jpg) |

| Options Page (full) |
|---------------------|
| ![Chrome options full](assets/000009.jpg) |

### In Action

| Force Dark | Force Light |
|------------|-------------|
| ![Force Dark on a website – Safari](assets/000005.jpg) | ![Force Light on a website – Safari](assets/000006.jpg) |


### Chrome Extension (Developer Mode)

1. Clone or download this repository.
2. Open Chrome and go to `chrome://extensions/`.
3. Enable **Developer mode**.
4. Click **Load unpacked**.
5. Select the `extension` directory.

### Safari App (Xcode)

1. Open `safari/Dark Light/Dark Light.xcodeproj` in Xcode.
2. Select the `Dark Light` scheme and run it on `My Mac`, or select `Dark Light iOS` to run it on iPhone or iPad (iOS 15+).
3. The host app opens a simple introduction window with buttons to launch Safari and open Safari's extension settings.
4. Enable `Dark Light` in Safari, then use the Safari toolbar popup as usual.

The userscript distribution is no longer maintained.

## Technical Details

Dark Light stores settings in `chrome.storage.sync` under `darkLightSettings`.

Force Dark is powered by the vendored `darkreader` package (`extension/vendor/darkreader/`), which is MIT licensed.

The current schema is:

```ts
type ConfiguredMode = 'followSystem' | 'preserveSite' | 'forceDark' | 'forceLight';

type SiteRule = {
  id: string;
  pattern: string;
  mode: ConfiguredMode;
  enabled: boolean;
  matchSubdomains: boolean;
};

type Settings = {
  version: 2;
  defaultMode: ConfiguredMode;
  siteRules: SiteRule[];
};
```

The content script resolves the matching rule, converts `followSystem` into the active system appearance, preserves the page untouched for `preserveSite`, or runs the Force Dark / Force Light strategy.

Permissions used:

- `storage`: Save default mode and site rules.
- `activeTab`: Read the current tab in the popup.
- `<all_urls>` content script: Apply appearance rules on matching pages.

## Privacy

Dark Light does not collect, track, or transmit personal data, browsing history, keystrokes, or page content. All processing happens locally in your browser.
