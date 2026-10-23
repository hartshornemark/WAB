"""Optional passive incumbent timing for the sealed Case 3 benchmark only.

No hints, changed limits, bound callbacks, early stops or model constraints.
Times start at calculate/model construction; proof is observed at solve return.
"""
import hashlib
import time
from ortools.sat.python import cp_model


class SearchProfile(cp_model.CpSolverSolutionCallback):
    def __init__(self):
        super().__init__()
        self.events = []

    def begin_calculation(self, started):
        self.started = started
        self.cpu_started = time.process_time()

    def begin_search(self, model):
        self.model_sha256 = hashlib.sha256(str(model.proto).encode()).hexdigest()
        self.search_started = time.perf_counter()
        self.preparation_ms = (self.search_started - self.started) * 1000

    def on_solution_callback(self):
        objective = round(self.objective_value)
        # Retain strict improvements only; equal-objective arrangements do not
        # reset the first time that the eventual best objective was reached.
        if not self.events or objective > self.events[-1]['netWeightGrams']:
            self.events.append({'calculationMilliseconds': (time.perf_counter() - self.started) * 1000,
                                'searchMilliseconds': self.wall_time * 1000,
                                'netWeightGrams': objective,
                                'upperBoundGrams': self.best_objective_bound})

    def finish_search(self, solver, status):
        self.ended_ms = (time.perf_counter() - self.started) * 1000
        self.cpu_ms = (time.process_time() - self.cpu_started) * 1000
        self.status = status
        self.upper_bound = solver.best_objective_bound
        self.solver_wall_ms = solver.wall_time * 1000
        self.final_deterministic_time = solver.response_proto.deterministic_time
        self.branches = solver.num_branches
        self.conflicts = solver.num_conflicts

    def report(self, result):
        final_net = (result.get('arrangement') or {}).get('cargoNetWeightGrams')
        reached = next((e for e in self.events if e['netWeightGrams'] == final_net), None)
        proved = self.status == cp_model.OPTIMAL
        return {'version': 'CASE3_INCUMBENTS_V1', 'clock': 'milliseconds from calculation start, excluding worker imports',
                'proofObservation': 'OPTIMAL returned by solve; includes solver return overhead',
                'modelProtoSha256': self.model_sha256, 'preparationMilliseconds': self.preparation_ms,
                'firstValidMilliseconds': self.events[0]['calculationMilliseconds'] if self.events else None,
                'bestFoundMilliseconds': reached['calculationMilliseconds'] if reached else None,
                'bestFoundNetWeightGrams': final_net,
                'proofMilliseconds': self.ended_ms if proved else None,
                'proofCensoredAtMilliseconds': None if proved else self.ended_ms,
                'finalUpperBoundGrams': self.upper_bound,
                'absoluteGapGrams': None if final_net is None else max(0, self.upper_bound - final_net),
                'relativeGap': None if final_net is None else max(0, self.upper_bound - final_net) / max(1, abs(final_net)),
                'processCpuMilliseconds': self.cpu_ms, 'solverWallMilliseconds': self.solver_wall_ms,
                'deterministicTime': self.final_deterministic_time, 'branches': self.branches,
                'conflicts': self.conflicts, 'improvements': self.events}
