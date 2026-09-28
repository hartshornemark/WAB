# CSV template help — draft

These guides cover the four CSV templates currently available in the aircraft configuration workspace. They are drafts for review before adding a HELP or DOWNLOAD GUIDE link beside each template.

- [D3 — ULD positions](d3-uld-positions.md)
- [G1 — ULD compatibility](g1-uld-compatibility.md)
- [C8 — tank curves](c8-tank-curves.md)
- [C8 — ordered loading schedules](c8-loading-schedules.md)

## Preparing any CSV

1. Download a fresh template from the relevant aircraft page.
2. Keep the column headings. Replace example rows, if present, with your aircraft data.
3. Use decimal points, without unit suffixes or thousands separators: `1250.5`, not `1,250.5 kg`.
4. Leave an unknown optional value blank. Zero means a real value of zero.
5. Save as comma-separated CSV, preferably UTF-8. Preserve position IDs and codes as text in your spreadsheet.
6. Check the import preview, including aircraft, holds, row counts and any errors, before applying it.

CSV line numbers include the heading: line 2 is the first data row. Import acceptance checks the data format and configured relationships; it does not establish that the source values are approved aircraft limits.

## Scope and implementation status

D3 supports an optional Fore-Aft Dimension (in) column. Blank retains the MASTER ULD base-length default; a positive value overrides it for calculating missing limits. Older CSV files without this column remain supported.

There is currently no downloadable CSV template for C8 Standard Fuel Loading (SG / Weight / Index), B5 stock, or MASTER ULD in these page uploaders. Those need separate guides if uploaders are added; do not use a tank-curve CSV as a substitute for a standard fuel table.
