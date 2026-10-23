/** Test-only end-to-end six-second caller. No live flight writes. */
import {parseArgs} from 'node:util';
import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {performance} from 'node:perf_hooks';
const {values}=parseArgs({options:{run:{type:'boolean'},url:{type:'string'},output:{type:'string'},samples:{type:'string',default:'3'}}});
const token=process.env.WAB_CAPACITY_TEST_TOKEN??'',n=Number(values.samples);
if(!values.run||!values.url||!values.output||token.length<32||!Number.isInteger(n)||n<1||n>10)throw Error('Use --run --url <https origin> --output <new directory> --samples 3, token from environment.');
const origin=new URL(values.url);
if(origin.protocol!=='https:'||origin.username||origin.password||origin.pathname!=='/'||origin.search||origin.hash)throw Error('HTTPS origin required');
const refs=JSON.parse(readFileSync(new URL('./verification/a350-v2-seven-scenarios-2026-10-23/final/results.json',import.meta.url))).rows;
mkdirSync(values.output);
const report={startedAt:new Date().toISOString(),origin:origin.origin,targetTotalMilliseconds:6000,serverBudgetMilliseconds:5500,validationReturnReserveMilliseconds:250,samplesPerCase:n,design:'Serial seven-case test, one excluded warm-up then measured requests per case. Six-second client timeout includes HTTPS, startup, calculation and validation. No operational publication.',rows:[]};
const save=()=>writeFileSync(values.output+'/results.json',JSON.stringify(report,null,2)+'\n');
for(const expected of refs)for(let i=0;i<=n;i++){
 const started=performance.now();let row;
 try{
  const response=await fetch(new URL('/api/internal/a350-capacity',origin),{method:'POST',redirect:'error',signal:AbortSignal.timeout(6000),headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify({caseId:expected.id,engine:'SOLVER',totalBudgetMilliseconds:6000,...(expected.id==='case-03'?{profileCase3:true}:{})})});
  const raw=await response.text();if(raw.length>1_000_000)throw Error('Oversized response');
  let body;try{body=JSON.parse(raw);}catch{body={outcome:'ERROR',error:'Non-JSON response'};}
  row={...body,httpStatus:response.status};
  if(!response.ok||body.caseId!==expected.id||body.publication?.testingOnly!==true||body.publication?.targetTotalMilliseconds!==6000)row.testOutcome='ERROR';
  else if(body.publication.state==='NO_VALID_RESULT')row.testOutcome='INCOMPLETE';
  else if(body.inputSha256!==expected.inputSha256||body.validation!=='PASS'||!['VERIFIED','INCONCLUSIVE'].includes(body.outcome))row.testOutcome='ERROR';
  else row.testOutcome='RETURNED';
 }catch(e){row={testOutcome:e.name==='TimeoutError'||e.name==='AbortError'?'CLIENT_DEADLINE':'ERROR'};}
 row={...row,requestedCaseId:expected.id,repetition:i,phase:i?'measured':'warmup',completeRequestMilliseconds:performance.now()-started};
 row.withinSixSeconds=row.testOutcome!=='CLIENT_DEADLINE'&&row.completeRequestMilliseconds<=6000;
 report.rows.push(row);save();console.log(expected.id,i,row.testOutcome,row.publication?.state,row.completeRequestMilliseconds.toFixed(1),row.result?.arrangement?.cargoNetWeightGrams??'');
 if([401,404,400,405,415].includes(row.httpStatus))throw Error('Gate/auth/configuration error; stopped without retries.');
}
report.finishedAt=new Date().toISOString();save();
