import"server-only";
import{spawn}from"node:child_process";
import{join}from"node:path";
import{validateLoadPlanningProblem,validateLoadPlanningSolution,type LoadPlanningSolution}from"@/domain/load-planning-solver";
import type{LoadPlanningSolver}from"@/ports/load-planning-solver";

const maximumOutputBytes=1_000_000;

export function createCpSatLoadPlanningSolver(options:{python?:string;script?:string}={}):LoadPlanningSolver{
 const python=options.python??process.env.WAB_SOLVER_PYTHON??"python3",script=options.script??join(process.cwd(),"solver/cp_sat_solver.py");
 return{solve(input){const problem=validateLoadPlanningProblem(input);return new Promise((resolve,reject)=>{const child=spawn(/*turbopackIgnore: true*/python,[script],{stdio:["pipe","pipe","pipe"],env:{...process.env,PYTHONUNBUFFERED:"1"}}),stdout:Buffer[]=[],stderr:Buffer[]=[];let outputBytes=0,settled=false;const finish=(error?:Error,solution?:LoadPlanningSolution)=>{if(settled)return;settled=true;clearTimeout(timeout);if(error)reject(error);else resolve(validateLoadPlanningSolution(problem,solution!))};const timeout=setTimeout(()=>{child.kill("SIGKILL");finish(new Error("AUTOLOAD exceeded its execution time limit."))},(problem.timeLimitSeconds+5)*1000);child.stdout.on("data",chunk=>{outputBytes+=chunk.length;if(outputBytes>maximumOutputBytes){child.kill("SIGKILL");finish(new Error("AUTOLOAD returned too much data."));return}stdout.push(chunk)});child.stderr.on("data",chunk=>stderr.push(chunk));child.on("error",error=>finish(new Error(`AUTOLOAD could not start: ${error.message}`)));child.on("close",code=>{if(settled)return;const text=Buffer.concat(stdout).toString("utf8").trim();if(code!==0){let detail=Buffer.concat(stderr).toString("utf8").trim();try{detail=JSON.parse(text).error??detail}catch{}finish(new Error(detail||"AUTOLOAD did not complete."));return}try{finish(undefined,JSON.parse(text)as LoadPlanningSolution)}catch{finish(new Error("AUTOLOAD returned an unreadable result."))}});child.stdin.end(JSON.stringify(problem))})}}
}
