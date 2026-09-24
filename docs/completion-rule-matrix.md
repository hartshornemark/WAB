## H1 — Special Loads

| Section | Applicability | Incomplete | Partial | Configured |
|---|---|---|---|---|
| Exceptions to ICAO / IATA DGR Incompatibility Charts | Checkbox controlled | Active with no row | Active with saved but incomplete data | Active with at least one complete Special Load Code / Incompatible With row |
| Exceptions to IATA Special Loads Incompatibility | Checkbox controlled | Active with no row | Active with saved but incomplete data | Active with at least one complete Special Load Code / Incompatible With row |
| Special Loads | Checkbox controlled | Active with no row | Active with saved but incomplete data | Active with at least one complete Hold, Special Load Code and non-negative whole Maximum Quantity row; zero prohibits the load, while Compartment or Position and Remarks are nullable |
| Additional Special Load Requirements | Unsupported | Excluded | Excluded | Excluded |

Unchecked supported sections display **NOT ACTIVE** and are excluded from H1 completion. Special Loads is divided by D2 hold type: bulk holds use the optional **Compartment** field and ULD holds use the optional **Position** field. A mixed ULD aircraft can therefore use both subsections. No saved row means unrestricted. In Bulk Holds, a saved Maximum Quantity of **0** explicitly prohibits that Special Load for the selected hold and optional compartment and automatically sets the read-only remark **Not Permitted This Hold**. Increasing the quantity clears that automatic remark. The single Section 3 completion rule is satisfied by at least one complete row across either subsection. H1 is configured after applicability is reviewed and every active supported section is configured. If no supported section is active, the reviewed page is configured.

# Configuration Completion Rule Matrix

Status values are calculated from saved data and the rules below. They are never selected directly by a user.

| Status | Display text | Meaning |
|---|---|---|
| Red | **INCOMPLETE** | A mandatory prerequisite is missing, the section has not been reviewed, or no meaningful configuration has been saved. |
| Amber | **PARTIALLY CONFIGURED** | Some relevant data has been saved, but at least one applicable completion rule is not satisfied. |
| Green | **CONFIGURED** | Every applicable completion rule is satisfied by valid saved data. |

## Status badge design

The shared badge uses the supplied aircraft-in-rounded-square symbol followed by the full uppercase status text. The symbol should be recreated as a scalable application SVG so it remains sharp, inherits the status colour, and does not require separate image files for each state.

| Status | Foreground | Background | Badge text |
|---|---|---|---|
| Red | `#a12c2c` | `#fdebec` | **INCOMPLETE** |
| Amber | `#745514` | `#fff4dc` | **PARTIALLY CONFIGURED** |
| Green | `#25633b` | `#e7f5ec` | **CONFIGURED** |

Design rules:

1. The aircraft symbol and text always appear together; colour and icon alone never communicate status.
2. The icon uses the same foreground colour as the status text and the rounded square uses the corresponding pale background.
3. Section badges use a compact version. Page, aircraft and carrier summaries may use a larger version with the same proportions.
4. The badge exposes the full status text to assistive technology.
5. **Unsupported**, **Out of Scope**, and **Skipped** use the existing neutral grey treatment rather than a Red/Amber/Green badge.
6. Badges remain static and do not pulse, flash or animate.

## Shared rules

1. Only saved data contributes to status. Unsaved drafts and master suggestions do not count.
2. Existing values are revalidated when status is calculated. A legacy or manually changed value can therefore produce Amber.
3. An optional section is Green only after an authorised user has reviewed it and either:
   - confirmed that it does not apply; or
   - saved valid applicable data.
4. **Unsupported**, **Out of Scope**, and deliberately skipped pages do not contribute to page, aircraft, or carrier status.
5. Remarks, labels and inventory records are optional unless a specific rule below says otherwise.
6. A blocking prerequisite makes the dependent page Red. Examples are missing B1 units for B2–B5 and incomplete C1 units for later aircraft pages.

## Aggregation

### Page

- **CONFIGURED**: every included section is Green.
- **INCOMPLETE**: a blocking prerequisite is Red, or every included section is Red.
- **PARTIALLY CONFIGURED**: every other mixture, including one or more Green sections with one or more Red or Amber sections.

### Aircraft Type and Sub-Type

- C1 is a blocking prerequisite.
- **CONFIGURED**: every active, supported C page is Green.
- **INCOMPLETE**: C1 is Red, or no active C page contains configured data.
- **PARTIALLY CONFIGURED**: every other state.
- C6 is excluded while it remains skipped.
- C7 Lateral Imbalance is excluded while it remains unsupported.

### Carrier

- B1 is a blocking prerequisite for the later B pages.
- **CONFIGURED**: B1–B5 are Green and every carrier aircraft is Green.
- **INCOMPLETE**: B1 is Red, or no B page and no aircraft has meaningful configured data.
- **PARTIALLY CONFIGURED**: every other state, including a carrier with no configured aircraft.

---

# A Section

## A2 — Carriers Contacts

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Carrier Contact Details | Mandatory | No contact value has been supplied. | Some contact data exists, but Address line 1, City or Country is absent, or a supplied Email or Teletype value is invalid. | Address line 1, City and Country are supplied, and every supplied contact value passes its format and length rules. |

## A5 — Automatic Documents

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Automatic Loadsheet Documents | Mandatory | No automatic loadsheet document is selected. | Not used. | At least one automatic loadsheet document is selected. |

A1 and A4 are **NOT REQUIRED**. A3 is **UNSUPPORTED**. They are excluded from A-section and overall progress. A2 and A5 are the two assessed A pages.

---

# B Section

## B1 — Standard Units and Codes

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Standard Units and Starting Weight Principle | Mandatory | Weight Unit, Volume Unit and Starting Weight Principle are all absent. | Some selections exist, or saved legacy values do not pass the current allowed-value rules. | Weight Unit is KG or LB; Volume Unit is m³ or ft³; Starting Weight Principle is Basic Weight or Dry Operating Weight. |
| Commodity Density Settings | Mandatory | All three values are blank, or B1 Weight or Volume Unit is missing. | One or two densities are missing, or a saved value is not positive. | Checked Baggage, General Cargo and General Mail are all populated with positive values using the selected carrier units. |
| Carrier Class Codes | Mandatory | No carrier-specific rows have been saved. Master suggestions do not count. | Carrier rows exist but there are more than four, or a code, priority or description fails validation. | One to four carrier classes; one-letter unique codes; unique priorities 1–4; valid descriptions. |
| Carrier Load Commodity Codes | Mandatory | No carrier-specific rows have been saved. Master suggestions do not count. | Carrier rows exist but the set fails a code, uniqueness or description rule. | One to 200 carrier codes; unique one or two character alphanumeric codes; valid descriptions. |

**B1 page:** Green only when all four sections are Green.


## B2 — Crew and Crew Baggage Weights

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Crew Weights | Mandatory | B1 Weight Unit is missing, or no B2 record exists. | A record exists but any Male/Female Flight Deck or Cabin Crew weight is absent or invalid. | All four crew weights are positive whole numbers. |
| Crew Hand Baggage | Mandatory choice | No B2 record exists. | Inclusion choice or required separate values are inconsistent. | “Included” is explicitly saved; or both separate hand-baggage values are valid whole numbers of zero or more. |
| Crew Hold Baggage | Mandatory | No flight applicability is selected. | A selection exists but one of its Flight Deck or Cabin Crew values is missing or invalid. | All Flights is selected alone, or Longhaul and/or Shorthaul is selected; both weights exist for every selected category. |

**B2 page:** Green only when all three sections are Green. Missing B1 Weight Unit makes the page Red.

## B3 — Passenger and Hand Baggage Weights

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Standard Passenger Weights — All Flights | Mandatory | B1 Weight Unit is missing, or the default record is absent. | A record exists but a required passenger or conditional hand-baggage value is missing or invalid. | Male, Female and Child are positive whole numbers; Infant is a whole number of zero or more; Adult may be blank; Hand Baggage is included or has a valid separate value. |
| Flight Variations | Optional, but must be reviewed | No review has been recorded. | Carrier variations exist but the set fails code, description or uniqueness validation. | Reviewed and deliberately empty, or every adopted variation has a unique three-character alphanumeric code and valid unique description. |
| Class-Specific Passenger Weights | Optional, but must be reviewed | No review has been recorded. | Rows exist but a class/variation pair is duplicated, references an unavailable class or variation, or contains invalid weights. | Reviewed and deliberately empty, or every row uses a saved B1 class, Standard/Default or an adopted variation, a unique pair, and valid passenger weights. |

**B3 page:** The Standard Passenger Weights section is blocking. Once it is Green, unreviewed optional sections produce Amber rather than Red.

**Required status metadata:** Flight Variations and Class-Specific Passenger Weights each need a reviewed/applicability state because an empty list can be intentional.

## B4 — Standard Baggage Weights and Planning

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Default Weight per Piece | Selected by default; mutually exclusive with Per-Passenger/Variation weights | Selected but B1 Weight Unit is missing or the default record is absent. | Selected and a record exists, but method or required Male, Female or Child weight is invalid. | Selected with Standard or Actual method saved; retained Male, Female and Child values are valid whole numbers; optional All-Passengers and seasonal values are valid when populated. Shown as SKIPPED when not selected. |
| Baggage Weights per Passenger and Variations | Applies only when Default Weight per Piece is unchecked | Selected but the fixed baseline row is absent or Weight per Passenger remains Unset. | Baseline or additional rows contain invalid/duplicate scope, unavailable references, or an active Standard method without a value. | Fixed baseline identity is intact and every saved row has unique valid scope, methods and active values. Shown as SKIPPED while Default Weight per Piece is checked. |
| Baggage Planning Assumptions | Mandatory | No saved planning row exists; the screen displays a suggested All Flights / All Classes row using one bag and the Standard All-Passengers piece weight. | Scope or numeric values are invalid, or Average Bag Volume is blank while B1 Checked Baggage Density is also blank. | At least one saved row exists; all rows have unique Class/Variation scope, valid Bags and Weight averages, and either Average Bag Volume or a B1 Checked Baggage Density fallback. |

**B4 page:** The selected baggage-weight method and Planning Assumptions are blocking. The unselected baggage-weight method is SKIPPED. Missing B1 Weight Unit makes the page Red.

**Required status metadata:** The Per-Passenger/Variation section stores `APPLIES` or `NOT_APPLICABLE`; existing carriers default to `NOT_APPLICABLE` so All Flights Weight per Piece remains selected. Planning completeness comes from its saved operational row rather than a review-only flag.

## B5 — Aircraft-specific ULD Specifications

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED | SKIPPED |
|---|---|---|---|---|---|
| ULD Specifications | Decided independently for each Carrier + Aircraft Type + Aircraft Series/Sub-Type | The applicability checkbox is selected but B1 Weight or Volume Unit is missing, or no ULD Type is configured. | One or more ULDs exist but a code/type, whole-number weight, volume, default-per-type or uniqueness rule fails. | The applicability checkbox is selected, at least one valid ULD Type exists, and exactly one default ULD Code is selected for every ULD Type. | “This Aircraft Type Can Accept Unit Load Devices” is unchecked. |
| ULD Inventory | Optional when B5 applies | Never incomplete solely because it is empty. | An existing saved inventory row fails serial, Carrier Code, uniqueness or range-order validation. | Empty, or all saved rows have two-character Carrier Codes, five-digit serial values and Start no greater than End. | B5 is skipped for this aircraft. |

**B5 page:** The page is evaluated for the selected aircraft identity. It is SKIPPED when the applicability checkbox is unchecked; otherwise it requires at least one valid ULD Type and valid saved inventory rows.

**Aircraft identity and preservation:** Specifications, defaults and inventory are keyed by Carrier IATA + Aircraft Type IATA + Aircraft Series/Sub-Type. Unchecking an active aircraft requires confirmation and then deletes that aircraft’s ULD specifications and inventory.

---

# C Section

## C1 — Aircraft Type or Fleet

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Aircraft Identity | Mandatory | Aircraft record or Aircraft Name is absent. | Identity exists but Type, Series/Sub-Type or Aircraft Name fails validation. | Three-character alphanumeric Aircraft Type; one-to-four character alphanumeric Series/Sub-Type; valid Aircraft Identity Name and Aircraft Name. Manufacturer remains optional and does not reduce status. |
| Aircraft Units of Measure | Mandatory | No unit groups have been saved. | Some groups are present or a saved value is outside its allowed options. | One valid selection is saved for Weight, Length, Liquid Volume, Volume, Fuel Density and Moments. |
| Remarks | Optional | Not applicable. | Not applicable unless an over-length legacy value exists. | Blank or no more than 2,000 characters. |

**C1 page:** Green when Aircraft Identity and all unit groups are Green. C1 is a blocking prerequisite for every later C page.

## C2 and C3 — Balance and Special Information Output on Loadsheet

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Loadsheet Documents | Mandatory | No document is selected. | A selected document has no selected valid Balance Output item. | At least one document is selected and every selected document has at least one valid Balance Output item. |
| Balance Output | Mandatory for every selected document | No output is selected for any selected document. | Some selected documents have output, but at least one has none; or an output is selected for an unsupported document format. | Every selected document has at least one valid output selection; Print RC appears only for a selected applicable primary item; remarks are within limits. |
| Passenger Trim Output | Mandatory | No Passenger Trim option is selected. | Selected options have missing, duplicated or out-of-range priorities. | At least one option is selected; each selected option has a unique priority from 1 to 3; standalone terminology/remarks are within limits. |
| Lower Loadsheet Information | Optional, but must be reviewed | No review has been recorded. | A saved field exceeds its limit. | Reviewed; both fields may be blank, otherwise Captain’s Information and Pre-LMC Load Message are within their limits. |

**C2/C3 page:** Missing or incomplete C1 makes the page Red. Otherwise, a mixture of completed and incomplete sections is Amber.

**Required status metadata:** Lower Loadsheet Information needs a reviewed state. The saved C2 snapshot should also expose section-level save/review state rather than only a page-level `exists` flag.

## C4 — Basic Index and MAC Formula

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Formula Values | Mandatory | C1 Length Unit is missing or no C4 row exists. | Some legacy values exist but one is missing or invalid. | Reference Arm and LEMAC/LERC are finite; K is a whole number; C is a positive whole number; MAC/RC Length is positive; all values are within the supported range. |

**C4 page:** Its single section determines the page status.

## C5.1 — Balance Envelope

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Balance Envelope Status | Mandatory | Curtailed/Not Curtailed has not been selected. | Not applicable: a saved Boolean is complete. | Curtailed or Not Curtailed is explicitly saved. |
| Maximum Weights | Mandatory | One or more of MZFW, MLAW, MTOW or MRW is absent, or neither a fleet DOW nor Standard Fleet Weight is available. | Values exist but are not positive whole numbers or fail Effective DOW ≤ MZFW ≤ MLAW ≤ MTOW ≤ MRW. | All four positive whole-number maxima exist; an Effective DOW is available; and the full hierarchy is satisfied. |
| Zero Fuel Envelope | Mandatory | FWD or AFT has fewer than two points. | Points exist but fail uniqueness, value range, first-weight coverage, maximum-weight, or final-point rules. | FWD and AFT each have at least two unique positive Weight points; each first Weight is no greater than the Effective DOW; Index is finite; optional % MAC is 0–100; no Weight exceeds MZFW; both final Weights equal MZFW. |
| Take-Off Envelope | Mandatory | FWD or AFT has fewer than two points. | Points exist but fail uniqueness, value range, first-weight coverage, maximum-weight, or final-point rules. | Equivalent Zero Fuel rules using MTOW, with each first Weight no greater than the Effective DOW. |
| Landing Envelope | Mandatory | FWD or AFT has fewer than two points. | Points exist but fail uniqueness, value range, first-weight coverage, maximum-weight, or final-point rules. | Equivalent Zero Fuel rules using MLAW, with each first Weight no greater than the Effective DOW. |

**C5.1 page:** Green only when all five sections are Green. Missing C1 Weight Unit makes the page Red.

**Effective DOW:** Use the smallest positive fleet DOW for the matching carrier, Aircraft Type and Series/Sub-Type. If none is available, use `Basic_Aircraft_Data.Standard_Fleet_Weight`. This rule ensures that an empty ferry flight, where Actual Zero Fuel Weight equals DOW, remains within the published envelope.

## C6 — Curtailments

C6 is currently skipped and has no active database integration. It receives no Red/Amber/Green status and is excluded from aircraft and carrier aggregation until support is activated.

## C7 — Ideal Trim, Tipping etc.

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Ideal Trim | Must be reviewed; may be not applicable | Applicability has not been reviewed. | Applicable is selected but there are no points, or saved points fail validation. | Explicitly Not Applicable; or Applicable with one or more unique positive Weight points, at least one Index or % MAC/RC value per point, % MAC/RC of 0–100, and no Weight above MRW. |
| Tipping Limits | Must be reviewed; may be not applicable | Applicability has not been reviewed. | Applicable is selected but there are no points, or saved points fail validation. | Explicitly Not Applicable; or Applicable with the same point rules as Ideal Trim. |
| Lateral Imbalance | Unsupported | Excluded. | Excluded. | Excluded. |

**C7 page:** MRW from C5.1 is required before an applicable point-based section can be Green. Lateral Imbalance does not affect status.

**Required status metadata:** The current `false` defaults for Ideal Trim and Tipping Limits do not distinguish “Not Reviewed” from “Not Applicable.” These must become nullable or gain a separate reviewed state before C7 status is introduced.

---

# Required metadata before implementation

The following sections can legitimately be empty and therefore need an explicit review/applicability state:

| Page | Section | Proposed saved state |
|---|---|---|
| B3 | Flight Variations | `NOT_REVIEWED` / `REVIEWED` |
| B3 | Class-Specific Passenger Weights | `NOT_REVIEWED` / `REVIEWED` |
| B4 | Additional Baggage Weight Sets | `NOT_REVIEWED` / `REVIEWED` |
| B4 | Baggage Planning Assumptions | `NOT_REVIEWED` / `REVIEWED` |
| B5 | ULD Specifications | `NOT_REVIEWED` / `APPLIES` / `NOT_APPLICABLE` |
| C2/C3 | Lower Loadsheet Information | `NOT_REVIEWED` / `REVIEWED` |
| C7 | Ideal Trim | `NOT_REVIEWED` / `APPLIES` / `NOT_APPLICABLE` |
| C7 | Tipping Limits | `NOT_REVIEWED` / `APPLIES` / `NOT_APPLICABLE` |

A shared review-state record is preferable to adding unrelated status columns to every operational table. The operational data remains authoritative; the review state only resolves deliberate-empty versus untouched sections.

# Implementation boundary

The first implementation should add:

1. a shared status type and badge;
2. pure completion evaluators for each page;
3. a shared review/applicability state for sections that may be empty;
4. section and page status in existing read functions;
5. aircraft aggregation across active C pages;
6. carrier aggregation across B pages and aircraft;
7. a checklist containing the reasons behind every non-Green status.

No colour should be calculated from row count alone where an empty configuration may be intentional.

---

# E Section

## E2 — Crew & Pantry Codes

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Crew Codes | Mandatory | No Crew Code row exists. | A row exists but its code, Flight Deck location/total, Cabin Crew location/total or uniqueness rule is invalid. | At least one complete row exists and every saved row is valid. Flight Deck and Cabin Crew baggage locations are optional; any supplied value must reference an Aircraft Hold defined for the same aircraft on D2. |
| Pantry Codes | Mandatory | No Pantry Code row exists. | A row exists but its code, Galley Locations, Total Weight, Balance Arm, Index or uniqueness rule is invalid. | At least one complete row exists and every saved row is valid. Zero Total Weight and a zero Index are valid. |

**E2 page:** Green only when both sections are Green. Index displays to one decimal place, Balance Arm to three decimal places and whole-number weights without digit grouping.

## E5 — Fleet/Aircraft Weights

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Fleet Weights | Applies only when selected on E5 | No approach is selected, the E1.2 fleet baseline is incomplete, or no complete registration row exists. | Relevant saved data exists but a required registration, Weight adjustment, Index adjustment or validation rule fails. | Fleet Weight and Fleet Index exist in E1.2, and at least one valid row supplies Registration, Weight adjustment and Index adjustment. |
| Individual Aircraft Weights | Applies only when selected on E5 | No approach is selected or no complete registration row exists. | Relevant saved data exists but a required Registration, actual Weight, actual Index or validation rule fails. | At least one valid row supplies Registration, positive actual Weight and actual Index. |

**E5 page:** Exactly one approach is selected on E5. The selected section alone determines status. E1.1 controls whether calculated or entered actual values are stored as Dry Operating Weight / Index or Basic Weight / Index.

**Fleet calculation:** Actual Weight = E1.2 Fleet Weight + E5 Weight adjustment. Actual Index = E1.2 Fleet Index + E5 Index adjustment.

**Registration preservation:** E5 updates the canonical registration-reference row in `Carrier_Aircraft_Fleet`. Detailed crew and pantry combination rows remain intact. E1.2 baseline changes recalculate canonical actual values from the saved E5 adjustments.

---

# F Section

## F1 — Aircraft Limiting Weights

| Section | Applicability | INCOMPLETE | PARTIALLY CONFIGURED | CONFIGURED |
|---|---|---|---|---|
| Maximum Weights Tables | Mandatory and provisioned | Rules pending. This section does not currently determine page completion. | Rules pending. | Rules pending. The default `ALL` table remains available and additional named tables may be added. |
| Aircraft Limiting Weights | Mandatory | No persisted complete row exists. Proposed C5.1 values do not count until saved. | At least one persisted row exists, but one or more required values or validation rules fail. | At least one persisted complete row supplies Weight Table Name, Registration, Zero Fuel Weight, Landing Weight, Take Off Weight and Ramp/Taxi Weight. Remarks are nullable. |

**F1 page:** Section 2 alone determines the current page status while Section 1 rules remain pending.

**C5.1 relationship:** Registration-specific limits may differ. C5.1 MZFW, MLAW, MTOW and MRW must equal the highest saved F1 value in the corresponding column. Saving F1 synchronises those C5.1 maxima; a direct C5.1 change that disagrees with saved F1 rows is rejected.

**Weight hierarchy:** Every F1 row must satisfy Zero Fuel Weight ≤ Landing Weight ≤ Take Off Weight ≤ Ramp/Taxi Weight. All weights are positive whole numbers displayed without digit grouping.
