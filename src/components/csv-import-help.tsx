"use client";

import { PageHelp } from "@/components/page-help";

type Kind = "d3" | "g1" | "tank" | "schedule";
const titles: Record<Kind,string> = {
  d3: "D3 — ULD positions CSV",
  g1: "G1 — ULD compatibility CSV",
  tank: "C8 — Tank curves CSV",
  schedule: "C8 — Loading schedules CSV",
};

export function CsvImportHelp({kind}:{kind:Kind}) {
  return <PageHelp icon title={titles[kind]}>
    <section><h3>Preparing your file</h3><p>Download the template and keep its headings. Use decimal points, without thousands separators or unit suffixes. Leave unknown optional values blank; zero is a real value. Save as comma-separated CSV. Example values must be replaced with your aircraft data.</p></section>
    {kind === "d3" && <>
      <section><h3>Required data</h3><p>Define the holds and compartments on D2 and select the ULD identities on B5. Complete C1 and C4 when coordinates need calculating.</p><ul>
        <li><strong>Group ID / Config:</strong> ULD identity, such as AKH or PAJ.</li>
        <li><strong>Position Name:</strong> position ID, such as 11, 11L, 11R or A1. Single positions do not need L/R suffixes.</li>
        <li><strong>Max Weight:</strong> approved position limit in the aircraft weight unit.</li>
        <li><strong>Index per wt unit:</strong> signed index change per weight unit. Retain the source precision.</li>
      </ul></section>
      <section><h3>Coordinates: supplied values come first</h3><p>Centroid, FWD and AFT use the aircraft’s C1 length unit. Supplied CSV values are retained. Blank Centroid is calculated as Reference Arm + C Constant × Index Per Weight Unit. Blank FWD/AFT use half the fore–aft dimension on either side of the centroid, converted to C1 length units.</p></section>
      <section><h3>Loading orientation</h3><p>Fore-Aft Dimension (in) is optional. Leave it blank for the MASTER ULD base-length default. Enter one positive number, such as 88 or 125, to override that default for this row. Supplied FWD/AFT values always take precedence. The calculated limits are saved with the position; MASTER ULD dimensions remain unchanged.</p></section>
      <section><h3>Check the preview</h3><p>Positions are assigned by their D2 compartment prefixes. Check every hold and row count: unmatched rows can be omitted, and identical compartment prefixes on different decks require an explicit mapping. Importing replaces the selected configuration code in every listed hold; other configuration codes remain.</p></section>
    </>}
    {kind === "g1" && <>
      <section><h3>A template for this aircraft</h3><p>Rows come from configured D3 bays and ULD identity columns from B5. Download a fresh template after changing either. Answer cells are deliberately empty.</p></section>
      <section><h3>Complete the matrix</h3><p>Keep Position Bay identifiers exactly as downloaded. Enter Y for permitted or N for not permitted in every ULD cell. Blank does not mean No. Keep all generated rows and columns; do not duplicate positions.</p></section>
      <section><h3>Identities sharing a type</h3><p>G1 currently stores answers by ULD type. Identity columns belonging to the same type must agree for each bay. If the aircraft rules distinguish those identities, retain the source answers and request identity-specific support.</p></section>
      <section><h3>Import result</h3><p>IMPORT COMPATIBILITY saves the reviewed matrix. It does not change B5 specifications or D3 positions. Compatibility describes what is permitted; D3 occupancy determines which overlapping positions become unavailable.</p></section>
    </>}
    {kind === "tank" && <>
      <section><h3>One row per tank and volume</h3><ul>
        <li><strong>Tank Code:</strong> required, one to six letters/numbers.</li>
        <li><strong>Volume:</strong> required whole number, zero or greater.</li>
        <li><strong>Balance Arm:</strong> required; decimals allowed.</li>
        <li><strong>Tank Name / Maximum Volume:</strong> optional. Capacity is a positive whole number.</li>
        <li><strong>Weight / Index / Source SG:</strong> optional source comparison values. Weight is a non-negative whole number; Index can be signed; SG must be positive.</li>
      </ul></section>
      <section><h3>Units and coverage</h3><p>Use the C1 units shown on C8. Volume and Balance Arm are the base data. Do not repeat a volume for the same tank. Include enough points to cover the schedules. Keep tank names, capacities and source SG consistent across rows.</p></section>
      <section><h3>Capacity and replacement</h3><p>If Maximum Volume is blank, the existing capacity is retained, or a new tank uses its highest imported volume. Check that this is correct. APPLY IMPORT replaces curve points for listed tanks in the form, retaining other tanks and existing By Tank weights. Then SAVE the section.</p></section>
      <section><h3>Upload order</h3><p>Tank curves and schedules can be uploaded in either order. Loading-effect calculations need the referenced curves, capacities and aircraft formula settings completed. This template is separate from the Standard Fuel Loading SG/Weight/Index table.</p></section>
    </>}
    {kind === "schedule" && <>
      <section><h3>One row per loading step</h3><ul>
        <li><strong>Schedule Name:</strong> required, up to 100 characters.</li>
        <li><strong>Specific Gravity:</strong> positive value, for example 0.79.</li>
        <li><strong>Step:</strong> consecutive whole numbers from 1, without duplicates.</li>
        <li><strong>Tank Code(s):</strong> tank codes matching the definitions; separate multiple codes with +, for example XTL + XTR.</li>
        <li><strong>Volume Amount / Weight Amount:</strong> fill exactly one column, with the positive amount added during that step—not the cumulative total.</li>
      </ul></section>
      <section><h3>Choose one basis per schedule</h3><p>Use Volume Amount or Weight Amount consistently for all steps of a schedule. Leave the other column empty. Use C1 units shown on C8. The counterpart quantity, cumulative amount and percentage/ratio are calculated.</p></section>
      <section><h3>Upload order and saving</h3><p>Schedules can be uploaded before tank curves; missing tank codes create placeholders. Complete the tank capacities and curves before using calculated loading effects. APPLY SCHEDULE IMPORT adds or replaces matching Schedule Name + Specific Gravity entries in the form; other schedules remain. Then SAVE the section.</p></section>
      <section><h3>Check downloaded rows</h3><p>The download may contain existing schedules. Remove or edit those deliberately before uploading; it is not necessarily an empty template.</p></section>
    </>}
    <section><h3>If an error appears</h3><p>CSV line numbers include the heading, so line 2 is the first data row. Correct the reported values and select the file again. Check the preview before applying the import.</p></section>
  </PageHelp>;
}
