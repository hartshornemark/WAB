/** Read-only audit of total-deadline tests; no solver/database/network calls. */
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {validateCargoCapacityResult} from '../src/domain/cargo-capacity.ts';
const directory=resolve(process.argv[2]);
const report=JSON.parse(readFileSync(directory+'/results.json'));
const refs=JSON.parse(readFileSync('solver/verification/a350-v2-seven-scenarios-2026-10-23/final/results.json')).rows;
const manifest=JSON.parse(readFileSync(directory+'/source-manifest.json'));
const measured=report.rows.filter(r=>r.phase==='measured'),audit=[];
for(const r of report.rows){
 let error=null;
 try{
  if(r.testOutcome==='RETURNED'){
   const expected=refs.find(x=>x.id===r.requestedCaseId);
   const problem=JSON.parse(readFileSync(`solver/verification/a350-v2-seven-scenarios-2026-10-23/final/inputs/${r.requestedCaseId}.json`));
   validateCargoCapacityResult(problem,r.result);
   if(r.inputSha256!==expected.inputSha256||r.backend?.revision!==manifest.runtimeCommit||r.backend?.modelSha256!==manifest.sourceFiles['solver/cargo_capacity.py'])throw Error('Source/input mismatch');
   const proven=['OPTIMAL','INFEASIBLE'].includes(r.result.status);
   if(proven?(r.outcome!=='VERIFIED'||r.result.status!==expected.solver.result.status||(r.result.arrangement?.cargoNetWeightGrams??null)!==(expected.solver.result.arrangement?.cargoNetWeightGrams??null)):r.publication.state!=='VALID_UNPROVEN')throw Error('Incorrect proof/publication state');
   if(!proven&&(!r.result.arrangement||r.result.arrangement.cargoNetWeightGrams>expected.solver.result.arrangement.cargoNetWeightGrams))throw Error('Invalid incumbent/reference comparison');
   if(r.executionBudget?.testingOnly!==true||!(r.executionBudget.calculationBudgetMilliseconds>0&&r.executionBudget.calculationBudgetMilliseconds<=5250))throw Error('Invalid narrowed budget');
  }else if(r.testOutcome==='INCOMPLETE'){
   if(r.publication?.state!=='NO_VALID_RESULT'||r.result?.arrangement)throw Error('Incomplete response fabricated a result');
  }else if(!['CLIENT_DEADLINE','ERROR'].includes(r.testOutcome))throw Error('Unrecognised outcome');
 }catch(e){error=e.message;}
 audit.push({caseId:r.requestedCaseId,repetition:r.repetition,phase:r.phase,testOutcome:r.testOutcome,arrangementValidated:r.testOutcome==='RETURNED'&&error===null,passed:error===null,error});
}
const stats=values=>{const v=values.filter(Number.isFinite).sort((a,b)=>a-b),n=v.length;return n?{min:v[0],median:(v[Math.floor((n-1)/2)]+v[Math.floor(n/2)])/2,max:v[n-1]}:{min:null,median:null,max:null};};
const cases=refs.map(expected=>{
 const rows=measured.filter(r=>r.requestedCaseId===expected.id),returned=rows.filter(r=>r.testOutcome==='RETURNED');
 return {caseId:expected.id,samples:rows.length,returnedWithinSixSeconds:returned.filter(r=>r.withinSixSeconds).length,returned:returned.length,proved:returned.filter(r=>r.outcome==='VERIFIED').length,unproved:returned.filter(r=>r.outcome==='INCONCLUSIVE').length,incomplete:rows.filter(r=>r.testOutcome==='INCOMPLETE').length,clientDeadlines:rows.filter(r=>r.testOutcome==='CLIENT_DEADLINE').length,errors:rows.filter(r=>r.testOutcome==='ERROR').length,referenceMatched:returned.filter(r=>r.result.status===expected.solver.result.status||(r.result.arrangement?.cargoNetWeightGrams??null)===(expected.solver.result.arrangement?.cargoNetWeightGrams??null)).length,netCargoKg:[...new Set(returned.map(r=>r.result.arrangement?r.result.arrangement.cargoNetWeightGrams/1000:null))],referenceNetCargoKg:expected.solver.result.arrangement?expected.solver.result.arrangement.cargoNetWeightGrams/1000:null,completeRequestMilliseconds:stats(rows.map(r=>r.completeRequestMilliseconds)),startupMilliseconds:stats(returned.map(r=>r.timings.workerStartupMilliseconds)),calculationBudgetMilliseconds:stats(returned.map(r=>r.executionBudget.calculationBudgetMilliseconds))};
});
const complete=!!report.finishedAt&&measured.length===refs.length*report.samplesPerCase;
const validationPassed=complete&&audit.every(r=>r.passed);
const summary={scope:report.design,targetTotalMilliseconds:6000,validationPassed,measuredRequests:measured.length,returnedWithinSixSeconds:cases.reduce((a,c)=>a+c.returnedWithinSixSeconds,0),validOrProvenResults:cases.reduce((a,c)=>a+c.returned,0),proved:cases.reduce((a,c)=>a+c.proved,0),unproved:cases.reduce((a,c)=>a+c.unproved,0),incomplete:cases.reduce((a,c)=>a+c.incomplete,0),clientDeadlines:cases.reduce((a,c)=>a+c.clientDeadlines,0),errors:cases.reduce((a,c)=>a+c.errors,0),cases};
writeFileSync(directory+'/summary.json',JSON.stringify(summary,null,2)+'\n');
writeFileSync(directory+'/validation.json',JSON.stringify({validationPassed,complete,audit},null,2)+'\n');
const sec=n=>n===null?'—':(n/1000).toFixed(3);
let text=`Six-second TOTAL request experiment — staging only\n\n${report.design}\nTarget: 6 seconds including HTTPS, startup, calculation, validation and response. Server budget 5.5 seconds, including a 0.25 second return/validation reserve; 0.5 second margin for transport. Actual network timing is measured, not guaranteed.\n\nMeasured requests: ${measured.length}; valid/proven results returned within six seconds: ${summary.returnedWithinSixSeconds}; proved: ${summary.proved}; valid but unproved: ${summary.unproved}; incomplete: ${summary.incomplete}; client deadlines: ${summary.clientDeadlines}; errors: ${summary.errors}.\nIndependent audit passed: ${validationPassed}. All attempts retained; one warm-up per case excluded from the measured totals.\n\nCase | Result by 6s | Proven | Matches reference outcome/net | Net kg returned | Complete median / max s\n`;
for(const c of cases)text+=`${c.caseId} | ${c.returnedWithinSixSeconds}/${c.samples} | ${c.proved}/${c.samples} | ${c.referenceMatched}/${c.samples} | ${c.netCargoKg.map(x=>x===null?'INFEASIBLE':x).join(', ')||'no result'} | ${sec(c.completeRequestMilliseconds.median)} / ${sec(c.completeRequestMilliseconds.max)}\n`;
text+='\nAn unproved arrangement is independently validated but is not labelled a confirmed maximum, even when its cargo total matches the known reference. Missing/incomplete responses do not become zero-capacity offers. Only testing was changed: no operational flight planning, AUTOLOAD, board, tray, calculation rules, saved inputs or database was altered. No merge was performed.\nThese are three measured requests per case, a practical test rather than a production latency guarantee.\n';
const context=JSON.parse(readFileSync(directory+'/deployment-context.json'));
text+=`\nTesting disabled after measurement: ${context.testingDisabledAfterRun}. Normal login page status: ${context.normalLoginStatus}. No operational STOP/PUBLISH policy was enabled.\n`;
writeFileSync(directory+'/REPORT.txt',text);console.log(text);if(!validationPassed)process.exitCode=1;
