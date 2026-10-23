import type { CargoCapacityProblem, CargoCapacityResult } from "@/domain/cargo-capacity";
export interface CargoCapacitySolver {
  solve(problem: CargoCapacityProblem): Promise<CargoCapacityResult>;
}
