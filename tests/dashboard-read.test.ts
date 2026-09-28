import test from 'node:test';
import assert from 'node:assert/strict';
import {createDashboardReader} from '../src/application/dashboard-read';
import {DataUnavailable} from '../src/domain/models';
import {AircraftC5Invalid} from '../src/domain/aircraft-c5';

test('dashboard limits simultaneous reads without dropping results',async()=>{
 const read=createDashboardReader(4);let active=0,peak=0;
 const result=await Promise.all(Array.from({length:32},(_,i)=>read(async()=>{
   active++;peak=Math.max(peak,active);await new Promise(resolve=>setTimeout(resolve,2));active--;return i;
 })));
 assert.equal(peak,4);assert.deepEqual(result,Array.from({length:32},(_,i)=>i));
});
test('temporary failure retries only the failed read',async()=>{
 const read=createDashboardReader();let calls=0;
 assert.equal(await read(async()=>{if(++calls===1)throw new DataUnavailable();return 'configured';}),'configured');
 assert.equal(calls,2);
});
test('persistent failure is not returned as missing configuration',async()=>{
 const read=createDashboardReader(1);let calls=0;
 await assert.rejects(read(async()=>{calls++;throw new DataUnavailable();}),DataUnavailable);
 assert.equal(calls,2);assert.equal(await read(async()=>123),123);
});
test('known missing prerequisites can still be assessed as incomplete',async()=>{
 assert.equal(await createDashboardReader()(async()=>{throw new AircraftC5Invalid('Complete C1 first');}),null);
});
