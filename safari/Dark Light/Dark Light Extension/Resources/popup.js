const SETTINGS_KEY = 'darkLightSettings';
const ENTITLEMENTS_KEY = 'darkLightEntitlements';
const SETTINGS_VERSION = 2;
const FREE_RULE_LIMIT = 5;
const VALID_DEFAULT_MODES = ['followSystem', 'preserveSite', 'forceDark', 'forceLight'];
const PREMIUM_AUTO_REFRESH_INTERVAL_MS = 2000;
const PREMIUM_AUTO_REFRESH_TIMEOUT_MS = 120000;
let currentEntitlements = { supportsPro: false, isPro: true, iCloudSyncEnabled: false };

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
            renderModeOptions(defaultMode, false);
            renderModeOptions(siteMode, true);
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
    const buyPremium = document.getElementById('buyPremium');
    const sitePanel = document.getElementById('sitePanel');
    const premiumPanel = document.getElementById('premiumPanel');

    let settings = null;
    let entitlements = { supportsPro: false, isPro: true, iCloudSyncEnabled: false };
    let currentHostname = '';
    let premiumAutoRefreshTimer = null;
    let premiumAutoRefreshStartedAt = 0;

    const versionEl = document.getElementById('version');
    if (versionEl && chrome.runtime.getManifest) {
        versionEl.textContent = 'v' + chrome.runtime.getManifest().version;
    }

    loadEntitlements((loadedEntitlements) => {
        entitlements = loadedEntitlements;
        currentEntitlements = entitlements;
        renderPremiumPanel();
        renderModeOptions(defaultMode, false);
        renderModeOptions(siteMode, true);
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

    buyPremium.addEventListener('click', openPremium);

    document.addEventListener('visibilitychange', () => {
        if (!document.hidden) {
            refreshEntitlements();
        }
    });
    window.addEventListener('focus', refreshEntitlements);
    chrome.storage.onChanged.addListener((changes, namespace) => {
        if (namespace !== 'local' || !changes[ENTITLEMENTS_KEY]) return;
        entitlements = normalizeEntitlements(changes[ENTITLEMENTS_KEY].newValue);
        currentEntitlements = entitlements;
        renderPremiumPanel();
        renderModeOptions(defaultMode, false);
        renderModeOptions(siteMode, true);
        if (settings) {
            settings = normalizeSettings(settings);
            defaultMode.value = settings.defaultMode;
            renderSiteRule();
        }
    });

    function renderPremiumPanel() {
        premiumPanel.classList.toggle('hidden', !requiresProUpgrade(entitlements));
    }

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
            if (requiresProUpgrade(entitlements) && settings.siteRules.length >= FREE_RULE_LIMIT) {
                siteMode.value = 'inherit';
                openPremium();
                return;
            }
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

    function openPremium() {
        chrome.runtime.sendMessage({ action: 'openPremium' }, (response) => {
            if (chrome.runtime.lastError || response?.ok !== true) {
                alert(I18n.getMessage('openPremiumFailed') || 'Open Dark Light and buy Premium to unlock this feature.');
                return;
            }
            startPremiumAutoRefresh();
        });
    }

    function refreshEntitlements() {
        loadEntitlements((loadedEntitlements) => {
            entitlements = loadedEntitlements;
            currentEntitlements = entitlements;
            renderPremiumPanel();
            renderModeOptions(defaultMode, false);
            renderModeOptions(siteMode, true);
            if (settings) {
                settings = normalizeSettings(settings);
                defaultMode.value = settings.defaultMode;
                renderSiteRule();
            }
            if (entitlements.isPro) {
                stopPremiumAutoRefresh();
            }
        });
    }

    function startPremiumAutoRefresh() {
        if (premiumAutoRefreshTimer) {
            return;
        }
        premiumAutoRefreshStartedAt = Date.now();
        premiumAutoRefreshTimer = setInterval(() => {
            if (Date.now() - premiumAutoRefreshStartedAt > PREMIUM_AUTO_REFRESH_TIMEOUT_MS) {
                stopPremiumAutoRefresh();
                return;
            }
            refreshEntitlements();
        }, PREMIUM_AUTO_REFRESH_INTERVAL_MS);
        refreshEntitlements();
    }

    function stopPremiumAutoRefresh() {
        if (!premiumAutoRefreshTimer) {
            return;
        }
        clearInterval(premiumAutoRefreshTimer);
        premiumAutoRefreshTimer = null;
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

function loadEntitlements(callback) {
    chrome.runtime.sendMessage({ action: 'refreshProState' }, (response) => {
        if (chrome.runtime.lastError) {
            chrome.storage.local.get([ENTITLEMENTS_KEY], (result) => {
                callback(normalizeEntitlements(result[ENTITLEMENTS_KEY]));
            });
            return;
        }
        callback(normalizeEntitlements(response));
    });
}

function normalizeEntitlements(entitlements) {
    return {
        supportsPro: entitlements?.supportsPro === true,
        isPro: entitlements?.supportsPro === true ? entitlements?.isPro === true : true,
        iCloudSyncEnabled: entitlements?.iCloudSyncEnabled === true
    };
}

function requiresProUpgrade(entitlements) {
    return entitlements.supportsPro && !entitlements.isPro;
}

function allowedDefaultModes(entitlements) {
    return VALID_DEFAULT_MODES;
}

function allowedRuleModes(entitlements) {
    return ['inherit', ...allowedDefaultModes(entitlements)];
}

function renderModeOptions(select, includeInherit) {
    const currentValue = select.value;
    const modes = includeInherit ? allowedRuleModes(currentEntitlements) : allowedDefaultModes(currentEntitlements);
    select.innerHTML = '';
    modes.forEach((mode) => {
        const option = document.createElement('option');
        option.value = mode;
        option.textContent = modeLabel(mode);
        select.appendChild(option);
    });
    select.value = modes.includes(currentValue) ? currentValue : modes[0];
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
    const validDefaultModes = allowedDefaultModes(currentEntitlements);
    const validRuleModes = allowedRuleModes(currentEntitlements);
    return {
        version: SETTINGS_VERSION,
        defaultMode: validDefaultModes.includes(settings.defaultMode) ? settings.defaultMode : 'followSystem',
        siteRules: Array.isArray(settings.siteRules)
            ? settings.siteRules
                .map((rule) => ({
                    id: rule.id || createId(),
                    pattern: normalizePattern(rule.pattern),
                    mode: validRuleModes.includes(rule.mode) ? rule.mode : 'followSystem',
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
