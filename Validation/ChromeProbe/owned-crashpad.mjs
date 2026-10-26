// Disposable hosted fixture lifecycle only. Never imported by the application.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {realpath,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const processOptions={encoding:'utf8',timeout:5000,env:{...process.env,LC_ALL:'C',LANG:'C'}};
export function qualifiesCrashpad(row,scope){
 if(!row||!Number.isInteger(row.pid)||row.pid<=0||row.uid!==scope.uid||scope.priorPIDs.has(row.pid)||!row.started)return false;
 if(!row.executable.startsWith(scope.bundle+'/')||!row.executable.endsWith('/chrome_crashpad_handler'))return false;
 if(/\s/.test(scope.userData))return false; // generated fixture roots have no whitespace
 const database='--database='+scope.userData+'/Crashpad';
 const args=row.command.split(/\s+/);
 return args.filter(arg=>arg.startsWith('--database=')).length===1&&args.includes(database);
}
export function sameCrashpad(prior,current,scope){
 return qualifiesCrashpad(current,scope)&&['pid','uid','started','executable'].every(key=>prior[key]===current[key]);
}
function hosted(){
 assert.equal(process.env.GITHUB_ACTIONS,'true');assert.equal(process.env.RUNNER_ENVIRONMENT,'github-hosted');assert.equal(process.platform,'darwin');
}
async function ownedScope(bundle,userData){
 const runner=await realpath(process.env.RUNNER_TEMP);
 assert(bundle.startsWith(runner+'/')&&bundle.endsWith('/Google Chrome.app'),'Extracted runner Stable bundle required');
 const temporary=await realpath(tmpdir());
 assert(userData.startsWith(temporary+'/StillChromeProbe-'),'Owned synthetic user-data root required');
 const parts=userData.slice(temporary.length+1).split('/');
 assert(parts.length>1&&parts[0].startsWith('StillChromeProbe-')&&!parts.includes('..'));
 const root=join(temporary,parts[0]);const info=await stat(root);
 assert(info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0,'Unsafe synthetic owner root');
 assert.equal(await realpath(bundle),bundle);assert.equal(await realpath(userData),userData);
}
function parseRows(text){
 return text.split('\n').filter(line=>line.trim()).map(line=>{
  const match=line.match(/^\s*(\d+)\s+(\d+)\s+(\w{3}\s+\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+(.+)$/);
  assert(match,'Process identity observation was not parseable');
  return {pid:Number(match[1]),uid:Number(match[2]),started:match[3].replace(/\s+/g,' '),executable:match[4].trim()};
 });
}
function rows(pid){
 try{return parseRows(execFileSync('/bin/ps',['-ww',...(pid?['-p',String(pid)]:['-a','-x']),'-o','pid=,uid=,lstart=,comm='],{...processOptions,maxBuffer:2*1024*1024}));}
 catch(error){if(pid&&error.status===1&&!error.stdout?.toString().trim())return [];throw error;}
}
function command(pid){
 try{return execFileSync('/bin/ps',['-ww','-p',String(pid),'-o','command='],{...processOptions,maxBuffer:1024*1024}).trim();}
 catch(error){if(error.status===1)return null;throw error;}
}
export function crashpadBaseline(bundle){
 hosted();return new Set(rows().filter(row=>row.executable.startsWith(bundle+'/')&&row.executable.endsWith('/chrome_crashpad_handler')).map(row=>row.pid));
}
export async function captureOwnedCrashpad(bundle,userData,priorPIDs){
 hosted();await ownedScope(bundle,userData);
 const scope={bundle,userData,priorPIDs,uid:process.getuid()};
 const captured=[];
 for(const row of rows().filter(row=>row.executable.startsWith(bundle+'/')&&row.executable.endsWith('/chrome_crashpad_handler'))){
  const argumentsText=command(row.pid);if(argumentsText===null)continue;
  const observed={...row,command:argumentsText};
  if(qualifiesCrashpad(observed,scope)){
   assert.equal(await realpath(observed.executable),observed.executable,'Helper executable must have physical bundle provenance');captured.push(observed);
  }
 }
 return {scope,captured};
}
export async function closeOwnedCrashpad(ownership){
 hosted();if(!ownership)return [];
 const {scope,captured}=ownership;await ownedScope(scope.bundle,scope.userData);const results=[];
 for(const prior of captured){
  let current;
  const observe=()=>{const row=rows(prior.pid)[0];if(!row)return null;const args=command(prior.pid);return args===null?null:{...row,command:args};};
  for(let attempt=0;attempt<20;attempt++){current=observe();if(!current)break;assert(sameCrashpad(prior,current,scope),'Captured helper identity changed; no termination permitted');await sleep(100);}
  if(!current){results.push({pid:prior.pid,outcome:'exited-naturally'});continue;}
  current=observe();if(!current){results.push({pid:prior.pid,outcome:'exited-naturally'});continue;}
  assert(sameCrashpad(prior,current,scope),'Captured helper identity changed before fixture shutdown');
  assert.equal(await realpath(current.executable),current.executable);
  process.kill(prior.pid,'SIGTERM'); // ordinary signal, exact proven synthetic helper only
  let gone=false;
  for(let attempt=0;attempt<50;attempt++){if(!observe()){gone=true;break;}await sleep(100);}
  assert(gone,'Owned crashpad fixture helper remained active after SIGTERM; cleanup must not run');
  results.push({pid:prior.pid,outcome:'fixture-helper-sigterm-and-exit'});
 }
 return results;
}
