const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const extensionRoot = path.join(root, 'extension');

function loadManifest() {
  return JSON.parse(fs.readFileSync(path.join(extensionRoot, 'manifest.json'), 'utf8'));
}

function createBackgroundSandbox(settings) {
  let startupListener = null;
  let installedListener = null;
  let storageChangeListener = null;
  const calls = {
    registered: [],
    unregistered: []
  };

  const sandbox = {
    chrome: {
      action: {
        setBadgeText() {},
        setBadgeBackgroundColor() {},
        setBadgeTextColor() {}
      },
      runtime: {
        onInstalled: {
          addListener(listener) {
            installedListener = listener;
          }
        },
        onStartup: {
          addListener(listener) {
            startupListener = listener;
          }
        },
        onMessage: { addListener() {} },
        lastError: null
      },
      storage: {
        onChanged: {
          addListener(listener) {
            storageChangeListener = listener;
          }
        },
        sync: {
          get(_keys, callback) {
            callback({ darkLightSettings: settings });
          },
          set(value, callback) {
            settings = value.darkLightSettings;
            if (callback) callback();
          }
        }
      },
      scripting: {
        getRegisteredContentScripts(_filter, callback) {
          callback([
            { id: 'dark-light-prepaint-old' },
            { id: 'unrelated-script' }
          ]);
        },
        unregisterContentScripts(options, callback) {
          calls.unregistered.push(options);
          if (callback) callback();
        },
        registerContentScripts(scripts, callback) {
          calls.registered.push(...scripts);
          if (callback) callback();
        }
      }
    },
    console
  };

  sandbox.runStartup = () => startupListener();
  sandbox.runInstalled = () => installedListener();
  sandbox.runStorageChange = (nextSettings) => storageChangeListener({
    darkLightSettings: { newValue: nextSettings }
  }, 'sync');
  sandbox.calls = calls;
  return sandbox;
}

function byId(scripts, id) {
  return scripts.find((script) => script.id === id);
}

function plain(value) {
  return JSON.parse(JSON.stringify(value));
}

function testManifestDeclaresPrepaintAssets() {
  const manifest = loadManifest();
  const contentScript = manifest.content_scripts[0];

  assert.ok(
    manifest.permissions.includes('scripting'),
    'dynamic prepaint registration needs the scripting permission'
  );
  assert.deepStrictEqual(
    manifest.host_permissions,
    ['<all_urls>'],
    'dynamic prepaint scripts need host permissions for the same pages as the static content script'
  );
  assert.deepStrictEqual(
    contentScript.css,
    ['prepaint-fallback.css'],
    'the fallback overlay should be a static document_start CSS file'
  );
}

function testBackgroundRegistersFixedCssFilesFromSiteRules() {
  const settings = {
    version: 2,
    defaultMode: 'forceDark',
    siteRules: [
      {
        id: 'root',
        pattern: 'example.com',
        mode: 'forceLight',
        enabled: true,
        matchSubdomains: true
      },
      {
        id: 'child',
        pattern: 'dark.example.com',
        mode: 'forceDark',
        enabled: true,
        matchSubdomains: false
      },
      {
        id: 'preserve',
        pattern: 'preserve.test',
        mode: 'preserveSite',
        enabled: true,
        matchSubdomains: true
      },
      {
        id: 'system',
        pattern: 'system.test',
        mode: 'followSystem',
        enabled: true,
        matchSubdomains: true
      },
      {
        id: 'inherit',
        pattern: 'inherit.test',
        mode: 'inherit',
        enabled: true,
        matchSubdomains: true
      },
      {
        id: 'disabled',
        pattern: 'disabled.test',
        mode: 'forceDark',
        enabled: false,
        matchSubdomains: true
      }
    ]
  };

  const sandbox = createBackgroundSandbox(settings);
  const source = fs.readFileSync(path.join(extensionRoot, 'background.js'), 'utf8');
  vm.runInNewContext(source, sandbox, { filename: 'background.js' });
  sandbox.runStartup();

  assert.deepStrictEqual(
    plain(sandbox.calls.unregistered),
    [{ ids: ['dark-light-prepaint-old'] }],
    'only previous Dark Light prepaint scripts should be unregistered'
  );

  const defaultScript = byId(sandbox.calls.registered, 'dark-light-prepaint-default');
  assert.ok(defaultScript, 'default mode should register a global prepaint script');
  assert.deepStrictEqual(plain(defaultScript.css), ['prepaint-force-dark.css']);
  assert.deepStrictEqual(plain(defaultScript.matches), ['<all_urls>']);
  assert.deepStrictEqual(
    plain(defaultScript.excludeMatches),
    ['*://example.com/*', '*://*.example.com/*', '*://preserve.test/*', '*://*.preserve.test/*', '*://system.test/*', '*://*.system.test/*']
  );
  assert.strictEqual(defaultScript.runAt, 'document_start');
  assert.strictEqual(defaultScript.allFrames, true);
  assert.strictEqual(defaultScript.persistAcrossSessions, true);

  const rootScript = byId(sandbox.calls.registered, 'dark-light-prepaint-root');
  assert.ok(rootScript, 'enabled force-light site rule should be registered');
  assert.deepStrictEqual(plain(rootScript.css), ['prepaint-force-light.css']);
  assert.deepStrictEqual(plain(rootScript.matches), ['*://example.com/*', '*://*.example.com/*']);
  assert.deepStrictEqual(plain(rootScript.excludeMatches), ['*://dark.example.com/*']);
  assert.strictEqual(rootScript.runAt, 'document_start');
  assert.strictEqual(rootScript.allFrames, true);
  assert.strictEqual(rootScript.persistAcrossSessions, true);

  const childScript = byId(sandbox.calls.registered, 'dark-light-prepaint-child');
  assert.ok(childScript, 'more-specific force-dark rule should be registered');
  assert.deepStrictEqual(plain(childScript.css), ['prepaint-force-dark.css']);
  assert.deepStrictEqual(plain(childScript.matches), ['*://dark.example.com/*']);
  assert.strictEqual(childScript.excludeMatches, undefined);

  const preserveScript = byId(sandbox.calls.registered, 'dark-light-prepaint-preserve');
  assert.ok(preserveScript, 'preserve-site rule should be registered to disable the fallback overlay');
  assert.deepStrictEqual(plain(preserveScript.css), ['prepaint-preserve.css']);

  const systemScript = byId(sandbox.calls.registered, 'dark-light-prepaint-system');
  assert.ok(systemScript, 'follow-system site rule should use a fixed CSS file too');
  assert.deepStrictEqual(plain(systemScript.css), ['prepaint-follow-system.css']);

  assert.strictEqual(byId(sandbox.calls.registered, 'dark-light-prepaint-inherit'), undefined);
  assert.strictEqual(byId(sandbox.calls.registered, 'dark-light-prepaint-disabled'), undefined);
}

testManifestDeclaresPrepaintAssets();
testBackgroundRegistersFixedCssFilesFromSiteRules();

console.log('prepaint registration tests passed');
