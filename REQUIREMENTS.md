# SMD Inventory Requirements (Current)

Last updated: 2026-02-09

## 1. Product Goal
Internal SMD inventory tool for:
- tracking on-hand parts
- importing board BOMs (KiCad CSV/TSV)
- estimating build readiness
- consuming stock when boards are built
- undoing build consumption
- running full stock audits via CSV export/import-replace
- planning procurement from board build cart + ad-hoc lines
- exporting DigiKey-ready purchase data

Backwards compatibility is not a priority.

## 2. Tech Stack
- Flutter + Dart
- Firebase Firestore
- `syncfusion_flutter_datagrid` for editable grid UX
- `go_router` for navigation

## 3. App Sections
- `/inventory`: inventory grid with search + filters + add/import
- `/boards`: board gallery/readiness + purchase planner cart (boards + ad-hoc lines)
- `/boards/new`, `/boards/:id`: board editor + BOM import/matching
- `/admin`: history undo + audit CSV export/import-replace

## 4. Canonical Firestore Model

### `inventory`
Required/expected fields:
- `part_#` (string)
- `type` (string)
- `value` (string)
- `package` (string)
- `description` (string)
- `qty` (number)
- `location` (string)
- `price_per_unit` (number|null)
- `notes` (string)
- `vendor_link` (string)
- `datasheet` (string)
- `last_updated` (timestamp)

### `boards`
Required/expected fields:
- `name` (string)
- `description` (string|null)
- `category` (string|null)
- `imageUrl` (string|null)
- `bom` (array)
- `createdAt` (timestamp)
- `updatedAt` (timestamp)

BOM line canonical schema:
- `designators` (string)
- `qty` (number)
- `required_attributes` (map)
  - `part_type` (string)
  - `value` (string)
  - `size` (string)
  - `part_#` (string)
  - `selected_component_ref` (string|null)
- `description` (string)
- `notes` (string)
- `_ignored` (bool)

### `history`
- `action` (`make_board`)
- `board_id`
- `board_name`
- `quantity`
- `timestamp`
- `bom_snapshot`
- `consumed_items` (array of `{doc_id, quantity}`)
- `undone_at` (timestamp|null)

## 5. Core Data Flow

### 5.1 Inventory
1. User edits/adds/imports inventory rows.
2. Inventory writes update Firestore.
3. Board readiness and BOM matching consume current inventory snapshots.

### 5.2 BOM Import
1. CSV/TSV parsed by `CsvParserService`.
2. KiCad-specific conversion done by `KicadBomParser`.
3. Parsed BOM lines auto-matched through `InventoryMatcher`.
4. User reviews statuses (matched/ambiguous/missing), then imports into editor grid.

### 5.3 Readiness
1. `ReadinessCalculator` evaluates non-ignored BOM lines against inventory.
2. Outputs: buildable quantity, readiness %, shortfalls, cost estimate.

### 5.4 Build + Undo
1. `BoardBuildService.makeBoards` resolves every active BOM line.
2. Transaction verifies stock, decrements inventory, writes history row with consumed deltas.
3. `undoMakeHistory` restores quantities from `consumed_items`, marks `undone_at`.

### 5.5 Audit Cycle
1. `InventoryAuditService.exportInventoryCsv` writes full stock snapshot to CSV.
2. User audits/edits in Excel.
3. `replaceInventoryFromCsvText` fully replaces inventory collection from CSV.

### 5.6 Procurement Planner
1. User adds boards with build quantities to the cart from board cards.
2. User can add ad-hoc/manual lines (including inventory-based extras) directly to cart.
3. `ProcurementPlannerService` resolves board BOM demand against inventory and returns:
   - required quantity per resolved part
   - current stock
   - shortage to order
   - unresolved/ambiguous issue list
4. Planner output can be copied as:
   - DigiKey-oriented CSV
   - quick-order `part,qty` lines

## 6. Matching + Parsing Rules (Current)

### 6.1 Matching Priority (`InventoryMatcher`)
1. `selected_component_ref`
2. `part_#` exact canonical match
3. non-passive fallback: BOM `value` as possible MPN
4. passive strict: `part_type + value + package`
5. passive relaxed if unique: `part_type + value`
6. weighted fallback for partial data

Normalization used:
- part-number canonicalization strips separators/case
- package normalization (metric/imperial aliases)
- value normalization (`100nF -> 100n`, `2u2 -> 2.2u`, resistor notation support)
- numeric equivalence for passive values (example: `0.01m` == `10u`)

### 6.2 KiCad BOM Parser (`KicadBomParser`)
- supports column aliases (`Reference`/`Designator`, `Qty`/`Quantity`, etc.)
- skips DNP / excluded rows
- skips mounting-hole mechanical rows
- infers part type from designator/value
- extracts package hints from footprint
- infers likely MPN for IC/connectors when safe

## 7. UX Requirements
- Dark mode is default.
- Layout and controls should stay usable on desktop and mobile widths.
- Build/audit destructive actions require explicit confirmation.
- Grid editing remains primary internal workflow.
- Anyone can view app data.
- Only authenticated UMD-domain users can perform write/edit actions.

## 8. Validation Requirements
- `flutter analyze` must pass.
- test suite must pass (`flutter test`).
- new parsing/matching behavior requires unit tests.

## 9. Still-Missing High-Value Features
These are not blockers for internal use, but are the next obvious additions:
- Low-stock threshold + alert view
- Inventory change log beyond build history (manual edits/import deltas)
- Bulk location move / bulk tag updates
- BOM line "locked choice" flag (prevent auto-repair from changing manual assignment)
- Board versioning (BOM revision history)
- Safer audit dry-run mode (preview row-level replacements before commit)
- Direct DigiKey API/cart handoff (currently CSV/quick-order export)

## 10. Table Package Decision
Current package (`syncfusion_flutter_datagrid`) is acceptable for this project because:
- inline editing, frozen columns, and custom editors are already integrated
- replacing now would create high churn with little immediate operational gain

Re-evaluate only if licensing, performance, or maintenance pain materially outweighs migration cost.
