// Hosted-only genuine Chrome UI qualification. No direct password DB, preference or Keychain manipulation.
import assert from 'node:assert/strict';
import {crashpadBaseline,captureOwnedCrashpad,closeOwnedCrashpad} from './owned-crashpad.mjs';
import {spawn, execFileSync} from 'node:child_process';
import {readFile, writeFile, mkdtemp, mkdir, unlink, realpath} from 'node:fs/promises';
import {join, dirname} from 'node:path';
import {tmpdir, release} from 'node:os';
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
assert.equal(process.env.GITHUB_ACTIONS, 'true');
assert.equal(process.env.RUNNER_ENVIRONMENT, 'github-hosted');
assert.equal(process.platform, 'darwin');
const [provisionPath, output] = process.argv.slice(2);
const provision = JSON.parse(await readFile(provisionPath, 'utf8'));
assert(provision.provisioningComplete && provision.sealedBundleVerified);
const bundle = await realpath(provision.bundle), browser = join(bundle, 'Contents/MacOS/Google Chrome');
assert(browser.includes('/expanded/') && !browser.startsWith('/Applications/'));
assert.equal(createHash('sha256').update(await readFile(browser)).digest('hex'), provision.executableSHA256);
const root = await realpath(await mkdtemp(join(tmpdir(), 'StillChromeProbe-'))), userData = join(root, 'headed-data');
await mkdir(userData); const downloads = join(root, 'downloads'); await mkdir(downloads);
const sleep = ms => new Promise(r=>setTimeout(r,ms));
const report = {productionSwiftAdapter:!!process.env.STILL_CHROME_SWIFT_RUNNER,source:process.env.GITHUB_SHA,run:process.env.GITHUB_RUN_ID,version:provision.version,os:release(),headed:true,mockKeychain:false,automationFlag:false,checks:{},limitations:['Saved-address record retention is observed through normal settings Edit fields and Web Data hash, not universal form-fill support; prior original native keyboard form acceptance failed before cleanup'],productionMutationSupported:false};
const save = ()=>writeFile(output, JSON.stringify(report,null,2)+'\n');
const server = createServer((req,res)=>{
  if(req.url==='/asset'){res.writeHead(200,{'Cache-Control':'public, max-age=86400'});res.end('genuine-owned-asset'.repeat(10000));}
  else if(req.url==='/download'){res.writeHead(200,{'Content-Disposition':'attachment; filename=still-headed.txt'});res.end('owned synthetic download');}
  else {res.writeHead(200,{'Content-Type':'text/html','Cache-Control':'no-store'});res.end('<!doctype html><title>Still synthetic form</title><form method="post" action="/signed-in"><input id="user" name="username" autocomplete="username"><input id="pass" name="password" type="password" autocomplete="current-password"><button>Sign in</button></form><form><input id="name" name="name" autocomplete="name"><input id="street" name="street-address" autocomplete="street-address"><input id="city" name="address-level2" autocomplete="address-level2"><input id="postal" name="postal-code" autocomplete="postal-code"></form><a id="download" href="/download">Download</a>');}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r)); const origin=`http://127.0.0.1:${server.address().port}`;
let owned, ws, cdp, session;
class CDP {constructor(ws){this.ws=ws;this.id=0;this.pending=new Map();ws.addEventListener('message',e=>{const r=JSON.parse(e.data),p=this.pending.get(r.id);if(p){clearTimeout(p.t);this.pending.delete(r.id);r.error?p.j(new Error(JSON.stringify(r.error))):p.r(r.result);}});}call(method,params={},sessionId){return new Promise((r,j)=>{const id=++this.id,t=setTimeout(()=>{this.pending.delete(id);j(new Error('CDP timeout '+method));},10000);this.pending.set(id,{r,j,t});this.ws.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));});}}
async function launch(){
 await unlink(join(userData,'DevToolsActivePort')).catch(e=>{if(e.code!=='ENOENT')throw e;});
 const priorCrashpad=process.env.STILL_CHROME_SWIFT_RUNNER?crashpadBaseline(bundle):null;
 owned=spawn(browser,['--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-component-update','--remote-debugging-address=127.0.0.1','--remote-debugging-port=0',`--user-data-dir=${userData}`,'about:blank'],{detached:true,stdio:['ignore','ignore','pipe']});
 let stderr='';owned.stderr.on('data',b=>{stderr=(stderr+b).slice(-4000);});let endpoint;
 for(let i=0;i<150;i++){assert.equal(owned.exitCode,null,stderr);try{const [p,s]=(await readFile(join(userData,'DevToolsActivePort'),'utf8')).trim().split('\n');endpoint=`ws://127.0.0.1:${p}${s}`;break;}catch(e){if(e.code!=='ENOENT')throw e;}await sleep(100);}
 assert(endpoint,'headed debug endpoint unavailable');ws=new WebSocket(endpoint);await new Promise((r,j)=>{ws.addEventListener('open',r,{once:true});ws.addEventListener('error',j,{once:true});});cdp=new CDP(ws);
 const {targetId}=await cdp.call('Target.createTarget',{url:'about:blank'});({sessionId:session}=await cdp.call('Target.attachToTarget',{targetId,flatten:true}));await cdp.call('Page.enable',{},session);
 if(priorCrashpad)owned.crashpadOwnership=await captureOwnedCrashpad(bundle,userData,priorCrashpad);
}
const evaluate=async expression=>{const r=await cdp.call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},session);if(r.exceptionDetails)throw new Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
async function navigate(url){await cdp.call('Page.navigate',{url},session);for(let i=0;i<80;i++){if(await evaluate('location.href+":"+document.readyState').catch(()=>null)===url+':complete')return;await sleep(100);}throw new Error('navigation incomplete '+url);}
// Traverse public rendered DOM/shadow DOM only; never Chrome's private service APIs.
const deep=`function all(root=document){return [...root.querySelectorAll('*')].flatMap(e=>[e,...(e.shadowRoot?all(e.shadowRoot):[])]);}function visible(e){return !!e.getClientRects().length&&!e.disabled;}`;
async function inspect(label){const data=await evaluate(`(()=>{${deep}return all().filter(e=>visible(e)&&(['INPUT','TEXTAREA','BUTTON','CR-BUTTON','SELECT'].includes(e.tagName))).map(e=>({tag:e.tagName,id:e.id,type:e.type,label:e.getAttribute('aria-label'),placeholder:e.placeholder,text:e.innerText?.slice(0,160)}));})()`);report[label]=data;await save();return data;}
async function clickText(text){const ok=await evaluate(`(()=>{${deep}const e=all().find(e=>visible(e)&&['BUTTON','CR-BUTTON'].includes(e.tagName)&&e.innerText.trim()===${JSON.stringify(text)});if(e)e.click();return !!e;})()`);assert(ok,'UI button absent: '+text);await sleep(400);}
async function field(match,value){const ok=await evaluate(`(()=>{${deep}const e=all().find(e=>visible(e)&&['INPUT','TEXTAREA'].includes(e.tagName)&&${match});if(!e)return false;e.focus();return true;})()`);assert(ok,'UI field absent: '+match);await cdp.call('Input.insertText',{text:value},session);}
async function close(){if(!owned)return;await cdp?.call('Browser.close').catch(()=>{});for(let i=0;i<100&&owned.exitCode===null;i++)await sleep(100);if(owned.exitCode===null){process.kill(-owned.pid,'SIGTERM');await sleep(1000);}assert(owned.exitCode!==null,'owned browser did not close');if(owned.crashpadOwnership){const outcomes=await closeOwnedCrashpad(owned.crashpadOwnership);(report.fixtureHelperTeardown??=[]).push(...outcomes);}ws?.close();owned=undefined;}
async function key(key,code,virtual){for(const type of ['keyDown','keyUp'])await cdp.call('Input.dispatchKeyEvent',{type,key,code,windowsVirtualKeyCode:virtual,nativeVirtualKeyCode:({ArrowDown:0x7D,Enter:0x24,Tab:0x30})[key]},session);}
async function savedAddress(phase){
 await navigate('chrome://settings/contactInfo');await sleep(700);await inspect(phase+'AddressSettingsControls');
 const opened=await evaluate(`(()=>{${deep}const buttons=all().filter(e=>visible(e)&&e.matches('cr-icon-button.address-menu'));if(buttons.length!==1)return false;buttons[0].click();return true;})()`);
 assert(opened,'Exactly one normal saved-address menu required');await sleep(300);await clickText('Edit');
 const record=await evaluate(`(()=>{${deep}const inputs=all().filter(e=>visible(e)&&['INPUT','TEXTAREA'].includes(e.tagName));return Object.fromEntries(inputs.filter(e=>['Name','Street address','City','State','ZIP code'].includes(e.getAttribute('aria-label'))).map(e=>[e.getAttribute('aria-label'),e.value]));})()`);
 report[phase+'SavedAddressRecord']=record;
 execFileSync('/usr/sbin/screencapture',['-x',output.replace(/\.json$/,'.'+phase+'-saved-address.png')],{timeout:5000});
 await clickText('Cancel');await save();
 assert.deepEqual(record,{'Name':'Still Synthetic','Street address':'123 Example Street','City':'Exampleville','State':'CA','ZIP code':'94043'},'Normal Edit dialog must retain actual synthetic address');
 return true;
}

try {
 await launch();await navigate('chrome://version/');report.profileVersionText=await evaluate('document.body.innerText');assert(report.profileVersionText.includes(userData));report.checks.browserOwnedProfilePath=true;
 await navigate('chrome://password-manager/passwords');await sleep(1000);await inspect('passwordUIBefore');await clickText('Add');await inspect('passwordAddDialog');
 await field("(e.id+' '+e.getAttribute('aria-label')+' '+e.placeholder).match(/website|site/i)",origin);
 await field("(e.id+' '+e.getAttribute('aria-label')+' '+e.placeholder).match(/username/i)",'still-synthetic');
 await field("e.type==='password'",'StillSynthetic-Password-42');await clickText('Save');await sleep(700);report.checks.passwordSavedViaBrowserUI=await evaluate(`(()=>{${deep}return all().some(e=>visible(e)&&e.innerText?.includes('127.0.0.1'));})()`);assert(report.checks.passwordSavedViaBrowserUI);
 await navigate('chrome://settings/contactInfo');await sleep(700);await inspect('addressUIBefore');await clickText('Add');await inspect('addressAddDialog');
 // Fill only synthetic address fields through rendered controls and normal input events.
 await field("(e.id+' '+e.getAttribute('aria-label')).match(/name/i)",'Still Synthetic');
 await field("(e.id+' '+e.getAttribute('aria-label')).match(/address.*line|street/i)",'123 Example Street');
 await field("(e.id+' '+e.getAttribute('aria-label')).match(/city/i)",'Exampleville');
 await field("(e.id+' '+e.getAttribute('aria-label')).match(/^input State$/i)",'CA');
 await field("(e.id+' '+e.getAttribute('aria-label')).match(/zip|postal/i)",'94043');await clickText('Save');report.checks.addressSavedViaBrowserUI=true;
 report.checks.savedAddressRecordBeforeCleanup=await savedAddress('before');await navigate(origin+'/form');await evaluate("fetch('/asset').then(r=>r.text())");await cdp.call('Browser.setDownloadBehavior',{behavior:'allow',downloadPath:downloads});await evaluate("document.querySelector('#download').click()");for(let i=0;i<80;i++){try{if((await readFile(join(downloads,'still-headed.txt'),'utf8'))==='owned synthetic download')break;}catch{}await sleep(100);}assert.equal(await readFile(join(downloads,'still-headed.txt'),'utf8'),'owned synthetic download');
 await close();const webData=join(userData,'Default/Web Data');report.webDataBeforeSHA256=createHash('sha256').update(await readFile(webData)).digest('hex');const cache=join(userData,'Default/Cache/Cache_Data'),args=['Validation/ChromeProbe/cache-group.py',root,cache,bundle];const approval=execFileSync('python3',[...args,'observe'],{encoding:'utf8'});report.cleanup=process.env.STILL_CHROME_SWIFT_RUNNER
 ? JSON.parse(execFileSync(process.env.STILL_CHROME_SWIFT_RUNNER,['--root',root,'--data',userData,'--bundle',bundle,'--profile','Default','--journal',join(root,'swift-journal-headed.json')],{encoding:'utf8',timeout:60000}))
 : JSON.parse(execFileSync('python3',[...args,'clean'],{input:approval,encoding:'utf8'}));assert.equal(report.cleanup.status,'completed');assert(report.cleanup.removed>0);report.webDataAfterSHA256=createHash('sha256').update(await readFile(webData)).digest('hex');report.checks.webDataUnchangedAroundCleanup=report.webDataBeforeSHA256===report.webDataAfterSHA256;assert(report.checks.webDataUnchangedAroundCleanup);
 await launch();await navigate(origin+'/form');await sleep(1000);
 await evaluate("document.querySelector('#user').focus()");await key('ArrowDown','ArrowDown',40);await key('Enter','Enter',13);await sleep(500);
 report.checks.savedPasswordFilledAfterCleanup=await evaluate("document.querySelector('#user').value==='still-synthetic'&&document.querySelector('#pass').value==='StillSynthetic-Password-42'");
 report.checks.savedAddressRecordAfterCleanup=await savedAddress('after');
 await navigate('chrome://downloads/');await sleep(700);report.checks.downloadHistoryVisibleAfterCleanup=await evaluate(`(()=>{${deep}return all().some(e=>visible(e)&&e.innerText?.includes('still-headed.txt'));})()`);report.checks.downloadFilePreserved=(await readFile(join(downloads,'still-headed.txt'),'utf8'))==='owned synthetic download';
 for(const [check,value]of Object.entries(report.checks))assert.equal(value,true,check);report.outcome='headed-protected-semantics-passed';
}catch(error){report.outcome='headed-protected-semantics-unavailable';report.error=String(error);if(cdp&&owned){await inspect('failureRenderedControls').catch(()=>{});await cdp.call('Page.captureScreenshot',{},session).then(r=>writeFile(output.replace(/\.json$/,'.png'),Buffer.from(r.data,'base64'))).catch(()=>{});}try{execFileSync('/usr/sbin/screencapture',['-x',output.replace(/\.json$/,'.desktop.png')],{timeout:5000});}catch{}process.exitCode=1;}
finally{await save();await close().catch(e=>{report.teardownError=String(e);process.exitCode=1;});server.close();execFileSync('/usr/bin/codesign',['--verify','--deep','--strict',bundle]);await save();}
