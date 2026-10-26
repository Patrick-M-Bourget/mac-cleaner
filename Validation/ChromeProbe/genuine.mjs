// Genuine disposable-browser qualification, never a production cleanup API.
import { spawn, execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, stat, readdir, realpath, statfs } from 'node:fs/promises';
import { createHash, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { tmpdir, release, arch } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import {crashpadBaseline,captureOwnedCrashpad,closeOwnedCrashpad} from './owned-crashpad.mjs';

// Hosted-only: no installed browser, personal profile, OS settings or permissions.
assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Run on an ephemeral GitHub-hosted macOS runner only');
assert.equal(process.env.RUNNER_ENVIRONMENT, 'github-hosted', 'Persistent/self-hosted runners are not supported');
assert.equal(process.platform, 'darwin');
assert.equal(arch(), 'arm64');
const [browserArg, outputArg] = process.argv.slice(2);
assert(browserArg && outputArg, 'usage: node genuine.mjs /owned/CfT/binary /owned/report.json');
const browser = await realpath(resolve(browserArg));
const stable = process.env.STILL_CHROME_STABLE_PROBE === '1';
let provisioning, version, bundle;
if (stable) {
assert(browser.includes('/expanded/') && browser.endsWith('/Google Chrome.app/Contents/MacOS/Google Chrome'), 'Explicit extracted Stable bundle required');
assert(!browser.startsWith('/Applications/'));
const disk = await statfs(tmpdir());
assert(disk.bavail * disk.bsize > 1024 ** 3, 'At least 1 GiB free required');
bundle = browser.slice(0, browser.indexOf('.app/') + 4);
provisioning = JSON.parse(await readFile(join(resolve(outputArg), '..', 'provision.json'), 'utf8'));
assert.equal(provisioning.bundleIdentifier, 'com.google.Chrome');
assert.equal(provisioning.provisioningComplete, true);
assert.equal(provisioning.sealedBundleVerified, true);
assert.equal(provisioning.bundle, bundle);
assert.equal(provisioning.executableSHA256, createHash('sha256').update(await readFile(browser)).digest('hex'));
version = execFileSync(browser, ['--version'], { encoding: 'utf8', timeout: 10000 }).trim();
assert.equal(version.split(/\s+/).at(-1), provisioning.version);

 } else {
assert(browser.includes('/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/'), 'Explicit downloaded CfT bundle required');
assert(!browser.startsWith('/Applications/'));
const disk = await statfs(tmpdir());
assert(disk.bavail * disk.bsize > 1024 ** 3, 'At least 1 GiB free required');
const expectedVersion = '156.0.8078.47';
bundle = browser.slice(0, browser.indexOf('.app/') + 4);
provisioning = JSON.parse(await readFile(join(dirname(dirname(bundle)), 'evidence', 'provision.json'), 'utf8'));
assert.equal(provisioning.archiveSHA256, 'ad7f2b49a4dc679af286b1b1b386670d93ca7868079f69012d21ba0ac8293df3');
assert.equal(provisioning.archiveBytes, 194932023);
assert.equal(provisioning.provisioningComplete, true);
assert.equal(provisioning.executableSHA256, createHash('sha256').update(await readFile(browser)).digest('hex'));
version = execFileSync(browser, ['--version'], { encoding: 'utf8', timeout: 10000 }).trim();
assert.equal(version.split(/\s+/).at(-1), expectedVersion, `Unexpected browser version: ${version}`);

 }
const root = await realpath(await mkdtemp(join(tmpdir(), 'StillChromeProbe-')));
const userData = join(root, 'custom', 'configured-user-data');
await mkdir(userData, { recursive: true });
const digest = x => createHash('sha256').update(x).digest('hex');
const token = randomBytes(16).toString('hex');
const asset = randomBytes(512 * 1024);
let assetRequests = 0;
let offlineShellRequests = 0;
const server = createServer((req, res) => {
  if (req.url === '/login' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; if (body.length > 1024) req.destroy(); });
    req.on('end', () => {
      if (body !== 'credential=' + token) { res.writeHead(403); res.end(); return; }
      res.writeHead(200, { 'Set-Cookie': `still-auth=${token}; HttpOnly; SameSite=Lax; Max-Age=3600; Path=/`, 'Cache-Control': 'no-store' }); res.end('authenticated');
    });
  } else if (req.url === '/account') {
    const authenticated = (req.headers.cookie || '').split('; ').includes('still-auth=' + token);
    res.writeHead(authenticated ? 200 : 401, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify({ authenticated }));
  } else if (req.url === '/sw.js') {
    res.writeHead(200, { 'Content-Type': 'application/javascript', 'Cache-Control': 'no-store', 'Service-Worker-Allowed': '/' });
    res.end(`self.addEventListener('install',event=>{event.waitUntil(caches.open('still-shell').then(cache=>cache.add('/offline-app')).then(()=>self.skipWaiting()));});self.addEventListener('activate',event=>{event.waitUntil(self.clients.claim());});self.addEventListener('fetch',event=>{if(new URL(event.request.url).pathname==='/offline-app')event.respondWith(caches.open('still-shell').then(cache=>cache.match('/offline-app')));});`);
  } else if (req.url === '/offline-app') {
    offlineShellRequests++;
    res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' }); res.end(`<!doctype html><title>Still offline shell</title><body>${token}</body>`);
  } else if (req.url === '/asset') {
    assetRequests++;
    res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Cache-Control': 'public, max-age=86400' });
    res.end(asset);
  } else if (req.url === '/download') {
    res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Disposition': 'attachment; filename=still-download.bin' }); res.end(asset);
  } else if (['/page', '/history-a', '/history-b', '/session-second'].includes(req.url)) {
    res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
    res.end('<!doctype html><title>Owned Still cache fixture</title><body>Disposable local fixture</body>');
  } else { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}`;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const report = { productionSwiftAdapter: !!process.env.STILL_CHROME_SWIFT_RUNNER, schema: 1, sealedBundleVerified: provisioning.sealedBundleVerified, signatureVerification: provisioning.signatureVerification, nativeCodeSignatureObservations: provisioning.nativeCodeSignatureObservations, browserVersion: version, executableSHA256: digest(await readFile(browser)), node: process.version, githubSHA: process.env.GITHUB_SHA, githubRunID: process.env.GITHUB_RUN_ID, os: release(), architecture: arch(), sourceURL: provisioning.sourceURL, profiles: [], productionMutationSupported: false, limitations: ['No production inactivity or reopen-race closure', 'No saved password/autofill or download-history UI qualification; restored-tab/history result reported separately; offline navigation starts from online-controlled page', 'No enterprise policy, shared cache, minimum OS or Intel qualification', 'Background-network flags are not a network trace; no network absence claim'] };
let owned;
class CDP {
  constructor(ws) {
    this.ws = ws; this.next = 0; this.pending = new Map();
    ws.addEventListener('message', event => {
      const result = JSON.parse(event.data);
      const pending = this.pending.get(result.id);
      if (pending) { this.pending.delete(result.id); clearTimeout(pending.timer); result.error ? pending.reject(new Error(JSON.stringify(result.error))) : pending.resolve(result.result); }
    });
  }
  call(method, params = {}, sessionId) {
    return new Promise((resolve, reject) => {
      const id = ++this.next;
      const timer = setTimeout(() => { this.pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 15000);
      this.pending.set(id, { resolve, reject, timer });
      this.ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
  }
}
async function launch(profile, restore = false) {
  assert(!owned, 'Only one owned browser at a time');
  const portFile = join(userData, 'DevToolsActivePort');
  const { unlink } = await import('node:fs/promises');
  await unlink(portFile).catch(e => { if (e.code !== 'ENOENT') throw e; });
  const args = ['--enable-automation', '--headless=new', '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--disable-component-update', '--disable-sync', '--disable-extensions', '--disable-default-apps', '--metrics-recording-only', '--password-store=basic', '--use-mock-keychain', '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0', `--user-data-dir=${userData}`, `--profile-directory=${profile}`, 'about:blank'];
  if (restore) args.splice(-1, 0, '--restore-last-session');
  const priorCrashpad = process.env.STILL_CHROME_SWIFT_RUNNER ? crashpadBaseline(bundle) : null;
  const child = spawn(browser, args, { detached: true, stdio: ['ignore', 'ignore', 'pipe'], env: process.env.STILL_CHROME_SWIFT_RUNNER ? {...process.env,BREAKPAD_DUMP_LOCATION:join(userData,'Crashpad')} : process.env });
  owned = { child, pid: child.pid, stderr: '' };
  child.stderr.on('data', b => { owned && (owned.stderr = (owned.stderr + b.toString()).slice(-8000)); });
  let endpoint;
  for (let i = 0; i < 150; i++) {
    assert(child.exitCode === null, `Browser exited before CDP: ${owned.stderr}`);
    try { const [port, path] = (await readFile(portFile, 'utf8')).trim().split('\n'); endpoint = `ws://127.0.0.1:${port}${path}`; break; } catch (e) { if (e.code !== 'ENOENT') throw e; }
    await sleep(100);
  }
  assert(endpoint, 'Owned CDP endpoint absent');
  const ws = new WebSocket(endpoint);
  await new Promise((resolve, reject) => { ws.addEventListener('open', resolve, { once: true }); ws.addEventListener('error', reject, { once: true }); });
  const cdp = new CDP(ws);
  if (priorCrashpad) {
    owned.crashpadOwnership = await captureOwnedCrashpad(bundle,userData,priorCrashpad);
    assert(owned.crashpadOwnership.captured.length>0,'Expected an observed helper with exact synthetic crash database');
    (report.fixtureHelperCapture??=[]).push({profile,capturedCount:owned.crashpadOwnership.captured.length});
    report.fixtureCrashDatabaseContainment={environment:'BREAKPAD_DUMP_LOCATION',database:'owned/user-data/Crashpad',sourceRevision:'d0c02bfad08ec92a6ffcf989e53cd995e6381a4c',productionBehaviorClaim:false};
  }
  if (restore) {
    let targets = [];
    for (let i = 0; i < 50; i++) {
      targets = (await cdp.call('Target.getTargets')).targetInfos.filter(target => target.type === 'page');
      if (targets.some(target => target.url === origin + '/history-b') && targets.some(target => target.url === origin + '/session-second')) break;
      await sleep(100);
    }
    owned.restoration = { requested: true, restoredFixtureTabs: targets.filter(target => [origin + '/history-b', origin + '/session-second'].includes(target.url)).length, expectedFixtureTabs: 2 };
    const restored = targets.find(target => target.url === origin + '/history-b');
    if (restored) {
      const { sessionId: restoredSession } = await cdp.call('Target.attachToTarget', { targetId: restored.targetId, flatten: true });
      const history = await cdp.call('Page.getNavigationHistory', {}, restoredSession);
      const prior = history.entries.find(item => item.url === origin + '/history-a');
      if (prior) {
        await cdp.call('Page.navigateToHistoryEntry', { entryId: prior.id }, restoredSession);
        for (let i = 0; i < 50; i++) {
          const location = await cdp.call('Runtime.evaluate', { expression: 'location.href', returnByValue: true }, restoredSession).catch(() => null);
          if (location?.result.value === origin + '/history-a') { owned.restoration.persistedBackTraversal = true; break; }
          await sleep(100);
        }
      }
    }
    owned.restoration.status = owned.restoration.restoredFixtureTabs === 2 && owned.restoration.persistedBackTraversal ? 'restored-and-back-traversed' : 'unavailable-in-this-headless-experiment';
  }
  const { targetId } = await cdp.call('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await cdp.call('Target.attachToTarget', { targetId, flatten: true });
  await cdp.call('Page.enable', {}, sessionId);
  await cdp.call('Page.navigate', { url: `${origin}/page` }, sessionId);
  for (let i = 0; i < 100; i++) {
    const r = await cdp.call('Runtime.evaluate', { expression: 'location.href + ":" + document.readyState', returnByValue: true }, sessionId);
    if (r.result.value === `${origin}/page:complete`) break;
    await sleep(100);
    assert(i < 99, 'Page did not navigate to local fixture');
  }
  owned.cdp = cdp; owned.ws = ws; owned.sessionId = sessionId;
  return async expression => {
    const r = await cdp.call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId);
    assert(!r.exceptionDetails, JSON.stringify(r.exceptionDetails));
    return r.result.value;
  };
}
async function navigateOwned(url, evaluate) {
  await owned.cdp.call('Page.navigate', { url }, owned.sessionId);
  for (let i = 0; i < 100; i++) {
    const state = await evaluate('location.href + ":" + document.readyState').catch(() => null);
    if (state === url + ':complete') return;
    await sleep(100);
  }
  throw new Error('Owned page navigation did not complete');
}
async function closeOwned() {
  if (!owned) return;
  const current = owned;
  await current.cdp?.call('Browser.close').catch(() => {});
  for (let i = 0; i < 100 && current.child.exitCode === null; i++) await sleep(100);
  if (current.child.exitCode === null) { process.kill(-current.pid, 'SIGTERM'); await sleep(1000); }
  // Only our fresh detached process group can be terminated. Never search/kill by browser name.
  let groupExists = true;
  try { process.kill(-current.pid, 0); } catch (e) { if (e.code === 'ESRCH') groupExists = false; else throw e; }
  if (groupExists) { process.kill(-current.pid, 'SIGTERM'); await sleep(1000); }
  try { process.kill(-current.pid, 0); throw new Error('Owned browser/helper group remains active'); } catch (e) { if (e.code !== 'ESRCH') throw e; }
  if (current.crashpadOwnership) {
    const outcomes = await closeOwnedCrashpad(current.crashpadOwnership);
    (report.fixtureHelperTeardown ??= []).push(...outcomes);
  }
  current.ws?.close(); owned = undefined;
}
async function leaves(directory) {
  const result = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    assert(!entry.isSymbolicLink(), 'Cache link unsupported');
    if (entry.isDirectory()) result.push(...await leaves(path));
    else { assert(entry.isFile(), 'Only regular disposable cache leaves'); const s = await stat(path); assert.equal(s.nlink, 1); result.push({ path, dev: s.dev, ino: s.ino, size: s.size, mtimeMs: s.mtimeMs }); }
  }
  return result;
}
async function clearCache(cache) {
  if (process.env.STILL_CHROME_SWIFT_RUNNER) {
    assert(stable, 'Swift qualification requires actual Stable');
    const profile = cache.slice(userData.length + 1).split('/')[0];
    const args = ['--root', root, '--data', userData, '--bundle', bundle, '--profile', profile,
      '--journal', join(root, 'swift-journal-' + profile.replaceAll(' ', '-') + '.json')];
    try { return JSON.parse(execFileSync(process.env.STILL_CHROME_SWIFT_RUNNER, args, {encoding:'utf8', timeout:60000})); }
    catch (error) {
      const observed = JSON.parse(error.stdout?.toString() || '{}');
      report.lastSwiftFailure = observed;
      if (observed.reason?.includes('Quit Chrome')) throw new Error('browser or helper activity observed: ' + observed.reason);
      throw new Error(observed.reason || String(error));
    }
  }
  if (stable) {
    const args = [join(dirname(fileURLToPath(import.meta.url)), 'cache-group.py'), root, cache, bundle];
    const approval = execFileSync('python3', [...args, 'observe'], { encoding: 'utf8', timeout: 15000 });
    return JSON.parse(execFileSync('python3', [...args, 'clean'], { input: approval, encoding: 'utf8', timeout: 15000 }));
  }
  assert(!owned, 'Refuse while owned browser/helper activity or reopen is possible');
  const manifest = await leaves(cache);
  assert(manifest.length > 0, 'No genuine generated cache leaves');
  execFileSync('python3', [join(dirname(fileURLToPath(import.meta.url)), 'remove-owned-cache.py'), root, cache], { input: JSON.stringify(manifest), timeout: 15000 });
  return { leafCount: manifest.length, logicalBytes: manifest.reduce((a, b) => a + b.size, 0) };
}
const stateExpression = `(async () => { const db = await new Promise((r,j) => { const q=indexedDB.open('still-fixture',1); q.onupgradeneeded=()=>q.result.createObjectStore('kv'); q.onsuccess=()=>r(q.result); q.onerror=()=>j(q.error); }); const idb = await new Promise((r,j)=>{ const q=db.transaction('kv').objectStore('kv').get('key');q.onsuccess=()=>r(q.result);q.onerror=()=>j(q.error); }); db.close(); const c=await caches.open('still-offline');const hit=await c.match('/offline');return {cookie:document.cookie,local:localStorage.getItem('still'),idb,offline:hit?await hit.text():null};})()`;
try {
  for (const profile of ['Default', 'Profile 1']) {
    const entry = { profile, configuredRoot: 'owned/custom/configured-user-data', cacheGroup: `${profile}/Cache/Cache_Data` };
    const evaluate = await launch(profile);
    assert.equal(await evaluate('document.cookie + "|" + localStorage.getItem("still")'), '|null', 'Distinct native profile starts without prior profile state');
    const processes = await owned.cdp.call('SystemInfo.getProcessInfo');
    entry.observedOwnedProcesses = processes.processInfo.map(p => ({ type: p.type }));
    entry.protocolVersion = await owned.cdp.call('Browser.getVersion');
    await evaluate(`(async()=>{ document.cookie='still=${token}; Max-Age=3600; SameSite=Lax';localStorage.setItem('still','${token}');const db=await new Promise((r,j)=>{const q=indexedDB.open('still-fixture',1);q.onupgradeneeded=()=>q.result.createObjectStore('kv');q.onsuccess=()=>r(q.result);q.onerror=()=>j(q.error);});await new Promise((r,j)=>{const t=db.transaction('kv','readwrite');t.objectStore('kv').put('${token}','key');t.oncomplete=r;t.onerror=()=>j(t.error);});db.close();const c=await caches.open('still-offline');await c.put('/offline',new Response('${token}'));return true;})()`);
    assert.equal(await evaluate(`fetch('/login',{method:'POST',body:'credential=${token}'}).then(r=>r.status)`), 200);
    assert.equal(await evaluate(`fetch('/account').then(r=>r.json()).then(r=>r.authenticated)`), true);
    assert.equal(await evaluate(`document.cookie.includes('still-auth')`), false, 'Synthetic authentication cookie is genuinely HttpOnly');
    await evaluate(`navigator.serviceWorker.register('/sw.js').then(()=>navigator.serviceWorker.ready).then(()=>true)`);
    for (let i = 0; i < 100; i++) { if (await evaluate('!!navigator.serviceWorker.controller')) break; await sleep(100); assert(i < 99, 'Offline fixture service worker did not control page'); }
    const expected = { cookie: `still=${token}`, local: token, idb: token, offline: token };
    assert.deepEqual(await evaluate(stateExpression), expected);
    const downloadDirectory = join(root, 'downloads', profile);
    await mkdir(downloadDirectory, { recursive: true });
    await owned.cdp.call('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: downloadDirectory });
    await evaluate(`(()=>{const a=document.createElement('a');a.href='/download';a.download='still-download.bin';document.body.append(a);a.click();return true;})()`);
    const download = join(downloadDirectory, 'still-download.bin');
    let downloaded = false;
    for (let i = 0; i < 100; i++) { try { if (digest(await readFile(download)) === digest(asset)) { downloaded = true; break; } } catch (e) { if (e.code !== 'ENOENT') throw e; } await sleep(100); }
    assert(downloaded, 'Actual disposable browser download must finish');
    const before = assetRequests;
    assert.equal(await evaluate(`fetch('/asset').then(r=>r.arrayBuffer()).then(b=>b.byteLength)`), asset.length);
    assert.equal(assetRequests, before + 1, 'First asset must reach owned HTTP server');
    const cache = join(userData, profile, 'Cache', 'Cache_Data');
    await assert.rejects(clearCache(cache), /Refuse while owned|browser or helper activity observed/);
    entry.activeRefusal = true;
    await closeOwned();
    entry.generated = { leafCount: (await leaves(cache)).length };
    assert(entry.generated.leafCount > 0);
    const warm = await launch(profile);
    assert.deepEqual(await warm(stateExpression), expected, 'Native persisted site state after first relaunch');
    await warm(`fetch('/asset').then(r=>r.arrayBuffer()).then(b=>b.byteLength)`);
    assert.equal(assetRequests, before + 1, 'Warm relaunch should serve asset from genuine disk cache');
    await assert.rejects(clearCache(cache), /Refuse while owned|browser or helper activity observed/); entry.reopenRefusal = true;
    await navigateOwned(origin + '/history-a', warm);
    await navigateOwned(origin + '/history-b', warm);
    const beforeHistory = await owned.cdp.call('Page.getNavigationHistory', {}, owned.sessionId);
    assert(beforeHistory.entries.some(item => item.url === origin + '/history-a'), 'Genuine page history must contain earlier fixture page');
    const second = await owned.cdp.call('Target.createTarget', { url: origin + '/session-second' });
    assert(second.targetId);
    const { sessionId: secondSession } = await owned.cdp.call('Target.attachToTarget', { targetId: second.targetId, flatten: true });
    let secondComplete = false;
    for (let i = 0; i < 100; i++) {
      const page = await owned.cdp.call('Runtime.evaluate', { expression: 'location.href + ":" + document.readyState', returnByValue: true }, secondSession).catch(() => null);
      if (page?.result.value === origin + '/session-second:complete') { secondComplete = true; break; }
      await sleep(100);
    }
    assert(secondComplete, 'Second session fixture tab must finish genuine navigation before browser close');
    entry.secondSessionTabCompleteBeforeClose = true;
    entry.preCleanupNavigationHistoryCreated = true;
    await closeOwned();
    // Browser-created protected files only: snapshot immediately around our closed-cache removal.
    const protectedPaths = ['Network/Cookies', 'Cookies', 'History', 'Login Data', 'Web Data', 'Preferences'];
    const snapshots = new Map();
    for (const relative of protectedPaths) {
      try { snapshots.set(relative, digest(await readFile(join(userData, profile, relative)))); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    entry.removed = await clearCache(cache);
    for (const [relative, hash] of snapshots) assert.equal(digest(await readFile(join(userData, profile, relative))), hash, 'Protected browser file changed during cache removal');
    assert.equal(digest(await readFile(download)), digest(asset), 'Actual downloaded file preserved');
    entry.downloadedFilePreserved = true;
    entry.protectedFileNames = [...snapshots.keys()]; entry.protectedBytesUnchangedDuringRemoval = true;
    const reopened = await launch(profile, true);
    entry.restoredSessionObservation = owned.restoration;
    assert.equal(await reopened(`fetch('/account').then(r=>r.json()).then(r=>r.authenticated)`), true, 'Synthetic HttpOnly-authenticated website session survives without logging in again');
    entry.httpOnlyAuthenticatedWebsiteSessionPreserved = true;
    for (let i = 0; i < 100; i++) { if (await reopened('!!navigator.serviceWorker.controller')) break; await sleep(100); assert(i < 99, 'Persisted service worker did not control page'); }
    const shellRequestsBeforeOffline = offlineShellRequests;
    await owned.cdp.call('Network.enable', {}, owned.sessionId);
    await owned.cdp.call('Network.emulateNetworkConditions', { offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0 }, owned.sessionId);
    try {
      await navigateOwned(origin + '/offline-app', reopened);
      assert.equal(await reopened('document.title'), 'Still offline shell');
      assert.equal(await reopened('document.body.textContent'), token);
      assert.equal(offlineShellRequests, shellRequestsBeforeOffline, 'Offline navigation must not request fixture shell from server');
      entry.serviceWorkerOfflineNavigationPreserved = true;
    } finally {
      await owned.cdp.call('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 }, owned.sessionId);
    }
    await navigateOwned(origin + '/page', reopened);
    assert.deepEqual(await reopened(stateExpression), expected, 'Cookie/localStorage/IDB/offline response must survive cache removal and genuine relaunch');
    assert.equal(await reopened(`fetch('/asset').then(r=>r.arrayBuffer()).then(b=>b.byteLength)`), asset.length);
    assert.equal(assetRequests, before + 2, 'Cleared asset must be fetched again from fixture server');
    await closeOwned();
    entry.regenerated = { leafCount: (await leaves(cache)).length };
    assert(entry.regenerated.leafCount > 0); entry.relaunchProtectedStatePassed = true;
    report.profiles.push(entry);
  }
  if (stable) {
    assert.equal(digest(await readFile(browser)), provisioning.executableSHA256);
    execFileSync('/usr/bin/codesign', ['--verify', '--deep', '--strict', bundle], { timeout: 90000 });
    report.postRunVendorSignatureVerified = true;
    report.limitations[0] = 'Native observations are not a lease: residual reopen/write/final-name-operation races accepted for bounded cache-only model';
  }
  report.passed = true;
} finally {
  await closeOwned(); server.close();
  await mkdir(dirname(resolve(outputArg)), { recursive: true });
  await writeFile(resolve(outputArg), JSON.stringify(report, null, 2) + '\n');
  // No recursive deletion of profiles here. Ephemeral runner owns final disposal.
}
console.log(JSON.stringify({ passed: report.passed, profiles: report.profiles.length, productionMutationSupported: false }));
