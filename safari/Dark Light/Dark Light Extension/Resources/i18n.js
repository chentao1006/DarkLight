const I18n = {
    messages: null,
    currentLang: 'en',
    
    async init() {
        const supported = ['en', 'zh', 'ja', 'ko', 'es', 'fr', 'de'];
        const storedLanguage = await new Promise((resolve) => {
            chrome.storage.local.get(['userLanguage', 'hostInterfaceLanguageRevision'], resolve);
        });
        let lang = storedLanguage.userLanguage;

        try {
            const response = await new Promise((resolve) => {
                chrome.runtime.sendMessage({ action: 'getInterfaceLanguage' }, (result) => {
                    if (chrome.runtime.lastError) {
                        resolve(null);
                        return;
                    }
                    resolve(result);
                });
            });
            if (supported.includes(response?.language)
                && typeof response.revision === 'number'
                && response.revision > 0
                && response.revision !== storedLanguage.hostInterfaceLanguageRevision) {
                lang = response.language;
                await new Promise((resolve) => {
                    chrome.storage.local.set({
                        userLanguage: lang,
                        hostInterfaceLanguageRevision: response.revision
                    }, resolve);
                });
            }
        } catch (_) {
            // Non-Safari builds retain their extension-local language choice.
        }

        if (!supported.includes(lang)) {
            const browserLang = ((typeof chrome !== 'undefined' && chrome.i18n && chrome.i18n.getUILanguage) ? chrome.i18n.getUILanguage() : (navigator.language || 'en')).toLowerCase();
            lang = supported.find((candidate) => browserLang.startsWith(candidate)) || 'en';
        }

        this.currentLang = lang;
        const dirName = lang === 'zh' ? 'zh_CN' : lang;
        try {
            const response = await fetch(`_locales/${dirName}/messages.json`);
            this.messages = await response.json();
        } catch (e) {
            console.warn("Failed to load language", lang, e);
            if (lang !== 'en') {
                try {
                    const fallback = await fetch(`_locales/en/messages.json`);
                    this.messages = await fallback.json();
                } catch (err) {}
            }
        }
    },

    getMessage(key) {
        if (this.messages && this.messages[key]) {
            return this.messages[key].message;
        }
        return chrome.i18n.getMessage(key);
    },

    applyToDOM(root = document) {
        root.querySelectorAll('[data-i18n]').forEach((el) => {
            const key = el.getAttribute('data-i18n');
            const message = this.getMessage(key);
            if (message) {
                if (el.tagName === 'TITLE') {
                    document.title = message;
                } else {
                    el.textContent = message;
                }
            }
        });
    }
};
