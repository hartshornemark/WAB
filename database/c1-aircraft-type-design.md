# AHM565 C1 - Aircraft Type or Fleet

## Purpose

C1 establishes the aircraft type/subtype context used by the remaining Section C sheets. It separates global aircraft identity from a carrier's aircraft-specific configuration.

## Screen title and context

**1. AIRCRAFT TYPE OR FLEET**  
**(AHM565 Sheet C1)**

The workspace header shows the selected carrier and the selected aircraft type/subtype. Until an aircraft is selected, the remaining Section C pages are unavailable.

## Aircraft identity

| Screen field | Storage | Behaviour |
| --- | --- | --- |
| Manufacturer | `MASTER_Aircraft_Manufactures.Manufacturer_UUID` through `MASTER_Aircraft_Type_IATA` | Searchable autocomplete. Search begins after two characters and returns a short, ranked list. Only a Solution Administrator may add a missing manufacturer. |
| Aircraft Type | `MASTER_Aircraft_Type_IATA.Aircraft_Type_IATA` | Searchable autocomplete for the global three-character aircraft code. If no combined identity exists, a permitted user may open `Add Aircraft Identity`. |
| Series or Subtype | `MASTER_Aircraft_Type_IATA.Aircraft_Series_Subtype` | Selected together with the aircraft type because the pair is the global identity key. |
| Aircraft Name | `Basic_Aircraft_Data.Aircraft_Type` | Carrier-specific load-sheet/display name, exposed through the application as `aircraftName`. |

Manufacturer, Aircraft Type and Series/Subtype are global reference data. A carrier cannot redefine them.

### Add Aircraft Identity

When the searches do not find the required manufacturer/type/subtype combination, a permitted user can create the complete global identity in one guided panel. The panel collects:

1. **Manufacturer** - search and select an existing manufacturer, or add a missing manufacturer inline.
2. **Aircraft Type Code** - exactly three alphanumeric characters. Letters, numbers or any mixture of the two are permitted; spaces and special characters are prohibited. Examples: `319`, `32N`, `7M8`.
3. **Series or Subtype** - one to four alphanumeric characters. Letters, numbers or any mixture of the two are permitted; spaces and special characters are prohibited. Examples: `100`, `8`, `NEO`, `21N`.
4. **Aircraft Identity Name** - the global descriptive name, up to 64 characters.

The application checks for an existing identity as the user enters the type and subtype. It prevents case-insensitive manufacturer duplicates and exact type/subtype duplicates before submission, while database constraints remain authoritative.

After a successful addition, the new identity is selected automatically and its global name is suggested as the carrier's Aircraft Name. The carrier may change that load-sheet/display name without changing the global identity.

Global identity creation is an explicit permission. The initial design assigns it to Solution Administrators through the existing `MASTER_DATA_CREATE` permission; it can also be granted to another role later without changing the screen or database model.

## Units of measure

C1 units are aircraft-specific. On first setup, the application copies the carrier's current B1 units as suggested values. Saving creates an independent C1 snapshot; later B1 changes do not silently alter configured aircraft.

Use one constrained value per category rather than multiple Boolean columns:

| Field | Allowed values |
| --- | --- |
| Weight | `KG`, `LB` |
| Length | `CM`, `M`, `IN`, `FT` |
| Liquid Volume | `L`, `US_GAL` |
| Volume | `M3`, `FT3` |
| Fuel Density | `KG_L`, `LB_L`, `KG_US_GAL`, `LB_US_GAL` |
| Moments | `KG_IN`, `LB_IN`, `KG_CM`, `LB_CM`, `KG_M`, `LB_M` |

Each category is displayed as a compact radio group. Radio buttons enforce one selection within each related group. Selecting another option automatically clears the previous selection. The visible labels use full names and `m³` where applicable.

## Proposed carrier-specific C1 table

`Basic_Carrier_Record.Carrier_Aircraft_C1_Settings`

| Column | Type | Rule |
| --- | --- | --- |
| `Carrier_IATA` | `varchar(2)` | Required |
| `Aircraft_Type_IATA` | `varchar(3)` | Required |
| `Aircraft_Series_Subtype` | `varchar(4)` | Required |
| `Weight_Unit` | `text` | Required; constrained values |
| `Length_Unit` | `text` | Required; constrained values |
| `Liquid_Volume_Unit` | `text` | Required; constrained values |
| `Volume_Unit` | `text` | Required; constrained values |
| `Fuel_Density_Unit` | `text` | Required; constrained values |
| `Moment_Unit` | `text` | Required; constrained values |
| `Remarks` | `text` | Optional; trimmed; maximum 2,000 characters |
| `Updated_At` | `timestamptz` | Used for stale-edit protection |

The primary key is `(Carrier_IATA, Aircraft_Type_IATA, Aircraft_Series_Subtype)`. The same three columns form a foreign key to `Basic_Aircraft_Data`, preventing settings for an aircraft the carrier has not adopted.

## Screen states

### Read-only

- Aircraft identity card: Manufacturer, Aircraft Type, Series/Subtype and Aircraft Name.
- Units card: six saved unit values.
- Remarks appear only when present.
- `Edit C1` is shown only to an authorised administrator.
- `NEXT` opens the next Section C sheet for the same carrier/type/subtype.

### Editing

- Global identity is selected through searchable reference controls, with `Add Aircraft Identity` when the required identity is absent and the user has permission.
- Aircraft Name is editable for the carrier.
- Units are compact radio groups.
- Remarks is optional.
- Buttons: `Save C1` and `Cancel`.
- Invalid fields and their containing group receive the established blue attention frame; the error message uses the established red text.

## Access rules

- Solution Administrator: create global manufacturers and complete aircraft identities; create or edit carrier C1 records.
- Carrier Administrator: select an existing global aircraft identity and create or edit the carrier C1 record.
- Other authorised carrier users: read-only.
- PostgreSQL RLS remains authoritative. React components use application services and repository ports and never call Supabase directly.

## Validation

- Manufacturer selection is required for newly created global aircraft identities. Existing master aircraft rows may remain unassigned during the approved transition.
- Aircraft Type is exactly three alphanumeric characters and is normalised to uppercase. Letters, numbers or a mixture are accepted; spaces and special characters are rejected.
- Series/Subtype is one to four alphanumeric characters and is normalised to uppercase. Letters, numbers or a mixture are accepted; spaces and special characters are rejected.
- Aircraft Name is required, trimmed and at most 64 characters.
- Exactly one unit value is required in every unit category.
- Remarks are optional and limited to 2,000 characters.
- Saves use `Updated_At` to reject stale edits.

## Navigation

Section C starts with an aircraft-selection screen listing the carrier's adopted aircraft type/subtype records. Selecting one opens C1 and fixes that aircraft context for all later Section C pages. A persistent `Change Aircraft` action returns to the aircraft selector.
