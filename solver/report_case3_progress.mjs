/** Read-only independent witness and timing audit; no solver/network calls. */
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {validateCargoCapacityResult} from '../src/domain/cargo-capacity.ts';
const directory=resolve(process.argv[2]);
const report=JSON.parse(readFileSync(directory+'/results.json','utf8'));
const expected=JSON.parse(readFileSync('solver/verification/a350-v2-seven-scenarios-2026-10-23/final/results.json','utf8')).rows.find(r=>r.id==='case-03');
const problem=JSON.parse(readFileSync('solver/verification/a350-v2-seven-scenarios-2026-10-23/final/inputs/case-03.json','utf8'));
const rows=report.rows.filter(r=>r.phase==='measured');
const audit=[];
for(const r of report.rows){
 let error=null;
 try{
  validateCargoCapacityResult(problem,r.result);
  if(r.inputSha256!==expected.inputSha256||r.result.arrangement.cargoNetWeightGrams!==40701000||r.httpStatus!==200||r.validation!=='PASS'||!['VERIFIED','INCONCLUSIVE'].includes(r.outcome))throw Error('Reference/result mismatch');
  if(r.mode==='profile'){
   const p=r.searchProfile;
   if(p.version!=='CASE3_INCUMBENTS_V1'||p.bestFoundNetWeightGrams!==40701000||!p.improvements.length||p.improvements.at(-1).netWeightGrams!==40701000)throw Error('Missing progress');
   for(const [i,e] of p.improvements.entries())if(!Number.isFinite(e.calculationMilliseconds)||e.calculationMilliseconds<0||(i&&(e.netWeightGrams<=p.improvements[i-1].netWeightGrams||e.calculationMilliseconds<p.improvements[i-1].calculationMilliseconds)))throw Error('Invalid progress ordering');
   if(p.firstValidMilliseconds!==p.improvements[0].calculationMilliseconds||p.bestFoundMilliseconds!==p.improvements.find(e=>e.netWeightGrams===40701000).calculationMilliseconds)throw Error('Incorrect discovery timing');
   const proved=r.result.status==='OPTIMAL';
   if(proved?(p.proofMilliseconds===null||p.proofCensoredAtMilliseconds!==null):(p.proofMilliseconds!==null||p.proofCensoredAtMilliseconds===null))throw Error('Incorrect proof/censor status');
   const end=proved?p.proofMilliseconds:p.proofCensoredAtMilliseconds;
   if(end<p.bestFoundMilliseconds||end>r.timings.calculationMilliseconds+1||p.absoluteGapGrams!==Math.max(0,p.finalUpperBoundGrams-40701000))throw Error('Invalid elapsed/gap');
  }
 }catch(e){error=e.message;}
 audit.push({mode:r.mode,repetition:r.repetition,phase:r.phase,passed:error===null,error});
}
const stat=values=>{
 const v=values.filter(Number.isFinite).sort((a,b)=>a-b),n=v.length;
 return n?{count:n,min:v[0],median:(v[Math.floor((n-1)/2)]+v[Math.floor(n/2)])/2,max:v[n-1]}:{count:0,min:null,median:null,max:null};
};
const summaries={};
for(const mode of ['control','profile']){
 const selected=rows.filter(r=>r.mode===mode),p=selected.map(r=>r.searchProfile).filter(Boolean);
 summaries[mode]={count:selected.length,proven:selected.filter(r=>r.result.status==='OPTIMAL').length,calculationMilliseconds:stat(selected.map(r=>r.timings.calculationMilliseconds)),workerStartupMilliseconds:stat(selected.map(r=>r.timings.workerStartupMilliseconds)),completeRequestMilliseconds:stat(selected.map(r=>r.completeRequestMilliseconds))};
 if(p.length)for(const key of ['firstValidMilliseconds','bestFoundMilliseconds','proofMilliseconds','proofCensoredAtMilliseconds','processCpuMilliseconds','solverWallMilliseconds','relativeGap','absoluteGapGrams','deterministicTime','branches','conflicts'])summaries[mode][key]=stat(p.map(x=>x[key]));
 if(p.length)summaries[mode].cpuToElapsedRatio=stat(p.map(x=>x.processCpuMilliseconds/(x.proofMilliseconds??x.proofCensoredAtMilliseconds)));
}
const revisions=[...new Set(report.rows.map(r=>r.backend?.revision))], modelHashes=[...new Set(report.rows.map(r=>r.backend?.modelSha256))],protoHashes=[...new Set(report.rows.filter(r=>r.mode==='profile').map(r=>r.searchProfile?.modelProtoSha256))];
const manifest=existsSync(directory+'/source-manifest.json')?JSON.parse(readFileSync(directory+'/source-manifest.json')):null;
const sourceMatches=!!manifest&&revisions.every(r=>r?.startsWith(manifest.deploymentCommit))&&modelHashes[0]===manifest.sourceFiles['solver/cargo_capacity.py'];
const local=JSON.parse(readFileSync(directory+'/local-results.json')).rows.filter(r=>r.phase==='measured'&&r.mode==='profile');
const localSummary={count:local.length,bestFoundMilliseconds:stat(local.map(r=>r.searchProfile.bestFoundMilliseconds)),proofMilliseconds:stat(local.map(r=>r.searchProfile.proofMilliseconds)),processCpuMilliseconds:stat(local.map(r=>r.searchProfile.processCpuMilliseconds)),modelProtoMatches:local.every(r=>r.searchProfile.modelProtoSha256===protoHashes[0])};
const diagnostic=JSON.parse(readFileSync(directory+'/proof-diagnostic.json'));
const diagnosticAudit=diagnostic.rows.map(r=>{
 let error=null;try{validateCargoCapacityResult(problem,r.result);if(r.result.status!=='OPTIMAL'||r.result.arrangement.cargoNetWeightGrams!==40701000||r.searchProfile.modelProtoSha256!==protoHashes[0]||r.searchProfile.proofMilliseconds===null||r.searchProfile.proofMilliseconds<r.searchProfile.bestFoundMilliseconds||r.searchProfile.proofMilliseconds>30100||r.searchProfile.finalUpperBoundGrams!==40701000||r.settings.searchWorkers!==1||r.settings.randomSeed!==0)throw Error('Diagnostic result/timing mismatch');}catch(e){error=e.message;}
 return {repetition:r.repetition,passed:error===null,error};
});
const diagnosticSummary={scope:diagnostic.scope,count:diagnostic.rows.length,bestFoundMilliseconds:stat(diagnostic.rows.map(r=>r.searchProfile.bestFoundMilliseconds)),proofMilliseconds:stat(diagnostic.rows.map(r=>r.searchProfile.proofMilliseconds)),processCpuMilliseconds:stat(diagnostic.rows.map(r=>r.searchProfile.processCpuMilliseconds))};
const dbReference=JSON.parse(readFileSync('solver/verification/a350-v2-seven-scenarios-2026-10-23/final/case-03.json')).database.result;
validateCargoCapacityResult(problem,{...dbReference,engine:'OR-TOOLS CP-SAT',solveMilliseconds:0});
const diagnosticPassed=diagnosticAudit.every(r=>r.passed)&&diagnostic.rows.length===3&&diagnostic.inputSha256===expected.inputSha256&&diagnostic.revision===revisions[0]&&diagnostic.modelSha256===modelHashes[0]&&diagnostic.effectiveDiagnosticCalculationLimitSeconds===30;
const passed=diagnosticPassed&&sourceMatches&&localSummary.modelProtoMatches&&audit.every(r=>r.passed)&&revisions.length===1&&modelHashes.length===1&&protoHashes.length===1&&rows.length===report.samplesPerMode*2;
writeFileSync(directory+'/validation.json',JSON.stringify({passed,sourceMatches,revisions,modelHashes,protoHashes,audit,diagnosticPassed,diagnosticAudit},null,2)+'\n');
writeFileSync(directory+'/summary.json',JSON.stringify({passed,startedAt:report.startedAt,finishedAt:report.finishedAt,summaries,local:localSummary,diagnostic:diagnosticSummary},null,2)+'\n');
const s=v=>v===null?'unproved':(v/1000).toFixed(3),p=summaries.profile,c=summaries.control;
const text=`Case 3 — discovery versus optimality proof, hosted staging\n\n${report.design}\nMeasured requests: ${rows.length}; independently audited warm-ups and measured requests: ${audit.length}; audit passed: ${passed}.\nSealed cargo objective: 40,701 kg. All final arrangements independently validated against the frozen input.\nSource revision: ${revisions.join(', ')}\n\nProfiled runs: ${p.count}; optimality proved: ${p.proven}/${p.count}.\nFirst valid arrangement: median ${s(p.firstValidMilliseconds.median)} s.\nBest returned objective first found: median ${s(p.bestFoundMilliseconds.median)} s; range ${s(p.bestFoundMilliseconds.min)}–${s(p.bestFoundMilliseconds.max)} s.\nProof observed at solve return: ${p.proofMilliseconds.count} proved runs; median ${s(p.proofMilliseconds.median)} s; range ${s(p.proofMilliseconds.min)}–${s(p.proofMilliseconds.max)} s.\nUnproved/censored: ${p.proofCensoredAtMilliseconds.count}; median stop observation ${s(p.proofCensoredAtMilliseconds.median)} s. These are not proof times.\n\nOrdinary control: ${c.proven}/${c.count} proved; all-response median calculation ${s(c.calculationMilliseconds.median)} s, complete request ${s(c.completeRequestMilliseconds.median)} s.\nProfiled: all-response median calculation ${s(p.calculationMilliseconds.median)} s, complete request ${s(p.completeRequestMilliseconds.median)} s.\nProcess CPU median ${s(p.processCpuMilliseconds.median)} s; CPU/elapsed median ${p.cpuToElapsedRatio.median?.toFixed(3)}. See summary.json for bounds, gaps and search effort.\n\nDiscovery/proof clocks include validation/model construction and exclude imports. Complete request includes startup and HTTPS. Proof observation includes solver return overhead. Only OPTIMAL contributes a proof time. Profile callbacks add some overhead; paired controls are descriptive observations, not a causal overhead estimate.\nNo rules, frozen inputs, seed, search workers or ten-second limit changed. No operational fallback was enabled. Best-found arrangements are not labelled proven maxima solely because they match the prior reference.\nLocal check (${localSummary.count} profiled runs): best objective median ${s(localSummary.bestFoundMilliseconds.median)} s; proof median ${s(localSummary.proofMilliseconds.median)} s; process CPU median ${s(localSummary.processCpuMilliseconds.median)} s. Identical model-proto hash locally and hosted: ${localSummary.modelProtoMatches}.\nSeparate longer diagnostic: three fresh models/solvers in one interpreter on one staging instance, with a 30-second calculation ceiling and 35-second hard stop per run. All three proved optimal; best-found median ${s(diagnosticSummary.bestFoundMilliseconds.median)} s, proof median ${s(diagnosticSummary.proofMilliseconds.median)} s (range ${s(diagnosticSummary.proofMilliseconds.min)}–${s(diagnosticSummary.proofMilliseconds.max)} s), CPU median ${s(diagnosticSummary.processCpuMilliseconds.median)} s. These are not ten-second benchmark samples or complete HTTP request timings. Only the diagnostic time parameter was intercepted in that process; the original model and saved input remained unchanged.\nNo exact hosting slowdown cause can be established from CPU and search counters alone.\n`;
writeFileSync(directory+'/REPORT.txt',text);console.log(text);if(!passed)process.exitCode=1;
