"""Read-only arithmetic certificate for frozen Case 3; no solver or database.

Relax compartment weight limits while retaining saved footprint exclusivity,
ULD limits, Bulk caps and the aircraft gross limit. A maximum of this relaxed
problem bounds the real problem. A validated real witness attains that bound.
This analysis is not wired into the operational or benchmark solver.
"""
from functools import lru_cache
import itertools
import json
from pathlib import Path


def certificate():
    base = Path(__file__).parent / 'verification/a350-v2-seven-scenarios-2026-10-23/final'
    problem = json.loads((base / 'inputs/case-03.json').read_text())
    witness = json.loads((base / 'case-03.json').read_text())['database']['result']['arrangement']
    assert not problem['fixedLoads']
    types = {}
    for kind in ('PALLET', 'CONTAINER'):
        values = {(p['maximumGrossWeightGrams'], p['tareWeightGrams']) for p in problem['positions'] if p['kind'] == kind}
        assert len(values) == 1
        types[kind] = next(iter(values))
    containers = [p for p in problem['positions'] if p['kind'] == 'CONTAINER']
    container_ids = {p['id'] for p in containers}
    for bag in problem['baggageUlds']:
        assert set(bag['compatiblePositionIds']) == container_ids
        assert all(bag['netWeightGrams'] + p['tareWeightGrams'] <= p['maximumGrossWeightGrams'] and bag['volumeMillilitres'] <= p['maximumVolumeMillilitres'] for p in containers)
    combined, group_tables = {0: 0}, {}
    for group in sorted({p['groupId'] for p in problem['positions']}):
        positions = [p for p in problem['positions'] if p['groupId'] == group]
        bays = sorted({b for p in positions for b in p['occupiedBayIds']})
        bits = {b: 1 << i for i, b in enumerate(bays)}
        masks = {kind: [sum(bits[b] for b in p['occupiedBayIds']) for p in positions if p['kind'] == kind] for kind in types}
        @lru_cache(None)
        def count_containers(i, used):
            if i == len(masks['CONTAINER']):
                return 0
            m = masks['CONTAINER'][i]
            return max(count_containers(i + 1, used), 1 + count_containers(i + 1, used | m) if not used & m else -1)
        table = {}
        for take in itertools.product([0, 1], repeat=len(masks['PALLET'])):
            used, valid = 0, True
            for flag, mask in zip(take, masks['PALLET']):
                if flag:
                    if used & mask:
                        valid = False
                        break
                    used |= mask
            if valid:
                n = sum(take)
                table[n] = max(table.get(n, -1), count_containers(0, used))
        group_tables[group] = table
        new = {}
        for p, c in combined.items():
            for q, d in table.items():
                new[p + q] = max(new.get(p + q, -1), c + d)
        combined = new
    pallet_gross, pallet_tare = types['PALLET']
    container_gross, container_tare = types['CONTAINER']
    headroom = problem['maximumZeroFuelWeightGrams'] - problem['dryOperatingWeightGrams'] - problem['passengerWeightGrams']
    bag_count = len(problem['baggageUlds'])
    baggage_net = sum(b['netWeightGrams'] for b in problem['baggageUlds'])
    baggage_tare = bag_count * container_tare
    # Relaxing group Bulk caps is conservative; each area's own volume and
    # weight cap remains. In this fixture the sum is the group cap, 2,780 kg.
    bulk_cap = sum(min(a['maximumGrossWeightGrams'], a['maximumVolumeMillilitres'] * problem['cargoDensityGramsPerM3'] // 1_000_000) for a in problem['bulkAreas'])
    rows = []
    for pallets, all_containers in sorted(combined.items()):
        cmax = all_containers - bag_count
        if cmax < 0:
            continue
        choices = []
        for cargo_containers in range(cmax + 1):
            tare = pallets * pallet_tare + cargo_containers * container_tare
            capacity = pallets * (pallet_gross - pallet_tare) + cargo_containers * (container_gross - container_tare) + bulk_cap
            upper = min(capacity, headroom - baggage_net - baggage_tare - tare)
            choices.append((upper, cargo_containers))
        best, count = max(choices)
        rows.append({'pallets': pallets, 'maxCargoContainersAfterBaggage': cmax, 'bestUpperBoundNetKg': best / 1000, 'cargoContainersAtBestBound': count})
    upper = max(r['bestUpperBoundNetKg'] for r in rows)
    assert upper == witness['cargoNetWeightGrams'] / 1000 == 40701
    return {'scope': __doc__, 'payloadHeadroomKg': headroom / 1000,
            'baggageNetKg': baggage_net / 1000, 'baggageTareKg': baggage_tare / 1000,
            'cargoGrossCeilingKg': (headroom - baggage_net - baggage_tare) / 1000,
            'palletGrossKg': pallet_gross / 1000, 'palletTareKg': pallet_tare / 1000,
            'containerGrossKg': container_gross / 1000, 'containerTareKg': container_tare / 1000,
            'bulkUpperBoundKg': bulk_cap / 1000, 'groupPackingCounts': group_tables,
            'upperBounds': rows, 'maximumUpperBoundNetKg': upper,
            'achievableDatabaseNetKg': witness['cargoNetWeightGrams'] / 1000}


if __name__ == '__main__':
    print(json.dumps(certificate(), indent=2))
