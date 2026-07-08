const SETTINGS_KEY = 'darkLightSettings';
const ENTITLEMENTS_KEY = 'darkLightEntitlements';
const SETTINGS_VERSION = 2;
const FREE_RULE_LIMIT = 3;
const VALID_DEFAULT_MODES = ['followSystem', 'preserveSite', 'forceDark', 'forceLight'];
const PREMIUM_AUTO_REFRESH_INTERVAL_MS = 2000;
const PREMIUM_AUTO_REFRESH_TIMEOUT_MS = 120000;

let settings = null;
let editingRuleId = null;
let entitlements = { supportsPro: false, isPro: true, iCloudSyncEnabled: false };
let premiumAutoRefreshTimer = null;
let premiumAutoRefreshStartedAt = 0;
let premiumOpenInFlight = false;

document.addEventListener('DOMContentLoaded', async () => {
  await I18n.init();

  const extLangSwitcher = document.getElementById('extLangSwitcher');
  if (extLangSwitcher) {
    extLangSwitcher.value = I18n.currentLang;
    extLangSwitcher.addEventListener('change', async (e) => {
      await new Promise(resolve => chrome.storage.local.set({ userLanguage: e.target.value }, resolve));
      await I18n.init();
      localize();
      render();
    });
  }

  localize();
  loadEntitlements((loadedEntitlements) => {
    entitlements = loadedEntitlements;
    loadSettings((loaded) => {
      settings = loaded;
      bindEvents();
      bindEntitlementRefreshEvents();
      render();
    });
  });
});

function bindEvents() {
  document.getElementById('defaultMode').addEventListener('change', (event) => {
    settings.defaultMode = event.target.value;
    saveSettings(settings, render);
  });

  document.getElementById('addRule').addEventListener('click', () => openRuleForm());
  document.getElementById('cancelRule').addEventListener('click', closeRuleForm);
  document.getElementById('saveRule').addEventListener('click', saveRuleFromForm);
  document.getElementById('buyPremium').addEventListener('click', openPremium);
  document.getElementById('iCloudSync').addEventListener('change', toggleICloudSync);
  document.getElementById('exportRules').addEventListener('click', exportRules);
  document.getElementById('importRules').addEventListener('click', () => {
    if (requiresProUpgrade()) {
      showProRequired();
      return;
    }
    document.getElementById('importFile').click();
  });
  document.getElementById('importFile').addEventListener('change', importRules);
}

function bindEntitlementRefreshEvents() {
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) {
      refreshEntitlements();
    }
  });
  window.addEventListener('focus', refreshEntitlements);
  chrome.storage.onChanged.addListener((changes, namespace) => {
    if (namespace !== 'local' || !changes[ENTITLEMENTS_KEY]) return;
    entitlements = normalizeEntitlements(changes[ENTITLEMENTS_KEY].newValue);
    render();
  });
}

function render() {
  renderModeOptions(document.getElementById('defaultMode'), false);
  renderModeOptions(document.getElementById('ruleMode'), true);
  document.getElementById('defaultMode').value = settings.defaultMode;
  renderProControls();
  const ruleList = document.getElementById('ruleList');
  ruleList.innerHTML = '';

  if (settings.siteRules.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = I18n.getMessage('emptyRules') || 'No site rules yet';
    ruleList.appendChild(empty);
    return;
  }

  settings.siteRules
    .slice()
    .sort((a, b) => a.pattern.localeCompare(b.pattern))
    .forEach((rule) => {
      const row = document.createElement('div');
      row.className = 'rule-row';

      const main = document.createElement('div');
      main.className = 'rule-main';

      const pattern = document.createElement('div');
      pattern.className = 'rule-pattern';
      pattern.textContent = rule.pattern;

      const meta = document.createElement('div');
      meta.className = 'rule-meta';
      meta.textContent = [
        modeLabel(rule.mode),
        rule.matchSubdomains ? I18n.getMessage('matchSubdomains') : I18n.getMessage('exactDomainOnly'),
        rule.enabled ? I18n.getMessage('enabled') : I18n.getMessage('disabled')
      ].filter(Boolean).join(' / ');

      const actions = document.createElement('div');
      actions.className = 'rule-actions';

      const toggleBtn = document.createElement('button');
      toggleBtn.textContent = rule.enabled ? I18n.getMessage('disable') : I18n.getMessage('enable');
      toggleBtn.addEventListener('click', () => {
        rule.enabled = !rule.enabled;
        saveSettings(settings, render);
      });

      const editBtn = document.createElement('button');
      editBtn.textContent = I18n.getMessage('editSite') || 'Edit';
      editBtn.addEventListener('click', () => openRuleForm(rule));

      const deleteBtn = document.createElement('button');
      deleteBtn.className = 'delete';
      deleteBtn.textContent = I18n.getMessage('deleteSite') || 'Delete';
      deleteBtn.addEventListener('click', () => {
        if (!confirmDeleteRule(rule)) return;
        settings.siteRules = settings.siteRules.filter((item) => item.id !== rule.id);
        saveSettings(settings, render);
      });

      main.appendChild(pattern);
      main.appendChild(meta);
      actions.appendChild(toggleBtn);
      actions.appendChild(editBtn);
      actions.appendChild(deleteBtn);
      row.appendChild(main);
      row.appendChild(actions);
      ruleList.appendChild(row);
    });
}

function confirmDeleteRule(rule) {
  const fallback = `Delete rule for ${rule.pattern}?`;
  const message = (I18n.getMessage('deleteRuleConfirm') || fallback).replace('{site}', rule.pattern);
  return window.confirm(message);
}

function openRuleForm(rule) {
  if (!rule && requiresProUpgrade() && settings.siteRules.length >= FREE_RULE_LIMIT) {
    showProRequired();
    return;
  }

  editingRuleId = rule ? rule.id : null;
  document.getElementById('rulePattern').value = rule ? rule.pattern : '';
  document.getElementById('ruleMode').value = rule ? rule.mode : 'forceDark';
  document.getElementById('ruleSubdomains').checked = rule ? rule.matchSubdomains !== false : true;
  document.getElementById('ruleForm').classList.remove('hidden');
  document.getElementById('rulePattern').focus();
}

function closeRuleForm() {
  editingRuleId = null;
  document.getElementById('ruleForm').classList.add('hidden');
}

function saveRuleFromForm() {
  const pattern = normalizePattern(document.getElementById('rulePattern').value);
  const mode = document.getElementById('ruleMode').value;
  const matchSubdomains = document.getElementById('ruleSubdomains').checked;
  if (!pattern || !allowedRuleModes().includes(mode)) return;

  const duplicate = settings.siteRules.find((rule) => rule.pattern === pattern && rule.id !== editingRuleId);
  if (duplicate) {
    duplicate.mode = mode;
    duplicate.enabled = true;
    duplicate.matchSubdomains = matchSubdomains;
    settings.siteRules = settings.siteRules.filter((rule) => rule.id !== editingRuleId);
  } else if (editingRuleId) {
    const rule = settings.siteRules.find((item) => item.id === editingRuleId);
    if (rule) {
      rule.pattern = pattern;
      rule.mode = mode;
      rule.matchSubdomains = matchSubdomains;
    }
  } else {
    if (requiresProUpgrade() && settings.siteRules.length >= FREE_RULE_LIMIT) {
      showProRequired();
      return;
    }
    settings.siteRules.push({
      id: createId(),
      pattern,
      mode,
      enabled: true,
      matchSubdomains
    });
  }

  closeRuleForm();
  saveSettings(settings, render);
}

function renderProControls() {
  const proStatus = document.getElementById('proStatus');
  const addRule = document.getElementById('addRule');
  const iCloudSync = document.getElementById('iCloudSync');
  const exportRulesButton = document.getElementById('exportRules');
  const importRulesButton = document.getElementById('importRules');
  const buyPremiumButton = document.getElementById('buyPremium');

  document.querySelector('.pro-section').classList.toggle('hidden', !entitlements.supportsPro);

  if (entitlements.isPro) {
    proStatus.textContent = entitlements.iCloudSyncEnabled
      ? I18n.getMessage('proStatusICloudOn') || 'Premium unlocked. iCloud sync is on.'
      : I18n.getMessage('proStatusICloudOff') || 'Premium unlocked. iCloud sync is off.';
  } else {
    proStatus.textContent = I18n.getMessage('proStatusLocked') || `Free version supports up to ${FREE_RULE_LIMIT} site rules. Buy Premium in the Dark Light app to unlock unlimited rules, import/export, and iCloud sync.`;
  }

  iCloudSync.checked = entitlements.iCloudSyncEnabled;
  iCloudSync.disabled = !entitlements.isPro;
  buyPremiumButton.classList.toggle('hidden', entitlements.isPro);
  exportRulesButton.disabled = requiresProUpgrade();
  importRulesButton.disabled = requiresProUpgrade();
  addRule.disabled = false;
}

function refreshEntitlements() {
  loadEntitlements((loadedEntitlements) => {
    entitlements = loadedEntitlements;
    render();
    if (entitlements.isPro) {
      stopPremiumAutoRefresh();
    }
  });
}

function toggleICloudSync(event) {
  if (requiresProUpgrade()) {
    event.target.checked = false;
    showProRequired();
    return;
  }

  chrome.runtime.sendMessage({ action: 'setICloudSyncEnabled', enabled: event.target.checked }, (response) => {
    if (chrome.runtime.lastError) {
      event.target.checked = entitlements.iCloudSyncEnabled;
      return;
    }
    entitlements = normalizeEntitlements(response);
    renderProControls();
  });
}

function exportRules() {
  if (requiresProUpgrade()) {
    showProRequired();
    return;
  }

  const payload = {
    exportedAt: new Date().toISOString(),
    app: 'Dark Light',
    settings: normalizeSettings(settings)
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = 'dark-light-rules.json';
  anchor.click();
  URL.revokeObjectURL(url);
}

function importRules(event) {
  if (requiresProUpgrade()) {
    showProRequired();
    event.target.value = '';
    return;
  }

  const file = event.target.files?.[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = () => {
    try {
      const payload = JSON.parse(String(reader.result || '{}'));
      const imported = payload.settings || payload;
      settings = normalizeSettings(imported);
      saveSettings(settings, render);
    } catch (error) {
      alert(I18n.getMessage('importFailed') || 'Import failed. Please choose a valid Dark Light JSON file.');
    } finally {
      event.target.value = '';
    }
  };
  reader.readAsText(file);
}

function showProRequired() {
  openPremium();
}

function openPremium() {
  if (premiumOpenInFlight) return;
  premiumOpenInFlight = true;
  startPremiumAutoRefresh();
  chrome.runtime.sendMessage({ action: 'openPremium' }, (response) => {
    premiumOpenInFlight = false;
  });
  setTimeout(() => {
    premiumOpenInFlight = false;
  }, 2000);
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

function modeLabel(mode) {
  const key = {
    inherit: 'useDefault',
    followSystem: 'followSystem',
    preserveSite: 'preserveSite',
    forceDark: 'forceDark',
    forceLight: 'forceLight'
  }[mode];
  return I18n.getMessage(key) || mode;
}

function renderModeOptions(select, includeInherit) {
  const currentValue = select.value;
  const modes = includeInherit ? ['inherit', ...allowedDefaultModes()] : allowedDefaultModes();
  select.innerHTML = '';
  modes.forEach((mode) => {
    const option = document.createElement('option');
    option.value = mode;
    option.textContent = modeLabel(mode);
    select.appendChild(option);
  });
  select.value = modes.includes(currentValue) ? currentValue : modes[0];
}

function localize() {
  I18n.applyToDOM(document);

  document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
    const key = el.getAttribute('data-i18n-placeholder');
    const message = I18n.getMessage(key);
    if (message) el.placeholder = message;
  });

  const appName = I18n.getMessage('appName') || 'Dark Light';
  const manageRules = I18n.getMessage('manageRules') || 'Options';
  document.title = `${appName} - ${manageRules}`;
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

function normalizeEntitlements(nextEntitlements) {
  return {
    supportsPro: nextEntitlements?.supportsPro === true,
    isPro: nextEntitlements?.supportsPro === true ? nextEntitlements?.isPro === true : true,
    iCloudSyncEnabled: nextEntitlements?.iCloudSyncEnabled === true
  };
}

function requiresProUpgrade() {
  return entitlements.supportsPro && !entitlements.isPro;
}

function allowedDefaultModes() {
  return VALID_DEFAULT_MODES;
}

function allowedRuleModes() {
  return ['inherit', ...allowedDefaultModes()];
}

function saveSettings(nextSettings, callback) {
  settings = normalizeSettings(nextSettings);
  chrome.storage.sync.set({ [SETTINGS_KEY]: settings }, callback);
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

function normalizeSettings(nextSettings) {
  const validDefaultModes = allowedDefaultModes();
  const validRuleModes = allowedRuleModes();
  return {
    version: SETTINGS_VERSION,
    defaultMode: validDefaultModes.includes(nextSettings.defaultMode) ? nextSettings.defaultMode : 'followSystem',
    siteRules: Array.isArray(nextSettings.siteRules)
      ? nextSettings.siteRules
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
