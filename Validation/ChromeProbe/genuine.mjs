// Genuine disposable-browser qualification, never a production cleanup API.
import { spawn, execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, stat, readdir, realpath, statfs } from 'node:fs/promises';
import { createHash, randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { tmpdir, release, arch } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

// Hosted-only: no installed browser, personal profile, OS settings or permissions.
assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Run on an ephemeral GitHub-hosted macOS runner only');
assert.equal(process.env.RUNNER_ENVIRONMENT, 'github-hosted', 'Persistent/self-hosted runners are not supported');
assert.equal(process.platform, 'darwin');
assert.equal(arch(), 'arm64');
const [browserArg, outputArg] = process.argv.slice(2);
assert(browserArg && outputArg, 'usage: node genuine.mjs /owned/CfT/binary /owned/report.json');
const browser = await realpath(resolve(browserArg));
assert(browser.includes('/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/'), 'Explicit downloaded CfT bundle required');
assert(!browser.startsWith('/Applications/'));
const disk = await statfs(tmpdir());
assert(disk.bavail * disk.bsize > 1024 ** 3, 'At least 1 GiB free required');
const expectedVersion = '156.0.8078.47';
const version = execFileSync(browser, ['--version'], { encoding: 'utf8', timeout: 10000 }).trim();
assert(version.includes(expectedVersion), `Unexpected browser version: ${version}`);
const bundle = browser.slice(0, browser.indexOf('.app/') + 4);
execFileSync('/usr/bin/codesign', ['--verify', '--deep', '--strict', bundle], { timeout: 30000 });

const root = await realpath(await mkdtemp(join(tmpdir(), 'StillChromeProbe-')));
const userData = join(root, 'custom', 'configured-user-data');
await mkdir(userData, { recursive: true });
const digest = x => createHash('sha256').update(x).digest('hex');
const token = randomBytes(16).toString('hex');
const asset = randomBytes(512 * 1024);
let assetRequests = 0;
const server = createServer((req, res) => {
  if (req.url === '/asset') {
    assetRequests++;
    res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Cache-Control': 'public, max-age=86400' });
    res.end(asset);
  } else if (req.url === '/page') {
    res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
    res.end('<!doctype html><title>Owned Still cache fixture</title><body>Disposable local fixture</body>');
  } else { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}`;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const report = { schema: 1, codeSignatureVerified: true, browserVersion: version, executableSHA256: digest(await readFile(browser)), os: release(), architecture: arch(), sourceURL: `https://storage.googleapis.com/chrome-for-testing-public/${expectedVersion}/mac-arm64/chrome-mac-arm64.zip`, profiles: [], productionMutationSupported: false, limitations: ['No production inactivity or reopen-race closure', 'No credentials/autofill/download/history/session-tab semantic qualification', 'No enterprise policy, shared cache, minimum OS or Intel qualification', 'Background-network flags are not a network trace; no network absence claim'] };
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
async function launch(profile) {
  assert(!owned, 'Only one owned browser at a time');
  const portFile = join(userData, 'DevToolsActivePort');
  const { unlink } = await import('node:fs/promises');
  await unlink(portFile).catch(e => { if (e.code !== 'ENOENT') throw e; });
  const args = ['--enable-automation', '--headless=new', '--no-first-run', '--no-default-browser-check', '--disable-background-networking', '--disable-component-update', '--disable-sync', '--disable-extensions', '--disable-default-apps', '--metrics-recording-only', '--password-store=basic', '--use-mock-keychain', '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0', `--user-data-dir=${userData}`, `--profile-directory=${profile}`, 'about:blank'];
  const child = spawn(browser, args, { detached: true, stdio: ['ignore', 'ignore', 'pipe'] });
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
  owned.cdp = cdp; owned.ws = ws;
  return async expression => {
    const r = await cdp.call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }, sessionId);
    assert(!r.exceptionDetails, JSON.stringify(r.exceptionDetails));
    return r.result.value;
  };
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
    const expected = { cookie: `still=${token}`, local: token, idb: token, offline: token };
    assert.deepEqual(await evaluate(stateExpression), expected);
    const before = assetRequests;
    assert.equal(await evaluate(`fetch('/asset').then(r=>r.arrayBuffer()).then(b=>b.byteLength)`), asset.length);
    assert.equal(assetRequests, before + 1, 'First asset must reach owned HTTP server');
    const cache = join(userData, profile, 'Cache', 'Cache_Data');
    await assert.rejects(clearCache(cache), /Refuse while owned/);
    entry.activeRefusal = true;
    await closeOwned();
    entry.generated = { leafCount: (await leaves(cache)).length };
    assert(entry.generated.leafCount > 0);
    const warm = await launch(profile);
    assert.deepEqual(await warm(stateExpression), expected, 'Native persisted site state after first relaunch');
    await warm(`fetch('/asset').then(r=>r.arrayBuffer()).then(b=>b.byteLength)`);
    assert.equal(assetRequests, before + 1, 'Warm relaunch should serve asset from genuine disk cache');
    await assert.rejects(clearCache(cache), /Refuse while owned/); entry.reopenRefusal = true;
    await closeOwned();
    // Browser-created protected files only: snapshot immediately around our closed-cache removal.
    const protectedPaths = ['Network/Cookies', 'Cookies', 'History', 'Login Data', 'Web Data', 'Preferences'];
    const snapshots = new Map();
    for (const relative of protectedPaths) {
      try { snapshots.set(relative, digest(await readFile(join(userData, profile, relative)))); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    entry.removed = await clearCache(cache);
    for (const [relative, hash] of snapshots) assert.equal(digest(await readFile(join(userData, profile, relative))), hash, 'Protected browser file changed during cache removal');
    entry.protectedFileNames = [...snapshots.keys()]; entry.protectedBytesUnchangedDuringRemoval = true;
    const reopened = await launch(profile);
    assert.deepEqual(await reopened(stateExpression), expected, 'Cookie/localStorage/IDB/offline response must survive cache removal and genuine relaunch');
    assert.equal(await reopened(`fetch('/asset').then(r=>r.arrayBuffer()).then(b=>b.byteLength)`), asset.length);
    assert.equal(assetRequests, before + 2, 'Cleared asset must be fetched again from fixture server');
    await closeOwned();
    entry.regenerated = { leafCount: (await leaves(cache)).length };
    assert(entry.regenerated.leafCount > 0); entry.relaunchProtectedStatePassed = true;
    report.profiles.push(entry);
  }
  report.passed = true;
} finally {
  await closeOwned(); server.close();
  await mkdir(dirname(resolve(outputArg)), { recursive: true });
  await writeFile(resolve(outputArg), JSON.stringify(report, null, 2) + '\n');
  // No recursive deletion of profiles here. Ephemeral runner owns final disposal.
}
console.log(JSON.stringify({ passed: report.passed, profiles: report.profiles.length, productionMutationSupported: false }));
