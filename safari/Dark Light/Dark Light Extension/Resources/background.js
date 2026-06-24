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
  chrome.action.setBadgeTextColor({ color: '#ffffff', tabId });
}

chrome.runtime.onInstalled.addListener(setBadgeOff);
chrome.runtime.onStartup.addListener(setBadgeOff);
chrome.tabs.onActivated.addListener(({ tabId }) => {
  refreshTabAppearance(tabId);
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'dl_fetch') {
    fetch(message.url, { credentials: 'omit' })
      .then(res => res.text())
      .then(text => sendResponse({ text }))
      .catch(err => sendResponse({ error: err.message }));
    return true;
  }
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
});
