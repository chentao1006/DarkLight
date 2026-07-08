const SETTINGS_KEY = 'darkLightSettings';
const ENTITLEMENTS_KEY = 'darkLightEntitlements';
const SAFARI_NATIVE_APP_ID = 'com.ct106.darklight.Extension';

const SETTINGS_VERSION = 2;
const MODE_FOLLOW_SYSTEM = 'followSystem';
const MODE_FORCE_DARK = 'forceDark';
const MODE_FORCE_LIGHT = 'forceLight';
const MODE_PRESERVE_SITE = 'preserveSite';
const MODE_INHERIT = 'inherit';
const PREPAINT_SCRIPT_PREFIX = 'dark-light-prepaint-';
const FREE_RULE_LIMIT = 3;

const PREPAINT_CSS_BY_MODE = {
  [MODE_FORCE_LIGHT]: 'prepaint-force-light.css',
  [MODE_FORCE_DARK]: 'prepaint-force-dark.css',
  [MODE_PRESERVE_SITE]: 'prepaint-preserve.css',
  [MODE_FOLLOW_SYSTEM]: 'prepaint-follow-system.css'
};


function setBadgeOff() {
  chrome.action.setBadgeText({ text: '' });
}

function refreshTabAppearance(tabId) {
  if (typeof tabId !== 'number') return;

  chrome.tabs.sendMessage(tabId, { action: 'darkLightRefresh' }, () => {
    if (chrome.runtime.lastError) {
      // Ignore tabs without a live content script, such as browser internal pages.
    }
  });
}

function setBadgeState(tabId, appearance, mode) {
  const isForcedDark = mode === 'forceDark';
  const isForcedLight = mode === 'forceLight';
  const isFollowSystem = mode === 'followSystem';
  const isPreserveSite = mode === 'preserveSite';
  const text = isForcedDark ? '🌙' : isForcedLight ? '☀️' : isFollowSystem ? 'A' : isPreserveSite ? 'O' : '';
  const color = isForcedDark ? '#2f3a40' : isForcedLight ? '#0b5cff' : '#334155';

  chrome.action.setBadgeText({ text, tabId });
  chrome.action.setBadgeBackgroundColor({ color, tabId });
  // setBadgeTextColor is not supported in Firefox; guard with try/catch
  try {
    chrome.action.setBadgeTextColor({ color: '#ffffff', tabId });
  } catch (_) {
    // Firefox does not support setBadgeTextColor — silently ignore
  }
}

chrome.runtime.onInstalled.addListener(() => {
  setBadgeOff();
  syncPrepaintContentScripts();
});
chrome.runtime.onInstalled.addListener(refreshProStateAndSync);
chrome.runtime.onStartup.addListener(() => {
  setBadgeOff();
  syncPrepaintContentScripts();
});
chrome.runtime.onStartup.addListener(refreshProStateAndSync);
chrome.tabs.onActivated.addListener(({ tabId }) => {
  refreshTabAppearance(tabId);
});

chrome.storage.onChanged.addListener((changes, namespace) => {
  if (namespace === 'sync' && changes[SETTINGS_KEY]) {
    pushSettingsToICloud(changes[SETTINGS_KEY].newValue);
    syncPrepaintContentScripts(changes[SETTINGS_KEY].newValue);
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'setBadgeState') {
    const tabId = message.tabId ?? sender.tab?.id;
    if (typeof tabId === 'number') {
      setBadgeState(tabId, message.effectiveAppearance, message.mode);
    }
  }
  if (message.action === 'clearBadgeState') {
    const tabId = message.tabId ?? sender.tab?.id;
    if (typeof tabId === 'number') {
      chrome.action.setBadgeText({ text: '', tabId });
    } else {
      chrome.action.setBadgeText({ text: '' });
    }
  }

  if (message.action === 'getProState') {
    getStoredEntitlements((entitlements) => {
      if (!entitlements.checkedAt) {
        refreshProStateAndSync((refreshed) => sendResponse(refreshed));
        return;
      }
      sendResponse(entitlements);
    });
    return true;
  }

  if (message.action === 'refreshProState') {
    refreshProStateAndSync((entitlements) => sendResponse(entitlements));
    return true;
  }

  if (message.action === 'setICloudSyncEnabled') {
    sendNativeMessage({ action: 'setICloudSyncEnabled', enabled: message.enabled === true }, (response) => {
      storeEntitlementsFromNative(response, (entitlements) => {
        if (entitlements.isPro && entitlements.iCloudSyncEnabled) {
          pullSettingsFromICloud((cloudSettings) => {
            if (!cloudSettings) {
              chrome.storage.sync.get([SETTINGS_KEY], (result) => {
                pushSettingsToICloud(result[SETTINGS_KEY]);
                sendResponse(entitlements);
              });
              return;
            }
            sendResponse(entitlements);
          });
        } else {
          sendResponse(entitlements);
        }
      });
    });
    return true;
  }

  if (message.action === 'openPremium') {
    sendNativeMessage({ action: 'openPremium' }, (response) => {
      if (response?.ok === true) {
        sendResponse(response);
        return;
      }
      openPremiumDeepLinkFallback((fallbackResponse) => {
        sendResponse(fallbackResponse);
      });
    });
    return true;
  }
});

function openPremiumDeepLinkFallback(callback) {
  if (!chrome.tabs?.create) {
    callback?.({ ok: false, error: 'openPremiumFailed' });
    return;
  }

  chrome.tabs.create({ url: 'darklight://premium' }, () => {
    if (chrome.runtime.lastError) {
      callback?.({ ok: false, error: chrome.runtime.lastError.message });
      return;
    }
    callback?.({ ok: true, source: 'tabsCreate' });
  });
}

function defaultEntitlements() {
  return {
    supportsPro: false,
    isPro: true,
    iCloudSyncEnabled: false,
    source: 'local',
    checkedAt: 0
  };
}

function getStoredEntitlements(callback) {
  chrome.storage.local.get([ENTITLEMENTS_KEY], (result) => {
    callback({
      ...defaultEntitlements(),
      ...(result[ENTITLEMENTS_KEY] || {})
    });
  });
}

function setStoredEntitlements(entitlements, callback) {
  chrome.storage.local.set({ [ENTITLEMENTS_KEY]: entitlements }, () => {
    if (typeof callback === 'function') callback(entitlements);
  });
}

function storeEntitlementsFromNative(response, callback) {
  const entitlements = {
    supportsPro: response?.ok === true,
    isPro: response?.ok === true ? response?.isPro === true : true,
    iCloudSyncEnabled: response?.iCloudSyncEnabled === true,
    source: response?.ok ? 'native' : 'local',
    checkedAt: Date.now()
  };
  setStoredEntitlements(entitlements, callback);
}

function refreshProStateAndSync(callback) {
  sendNativeMessage({ action: 'getProState' }, (response) => {
    storeEntitlementsFromNative(response, (entitlements) => {
      if (entitlements.isPro && entitlements.iCloudSyncEnabled) {
        pullSettingsFromICloud(() => {
          if (typeof callback === 'function') callback(entitlements);
        });
        return;
      }
      if (typeof callback === 'function') callback(entitlements);
    });
  });
}

function pullSettingsFromICloud(callback) {
  sendNativeMessage({ action: 'getCloudSettings' }, (response) => {
    if (response?.ok && response.settings && typeof response.settings === 'object') {
      chrome.storage.sync.set({ [SETTINGS_KEY]: response.settings }, () => {
        if (typeof callback === 'function') callback(response.settings);
      });
      return;
    }
    if (typeof callback === 'function') callback(null);
  });
}

function pushSettingsToICloud(settings) {
  if (!settings || typeof settings !== 'object') return;

  getStoredEntitlements((entitlements) => {
    if (!entitlements.isPro || !entitlements.iCloudSyncEnabled) return;
    sendNativeMessage({ action: 'setCloudSettings', settings }, () => {});
  });
}

function sendNativeMessage(message, callback) {
  if (!chrome.runtime.sendNativeMessage) {
    callback?.({ ok: false, error: 'nativeMessagingUnavailable' });
    return;
  }

  try {
    chrome.runtime.sendNativeMessage(SAFARI_NATIVE_APP_ID, message, (response) => {
      if (chrome.runtime.lastError) {
        callback?.({ ok: false, error: chrome.runtime.lastError.message });
        return;
      }
      callback?.(response || { ok: false, error: 'emptyResponse' });
    });
  } catch (error) {
    callback?.({ ok: false, error: String(error) });
  }
}


function syncPrepaintContentScripts(settingsOverride) {
  if (!chrome.scripting?.getRegisteredContentScripts) return;

  const applySettings = (settings) => {
    getStoredEntitlements((entitlements) => {
      let finalSettings = normalizeSettings(settings);
      if (entitlements.supportsPro && !entitlements.isPro) {
        finalSettings.siteRules = finalSettings.siteRules.slice(0, FREE_RULE_LIMIT);
      }
      const scripts = buildPrepaintContentScripts(finalSettings);

      chrome.scripting.getRegisteredContentScripts({}, (registeredScripts) => {
        if (chrome.runtime.lastError) return;

        const registeredIds = (registeredScripts || [])
          .map((script) => script.id)
          .filter((id) => typeof id === 'string' && id.startsWith(PREPAINT_SCRIPT_PREFIX));

        const registerNext = () => {
          if (scripts.length === 0) return;
          chrome.scripting.registerContentScripts(scripts, () => {});
        };

        if (registeredIds.length === 0) {
          registerNext();
          return;
        }

        chrome.scripting.unregisterContentScripts({ ids: registeredIds }, () => {
          if (chrome.runtime.lastError) return;
          registerNext();
        });
      });
    });
  };

  if (settingsOverride) {
    applySettings(settingsOverride);
    return;
  }
  loadSettings(applySettings);
}

function buildPrepaintContentScripts(settings) {
  const rules = settings.siteRules.filter((rule) => rule.enabled && PREPAINT_CSS_BY_MODE[rule.mode]);
  const usedIds = new Set();
  return rules.map((rule, index) => {
    const matches = matchPatternsForRule(rule);
    if (matches.length === 0) return null;
    const excludeMatches = unique(rules.filter((other) => other !== rule && isMoreSpecificCoveredRule(rule, other)).flatMap(matchPatternsForRule));
    const script = {
      id: createPrepaintScriptId(rule, index, usedIds),
      matches,
      css: [PREPAINT_CSS_BY_MODE[rule.mode]],
      runAt: 'document_start',
      allFrames: true,
      persistAcrossSessions: true
    };
    if (excludeMatches.length > 0) script.excludeMatches = excludeMatches;
    return script;
  }).filter(Boolean);
}

function createPrepaintScriptId(rule, index, usedIds) {
  const rawId = rule.id || rule.pattern || String(index);
  const safeId = rawId.toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '') || String(index);
  let scriptId = PREPAINT_SCRIPT_PREFIX + safeId;
  if (!usedIds.has(scriptId)) {
    usedIds.add(scriptId);
    return scriptId;
  }
  scriptId = `${scriptId}-${index}`;
  usedIds.add(scriptId);
  return scriptId;
}

function matchPatternsForRule(rule) {
  const host = normalizePattern(rule.pattern);
  if (!host) return [];
  const patterns = [`*://${host}/*`];
  if (rule.matchSubdomains !== false && host !== 'localhost' && !isIPAddress(host)) {
    patterns.push(`*://*.${host}/*`);
  }
  return patterns;
}

function isMoreSpecificCoveredRule(parentRule, childRule) {
  if (!parentRule.matchSubdomains) return false;
  if (childRule.pattern.length <= parentRule.pattern.length) return false;
  return childRule.pattern.endsWith('.' + parentRule.pattern);
}

function isIPAddress(host) {
  return /^\d{1,3}(?:\.\d{1,3}){3}$/.test(host) || host.includes(':');
}

function unique(items) {
  return [...new Set(items)];
}

function loadSettings(callback) {
  chrome.storage.sync.get([SETTINGS_KEY, 'lightForceEnabled', 'runMode', 'siteList'], (result) => {
    const existing = result[SETTINGS_KEY];
    if (existing && existing.version === SETTINGS_VERSION) {
      callback(normalizeSettings(existing));
      return;
    }
    const migrated = migrateLegacySettings(result);
    chrome.storage.sync.set({ [SETTINGS_KEY]: migrated }, () => callback(migrated));
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
        id: String(Date.now() + Math.random()),
        pattern,
        mode: MODE_FORCE_LIGHT,
        enabled: true,
        matchSubdomains: true
      });
    });
  }
  return normalizeSettings({
    version: SETTINGS_VERSION,
    defaultMode: legacyEnabled && runMode !== 'inclusion' ? MODE_FORCE_LIGHT : MODE_FOLLOW_SYSTEM,
    siteRules
  });
}

function normalizeSettings(settings) {
  const validDefaultModes = [MODE_FOLLOW_SYSTEM, MODE_FORCE_DARK, MODE_FORCE_LIGHT, MODE_PRESERVE_SITE];
  const validRuleModes = [...validDefaultModes, MODE_INHERIT];
  const normalized = {
    version: SETTINGS_VERSION,
    defaultMode: validDefaultModes.includes(settings?.defaultMode) ? settings.defaultMode : MODE_FOLLOW_SYSTEM,
    siteRules: []
  };
  if (Array.isArray(settings?.siteRules)) {
    normalized.siteRules = settings.siteRules.map((rule) => ({
      id: rule.id || String(Date.now() + Math.random()),
      pattern: normalizePattern(rule.pattern),
      mode: validRuleModes.includes(rule.mode) ? rule.mode : MODE_FOLLOW_SYSTEM,
      enabled: rule.enabled !== false,
      matchSubdomains: rule.matchSubdomains !== false
    })).filter((rule) => rule.pattern);
  }
  return normalized;
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
  return pattern.trim().replace(/^\*\./, '').replace(/^www\./, '').replace(/\/.*$/, '').toLowerCase();
}
