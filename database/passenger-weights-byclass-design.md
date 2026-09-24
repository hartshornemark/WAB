# Proposed Carrier_Passenger_Weights_BYCLASS

Status: approved and applied on 17 September 2026. Table, validation triggers, RLS policies and variation access created. B3 UI and save/read RPCs subsequently completed; see passenger-weights-b3-verification.md.
Schema: Basic_Carrier_Record.

## Record structure

One row represents a complete passenger-weight set for a carrier, class and optional flight variation. A NULL variation means the standard/default set for that class, not an unknown variation. Named variations are explicit configurations; this design does not infer which applies when flight characteristics overlap.

| Column | PostgreSQL type | Requirement |
| --- | --- | --- |
| Passenger_Weight_Set_ID | uuid | Primary key, generated UUID; stable row identifier |
| Carrier_IATA | varchar(2) | Required; exactly two characters; references Basic_Carrier_Data.Carrier_IATA |
| Class_Code | varchar(1) | Required uppercase A–Z; must be a saved class for this carrier on B1 |
| Flight_Type_Variation | varchar(3), nullable | NULL = Standard/Default; otherwise references this carrier's adopted variation |
| Adult | integer, nullable | Positive when supplied; matches the optional Adult field in ALLFLIGHTS |
| Male | integer | Required, positive |
| Female | integer | Required, positive |
| Child | integer | Required, positive |
| Infant | integer | Required, zero or greater |
| Passenger_Weights_Include_Handbaggage | boolean | Required; default true, matching ALLFLIGHTS |
| Hand_Baggage_Weight | integer, nullable | Zero or greater when supplied; required when hand baggage is not included under the initial standard-weight model |
| Remarks | text, nullable | Proposed maximum 2,000 characters per weight set |

No numeric passenger or baggage weights are automatically populated. Units follow the carrier's B1 weight-unit setting, consistent with the existing passenger table and B2. Changing that setting must not silently convert existing numeric values; unit-change handling should be reviewed in the B3 save implementation.

## Keys and relationship protection

- UNIQUE NULLS NOT DISTINCT (Carrier_IATA, Class_Code, Flight_Type_Variation), supported by the project's PostgreSQL 17: one default per carrier/class, one row per named variation.
- Composite foreign key (Flight_Type_Variation, Carrier_IATA) to Carrier_Flight_Variations (Flight_Type_Variation, Carrier_IATA). NULL variation bypasses this optional relationship. An adopted variation from another carrier is not valid.
- Restrict deletion or code changes of a variation referenced by weight sets; descriptions may change. No automatic cascading deletion of weights.
- Class membership cannot use a conventional foreign key to the existing four-column Carrier_Class_Codes layout. Implementation must validate membership against all four saved class-code columns and protect the reverse relationship when classes are changed or deleted.
- Class membership checks and class edits must share locking, so concurrent edits cannot create an orphan. A class priority change is allowed if its code remains present; removal or renaming of a referenced code is rejected until its weight records are resolved. Do not attach weights to priority slots.
- Carrier ownership is immutable after row creation, consistent with existing table protections.
- Master classes/variations are suggestions only. Adopt and save them for the carrier before creating linked weight sets.

## Permissions and application integration

- Enable RLS at creation and explicitly revoke PUBLIC/anon access.
- Authorised carrier users with the agreed operating-configuration view permission may read; Solution Administrators and Carrier Administrators may insert, update and delete within their authorised carrier scope.
- Reuse verified private permission helpers, with UPDATE USING and WITH CHECK policies. Keep functions SECURITY INVOKER and restrict execution to authenticated users.
- Check current class and variation table read policies support authorised writes; Carrier_Flight_Variations currently has RLS with no policies, so its access configuration must be included in the B3 integration approval.
- Save the full weight set atomically and reject stale edits. Do not overwrite ALLFLIGHTS weights.
- Add B3 application ports and Supabase adapters separately; this document does not implement the screen or RPC functions.

## Scope choices proposed for approval

1. Include support for named variations now, with Standard/Default represented by NULL rather than inserting an artificial master code.
2. Initially use a separate standard hand-baggage value when baggage is excluded, matching the current ALLFLIGHTS structure. Actual hand-baggage mode remains an open product decision; it would require a separate mode field and conditional validation before implementation.
3. Use per-row remarks with the proposed 2,000-character limit. Sheet-level remarks can be added separately if required.
4. Empty BYCLASS records mean no saved class-specific set; no implicit records or defaults are inserted.

## Verification required when applied

Verify valid defaults and variations; duplicate default and named rows; missing/foreign-carrier variations; unsupported class codes; referenced class/variation deletion or rename; priority-only changes; negative/null/zero weights; baggage inclusion rules; administrator writes and unauthorised/cross-carrier/anonymous denials; concurrent class edits; unchanged existing passenger data. Run the security advisor after deployment.
