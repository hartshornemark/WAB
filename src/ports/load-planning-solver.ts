import type{LoadPlanningProblem,LoadPlanningSolution}from"@/domain/load-planning-solver";
export interface LoadPlanningSolver{solve(problem:LoadPlanningProblem):Promise<LoadPlanningSolution>}
