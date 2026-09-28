# D3 — ULD positions CSV

**Draft user guide**

## What this file does

Creates loading positions and their occupied physical bays for the aircraft's ULD holds. One file can contain multiple holds. A different ULD identity at the same position can have its own arm, limits and footprint.

## Before importing

- Define the holds and compartments on D2, including the correct deck.
- Select the required ULD identities on B5.
- Complete C1 units and C4 if coordinates must be calculated from Index per Weight Unit.
- Check that position names can be matched to the intended compartment. The current importer uses compartment prefixes; for example, 11 belongs to compartment 1 and A1 to compartment A. If the same compartment prefix is used on different decks, do not assume the importer can distinguish them: an explicit mapping is needed.

## Columns

| Column | What to enter |
|---|---|
| Group ID / Config | The ULD identity, such as AKH or PAJ, recognised in MASTER ULD and selected on B5. Despite the heading, this is not the configuration code entered in the preview. |
| Position Name | The position ID, for example 11, 11L, 11R or A1. Separate entities should normally have separate rows. |
| Max Weight | The approved maximum weight at this position, in the aircraft's selected weight unit. |
| Centroid | Balance arm in the aircraft's C1 length unit. Optional if C4 and Index per Weight Unit allow calculation. |
| FWD | Forward footprint limit, in the same C1 length unit. Preserve the source value when available. |
| AFT | Aft footprint limit, in the same C1 length unit. Preserve the source value when available. |
| Index per wt unit | Signed index change per one aircraft weight unit. Enter the source precision; do not round it unnecessarily. |
| **Fore-Aft Dimension (in)** | Optional. Blank uses MASTER ULD base length. To override, enter **one positive number:** the ULD dimension running along the aircraft, e.g. `88` or `125`. Always inches, independently of C1 arm units. No second dimension, orientation code or degree value is needed. |

## Supplied values take precedence

Use each coordinate provided in the CSV. Calculate only a blank coordinate:

- Centroid = C4 Reference Arm + (C4 C Constant × Index per Weight Unit).
- FWD = Centroid − half the fore–aft dimension, converted to C1 length units.
- AFT = Centroid + half the fore–aft dimension, converted to C1 length units.

The K constant is not added to this per-weight-unit calculation. A supplied value of zero is retained; malformed text is an error, not a request to calculate.

These calculated boundaries describe a ULD footprint centred on the supplied or derived balance arm. If the source gives an offset load centroid or different physical limits, enter its FWD/AFT values explicitly.

## Fore–aft dimension rule

The override applies only to this CSV row/loading arrangement; it does not change MASTER ULD. The resulting FWD/AFT limits are saved with the position.

If both FWD and AFT are present, use them. If either is blank, calculate that limit using Fore-Aft Dimension (in), or MASTER ULD base length when the column is blank or absent. A malformed, zero or negative override is an error; it does not silently fall back to the default.

For a ULD whose stored base length is 88 inches, blank means 88 inches fore–aft; enter 125 for the rotated fit. Defaults are specific to the ULD record, not a universal 88/125 rule. Always check the approved loading arrangement. If no usable dimension or C1 length unit is available, enter explicit limits or complete those settings.

## Example

Illustration only, not operational aircraft data. With C4 Reference Arm 23.117 m and C Constant 1000:

```csv
Group ID / Config,Position Name,Max Weight,Centroid,FWD,AFT,Index per wt unit,Fore-Aft Dimension (in)
PAJ,A1,1513,,,,-0.01474,88
```

This gives a centroid of 8.377 m, a 2.2352 m footprint, FWD 7.2594 m and AFT 9.4946 m.

## Position layouts

- Single positions such as 11 and A1 are supported without L/R suffixes.
- Paired positions such as 11L and 11R remain separate physical bays.
- Do not invent L/R positions for a single-position layout.
- Different identities at the same position remain distinct loading arrangements.
- Review calculated overlaps against the approved loading arrangement, especially where alternative lock positions exist.

## Applying the import

Choose the Configuration Code in the preview. Importing replaces that configuration in every listed hold; other configuration codes remain. Check the hold allocation and number of positions before clicking IMPORT ALL HOLDS.

If a position has no matching D2 compartment, resolve its mapping before importing. The current importer can omit unmatched rows: compare the preview counts with the source file.
