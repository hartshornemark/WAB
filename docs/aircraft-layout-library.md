# Global aircraft layout library

Implemented 25 September 2026. Both hold and seat-map viewers now load the active template from Supabase. There is no carrier-specific SVG copy and no local runtime fallback.

## Stored records

- Private Storage bucket: `aircraft-layouts`.
- Immutable, content-addressed objects: `<type>/<series>/<sha256>.svg`.
- `Basic_Carrier_Record.Aircraft_Layout_Versions`: SVG path, checksum, byte size, version, aircraft type/series, physical nose arm, datum description/source, source drawing and complete calibration JSON.
- `Basic_Carrier_Record.Aircraft_Layout_Active`: one active version per aircraft type/series. SVG and calibration are selected together in one database read.
- `MASTER_Aircraft_Type_IATA.Balance_Arm_At_Nose`: default for new carrier C4 records. Publication updates this value from the version in the same transaction. Existing carrier C4 overrides are preserved.
- C4 reference station, K/C constants, MAC/RC and LEMAC/LERC remain in their existing database records.

## Datum and drawing coordinates

All longitudinal physical values are metres. The nose is at balance arm **+2.540 m** for both stored aircraft. Datum zero is forward of the nose. Seats use each carrier's C4 nose arm and its C4 index formula.

Calibration `noseArm` is the existing **hold coordinate origin**, not necessarily the physical nose arm: A319 = 2.540; A320 = 0.000. The accepted A320 hold boundaries use that legacy coordinate basis. Its aft hold drawing offsets remain −2.735 m for holds 3, 4 and 5. These adjustments must never be applied to passenger rows.

Calibration stores aircraft length, nose X (`tailX`, retained legacy field name), longitudinal span, centreline Y, image frame, crop bounds, hold band dimensions, door label coordinates, offsets and default hold boundaries. Drawing coordinates use the SVG's existing coordinate system. Projection is `noseX - (arm - holdOrigin) * span / length`. Seat maps substitute the carrier C4 nose arm for the hold origin.

## Access and publication

Only users with global `AIRCRAFT_CONFIG_EDIT` may publish. Viewing requires global aircraft-view permission or carrier aircraft-view permission for a matching aircraft. Anonymous and unrelated users cannot read the metadata or objects. Signed image URLs expire after one hour; reopening the viewer obtains a fresh URL. Storage objects have no authenticated UPDATE or DELETE policy. Metadata tables have no authenticated mutation grants; controlled publication updates the active pointer.

Initial publication is available at `/admin/aircraft-layouts`. It checks the approved manifest, uploads without replacement, downloads the stored file to verify its SHA-256 and activates the version only after verification. It is safe to retry and will not replace a newer active version with version 1. The manifest is in `src/infrastructure/aircraft-layouts/seed.json`; original SVGs remain in `src/assets/aircraft-layouts` as recovery copies.

Future templates: create a new version through a reviewed migration (complete calibration, source and checksum), upload the exact SVG through an authorised Storage client, download and verify its checksum, then call `activate_aircraft_layout`. Review the rendered hold and seat overlays before switching versions. Do not overwrite an existing object or version. Rollback selects the previous verified version and restores its master datum; carrier overrides remain unchanged. A general-purpose administrator editing/upload interface is not implemented.

## Verification

Both uploaded objects were downloaded and checksum-verified before publication. Regression tests preserve the approved A319/A320 geometry, distinguish physical datum from hold origin, and reject missing/corrupt/cross-aircraft calibration. Live checks include ZZ A319 hold layout and BC A320 configurations A/B. Unauthorised metadata, object and publication access are denied in database tests.

Back up **both** Storage object bytes and database records; a database-only backup is insufficient to restore the complete library.

## Shared airframe master geometry

`Airframe_Geometry_Families` and its immutable version tables separate the
physical airframe from an operational aircraft identity. An identity such as
`321 / P2F` or a future passenger `321` is assigned explicitly to one profile
in the active `AIRBUS_A321` family version. A missing dedicated SVG can then use
the family's verified source SVG without copying or recalibrating it.

Profiles distinguish geometry that affects an overlay: standard passenger,
Airbus Cabin Flex, P2F and XLR. Engine choice alone does not create another
airframe family. Assignment is deliberately explicit; subtype text is never
used to guess ACF, XLR or a conversion.

Master decks, structural cabin/hold zones and doors are normalized child
records. Only authoritative physical geometry belongs there. Carrier maximum
weights, volumes, indexes, compartments, ULD arrangements, cabin areas, rows
and seat groupings remain carrier configuration. New geometry is published as
a complete family version, and activation is rejected if it omits a profile
already assigned to an aircraft identity.

The geometry tables intentionally have no direct authenticated grants or RLS
policies. Carrier reads and administrator changes pass through the permission-
checked `get_aircraft_master_geometry`, `assign_airframe_geometry` and
`activate_airframe_geometry` functions.

## A321-P2F (28 September 2026)

The user-supplied `Airbus_A321_WTF.dxf` (2013 ASCII DXF) supplies one general
A321 plan for both Main Deck and Lower Deck. Rebuild with
`output/aircraft-calibration/a321-p2f/build-template.py`. Source units are labelled
mm; original plan endpoints span 44.62930078125 m. The separate side/front views
are excluded. Curves are flattened within 1 mm, then clipped to the fuselage
band. Geometry/checksum provenance is saved alongside the script.

The initial template records the existing ZZ C4 nose arm of 0 m as provisional.
The live 321-P2F overlay follows its carrier's saved C4 datum without changing C4.
The original drawing does not establish P2F-specific cargo doors.

When optional D2 limits are absent, complete D3 loading-position footprints can
supply an occupied range for a ULD hold. This range is explicitly labelled and
is not stored as a structural hold boundary. Supplied D2 boundaries take
precedence. A hold without usable limits/footprints is listed as not drawn;
other fully located holds remain visible. Bulk boundaries are never inferred
from a centroid. Holds and configurations are matched by deck-aware hold ID.
