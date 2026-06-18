const SETTINGS_KEY = 'darkLightSettings';
const SETTINGS_VERSION = 2;
const VALID_DEFAULT_MODES = ['followSystem', 'preserveSite', 'forceDark', 'forceLight'];
const VALID_RULE_MODES = [...VALID_DEFAULT_MODES, 'inherit'];

let settings = null;
let editingRuleId = null;

document.addEventListener('DOMContentLoaded', () => {
  localize();
  loadSettings((loaded) => {
    settings = loaded;
    bindEvents();
    render();
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
}

function render() {
  document.getElementById('defaultMode').value = settings.defaultMode;
  const ruleList = document.getElementById('ruleList');
  ruleList.innerHTML = '';

  if (settings.siteRules.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = chrome.i18n.getMessage('emptyRules') || 'No site rules yet';
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
        rule.matchSubdomains ? chrome.i18n.getMessage('matchSubdomains') : chrome.i18n.getMessage('exactDomainOnly'),
        rule.enabled ? chrome.i18n.getMessage('enabled') : chrome.i18n.getMessage('disabled')
      ].filter(Boolean).join(' / ');

      const actions = document.createElement('div');
      actions.className = 'rule-actions';

      const toggleBtn = document.createElement('button');
      toggleBtn.textContent = rule.enabled ? chrome.i18n.getMessage('disable') : chrome.i18n.getMessage('enable');
      toggleBtn.addEventListener('click', () => {
        rule.enabled = !rule.enabled;
        saveSettings(settings, render);
      });

      const editBtn = document.createElement('button');
      editBtn.textContent = chrome.i18n.getMessage('editSite') || 'Edit';
      editBtn.addEventListener('click', () => openRuleForm(rule));

      const deleteBtn = document.createElement('button');
      deleteBtn.className = 'delete';
      deleteBtn.textContent = chrome.i18n.getMessage('deleteSite') || 'Delete';
      deleteBtn.addEventListener('click', () => {
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

function openRuleForm(rule) {
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
  if (!pattern || !VALID_RULE_MODES.includes(mode)) return;

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

function modeLabel(mode) {
  const key = {
    inherit: 'useDefault',
    followSystem: 'followSystem',
    preserveSite: 'preserveSite',
    forceDark: 'forceDark',
    forceLight: 'forceLight'
  }[mode];
  return chrome.i18n.getMessage(key) || mode;
}

function localize() {
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.getAttribute('data-i18n');
    const message = chrome.i18n.getMessage(key);
    if (message) el.textContent = message;
  });

  document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
    const key = el.getAttribute('data-i18n-placeholder');
    const message = chrome.i18n.getMessage(key);
    if (message) el.placeholder = message;
  });
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
  return {
    version: SETTINGS_VERSION,
    defaultMode: VALID_DEFAULT_MODES.includes(nextSettings.defaultMode) ? nextSettings.defaultMode : 'followSystem',
    siteRules: Array.isArray(nextSettings.siteRules)
      ? nextSettings.siteRules
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
