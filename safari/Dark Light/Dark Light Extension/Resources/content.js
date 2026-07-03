// Dark Light - per-site appearance controller.
// The runtime resolves a configured mode first, then applies a light or dark
// strategy to the current page. Chrome and Safari wrappers can keep this file
// as the shared content engine.

const SETTINGS_KEY = 'darkLightSettings';
const ENTITLEMENTS_KEY = 'darkLightEntitlements';
const SETTINGS_VERSION = 2;
const FREE_RULE_LIMIT = 5;
const MODE_FOLLOW_SYSTEM = 'followSystem';
const MODE_FORCE_DARK = 'forceDark';
const MODE_FORCE_LIGHT = 'forceLight';
const MODE_PRESERVE_SITE = 'preserveSite';
const MODE_INHERIT = 'inherit';
const VALID_DEFAULT_MODES = [MODE_FOLLOW_SYSTEM, MODE_FORCE_DARK, MODE_FORCE_LIGHT, MODE_PRESERVE_SITE];

const MATCH_ATTRS = [
  'theme',
  'data-theme',
  'data-color-mode',
  'data-color-scheme',
  'data-mode',
  'data-appearance',
  'data-bs-theme'
];

const THEME_CLASSES = [
  'dark',
  'light',
  'dark-mode',
  'light-mode',
  'dark-theme',
  'light-theme',
  'theme-dark',
  'theme-light',
  'night',
  'day',
  'night-mode',
  'day-mode',
  'theme-system'
];

let currentSettings = null;
let currentEntitlements = { supportsPro: false, isPro: true, iCloudSyncEnabled: false };
let activeAppearance = null;
let themeObserver = null;
let appearanceRunId = 0;
let systemSchemeMediaQuery = null;
let systemSchemeChangeHandler = null;
const themeSnapshots = new WeakMap();

loadEntitlements((entitlements) => {
  currentEntitlements = entitlements;
  loadSettings((settings) => {
    applyResolvedSettings(settings);
  });
});
setupSystemAppearanceListener();

chrome.storage.onChanged.addListener((changes, namespace) => {
  if (namespace === 'sync' && changes[SETTINGS_KEY]) {
    applyResolvedSettings(normalizeSettings(changes[SETTINGS_KEY].newValue));
  }
  if (namespace === 'local' && changes[ENTITLEMENTS_KEY]) {
    currentEntitlements = normalizeEntitlements(changes[ENTITLEMENTS_KEY].newValue);
    if (currentSettings) {
      applyResolvedSettings(currentSettings);
    }
  }
});

chrome.runtime.onMessage.addListener((message) => {
  if (message.action === 'darkLightRefresh') {
    loadSettings((settings) => {
      applyResolvedSettings(settings);
    });
  }
});

let lastAppliedState = null;

function applyResolvedSettings(settings) {
  const normalized = normalizeSettings(settings);
  const hostname = window.location.hostname;
  const rule = resolveRule(hostname, normalized);
  const configuredMode = rule && rule.mode !== MODE_INHERIT ? rule.mode : normalized.defaultMode;
  const effectiveAppearance = resolveEffectiveAppearance(configuredMode);

  const stateString = JSON.stringify(normalized) + '|' + effectiveAppearance;
  if (lastAppliedState === stateString) {
    if (configuredMode === MODE_PRESERVE_SITE) {
      try {
        chrome.runtime.sendMessage({ action: 'clearBadgeState', source: rule ? 'siteRule' : 'default' });
      } catch (e) {}
    } else {
      try {
        chrome.runtime.sendMessage({ action: 'setBadgeState', mode: configuredMode, effectiveAppearance, source: rule ? 'siteRule' : 'default' });
      } catch (e) {}
    }
    return;
  }
  lastAppliedState = stateString;

  const runId = ++appearanceRunId;
  currentSettings = normalized;

  cleanupAppearanceOverrides();
  if (configuredMode === MODE_PRESERVE_SITE) {
    activeAppearance = null;
    try {
      chrome.runtime.sendMessage({
        action: 'clearBadgeState',
        source: rule ? 'siteRule' : 'default'
      });
    } catch (e) {}
    return;
  }

  activeAppearance = effectiveAppearance;

  try {
    chrome.runtime.sendMessage({
      action: 'setBadgeState',
      mode: configuredMode,
      effectiveAppearance,
      source: rule ? 'siteRule' : 'default'
    });
  } catch (e) {}

  if (effectiveAppearance === 'dark') {
    applyDarkLight(runId);
  } else {
    applyLightForce(runId);
  }
}

function isCurrentRun(runId) {
  return runId === appearanceRunId;
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

function migrateLegacySettings(result) {
  const legacyEnabled = result.lightForceEnabled !== false;
  const siteList = Array.isArray(result.siteList) ? result.siteList : [];
  const runMode = result.runMode || 'inclusion';
  const siteRules = [];

  if (legacyEnabled && runMode === 'inclusion') {
    siteList.forEach((site) => {
      siteRules.push(createRule(site, MODE_FORCE_LIGHT));
    });
  }

  return normalizeSettings({
    version: SETTINGS_VERSION,
    defaultMode: legacyEnabled && runMode !== 'inclusion' ? MODE_FORCE_LIGHT : MODE_FOLLOW_SYSTEM,
    siteRules
  });
}

function normalizeSettings(settings) {
  const validDefaultModes = allowedDefaultModes();
  const validRuleModes = allowedRuleModes();
  const normalized = {
    version: SETTINGS_VERSION,
    defaultMode: validDefaultModes.includes(settings.defaultMode) ? settings.defaultMode : MODE_FOLLOW_SYSTEM,
    siteRules: []
  };

  if (Array.isArray(settings.siteRules)) {
    normalized.siteRules = settings.siteRules
      .map((rule) => ({
        id: rule.id || String(Date.now() + Math.random()),
        pattern: normalizePattern(rule.pattern),
        mode: validRuleModes.includes(rule.mode) ? rule.mode : MODE_FOLLOW_SYSTEM,
        enabled: rule.enabled !== false,
        matchSubdomains: rule.matchSubdomains !== false
      }))
      .filter((rule) => rule.pattern);
  }

  if (currentEntitlements.supportsPro && !currentEntitlements.isPro) {
    normalized.siteRules = normalized.siteRules.slice(0, FREE_RULE_LIMIT);
  }

  return normalized;
}

function allowedDefaultModes() {
  return VALID_DEFAULT_MODES;
}

function allowedRuleModes() {
  return [...allowedDefaultModes(), MODE_INHERIT];
}

function requiresProUpgrade() {
  return currentEntitlements.supportsPro && !currentEntitlements.isPro;
}

function loadEntitlements(callback) {
  chrome.runtime.sendMessage({ action: 'getProState' }, (response) => {
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

function createRule(pattern, mode) {
  return {
    id: String(Date.now() + Math.random()),
    pattern: normalizePattern(pattern),
    mode,
    enabled: true,
    matchSubdomains: true
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

function resolveRule(hostname, settings) {
  const normalizedHost = normalizePattern(hostname);
  const matches = settings.siteRules.filter((rule) => {
    if (!rule.enabled) return false;
    if (normalizedHost === rule.pattern) return true;
    return rule.matchSubdomains && normalizedHost.endsWith('.' + rule.pattern);
  });

  matches.sort((a, b) => b.pattern.length - a.pattern.length);
  return matches[0] || null;
}

function resolveEffectiveAppearance(configuredMode) {
  if (configuredMode === MODE_FORCE_DARK) return 'dark';
  if (configuredMode === MODE_FORCE_LIGHT) return 'light';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function setupSystemAppearanceListener() {
  if (typeof window.matchMedia !== 'function') return;

  const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
  const onSystemAppearanceChanged = () => {
    if (!currentSettings) return;

    const rule = resolveRule(window.location.hostname, currentSettings);
    const configuredMode = rule && rule.mode !== MODE_INHERIT ? rule.mode : currentSettings.defaultMode;
    if (configuredMode !== MODE_FOLLOW_SYSTEM) return;

    applyResolvedSettings(currentSettings);
  };

  if (systemSchemeMediaQuery && systemSchemeChangeHandler) {
    removeMediaQueryListener(systemSchemeMediaQuery, systemSchemeChangeHandler);
  }

  addMediaQueryListener(mediaQuery, onSystemAppearanceChanged);
  systemSchemeMediaQuery = mediaQuery;
  systemSchemeChangeHandler = onSystemAppearanceChanged;
}

function addMediaQueryListener(mediaQuery, handler) {
  if (typeof mediaQuery.addEventListener === 'function') {
    mediaQuery.addEventListener('change', handler);
  } else if (typeof mediaQuery.addListener === 'function') {
    mediaQuery.addListener(handler);
  }
}

function removeMediaQueryListener(mediaQuery, handler) {
  if (typeof mediaQuery.removeEventListener === 'function') {
    mediaQuery.removeEventListener('change', handler);
  } else if (typeof mediaQuery.removeListener === 'function') {
    mediaQuery.removeListener(handler);
  }
}

function getLuminance(r, g, b) {
  const [rs, gs, bs] = [r, g, b].map((c) => {
    c = c / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs;
}

function parseColor(colorStr) {
  if (!colorStr || colorStr === 'transparent' || colorStr === 'rgba(0, 0, 0, 0)') {
    return null;
  }
  const match = colorStr.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/);
  if (match) {
    const a = match[4] !== undefined ? parseFloat(match[4]) : 1;
    if (a < 0.1) return null;
    return { r: parseInt(match[1], 10), g: parseInt(match[2], 10), b: parseInt(match[3], 10), a };
  }
  return null;
}

function isDarkColor(r, g, b) {
  return getLuminance(r, g, b) < 0.12;
}

function isLightColor(r, g, b) {
  return getLuminance(r, g, b) > 0.4;
}

function isTextDark(el) {
  if (!el) return false;
  const style = window.getComputedStyle(el);
  const color = parseColor(style.color);
  return color && getLuminance(color.r, color.g, color.b) < 0.25;
}

function getEffectiveBackground(el) {
  if (!el) return null;
  const style = window.getComputedStyle(el);
  const bg = parseColor(style.backgroundColor);
  if (bg) return bg;

  const bgImage = style.backgroundImage;
  if (bgImage && bgImage !== 'none') {
    const gradientColors = bgImage.match(/rgba?\(\d+,\s*\d+,\s*\d+(?:,\s*[\d.]+)?\)/g);
    if (gradientColors) {
      let darkCount = 0;
      for (const colorStr of gradientColors) {
        const c = parseColor(colorStr);
        if (c && isDarkColor(c.r, c.g, c.b)) darkCount++;
      }
      if (darkCount > gradientColors.length / 2) return parseColor(gradientColors[0]);
    }
  }

  return null;
}

function isPageDark() {
  const majorTargets = document.querySelectorAll('body > div, #app, #__next, div, section, main, article');
  for (const el of majorTargets) {
    const rect = el.getBoundingClientRect();
    if (rect.width > window.innerWidth * 0.6 && rect.height > window.innerHeight * 0.4) {
      const bg = getEffectiveBackground(el);
      if (bg && bg.a > 0.5 && isLightColor(bg.r, bg.g, bg.b)) return false;
    }
  }

  const targets = [document.documentElement, document.body];
  for (const el of targets) {
    if (!el) continue;
    const style = window.getComputedStyle(el);
    if (style.colorScheme === 'dark') return true;

    const bg = getEffectiveBackground(el);
    if (!bg) continue;
    if (isLightColor(bg.r, bg.g, bg.b)) return false;
    if (isDarkColor(bg.r, bg.g, bg.b) && !isTextDark(el)) return true;
  }

  const themeColorMeta = document.querySelector('meta[name="theme-color"]');
  if (themeColorMeta) {
    const content = themeColorMeta.getAttribute('content');
    if (content && content.toLowerCase() === '#000000') return true;
  }

  if (document.body) {
    const children = document.body.children;
    let darkBgCount = 0;
    let darkTextCount = 0;
    let sampled = 0;
    const maxSample = Math.min(children.length, 12);
    for (let i = 0; i < maxSample; i++) {
      const child = children[i];
      if (!child || child.tagName === 'SCRIPT' || child.tagName === 'STYLE' || child.tagName === 'LINK' || child.tagName === 'NOSCRIPT') continue;
      const rect = child.getBoundingClientRect();
      if (rect.width < 50 || rect.height < 20) continue;

      const bg = getEffectiveBackground(child);
      if (bg && isDarkColor(bg.r, bg.g, bg.b)) darkBgCount++;
      if (isTextDark(child)) darkTextCount++;
      sampled++;
    }
    if (sampled > 0 && (darkBgCount / sampled >= 0.4) && (darkTextCount / sampled < 0.3)) return true;
  }

  try {
    const samplePoints = [
      [window.innerWidth * 0.5, window.innerHeight * 0.1],
      [window.innerWidth * 0.5, window.innerHeight * 0.5],
      [window.innerWidth * 0.1, window.innerHeight * 0.5],
      [window.innerWidth * 0.9, window.innerHeight * 0.5],
      [window.innerWidth * 0.5, window.innerHeight * 0.9]
    ];
    let darkBgSamples = 0;
    let darkTextSamples = 0;
    let totalSamples = 0;
    for (const [x, y] of samplePoints) {
      const el = document.elementFromPoint(x, y);
      if (!el) continue;
      let current = el;
      let foundBg = false;
      while (current && current !== document.documentElement) {
        const bg = getEffectiveBackground(current);
        if (bg) {
          if (isDarkColor(bg.r, bg.g, bg.b)) darkBgSamples++;
          foundBg = true;
          break;
        }
        current = current.parentElement;
      }
      if (foundBg) {
        if (isTextDark(el)) darkTextSamples++;
        totalSamples++;
      }
    }
    if (totalSamples >= 3 && (darkBgSamples / totalSamples >= 0.5) && (darkTextSamples / totalSamples < 0.3)) {
      return true;
    }
  } catch (e) {
    return false;
  }

  return false;
}

function flipThemeSignalsToLight() {
  injectStyle('dark-light-color-scheme', `
    :root, html, body {
      color-scheme: light !important;
    }
  `);

  flipThemeSignals('light');

  injectStyle('dark-light-theme-overrides', `
    :root[data-theme="dark"], :root.dark,
    [data-theme="dark"] body, .dark body {
      --background: 0 0% 100% !important;
      --foreground: 222.2 84% 4.9% !important;
      background-color: white !important;
      color: #1a1a1a !important;
    }
  `);
}

function flipThemeSignalsToDark() {
  injectStyle('dark-light-color-scheme', `
    :root, html, body {
      color-scheme: dark !important;
    }
  `);

  flipThemeSignals('dark');
}

function flipThemeSignals(target) {
  [document.documentElement, document.body].forEach((el) => {
    if (!el) return;
    captureThemeSnapshot(el);
    THEME_CLASSES.forEach((cls) => {
      if (!el.classList.contains(cls)) return;
      el.classList.remove(cls);
      if (target === 'dark' && /light|day/i.test(cls)) {
        el.classList.add(cls.replace(/light/gi, 'dark').replace(/day/gi, 'night'));
      } else if (target === 'light' && /dark|night/i.test(cls)) {
        el.classList.add(cls.replace(/dark/gi, 'light').replace(/night/gi, 'day'));
      }
    });

    if (target === 'dark') el.classList.add('dark');
    if (target === 'light') el.classList.add('light');

    MATCH_ATTRS.forEach((attr) => {
      const val = el.getAttribute(attr);
      if (!val) return;
      if (target === 'dark' && /light|day/i.test(val)) {
        el.setAttribute(attr, val.replace(/light/gi, 'dark').replace(/day/gi, 'night'));
      }
      if (target === 'light' && /dark|night/i.test(val)) {
        el.setAttribute(attr, val.replace(/dark/gi, 'light').replace(/night/gi, 'day'));
      }
    });

    const inlineStyle = el.getAttribute('style') || '';
    if (target === 'dark' && /color-scheme:\s*light/i.test(inlineStyle)) {
      el.setAttribute('style', inlineStyle.replace(/color-scheme:\s*light/gi, 'color-scheme: dark'));
    }
    if (target === 'light' && /color-scheme:\s*dark/i.test(inlineStyle)) {
      el.setAttribute('style', inlineStyle.replace(/color-scheme:\s*dark/gi, 'color-scheme: light'));
    }
  });
}

function captureThemeSnapshot(el) {
  if (themeSnapshots.has(el)) return;

  const attrs = {};
  MATCH_ATTRS.forEach((attr) => {
    attrs[attr] = el.hasAttribute(attr) ? el.getAttribute(attr) : null;
  });

  themeSnapshots.set(el, {
    className: el.getAttribute('class'),
    style: el.getAttribute('style'),
    attrs
  });
}

function restoreThemeSnapshots() {
  [document.documentElement, document.body].forEach((el) => {
    if (!el || !themeSnapshots.has(el)) return;
    const snapshot = themeSnapshots.get(el);

    restoreNullableAttribute(el, 'class', snapshot.className);
    restoreNullableAttribute(el, 'style', snapshot.style);
    Object.keys(snapshot.attrs).forEach((attr) => {
      restoreNullableAttribute(el, attr, snapshot.attrs[attr]);
    });

    themeSnapshots.delete(el);
  });
}

function restoreNullableAttribute(el, attr, value) {
  if (value === null) {
    el.removeAttribute(attr);
  } else {
    el.setAttribute(attr, value);
  }
}

function injectStyle(id, css) {
  if (document.getElementById(id)) return;
  const style = document.createElement('style');
  style.id = id;
  style.textContent = css;
  (document.head || document.documentElement).appendChild(style);
}

function cleanupAppearanceOverrides() {
  if (window.DarkReader?.isEnabled?.()) {
    window.DarkReader.disable();
  }

  restoreThemeSnapshots();

  if (themeObserver) {
    themeObserver.disconnect();
    themeObserver = null;
  }

  [
    'dark-light-color-scheme',
    'dark-light-theme-overrides',
    'dark-light-invert',
    'dark-light-bg-reinvert',
    'dark-light-dark-tokens'
  ].forEach((id) => {
    document.getElementById(id)?.remove();
  });

  document.querySelectorAll('[data-dl-darkened]').forEach((el) => {
    el.style.removeProperty('background-color');
    el.style.removeProperty('color');
    el.style.removeProperty('border-color');
    el.style.removeProperty('box-shadow');
    el.removeAttribute('data-dl-darkened');
  });

  document.querySelectorAll('[data-dl-foreground]').forEach((el) => {
    el.style.removeProperty('color');
    el.style.removeProperty('-webkit-text-fill-color');
    el.style.removeProperty('fill');
    el.style.removeProperty('stroke');
    el.style.removeProperty('text-shadow');
    el.style.removeProperty('opacity');
    el.removeAttribute('data-dl-foreground');
  });

  document.querySelectorAll('[data-dl-illuminated]').forEach((el) => {
    el.style.removeProperty('filter');
    el.querySelectorAll('img, video, canvas, svg, [style*="background-image"]').forEach((media) => {
      media.style.removeProperty('filter');
    });
    el.removeAttribute('data-dl-illuminated');
  });

  document.querySelectorAll('[data-dl-bg]').forEach((el) => {
    el.removeAttribute('data-dl-bg');
    el.style.removeProperty('filter');
  });
}

function applyFilterInversion(runId) {
  if (!isCurrentRun(runId)) return;
  if (document.getElementById('dark-light-invert')) return;

  injectStyle('dark-light-invert', `
    html {
      filter: invert(1) hue-rotate(180deg) !important;
    }

    img,
    video,
    canvas,
    .emoji,
    iframe {
      filter: invert(1) hue-rotate(180deg) !important;
    }

    svg image {
      filter: invert(1) hue-rotate(180deg) !important;
    }
  `);

  requestAnimationFrame(() => {
    if (isCurrentRun(runId)) reInvertBackgroundImages();
  });
}

function reInvertBackgroundImages() {
  if (document.getElementById('dark-light-bg-reinvert')) return;

  const walker = document.createTreeWalker(
    document.body || document.documentElement,
    NodeFilter.SHOW_ELEMENT,
    null
  );

  const leafRules = [];
  const containerRules = [];
  let count = 0;
  let node;

  while ((node = walker.nextNode()) && count < 5000) {
    count++;
    const style = window.getComputedStyle(node);
    const bg = style.backgroundImage;
    if (!bg || bg === 'none' || !bg.includes('url(')) continue;

    const uid = 'dl-' + Math.random().toString(36).substr(2, 6);
    node.setAttribute('data-dl-bg', uid);

    const hasMediaChildren = node.querySelector('img, video, canvas, iframe');
    const isLarge = node.offsetWidth > window.innerWidth * 0.4 && node.offsetHeight > window.innerHeight * 0.4;

    if (hasMediaChildren || isLarge || node === document.body || node === document.documentElement) {
      containerRules.push(`
        [data-dl-bg="${uid}"] {
          position: relative !important;
          background-image: none !important;
          z-index: 0 !important;
        }
        [data-dl-bg="${uid}"]::before {
          content: "" !important;
          position: absolute !important;
          inset: 0 !important;
          background-image: ${bg} !important;
          background-size: ${style.backgroundSize} !important;
          background-position: ${style.backgroundPosition} !important;
          background-repeat: ${style.backgroundRepeat} !important;
          background-attachment: ${style.backgroundAttachment} !important;
          filter: invert(1) hue-rotate(180deg) !important;
          z-index: -1 !important;
          pointer-events: none !important;
          opacity: ${style.opacity} !important;
        }
      `);
    } else {
      leafRules.push(`[data-dl-bg="${uid}"] { filter: invert(1) hue-rotate(180deg) !important; }`);
    }
  }

  if (leafRules.length > 0 || containerRules.length > 0) {
    injectStyle('dark-light-bg-reinvert', leafRules.join('\n') + '\n' + containerRules.join('\n'));
  }
}

function applyDarkTokenLayer() {
  injectStyle('dark-light-dark-tokens', `
    :root {
      --dl-bg: #111315;
      --dl-surface: #171a1d;
      --dl-surface-2: #202429;
      --dl-border: #343a40;
      --dl-text: #e7e9ec;
      --dl-muted: #b2bac2;
      --dl-link: #8ab4ff;
    }

    html, body {
      background-color: var(--dl-bg) !important;
      color: var(--dl-text) !important;
    }

    body {
      color-scheme: dark !important;
    }

    main, article, section, aside, nav, header, footer,
    div, form, table, thead, tbody, tr, td, th,
    dialog, [role="dialog"], [role="menu"], [role="listbox"],
    [class*="card"], [class*="panel"], [class*="modal"], [class*="popover"],
    [class*="dropdown"], [class*="container"], [class*="content"] {
      border-color: var(--dl-border) !important;
    }

    p, span, li, label, strong, em, small, h1, h2, h3, h4, h5, h6,
    td, th, blockquote, pre, code {
      color: inherit;
    }

    a {
      color: var(--dl-link) !important;
    }

    input, textarea, select {
      background-color: var(--dl-surface-2) !important;
      color: var(--dl-text) !important;
      border-color: var(--dl-border) !important;
      color-scheme: dark !important;
    }

    input[type="text"], input[type="search"], input:not([type]),
    textarea {
      background-color: #171b1f !important;
      color: #f0f3f6 !important;
      border-color: #4b5560 !important;
      box-shadow: inset 0 0 0 1px rgba(148, 163, 184, 0.28) !important;
    }

    input::placeholder, textarea::placeholder {
      color: #9aa5af !important;
      opacity: 1 !important;
    }

    button, input[type="button"], input[type="submit"], input[type="reset"],
    [role="button"], [class*="button"], [class*="Button"] {
      color: #f8fafc !important;
      -webkit-text-fill-color: #f8fafc !important;
      fill: #f8fafc !important;
      stroke: #f8fafc !important;
      border-color: #59636e;
      color-scheme: dark !important;
      text-shadow: none !important;
      opacity: 1 !important;
    }

    center input[type="submit"],
    form input[type="submit"],
    input.gNO89b,
    input.RNmpXc,
    input[name="btnK"],
    input[name="btnI"] {
      color: #ffffff !important;
      -webkit-text-fill-color: #ffffff !important;
      fill: #ffffff !important;
      stroke: #ffffff !important;
    }

    img, video, canvas, svg {
      opacity: 1 !important;
    }

    pre, code, kbd, samp {
      background-color: #171a1d !important;
      color: #e7e9ec !important;
      border-color: var(--dl-border) !important;
    }

    ::selection {
      background-color: #315c9f !important;
      color: #ffffff !important;
    }
  `);
}

function hasDominantMedia(el) {
  const rect = el.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return false;

  const media = el.querySelectorAll('img, picture, video, canvas, svg');
  if (media.length === 0) return false;

  let mediaArea = 0;
  media.forEach((item) => {
    const mediaRect = item.getBoundingClientRect();
    mediaArea += Math.max(0, mediaRect.width) * Math.max(0, mediaRect.height);
  });

  const textLength = (el.innerText || '').trim().length;
  const areaRatio = mediaArea / (rect.width * rect.height);
  return areaRatio > 0.28 && textLength < 120;
}

function getReadableBackground(el) {
  let current = el;
  while (current && current.nodeType === Node.ELEMENT_NODE) {
    const bg = getEffectiveBackground(current);
    if (bg) return bg;
    current = current.parentElement;
  }
  return { r: 17, g: 19, b: 21, a: 1 };
}

function setReadableForeground(el, color) {
  el.setAttribute('data-dl-foreground', 'true');
  el.style.setProperty('color', color, 'important');
  el.style.setProperty('-webkit-text-fill-color', color, 'important');
  el.style.setProperty('text-shadow', 'none', 'important');
  el.style.setProperty('opacity', '1', 'important');
}

function setReadableVectorForeground(el, color) {
  el.setAttribute('data-dl-foreground', 'true');
  el.style.setProperty('color', color, 'important');
  el.style.setProperty('fill', color, 'important');
  el.style.setProperty('stroke', color, 'important');
  el.style.setProperty('opacity', '1', 'important');
}

function isVisibleElement(el) {
  const rect = el.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return false;
  if (rect.bottom < 0 || rect.top > window.innerHeight) return false;
  const style = window.getComputedStyle(el);
  return style.display !== 'none' && style.visibility !== 'hidden' && parseFloat(style.opacity || '1') > 0.05;
}

function liftDarkForegrounds() {
  if (!document.body) return;

  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT, {
    acceptNode(node) {
      if (node.closest('img, picture, video, canvas')) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    }
  });

  let count = 0;
  let node;
  while ((node = walker.nextNode()) && count < 6000) {
    count++;
    const el = node;
    if (!isVisibleElement(el)) continue;

    const bg = getReadableBackground(el);
    const bgLum = getLuminance(bg.r, bg.g, bg.b);
    const isDarkBg = bgLum < 0.22;
    if (!isDarkBg) continue;

    const style = window.getComputedStyle(el);
    const color = parseColor(style.color);
    if (color && getLuminance(color.r, color.g, color.b) < 0.45) {
      setReadableForeground(el, '#f1f5f9');
    }

    if (el.matches('svg, path, circle, rect, polygon, line, polyline, use, [role="img"], [aria-hidden="true"]')) {
      const fill = parseColor(style.fill);
      const stroke = parseColor(style.stroke);
      const fillIsDark = fill && getLuminance(fill.r, fill.g, fill.b) < 0.45;
      const strokeIsDark = stroke && getLuminance(stroke.r, stroke.g, stroke.b) < 0.45;
      if (fillIsDark || strokeIsDark || el.matches('svg, [role="img"], [aria-hidden="true"]')) {
        setReadableVectorForeground(el, '#f1f5f9');
      }
    }
  }
}

function darkenPersistentLightContainers() {
  if (!document.body) return;

  const selector = [
    'body > div',
    '#app',
    '#__next',
    'main',
    'article',
    'section',
    'aside',
    'nav',
    'header',
    'footer',
    '[role="main"]',
    '[role="dialog"]',
    '[class*="card"]',
    '[class*="panel"]',
    '[class*="modal"]',
    '[class*="content"]',
    '[class*="container"]',
    '[class*="wrapper"]',
    '[class*="layout"]',
    '[class*="page-wrapper"]',
    '[class*="site-wrapper"]'
  ].join(',');

  document.querySelectorAll(selector).forEach((el) => {
    if (el.hasAttribute('data-dl-darkened')) return;
    if (el.closest('svg, picture, video, canvas')) return;
    const rect = el.getBoundingClientRect();
    if (rect.width < 80 || rect.height < 40) return;
    if (hasDominantMedia(el)) return;

    const bg = getEffectiveBackground(el);
    if (!bg || !isLightColor(bg.r, bg.g, bg.b)) return;

    el.setAttribute('data-dl-darkened', 'true');
    el.style.setProperty('background-color', rect.width > window.innerWidth * 0.55 ? '#111315' : '#1a1f24', 'important');
    el.style.setProperty('color', '#e7e9ec', 'important');
    el.style.setProperty('border-color', '#343a40', 'important');
  });
}

function darkenVisibleLightBlocks() {
  if (!document.body) return;

  const targets = document.querySelectorAll('div, form, center, [role="search"], [role="button"], [role="contentinfo"]');
  let inspected = 0;

  targets.forEach((el) => {
    if (inspected > 1800) return;
    inspected++;
    if (el.hasAttribute('data-dl-darkened')) return;
    if (el.closest('svg, picture, video, canvas')) return;

    const rect = el.getBoundingClientRect();
    if (rect.width < 180 || rect.height < 28) return;
    if (rect.bottom < 0 || rect.top > window.innerHeight) return;
    if (hasDominantMedia(el)) return;

    const bg = getEffectiveBackground(el);
    if (!bg || !isLightColor(bg.r, bg.g, bg.b)) return;

    const isWideBand = rect.width > window.innerWidth * 0.7;
    const isControlLike = el.matches('form, [role="search"], [role="button"]') || el.querySelector('input, textarea, select, button');
    if (!isWideBand && !isControlLike) return;

    el.setAttribute('data-dl-darkened', 'true');
    el.style.setProperty('background-color', isWideBand ? '#111315' : '#1a1f24', 'important');
    el.style.setProperty('color', '#e7e9ec', 'important');
    el.style.setProperty('border-color', '#3d4650', 'important');
    el.style.setProperty('box-shadow', 'none', 'important');
  });
}

function applyDarkLight(runId) {
  if (!isCurrentRun(runId)) return;
  flipThemeSignalsToDark();

  const startDarkReader = () => {
    if (!isCurrentRun(runId)) return;
    if (window.DarkReader?.enable) {
      try {
        window.DarkReader.setFetchMethod?.(async (url) => {
          return new Promise((resolve, reject) => {
            const tryFetch = (retries = 15) => {
              let handled = false;
              const timeoutId = setTimeout(() => {
                if (handled) return;
                handled = true;
                if (retries > 0) {
                  tryFetch(retries - 1);
                } else {
                  window.fetch(url).then(resolve).catch(reject);
                }
              }, 500);

              try {
                chrome.runtime.sendMessage({ action: 'dl_fetch', url }, (response) => {
                  if (handled) return;
                  handled = true;
                  clearTimeout(timeoutId);

                  if (chrome.runtime.lastError) {
                    if (retries > 0) {
                      setTimeout(() => tryFetch(retries - 1), 200);
                      return;
                    }
                    window.fetch(url).then(resolve).catch(reject);
                    return;
                  }
                  if (!response || response.error || typeof response.text !== 'string') {
                    window.fetch(url).then(resolve).catch(reject);
                    return;
                  }
                  resolve(new Response(response.text, {
                    status: 200,
                    headers: { 'Content-Type': 'text/css' }
                  }));
                });
              } catch (e) {
                if (handled) return;
                handled = true;
                clearTimeout(timeoutId);
                if (retries > 0) {
                  setTimeout(() => tryFetch(retries - 1), 200);
                } else {
                  window.fetch(url).then(resolve).catch(reject);
                }
              }
            };
            tryFetch();
          });
        });
        window.DarkReader.enable({
          brightness: 100,
          contrast: 100,
          sepia: 0
        });
        
        setTimeout(() => {
          if (!isCurrentRun(runId)) return;
          if (!isPageDark()) {
            applyDarkTokenLayer();
            darkenPersistentLightContainers();
            darkenVisibleLightBlocks();
            liftDarkForegrounds();
          }
        }, 1500);
      } catch (e) {
        console.warn('[Dark Light] Dark Reader failed, falling back to basic dark mode.', e);
        applyDarkTokenLayer();
        darkenPersistentLightContainers();
        darkenVisibleLightBlocks();
        liftDarkForegrounds();
      }
    } else {
      applyDarkTokenLayer();
      darkenPersistentLightContainers();
      darkenVisibleLightBlocks();
      liftDarkForegrounds();
    }
  };

  if (document.head) {
    startDarkReader();
  } else {
    const headObserver = new MutationObserver(() => {
      if (document.head) {
        headObserver.disconnect();
        startDarkReader();
      }
    });
    headObserver.observe(document.documentElement || document, { childList: true, subtree: true });
  }

  const reinforceNativeSignals = () => {
    if (!isCurrentRun(runId)) return;
    flipThemeSignalsToDark();
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      setTimeout(reinforceNativeSignals, 50);
    });
  } else {
    setTimeout(reinforceNativeSignals, 50);
  }

  window.addEventListener('load', () => setTimeout(reinforceNativeSignals, 200));
  observeThemeChanges(() => {
    if (!isCurrentRun(runId)) return;
    flipThemeSignalsToDark();
    setTimeout(() => {
      if (isCurrentRun(runId) && !isPageDark()) {
        darkenPersistentLightContainers();
        darkenVisibleLightBlocks();
      }
    }, 150);
  });
}

function applyLightForce(runId) {
  if (!isCurrentRun(runId)) return;
  flipThemeSignalsToLight();

  const detectAndFix = () => {
    if (!isCurrentRun(runId)) return;
    flipThemeSignalsToLight();
    requestAnimationFrame(() => {
      if (!isCurrentRun(runId)) return;
      if (isPageDark()) {
        applyFilterInversion(runId);
      }
    });
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => setTimeout(detectAndFix, 50));
  } else {
    setTimeout(detectAndFix, 50);
  }

  window.addEventListener('load', () => setTimeout(detectAndFix, 200));
  observeThemeChanges(() => {
    if (!isCurrentRun(runId)) return;
    flipThemeSignalsToLight();
    if (!document.getElementById('dark-light-invert')) {
      requestAnimationFrame(() => {
        if (!isCurrentRun(runId)) return;
        if (isPageDark()) applyFilterInversion(runId);
      });
    }
  });
}

function observeThemeChanges(callback) {
  if (themeObserver) {
    themeObserver.disconnect();
  }

  themeObserver = new MutationObserver(() => {
    clearTimeout(themeObserver._timer);
    themeObserver._timer = setTimeout(callback, 200);
  });

  if (document.documentElement) {
    themeObserver.observe(document.documentElement, {
      attributes: true,
      childList: true,
      subtree: true,
      attributeFilter: ['class', 'theme', 'data-theme', 'data-color-mode', 'data-color-scheme', 'style', 'data-bs-theme']
    });
  }
}
