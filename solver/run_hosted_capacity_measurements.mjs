/** Explicit, authenticated staging-only fixed-case caller. Never prints secrets. */
import { parseArgs } from 'node:util';
import { mkdirSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
const { values } = parseArgs({ options: { run: {type:'boolean'}, smoke: {type:'boolean'}, 'first-request': {type:'boolean'}, cases: {type:'string'}, url: {type:'string'}, output: {type:'string'}, samples: {type:'string',default:'10'} } });
const token = process.env.WAB_CAPACITY_TEST_TOKEN ?? '', n = Number(values.samples);
if (!values.run || !values.url || !values.output || token.length<32 || !Number.isInteger(n) || n<2 || n>50) throw Error('Use --run --url <https staging origin> --output <new directory> --samples 10; token comes from WAB_CAPACITY_TEST_TOKEN.');
const origin = new URL(values.url);
if (origin.protocol!=='https:' || origin.username || origin.password || origin.search || origin.hash || origin.pathname!=='/') throw Error('Use the HTTPS staging origin only.');
const repo=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const references=JSON.parse(readFileSync(repo+'/solver/verification/a350-v2-seven-scenarios-2026-10-23/final/results.json','utf8')).rows;
const selected=values.cases?.split(',')??references.map(r=>r.id);
if(selected.some(id=>!references.some(r=>r.id===id))||(values.smoke&&values['first-request']))throw Error('Invalid case or run mode.');
mkdirSync(values.output);
const report = { scope:'Hosted fixed-input staging requests; not browser rendering or live passenger/baggage preparation.', startedAt:new Date().toISOString(), origin:origin.origin, samplesPerEngineCase:values.smoke||values['first-request']?1:n, mode:values.smoke?'smoke':values['first-request']?'first-request':'repeated', rows:[] };
const save=()=>writeFileSync(values.output+'/results.json',JSON.stringify(report,null,2)+'\n');
for (const selectedId of selected) for(let i=0;i<=(values.smoke||values['first-request']?0:n);i++) for(const engine of i%2?['SOLVER','DATABASE']:['DATABASE','SOLVER']) {
 const caseId=selectedId, expected=references.find(r=>r.id===caseId), phase=values.smoke?'smoke':values['first-request']?'first-request':i===0?'warmup':'repeated', started=performance.now();
 let row;
 try {
  const response=await fetch(new URL('/api/internal/a350-capacity',origin),{method:'POST',redirect:'error',signal:AbortSignal.timeout(80000),headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify({caseId,engine})});
  const raw=await response.text();
  if(raw.length>1_000_000)throw Error('Oversized response');
  let body, nonJson=false;
  try{body=JSON.parse(raw);if(!body||typeof body!=='object'||Array.isArray(body))throw Error('Invalid response');}catch{body={};nonJson=true;}
  row={caseId,engine,repetition:i,phase,httpStatus:response.status,...body,completeRequestMilliseconds:performance.now()-started};
  if(nonJson){row.outcome='ERROR';row.error='Non-JSON HTTP response';}
  else if(!response.ok) row.outcome='ERROR';
  else if(body.caseId!==caseId||body.engine!==engine||body.inputSha256!==expected.inputSha256||body.validation!=='PASS'||!['VERIFIED','INCONCLUSIVE','MISMATCH'].includes(body.outcome))row.outcome='MISMATCH';
  else if(body.outcome==='VERIFIED'&&(body.result.status!==expected.solver.result.status||(body.result.arrangement?.cargoNetWeightGrams??null)!==(expected.solver.result.arrangement?.cargoNetWeightGrams??null)))row.outcome='MISMATCH';
  row.completeRequestMilliseconds=performance.now()-started;
 }catch{row={caseId,engine,repetition:i,phase,outcome:'ERROR',completeRequestMilliseconds:performance.now()-started};}
 report.rows.push(row);save();console.log(caseId,engine,i,row.outcome);
 // Fail fast on unavailable/disabled/auth errors; do not pound a misconfigured app.
 if(row.httpStatus && [401,404,405,415].includes(row.httpStatus))throw Error('Staging endpoint is disabled or authentication/configuration failed; stopped.');
}
report.finishedAt=new Date().toISOString();save();
