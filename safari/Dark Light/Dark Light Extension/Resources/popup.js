const SETTINGS_KEY = 'darkLightSettings';
const SETTINGS_VERSION = 2;
const VALID_DEFAULT_MODES = ['followSystem', 'preserveSite', 'forceDark', 'forceLight'];
const VALID_RULE_MODES = [...VALID_DEFAULT_MODES, 'inherit'];

document.addEventListener('DOMContentLoaded', async () => {
    if (navigator.userAgent.includes('iPhone')) {
        document.body.style.width = '100%';
    }

    await I18n.init();

    const extLangSwitcher = document.getElementById('extLangSwitcher');
    if (extLangSwitcher) {
        extLangSwitcher.value = I18n.currentLang;
        extLangSwitcher.addEventListener('change', async (e) => {
            await new Promise(resolve => chrome.storage.local.set({ userLanguage: e.target.value }, resolve));
            await I18n.init();
            localize();
            if (typeof renderSiteRule === 'function') {
                renderSiteRule();
            }
        });
    }

    localize();

    const defaultMode = document.getElementById('defaultMode');
    const siteMode = document.getElementById('siteMode');
    const matchSubdomains = document.getElementById('matchSubdomains');
    const currentHostnameEl = document.getElementById('currentHostname');
    const openOptions = document.getElementById('openOptions');
    const sitePanel = document.getElementById('sitePanel');

    let settings = null;
    let currentHostname = '';

    const versionEl = document.getElementById('version');
    if (versionEl && chrome.runtime.getManifest) {
        versionEl.textContent = 'v' + chrome.runtime.getManifest().version;
    }

    loadSettings((loaded) => {
        settings = loaded;
        defaultMode.value = settings.defaultMode;

        chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
            const tab = tabs[0];
            if (!tab || !tab.url) {
                sitePanel.classList.add('hidden');
                return;
            }

            const isNormalPage = tab.url.startsWith('http://') || tab.url.startsWith('https://');
            if (!isNormalPage) {
                sitePanel.classList.add('hidden');
                return;
            }

            try {
                currentHostname = normalizePattern(new URL(tab.url).hostname);
                currentHostnameEl.textContent = currentHostname;
                chrome.action.getBadgeText({ tabId: tab.id }, (text) => {
                    if (text) {
                        const activeBanner = document.getElementById('activeBanner');
                        if (activeBanner) {
                            activeBanner.classList.remove('hidden');
                            updateActiveBanner(resolveEffectiveMode(currentHostname, settings));
                        }
                    }
                });
                renderSiteRule();
            } catch (e) {
                sitePanel.classList.add('hidden');
            }
        });
    });

    defaultMode.addEventListener('change', () => {
        settings.defaultMode = defaultMode.value;
        saveSettings(settings, () => {
            renderSiteRule();
            notifyActiveTab();
        });
    });

    siteMode.addEventListener('change', () => {
        if (!currentHostname) return;
        setRuleForCurrentSite(siteMode.value);
    });

    matchSubdomains.addEventListener('change', () => {
        if (!currentHostname) return;
        const rule = resolveRule(currentHostname, settings, true);
        if (!rule) return;
        rule.matchSubdomains = matchSubdomains.checked;
        saveSettings(settings, () => {
            renderSiteRule();
            notifyActiveTab();
        });
    });

    openOptions.addEventListener('click', () => {
        chrome.runtime.openOptionsPage();
    });

    function renderSiteRule() {
        const rule = resolveRule(currentHostname, settings, true);
        siteMode.value = rule ? rule.mode : 'inherit';
        matchSubdomains.checked = rule ? rule.matchSubdomains !== false : true;
        matchSubdomains.disabled = !rule;

        const activeBanner = document.getElementById('activeBanner');
        if (activeBanner && !activeBanner.classList.contains('hidden')) {
            updateActiveBanner(resolveEffectiveMode(currentHostname, settings));
        }
    }

    function setRuleForCurrentSite(mode) {
        const exactRule = settings.siteRules.find((rule) => rule.pattern === currentHostname);
        if (mode === 'inherit') {
            if (exactRule) {
                settings.siteRules = settings.siteRules.filter((rule) => rule.pattern !== currentHostname);
            }
            matchSubdomains.disabled = true;
            matchSubdomains.checked = true;
            saveSettings(settings, () => {
                renderSiteRule();
                notifyActiveTab();
            });
            return;
        }

        if (exactRule) {
            exactRule.mode = mode;
            exactRule.enabled = true;
        } else {
            settings.siteRules.push({
                id: createId(),
                pattern: currentHostname,
                mode,
                enabled: true,
                matchSubdomains: matchSubdomains.checked
            });
        }
        matchSubdomains.disabled = false;
        saveSettings(settings, () => {
            renderSiteRule();
            notifyActiveTab();
        });
    }
});

function localize() {
    I18n.applyToDOM(document);
}

function resolveEffectiveMode(hostname, settings) {
    const rule = resolveRule(hostname, settings, false);
    if (rule && rule.mode !== 'inherit') {
        return rule.mode;
    }
    return settings.defaultMode;
}

function updateActiveBanner(mode) {
    const activeBannerText = document.getElementById('activeBannerText');
    if (!activeBannerText) {
        return;
    }

    const prefix = I18n.getMessage('activeBannerText') || 'Current page mode';
    activeBannerText.textContent = `${prefix}: ${modeLabel(mode)}`;
}

function modeLabel(mode) {
    const key = {
        inherit: 'useDefault',
        followSystem: 'followSystem',
        preserveSite: 'preserveSite',
        forceDark: 'forceDark',
        forceLight: 'forceLight'
    }[mode] || 'followSystem';

    return I18n.getMessage(key) || mode || 'followSystem';
}

function loadSettings(callback) {
    chrome.storage.sync.get([
        SETTINGS_KEY,
        'lightForceEnabled',
        'runMode',
        'siteList'
    ], (result) => {
        const existing = result[SETTINGS_KEY];
        if (existing && existing.version === SETTINGS_VERSION) {
            callback(normalizeSettings(existing));
            return;
        }

        const migrated = migrateLegacySettings(result);
        chrome.storage.sync.set({ [SETTINGS_KEY]: migrated }, () => callback(migrated));
    });
}

function saveSettings(nextSettings, callback) {
    const normalized = normalizeSettings(nextSettings);
    // Update the outer settings reference so subsequent reads see the latest state
    settings = normalized;
    chrome.storage.sync.set({ [SETTINGS_KEY]: normalized }, () => {
        if (chrome.runtime.lastError) {
            console.error('[DarkLight] saveSettings error:', chrome.runtime.lastError.message);
        }
        if (typeof callback === 'function') callback();
    });
}

function migrateLegacySettings(result) {
    const legacyEnabled = result.lightForceEnabled !== false;
    const siteList = Array.isArray(result.siteList) ? result.siteList : [];
    const runMode = result.runMode || 'inclusion';
    const siteRules = [];

    if (legacyEnabled && runMode === 'inclusion') {
        siteList.forEach((site) => {
            const pattern = normalizePattern(site);
            if (!pattern) return;
            siteRules.push({
                id: createId(),
                pattern,
                mode: 'forceLight',
                enabled: true,
                matchSubdomains: true
            });
        });
    }

    return normalizeSettings({
        version: SETTINGS_VERSION,
        defaultMode: legacyEnabled && runMode !== 'inclusion' ? 'forceLight' : 'followSystem',
        siteRules
    });
}

function normalizeSettings(settings) {
    return {
        version: SETTINGS_VERSION,
        defaultMode: VALID_DEFAULT_MODES.includes(settings.defaultMode) ? settings.defaultMode : 'followSystem',
        siteRules: Array.isArray(settings.siteRules)
            ? settings.siteRules
                .map((rule) => ({
                    id: rule.id || createId(),
                    pattern: normalizePattern(rule.pattern),
                    mode: VALID_RULE_MODES.includes(rule.mode) ? rule.mode : 'followSystem',
                    enabled: rule.enabled !== false,
                    matchSubdomains: rule.matchSubdomains !== false
                }))
                .filter((rule) => rule.pattern)
            : []
    };
}

function resolveRule(hostname, settings, includeDisabled) {
    const matches = settings.siteRules.filter((rule) => {
        if (!includeDisabled && !rule.enabled) return false;
        if (hostname === rule.pattern) return true;
        return rule.matchSubdomains && hostname.endsWith('.' + rule.pattern);
    });
    matches.sort((a, b) => b.pattern.length - a.pattern.length);
    return matches[0] || null;
}

function normalizePattern(pattern) {
    if (!pattern || typeof pattern !== 'string') return '';
    try {
        if (/^https?:\/\//i.test(pattern)) {
            return new URL(pattern).hostname.toLowerCase();
        }
    } catch (e) {
        return '';
    }
    return pattern
        .trim()
        .replace(/^\*\./, '')
        .replace(/^www\./, '')
        .replace(/\/.*$/, '')
        .toLowerCase();
}

function createId() {
    return String(Date.now()) + '-' + Math.random().toString(36).slice(2, 8);
}

function notifyActiveTab() {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
        if (tabs[0] && typeof tabs[0].id === 'number') {
            chrome.runtime.sendMessage({ action: 'clearBadgeState', tabId: tabs[0].id });
            chrome.tabs.sendMessage(tabs[0].id, { action: 'darkLightRefresh' }, () => {
                chrome.runtime.lastError;
            });
        }
    });
}
