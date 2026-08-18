const I18n = {
    messages: null,
    currentLang: 'en',
    
    async init() {
        return new Promise((resolve) => {
            chrome.storage.local.get(['userLanguage'], async (result) => {
                let lang = result.userLanguage;
                if (!lang) {
                    const browserLang = ((typeof chrome !== 'undefined' && chrome.i18n && chrome.i18n.getUILanguage) ? chrome.i18n.getUILanguage() : (navigator.language || 'en')).toLowerCase();
                    const supported = ['en', 'zh', 'ja', 'ko', 'es', 'fr', 'de'];
                    lang = 'en';
                    for (const l of supported) {
                        if (browserLang.startsWith(l)) {
                            lang = l;
                            break;
                        }
                    }
                }
                this.currentLang = lang;
                
                let dirName = lang;
                if (lang === 'zh') {
                    dirName = 'zh_CN';
                }
                
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
                resolve();
            });
        });
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
