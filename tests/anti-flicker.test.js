const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const extensionRoot = path.resolve(__dirname, '..', 'extension');

class FakeElement {
  constructor(tagName, document) {
    this.tagName = tagName.toUpperCase();
    this.ownerDocument = document;
    this.children = [];
    this.attributes = new Map();
    this.style = {
      setProperty() {},
      removeProperty() {}
    };
    this.classList = {
      contains: () => false,
      add: () => {},
      remove: () => {}
    };
  }

  set id(value) {
    this.attributes.set('id', value);
  }

  get id() {
    return this.attributes.get('id') || '';
  }

  appendChild(child) {
    this.children.push(child);
    if (child.id) {
      this.ownerDocument.elements.set(child.id, child);
    }
    return child;
  }

  remove() {
    if (this.id) {
      this.ownerDocument.removedIds.push(this.id);
      this.ownerDocument.elements.delete(this.id);
    }
  }

  getAttribute(name) {
    return this.attributes.has(name) ? this.attributes.get(name) : null;
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }

  removeAttribute(name) {
    this.attributes.delete(name);
  }

  hasAttribute(name) {
    return this.attributes.has(name);
  }

  querySelectorAll() {
    return [];
  }
}

function createContentSandbox(settings) {
  const documentListeners = new Map();
  const document = {
    readyState: 'loading',
    elements: new Map(),
    removedIds: [],
    createElement(tagName) {
      return new FakeElement(tagName, document);
    },
    getElementById(id) {
      return document.elements.get(id) || null;
    },
    querySelector() {
      return null;
    },
    querySelectorAll() {
      return [];
    },
    addEventListener(eventName, listener) {
      documentListeners.set(eventName, listener);
    },
    dispatchEventName(eventName) {
      const listener = documentListeners.get(eventName);
      if (listener) listener();
    },
    elementFromPoint() {
      return document.body;
    }
  };

  document.documentElement = new FakeElement('html', document);
  document.body = new FakeElement('body', document);
  document.head = new FakeElement('head', document);

  const sandbox = {
    chrome: {
      runtime: {
        onMessage: { addListener() {} },
        sendMessage() {}
      },
      storage: {
        onChanged: { addListener() {} },
        sync: {
          get(_keys, callback) {
            callback({ darkLightSettings: settings });
          },
          set(_value, callback) {
            if (callback) callback();
          }
        }
      }
    },
    console,
    document,
    window: {
      location: { hostname: 'example.com' },
      matchMedia() {
        return {
          matches: false,
          addEventListener() {},
          removeEventListener() {}
        };
      },
      addEventListener() {},
      getComputedStyle() {
        return {
          color: 'rgb(26, 26, 26)',
          backgroundColor: 'rgb(255, 255, 255)',
          backgroundImage: 'none',
          colorScheme: 'light',
          display: 'block',
          visibility: 'visible',
          opacity: '1'
        };
      },
      innerWidth: 1280,
      innerHeight: 720
    },
    MutationObserver: class {
      observe() {}
      disconnect() {}
    },
    NodeFilter: { SHOW_ELEMENT: 1, FILTER_ACCEPT: 1, FILTER_REJECT: 2 },
    Node: { ELEMENT_NODE: 1 },
    requestAnimationFrame(callback) {
      callback();
    },
    setTimeout() {},
    clearTimeout() {}
  };
  sandbox.window.window = sandbox.window;
  sandbox.window.document = document;
  sandbox.globalThis = sandbox;
  return sandbox;
}

function testContentRefreshIsIdempotent() {
  const settings = {
    version: 2,
    defaultMode: 'forceLight',
    siteRules: []
  };
  const sandbox = createContentSandbox(settings);
  const source = fs.readFileSync(path.join(extensionRoot, 'content.js'), 'utf8');
  vm.runInNewContext(source, sandbox, { filename: 'content.js' });

  assert.ok(
    sandbox.document.getElementById('dark-light-color-scheme'),
    'initial force-light pass should inject the color-scheme style'
  );

  sandbox.document.removedIds.length = 0;
  sandbox.applyResolvedSettings(settings);

  assert.deepStrictEqual(
    sandbox.document.removedIds,
    [],
    'refreshing the same force-light appearance should not remove injected styles'
  );
}

function testForceLightReleasesPrepaintAfterDOMContentLoaded() {
  const settings = {
    version: 2,
    defaultMode: 'forceLight',
    siteRules: []
  };
  const sandbox = createContentSandbox(settings);
  const source = fs.readFileSync(path.join(extensionRoot, 'content.js'), 'utf8');
  vm.runInNewContext(source, sandbox, { filename: 'content.js' });

  assert.strictEqual(
    sandbox.document.documentElement.getAttribute('data-dl-ready'),
    null,
    'force-light fallback prepaint should stay up while the document is still loading'
  );

  sandbox.document.dispatchEventName('DOMContentLoaded');

  assert.strictEqual(
    sandbox.document.documentElement.getAttribute('data-dl-ready'),
    'true',
    'force-light fallback prepaint should be released after the first DOMContentLoaded appearance check'
  );
}

function testTabActivationDoesNotRefreshContentScript() {
  let activationListener = null;
  let refreshMessages = 0;
  const sandbox = {
    chrome: {
      action: {
        setBadgeText() {},
        setBadgeBackgroundColor() {},
        setBadgeTextColor() {}
      },
      runtime: {
        onInstalled: { addListener() {} },
        onStartup: { addListener() {} },
        onMessage: { addListener() {} },
        lastError: null
      },
      storage: {
        onChanged: { addListener() {} },
        sync: {
          get(_keys, callback) {
            callback({ darkLightSettings: { version: 2, defaultMode: 'followSystem', siteRules: [] } });
          },
          set(_value, callback) {
            if (callback) callback();
          }
        }
      },
      scripting: {
        getRegisteredContentScripts(_filter, callback) {
          callback([]);
        },
        registerContentScripts(_scripts, callback) {
          if (callback) callback();
        },
        unregisterContentScripts(_options, callback) {
          if (callback) callback();
        }
      },
      tabs: {
        onActivated: {
          addListener(listener) {
            activationListener = listener;
          }
        },
        sendMessage(_tabId, message, callback) {
          if (message && message.action === 'darkLightRefresh') {
            refreshMessages++;
          }
          if (callback) callback();
        }
      }
    }
  };

  const source = fs.readFileSync(path.join(extensionRoot, 'background.js'), 'utf8');
  vm.runInNewContext(source, sandbox, { filename: 'background.js' });

  if (activationListener) {
    activationListener({ tabId: 42 });
  }

  assert.strictEqual(
    refreshMessages,
    0,
    'activating an already-open tab should not force the content script to rebuild appearance'
  );
}

testContentRefreshIsIdempotent();
testForceLightReleasesPrepaintAfterDOMContentLoaded();
testTabActivationDoesNotRefreshContentScript();

console.log('anti-flicker tests passed');
