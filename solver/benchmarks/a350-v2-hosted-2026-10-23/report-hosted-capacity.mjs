import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
const {validateCargoCapacityProblem,validateCargoCapacityResult}=await import(pathToFileURL(resolve('src/domain/cargo-capacity.ts')).href);
const {distribution}=await import(pathToFileURL(resolve('solver/cargo_capacity_statistics.mjs')).href);
// Run from repository root with tsx. This script never sends requests or reads secrets.
const root=resolve(process.argv[2]), sealed='solver/verification/a350-v2-seven-scenarios-2026-10-23/final';
const read=p=>JSON.parse(readFileSync(p,'utf8')),save=(p,v)=>writeFileSync(p,JSON.stringify(v,null,2)+'\n');
const report=read(root+'/repeated/results.json'), registry=read(sealed+'/results.json').rows, context=read(root+'/deployment-context.json'), source=read(root+'/source-manifest.json');
if(!report.finishedAt)throw Error('Incomplete hosted measurement');
const expected=registry.length*2*(report.samplesPerEngineCase+1);
if(report.rows.length!==expected)throw Error('Missing requests');
const validation=[],summary=[];
for(const row of report.rows){
 const expected=registry.find(r=>r.id===row.caseId);let valid=false,witnessValid=false,proven=false,matchesKnownMaximum=false,reason;
 try{
  if(!expected||!['VERIFIED','INCONCLUSIVE'].includes(row.outcome))throw Error('Request failed or mismatched');
  if(row.backend?.revision!==context.source.commit||row.backend?.modelSha256!==source.files['solver/cargo_capacity.py'])throw Error('Deployment/model changed');
  const raw=readFileSync(sealed+'/inputs/'+row.caseId+'.json','utf8');
  if(createHash('sha256').update(raw).digest('hex')!==row.inputSha256||row.inputSha256!==expected.inputSha256)throw Error('Input hash mismatch');
  const problem=validateCargoCapacityProblem(JSON.parse(raw));
  const result=validateCargoCapacityResult(problem,{...row.result,engine:'OR-TOOLS CP-SAT',solveMilliseconds:0});
  witnessValid=true;proven=['OPTIMAL','INFEASIBLE'].includes(result.status);matchesKnownMaximum=(result.arrangement?.cargoNetWeightGrams??null)===(expected.solver.result.arrangement?.cargoNetWeightGrams??null);
  if(!proven)throw Error('Feasible/unknown result does not prove the maximum');
  if(result.status!==expected.solver.result.status||!matchesKnownMaximum||row.outcome!=='VERIFIED')throw Error('Result mismatch');
  valid=true;
 }catch(e){reason=e.message;}
 validation.push({caseId:row.caseId,engine:row.engine,repetition:row.repetition,phase:row.phase,valid,witnessValid,proven,matchesKnownMaximum,reason});
}
for(const c of registry)for(const engine of ['DATABASE','SOLVER']){
 const rows=report.rows.filter(r=>r.caseId===c.id&&r.engine===engine&&r.phase==='repeated');
 const good=rows.filter(r=>r.outcome==='VERIFIED');
 const metrics=Object.fromEntries(['calculationMilliseconds','workerStartupMilliseconds','executionRoundTripMilliseconds','inputMilliseconds','validationMilliseconds','handlerMilliseconds','completeRequestMilliseconds'].map(k=>[k,distribution(good.map(r=>k==='completeRequestMilliseconds'?r[k]:r.timings[k]).filter(v=>v!==undefined&&v!==null))]));
 summary.push({caseId:c.id,engine,recorded:rows.length,verified:good.length,allResponseLatencies:{calculationMilliseconds:distribution(rows.filter(r=>r.timings).map(r=>r.timings.calculationMilliseconds)),completeRequestMilliseconds:distribution(rows.map(r=>r.completeRequestMilliseconds))},exceptions:rows.filter(r=>r.outcome!=='VERIFIED').map(r=>({repetition:r.repetition,outcome:r.outcome,status:r.result?.status})),metrics});
}
const versions=[...new Set(report.rows.filter(r=>r.backend).map(r=>JSON.stringify(r.backend)))].map(s=>JSON.parse(s));
const allPassed=validation.every(r=>r.valid);
const measuredValidation=validation.filter(r=>r.phase==='repeated');
const totals={measured:measuredValidation.length,proven:measuredValidation.filter(r=>r.valid).length,unprovedOrFailed:measuredValidation.filter(r=>!r.valid).length,allWitnessesValid:measuredValidation.every(r=>r.witnessValid),allMatchKnownReferenceObjective:measuredValidation.every(r=>r.matchesKnownMaximum),transportErrors:report.rows.filter(r=>r.outcome==='ERROR').length};
save(root+'/validation.json',{allPassed,totals,rows:validation});
save(root+'/summary.json',{allPassed,totals,measuredRequests:report.rows.filter(r=>r.phase==='repeated').length,warmupsExcluded:report.rows.filter(r=>r.phase==='warmup').length,percentileMethod:'Nearest-rank p95; with 10 samples this equals the observed maximum. Median averages central two values.',versions,summary});
const lines=['Hosted A350 fixed-input benchmark — 23 October 2026','',allPassed?'All recorded results in the final complete run independently revalidated.':'Exceptions recorded: inspect validation.json and raw results before making performance claims.','',`Existing DigitalOcean app: ${context.app.name}, ${context.app.region}, 2 x 1 shared vCPU / 1GB.`,`Current Supabase: ${context.database.region}, ${context.database.compute}, PostgreSQL ${context.database.postgresVersion}.`,`Final run: ${totals.measured} measured requests, ${totals.proven} proved, ${totals.unprovedOrFailed} unproved/failed; transport errors ${totals.transportErrors}. All returned witnesses valid: ${totals.allWitnessesValid}; all match the known reference objective/infeasibility: ${totals.allMatchKnownReferenceObjective}.`,'Serial requests; 10 measured requests per engine/case after one excluded warm-up.','Complete request includes external HTTPS, app handling, child startup, validation and, for DATABASE, native database connection/transport.','Core time excludes startup and transport. These are fixture comparisons, not the live passenger/baggage preparation workflow.','No operational cargo calculation was switched.','','Case | DB core median s | Solver core median s | DB request median / p95 s | Solver request median / p95 s | Proven DB; Solver'];
const f=v=>(v/1000).toFixed(3);
for(const c of registry){const d=summary.find(r=>r.caseId===c.id&&r.engine==='DATABASE'),s=summary.find(r=>r.caseId===c.id&&r.engine==='SOLVER');const m=(r,k,p='median')=>r.verified!==r.recorded?'unproved requests':r.metrics[k][p]===null?'n/a':f(r.metrics[k][p]);lines.push(`${c.id} | ${m(d,'calculationMilliseconds')} | ${m(s,'calculationMilliseconds')} | ${m(d,'completeRequestMilliseconds')} / ${m(d,'completeRequestMilliseconds','p95')} | ${m(s,'completeRequestMilliseconds')} / ${m(s,'completeRequestMilliseconds','p95')} | ${d.verified}/${d.recorded}; ${s.verified}/${s.recorded}`);}
for(const r of summary.filter(r=>r.exceptions.length))lines.push(`${r.caseId} ${r.engine}: ${r.verified}/${r.recorded} measured requests proved; exceptions: ${r.exceptions.map(e=>e.outcome+' '+(e.status??'no result')).join(', ')}. All-response median core ${f(r.allResponseLatencies.calculationMilliseconds.median??0)} s, complete ${f(r.allResponseLatencies.completeRequestMilliseconds.median??0)} s; these are not time-to-proven-optimum figures.`);
lines.push('','Timing distributions use verified/proven responses only. Failed and unproved requests remain counted and visible in raw results and validation.json; they are not successful timings.','Read raw results for every failure, unproved result and metadata field; no outliers removed.','The database and app are in different regions, which is part of this deployed request path.','No hosted timing claim is transferable to another environment without measurement.');
writeFileSync(root+'/REPORT.txt',lines.join('\n')+'\n');
console.log(JSON.stringify({allPassed,measured:140,warmups:14,versions,summary:summary.map(r=>({case:r.caseId,engine:r.engine,verified:r.verified,core:r.metrics.calculationMilliseconds.median,request:r.metrics.completeRequestMilliseconds.median}))},null,2));
