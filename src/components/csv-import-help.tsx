"use client";

import { PageHelp } from "@/components/page-help";

type Kind = "d2" | "d3" | "g1" | "standard" | "tank" | "schedule" | "c11";
const titles: Record<Kind,string> = {
  d2: "D2 — Hold CSV",
  d3: "D3 — ULD positions CSV",
  g1: "G1 — ULD compatibility CSV",
  standard: "C8 — Standard fuel tables CSV",
  tank: "C8 — Tank curves CSV",
  schedule: "C8 — Loading schedules CSV",
  c11: "C11.1 — Weight / %MAC matrix CSV",
};

export function CsvImportHelp({kind}:{kind:Kind}) {
  return <PageHelp icon title={titles[kind]}>
    <section><h3>Preparing your file</h3><p>Download the template and keep its headings. Use decimal points, without thousands separators or unit suffixes. Leave unknown optional values blank; zero is a real value. Save as comma-separated CSV. Example values must be replaced with your aircraft data.</p></section>
    <section><h3>Aircraft identity protection</h3><p>Every aircraft data template includes Aircraft Type IATA and Series/Sub-Type. Keep both values on every data row. They must match the aircraft page where the file is selected; a missing or different identity blocks the import. Download a fresh template from the intended aircraft page rather than reusing another type&apos;s file.</p></section>
    {kind === "d2" && <>
      <section><h3>Hold Type</h3><p>Enter <strong>BLK</strong> for a Bulk Hold or <strong>ULD</strong> for a ULD Hold. One file may contain both. Every included Hold Type replaces that complete D2 section; a Hold Type omitted from the file is left unchanged.</p></section>
      <section><h3>Row structure</h3><p>For BLK, use one row per Area. Repeating Deck ID, Hold ID, optional Hold Sub Code and Compartment ID groups Area rows and derives the Hold totals and boundaries. For ULD, use one row per Compartment, leave Area ID blank and repeat identical Hold values when one ULD Hold has several Compartments. Bays and loading positions remain on D3.</p></section>
      <section><h3>Hold identity and deck</h3><p>Enter Deck ID on every row, using the D2 deck code or displayed deck name. For standard lower-deck holds, Hold ID is FWD, AFT or ALB and Hold Sub Code adds optional detail such as FLF or ALA. A ULD Hold may instead use another three-letter Hold ID with no sub-code. Together Hold Type, deck, Hold ID and sub-code identify the saved hold.</p></section>
      <section><h3>Standard three-character Hold IDs</h3><p>Use FWD or AFT without a sub-code when no further detail is needed. Otherwise select the applicable optional sub-code.</p><ul><li><strong>FWD:</strong> Forward; optional sub-codes FLF (Forward Lower Forward), FLM (Forward Lower Mid), FLA (Forward Lower Aft)</li><li><strong>AFT:</strong> Aft; optional sub-codes ALF (Aft Lower Forward), ALM (Aft Lower Mid), ALA (Aft Lower Aft)</li><li><strong>ALB:</strong> Aft Lower Bulk, a separate Bulk Hold rather than an AFT sub-code</li></ul><p>The parent family is derived from the selected code, so it is not an additional CSV row. Compartment IDs may be a single letter or number. BLK rows continue from Compartment to Area; ULD Positions are configured under the applicable ULD Hold compartment on D3.</p></section>
      <section><h3>Door Y/N</h3><p>Enter <strong>Y</strong> when the Hold has a door and <strong>N</strong> when it does not. Repeat the same answer on every row belonging to that Hold. D4 requests door dimensions only for Holds marked Y.</p></section>
      <section><h3>Required and optional values</h3><p>Aircraft Type IATA, Series/Sub-Type, Deck ID, Hold Type, Hold ID, Compartment ID, MAXWT, Index Per Weight Unit and Door are mandatory. Area ID is mandatory for BLK Area rows and must be blank for ULD rows. Hold Sub Code, VOL and all three balance-arm columns are optional. A blank centroid is calculated from Index Per Weight Unit using the saved C4 formula; a supplied centroid is retained. If one balance-arm limit is entered, both forward and aft limits are required and must be in order.</p></section>
      <section><h3>Import and save</h3><p>The preview separately counts Bulk and ULD Holds and checks hold type, hierarchy, identifiers, deck routing, duplicates and numeric values. Selecting <strong>IMPORT &amp; SAVE D2 HOLDS</strong> immediately saves all included sections together, so there is no additional section SAVE step. Fitted-configuration applicability and overrides can then be assigned to the imported rows on D2.</p></section>
    </>}
    {kind === "d3" && <>
      <section><h3>Row routing</h3><p>Deck ID, Hold ID, optional Hold Sub Code and Compartment ID route each row explicitly. Bay ID is the physical/loading position identifier. Use FWD with optional FLF/FLM/FLA, AFT with optional ALF/ALM/ALA, or another configured D2 ULD Hold ID without a sub-code. ALB is a Bulk Hold and uses D2 Area rows rather than D3 Bay rows.</p></section>
      <section><h3>Configuration Code</h3><p>This is the name of the <strong>D3 ULD loading arrangement</strong>, such as A or B. It is not an E1.2 fitted fuel configuration. Choose a short code that identifies the arrangement and repeat it on every row belonging to that arrangement. Importing the same code replaces that saved D3 arrangement.</p></section>
      <section><h3>Required data</h3><p>Define the holds and compartments on D2 and select the ULD identities on B5. Complete C1 and C4 when coordinates need calculating.</p><ul>
        <li><strong>ULD ID / Config:</strong> ULD identity, such as AKH or PAJ.</li>
        <li><strong>Bay ID:</strong> position ID, such as 11, 11L, 11R or A1. Single positions do not need L/R suffixes.</li>
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
      <section><h3>Configuration Code</h3><p>This column means the <strong>E1.2 fitted fuel configuration</strong>. Enter an E1.2 code exactly as displayed, or use <strong>ALL</strong> or leave the cell blank when the tank curve is common to every fitted configuration. If E1.2 has no fitted configurations, use ALL or blank. <strong>STD is not a general label</strong>; it is valid only when STD is an actual E1.2 code.</p></section>
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
    {kind === "standard" && <>
      <section><h3>Configuration Code</h3><p>This column means the <strong>E1.2 fitted fuel configuration</strong>. Enter an E1.2 code exactly as displayed, or use <strong>ALL</strong> or leave the cell blank when the Standard Fuel table is common to every fitted configuration. If E1.2 has no fitted configurations, use ALL or blank. <strong>STD is not a general label</strong>; it is valid only when STD is an actual E1.2 code.</p></section>
      <section><h3>Column guide</h3><ul><li><strong>Aircraft Type IATA / Series/Sub-Type:</strong> repeat the identity shown in the downloaded template on every row.</li><li><strong>Configuration Code:</strong> follow the E1.2 rule above.</li><li><strong>Specific Gravity:</strong> required and greater than zero; repeat it for every row in that table.</li><li><strong>Fuel Weight:</strong> required whole number, zero or greater.</li><li><strong>Index:</strong> required; signed decimals are accepted.</li><li><strong>Fuel Volume:</strong> optional positive whole number.</li><li><strong>H-Arm:</strong> optional signed decimal.</li></ul><p>Use one row per fuel weight. Do not use thousands separators or unit suffixes. The zero-weight, zero-index origin is generated automatically, so it does not need a CSV row.</p></section>
      <section><h3>Several tables in one file</h3><p>Configuration Code plus Specific Gravity identifies a table. A file may contain several configurations, several SG values, or both. Fuel Weight may appear only once within each table.</p></section>
      <section><h3>Import and save</h3><p>The preview checks aircraft identity, fitted configuration codes, duplicates and numeric values. <strong>IMPORT &amp; SAVE TABLES</strong> immediately replaces each matching Configuration Code + Specific Gravity table. Other Standard Fuel tables remain unchanged and no additional section SAVE is required.</p></section>
    </>}
    {kind === "schedule" && <>
      <section><h3>Configuration Code</h3><p>This column means the <strong>E1.2 fitted fuel configuration</strong>. Enter an E1.2 code exactly as displayed, or use <strong>ALL</strong> or leave the cell blank when the loading schedule is common to every fitted configuration. If E1.2 has no fitted configurations, use ALL or blank. <strong>STD is not a general label</strong>; it is valid only when STD is an actual E1.2 code.</p></section>
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
    {kind === "c11" && <>
      <section><h3>One row per matrix cell</h3><p>Each row identifies one Actual TOW and one %MAC point. Enter the stabiliser trim value for a permitted combination. Use a blank cell or a single dash in Stabiliser Trim when that weight/CG combination does not apply.</p></section>
      <section><h3>Column guide</h3><ul><li><strong>Aircraft Type IATA / Series/Sub-Type:</strong> repeat the identity from the downloaded template on every row.</li><li><strong>Actual TOW:</strong> required positive whole number in the aircraft C1 weight unit.</li><li><strong>%MAC:</strong> required CG position; decimals are accepted.</li><li><strong>Stabiliser Trim:</strong> signed numeric trim setting, or blank/dash for a combination that does not apply.</li></ul></section>
      <section><h3>Building the matrix</h3><p>The importer sorts the distinct Actual TOW values into rows and the distinct %MAC values into columns. Include at least two weight rows and two %MAC columns. Every weight row needs at least two numeric trim settings. A missing Actual TOW + %MAC pair is also treated as not applicable.</p></section>
      <section><h3>Review and save</h3><p><strong>APPLY TO MATRIX</strong> replaces the editable grid but does not save it immediately. Review the resulting table, then select the main C11.1 <strong>SAVE</strong> button. C11.2 uses the saved cells and leaves gaps wherever the matrix is blank.</p></section>
    </>}
    <section><h3>If an error appears</h3><p>CSV line numbers include the heading, so line 2 is the first data row. Correct the reported values and select the file again. Check the preview before applying the import.</p></section>
  </PageHelp>;
}
