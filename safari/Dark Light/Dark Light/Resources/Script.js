const STRINGS = {
    en: {
        pageTitle: 'Dark Light for Safari',
        appIconAlt: 'Dark Light Icon',
        heroTitle: 'Dark Light for Safari',
        heroIntro: 'Dark Light lets you decide how each website should look: follow system, preserve site design, force dark, or force light.',
        usageTitle: 'How to use it',
        usageStep1: 'Open Safari.',
        usageStep2: 'Enable Dark Light in Safari Extensions settings and set "Always Allow on Every Website".',
        usageStep3: 'Use the toolbar popup to switch modes for the current site.',
        statusUnknownSettings: 'You can turn on Dark Light in the Extensions section of Safari Settings.',
        statusOnSettings: 'Dark Light is enabled in Safari. You can turn it off in the Extensions section of Safari Settings.',
        statusOffSettings: 'Dark Light is currently disabled in Safari. You can turn it on in the Extensions section of Safari Settings.',
        statusUnknownPreferences: 'You can turn on Dark Light in Safari Extensions preferences.',
        statusOnPreferences: 'Dark Light is enabled in Safari. You can turn it off in Safari Extensions preferences.',
        statusOffPreferences: 'Dark Light is currently disabled in Safari. You can turn it on in Safari Extensions preferences.',
        openSafari: 'Open Safari',
        openPreferencesSettings: 'Open Safari Extensions Settings',
        openPreferencesPreferences: 'Open Safari Extensions Preferences'
    },
    zh: {
        pageTitle: 'Safari 版暗光',
        appIconAlt: '暗光图标',
        heroTitle: 'Safari 版暗光',
        heroIntro: '暗光让你决定每个网站该如何显示：跟随系统外观、维持网站设计、强制深色或强制浅色。',
        usageTitle: '如何使用',
        usageStep1: '打开 Safari。',
        usageStep2: '在 Safari 扩展设置中启用暗光，并将“在所有网站上始终允许”设为允许。',
        usageStep3: '使用工具栏弹窗为当前网站切换模式。',
        statusUnknownSettings: '你可以在 Safari 的“扩展”设置中启用暗光。',
        statusOnSettings: '暗光已在 Safari 中启用。你可以在 Safari 的“扩展”设置中关闭它。',
        statusOffSettings: '暗光当前在 Safari 中处于关闭状态。你可以在 Safari 的“扩展”设置中启用它。',
        statusUnknownPreferences: '你可以在 Safari 扩展偏好设置中启用暗光。',
        statusOnPreferences: '暗光已在 Safari 中启用。你可以在 Safari 扩展偏好设置中关闭它。',
        statusOffPreferences: '暗光当前在 Safari 中处于关闭状态。你可以在 Safari 扩展偏好设置中启用它。',
        openSafari: '打开 Safari',
        openPreferencesSettings: '打开 Safari 扩展设置',
        openPreferencesPreferences: '打开 Safari 扩展偏好设置'
    }
};

function resolveLocale() {
    const language = (navigator.language || 'en').toLowerCase();
    if (language.startsWith('zh')) {
        return 'zh';
    }
    return 'en';
}

function t(key) {
    const locale = resolveLocale();
    return STRINGS[locale][key] || STRINGS.en[key] || '';
}

function updateStatusBanner(enabled, suffix) {
    const statusBanner = document.querySelector('.status-banner');
    if (!statusBanner) {
        return;
    }

    let statusKey = `statusUnknown${suffix}`;
    if (enabled === true) {
        statusKey = `statusOn${suffix}`;
    } else if (enabled === false) {
        statusKey = `statusOff${suffix}`;
    }
    statusBanner.textContent = t(statusKey);
}

function applyLocalizedCopy(useSettingsInsteadOfPreferences) {
    document.documentElement.lang = resolveLocale() === 'zh' ? 'zh-CN' : 'en';

    document.querySelectorAll('[data-i18n]').forEach((element) => {
        const key = element.dataset.i18n;
        if (key === 'statusUnknownSettings' || key === 'statusOnSettings' || key === 'statusOffSettings') {
            return;
        }
        element.textContent = t(key);
    });

    document.querySelectorAll('[data-i18n-attr]').forEach((element) => {
        const mappings = element.dataset.i18nAttr.split(',');
        mappings.forEach((mapping) => {
            const [attribute, key] = mapping.split(':');
            if (!attribute || !key) {
                return;
            }
            element.setAttribute(attribute.trim(), t(key.trim()));
        });
    });

    const suffix = useSettingsInsteadOfPreferences ? 'Settings' : 'Preferences';
    updateStatusBanner(null, suffix);
    document.querySelector('.open-preferences').textContent = t(`openPreferences${suffix}`);
    document.title = t('pageTitle');
}

function show(enabled, useSettingsInsteadOfPreferences) {
    applyLocalizedCopy(useSettingsInsteadOfPreferences);

    const suffix = useSettingsInsteadOfPreferences ? 'Settings' : 'Preferences';
    updateStatusBanner(enabled, suffix);

    if (typeof enabled === "boolean") {
        document.body.classList.toggle(`state-on`, enabled);
        document.body.classList.toggle(`state-off`, !enabled);
    } else {
        document.body.classList.remove(`state-on`);
        document.body.classList.remove(`state-off`);
    }
}

function openPreferences() {
    webkit.messageHandlers.controller.postMessage("open-preferences");
}

function openSafari() {
    webkit.messageHandlers.controller.postMessage("open-safari");
}

const openPreferencesButton = document.querySelector("button.open-preferences");
if (openPreferencesButton) {
    openPreferencesButton.addEventListener("click", openPreferences);
}

const openSafariButton = document.querySelector("button.open-safari");
if (openSafariButton) {
    openSafariButton.addEventListener("click", openSafari);
}
applyLocalizedCopy(true);
