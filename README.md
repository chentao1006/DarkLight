# Dark Light

**Per-site appearance control for the web.**

**English** | [简体中文](./README_CN.md)

---

Dark Light is a lightweight browser extension that lets you decide how each website should look. Use one global default, then override individual domains when a site needs its own rule.

## Why Use Dark Light?

* **Follow your real preference:** Choose Follow System, Preserve Site Design, Force Dark, or Force Light as the default behavior.
* **Per-site rules:** Set a different mode for any domain, with optional subdomain matching.
* **Better dark mode:** Dark Light first asks sites to use their native dark theme, then applies conservative fixes for stubborn light containers.
* **Reliable light mode:** The previous force-light behavior is preserved for dark sites that ignore your preference.
* **Local and private:** Settings and style changes stay in your browser.

## Features

* **Global default mode:** Follow System, Preserve Site Design, Force Dark, or Force Light.
* **Current-site popup controls:** Change the current domain in seconds.
* **Rules manager:** Add, edit, disable, and remove all site rules from the options page.
* **Visual badge:** The toolbar badge shows whether the current tab is being pushed to dark or light.
* **Manifest V3:** Built as a modern Chrome extension, with the code organized for a future Safari Web Extension.

## Installation

### Chrome Extension (Developer Mode)

1. Clone or download this repository.
2. Open Chrome and go to `chrome://extensions/`.
3. Enable **Developer mode**.
4. Click **Load unpacked**.
5. Select the `extension` directory.

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
