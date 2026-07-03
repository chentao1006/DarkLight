const SETTINGS_KEY = 'darkLightSettings';
const ENTITLEMENTS_KEY = 'darkLightEntitlements';
const SAFARI_NATIVE_APP_ID = 'com.ct106.darklight.Extension';

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
  const text = isForcedDark ? '🌙' : isForcedLight ? '☀️' : isFollowSystem ? 'A' : '';
  const color = isForcedDark ? '#2f3a40' : isForcedLight ? '#0f766e' : '#334155';

  chrome.action.setBadgeText({ text, tabId });
  chrome.action.setBadgeBackgroundColor({ color, tabId });
  // setBadgeTextColor is not supported in Firefox; guard with try/catch
  try {
    chrome.action.setBadgeTextColor({ color: '#ffffff', tabId });
  } catch (_) {
    // Firefox does not support setBadgeTextColor — silently ignore
  }
}

chrome.runtime.onInstalled.addListener(setBadgeOff);
chrome.runtime.onInstalled.addListener(refreshProStateAndSync);
chrome.runtime.onStartup.addListener(setBadgeOff);
chrome.runtime.onStartup.addListener(refreshProStateAndSync);
chrome.tabs.onActivated.addListener(({ tabId }) => {
  refreshTabAppearance(tabId);
});

chrome.storage.onChanged.addListener((changes, namespace) => {
  if (namespace === 'sync' && changes[SETTINGS_KEY]) {
    pushSettingsToICloud(changes[SETTINGS_KEY].newValue);
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'setBadgeState' && typeof sender.tab?.id === 'number') {
    setBadgeState(sender.tab.id, message.effectiveAppearance, message.mode);
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
      sendResponse(response || { ok: false, error: 'emptyResponse' });
    });
    return true;
  }
});

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
