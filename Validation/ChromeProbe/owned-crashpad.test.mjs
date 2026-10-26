import test from 'node:test';
import assert from 'node:assert/strict';
import { qualifiesCrashpad, sameCrashpad, captureOwnedCrashpad, closeOwnedCrashpad } from './owned-crashpad.mjs';
const scope={bundle:'/runner/Chrome.app',userData:'/tmp/StillChromeProbe-owned/data',uid:501,priorPIDs:new Set([9])};
const observed={pid:10,uid:501,started:'Mon Oct 26 03:40:00 2026',executable:'/runner/Chrome.app/Contents/Frameworks/Version/Helpers/chrome_crashpad_handler',command:'/runner/Chrome.app/Contents/Frameworks/Version/Helpers/chrome_crashpad_handler --database=/tmp/StillChromeProbe-owned/data/Crashpad --url=https://example.invalid'};
test('only a new exact synthetic-root helper gains fixture teardown authority',()=>{
 assert(qualifiesCrashpad(observed,scope));
 for(const changed of [{pid:9},{uid:502},{executable:'/other/Chrome.app/chrome_crashpad_handler'},{command:observed.command.replace('/data/Crashpad','/other/Crashpad')},{command:observed.command.replace('/Crashpad ','/Crashpad-extra ')},{command:observed.command+' --database=/another/Crashpad'}])assert(!qualifiesCrashpad({...observed,...changed},scope));
});
test('reused or changed helper identity refuses teardown',()=>{
 assert(sameCrashpad(observed,{...observed},scope));
 for(const changed of [{pid:11},{uid:502},{started:'Mon Oct 26 03:40:01 2026'},{executable:'/other/chrome_crashpad_handler'},{command:'unrelated'}])assert(!sameCrashpad(observed,{...observed,...changed},scope));
});

test('fixture lifecycle rejects non-hosted context before process inspection',async()=>{
 const prior=process.env.GITHUB_ACTIONS;process.env.GITHUB_ACTIONS='false';
 try{await assert.rejects(captureOwnedCrashpad('/unowned/Chrome.app','/unowned/data',new Set()));await assert.rejects(closeOwnedCrashpad(undefined));}
 finally{if(prior===undefined)delete process.env.GITHUB_ACTIONS;else process.env.GITHUB_ACTIONS=prior;}
});
