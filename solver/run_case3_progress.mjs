/** Serial paired Case 3 control/profile measurements; operator token stays in env. */
import { parseArgs } from 'node:util';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
const {values} = parseArgs({options:{run:{type:'boolean'},url:{type:'string'},output:{type:'string'},samples:{type:'string',default:'10'}}});
const n=Number(values.samples), token=process.env.WAB_CAPACITY_TEST_TOKEN??'';
if(!values.run||!values.url||!values.output||token.length<32||!Number.isInteger(n)||n<1||n>20)throw Error('Use --run --url <https origin> --output <new directory> --samples 10; token from environment.');
const origin=new URL(values.url);
if(origin.protocol!=='https:'||origin.username||origin.password||origin.pathname!=='/'||origin.search||origin.hash)throw Error('HTTPS origin required');
const expected=JSON.parse(readFileSync(new URL('./verification/a350-v2-seven-scenarios-2026-10-23/final/results.json',import.meta.url))).rows.find(r=>r.id==='case-03');
mkdirSync(values.output);
const report={startedAt:new Date().toISOString(),origin:origin.origin,design:'One excluded warm-up per mode, then alternating serial control/profile pairs. Same sealed 10-second input; no database requests.',samplesPerMode:n,rows:[]};
const save=()=>writeFileSync(values.output+'/results.json',JSON.stringify(report,null,2)+'\n');
for(let i=0;i<=n;i++)for(const profile of i%2?[true,false]:[false,true]){
 const started=performance.now(); let row;
 try{
  const response=await fetch(new URL('/api/internal/a350-capacity',origin),{method:'POST',redirect:'error',signal:AbortSignal.timeout(45000),headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify({caseId:'case-03',engine:'SOLVER',...(profile?{profileCase3:true}:{})})});
  const raw=await response.text();if(raw.length>1_000_000)throw Error('Oversized response');
  let body;try{body=JSON.parse(raw);}catch{body={outcome:'ERROR',error:'Non-JSON HTTP response'};}
  row={...body,httpStatus:response.status};
  if(!response.ok||body.caseId!=='case-03'||body.engine!=='SOLVER'||body.inputSha256!==expected.inputSha256||body.validation!=='PASS'||!['VERIFIED','INCONCLUSIVE'].includes(body.outcome)||body.result?.arrangement?.cargoNetWeightGrams!==40701000)row.outcome='ERROR';
  if(profile&&body.searchProfile?.version!=='CASE3_INCUMBENTS_V1')row.outcome='ERROR';
 }catch{row={outcome:'ERROR'};}
 row={...row,mode:profile?'profile':'control',repetition:i,phase:i?'measured':'warmup',completeRequestMilliseconds:performance.now()-started};
 report.rows.push(row);save();console.log(i,row.mode,row.outcome,row.searchProfile?.bestFoundMilliseconds??'',row.searchProfile?.proofMilliseconds??'unproved');
 if(row.outcome==='ERROR')throw Error('Unexpected response; stopped without retries.');
}
report.finishedAt=new Date().toISOString();save();
