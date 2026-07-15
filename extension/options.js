const SETTINGS_KEY = 'darkLightSettings';
const SETTINGS_VERSION = 2;
const VALID_DEFAULT_MODES = ['followSystem', 'preserveSite', 'forceDark', 'forceLight'];

let settings = null;
let editingRuleId = null;

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

chrome.storage.onChanged.addListener((changes, namespace) => {
  if (namespace !== 'sync' || !changes[SETTINGS_KEY]) return;
  settings = normalizeSettings(changes[SETTINGS_KEY].newValue);
  render();
});

function render() {
  renderModeOptions(document.getElementById('defaultMode'), false);
  renderModeOptions(document.getElementById('ruleMode'), true);
  document.getElementById('defaultMode').value = settings.defaultMode;
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
