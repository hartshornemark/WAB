# G1 — ULD compatibility CSV

**Draft user guide**

## What this file does

Records whether each ULD type is permitted at each configured position bay. It does not create D3 positions or alter B5 specifications.

## Before importing

Complete the relevant B5 ULD selections and D3 positions. Download the template again after changing either: its rows come from the aircraft's configured bays and its ULD identity columns come from B5.

## Filling the template

| Column | What to enter |
|---|---|
| Position Bay | Keep the generated position identifier exactly as supplied. |
| Each ULD column, such as AKH or PAJ | Enter `Y` if permitted or `N` if not permitted. |

The downloaded answer cells are deliberately blank. Complete every answer; blank does not mean No. Keep all generated position rows and ULD columns, and do not duplicate positions.

Example only:

```csv
Position Bay,AKH,PAJ
11,Y,N
A1,N,Y
```

The importer also recognises YES/NO, TRUE/FALSE and 1/0, but Y/N is recommended.

## Current compatibility limitation

Although the template uses individual ULD identity columns, the current G1 result is stored by ULD type. If two identity columns map to the same type, their answers at a position must agree. An error saying those identities disagree is not a duplicate-position error. If the approved aircraft rules genuinely distinguish them, retain the source answers and request identity-specific support rather than forcing them to agree.

## Applying the import

Resolve all preview errors, then choose IMPORT COMPATIBILITY. This saves the matrix as the reviewed G1 result. It does not change the physical dimensions or lock arrangements held in D3.

Compatibility and occupancy are separate: a ULD may be permitted at a position while loading it makes overlapping positions unavailable.
