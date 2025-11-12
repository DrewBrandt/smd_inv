# SMD Inventory - Application Requirements & Overview

## Executive Summary

**SMD Inventory** is a Flutter-based cross-platform application for managing electronic component inventory and PCB assembly projects. The application enables electronics manufacturers, hobbyists, and engineering teams to track SMD (Surface Mount Device) components, manage Bills of Materials (BOMs), and determine build readiness based on available inventory.

## Technical Stack

### Core Technologies
- **Framework**: Flutter SDK 3.7.2+
- **Language**: Dart
- **UI Design**: Material Design 3
- **Backend**: Firebase Cloud Firestore (NoSQL real-time database)
- **Project ID**: `trt-smd-inventory`

### Key Dependencies
| Package | Version | Purpose |
|---------|---------|---------|
| syncfusion_flutter_datagrid | 31.2.2 | Advanced spreadsheet-like data grid |
| go_router | 16.2.5 | Declarative routing with deep linking |
| file_picker | 10.3.3 | Native file selection dialogs |
| csv | 6.0.0 | CSV parsing for import/export |
| url_launcher | 6.3.2 | Opening external URLs |
| shared_preferences | 2.5.3 | Persistent local storage |

### Platform Support
- ✅ Windows (primary development target)
- ✅ Web
- ✅ Android
- ✅ iOS
- ✅ macOS
- ✅ Linux

---

## Application Architecture

### Navigation Structure

```
/ (root) → redirects to /inventory
├── /inventory - Component inventory management
├── /boards - PCB project gallery
│   ├── /boards/new - Create new board
│   └── /boards/:id - Edit existing board
└── /admin - Administrative functions (placeholder)
```

### Data Architecture

#### Firestore Collections

**1. `inventory` Collection**
```
Document Schema:
- part_# (string) - Manufacturer or internal part number
- type (string) - Component category
- value (string) - For passives: resistance, capacitance, inductance
- package (string) - Physical package (0603, SOIC-8, etc.)
- description (string) - Human-readable description
- qty (number) - Current stock quantity
- location (string) - Physical storage location
- price_per_unit (number) - Unit cost
- notes (string) - Free-form notes
- vendor_link (string) - URL to supplier page
- datasheet (string) - URL to technical documentation
- last_updated (timestamp) - Automatic timestamp
```

**2. `boards` Collection**
```
Document Schema:
- name (string) - Board project name
- description (string) - Project description
- category (string) - Optional categorization
- color (string) - Hex color code for visual identification
- imageUrl (string) - URL to board image
- bom (array) - Bill of Materials
  - qty (number) - Quantity per board
  - category (string) - Component type
  - required_attributes (map) - Required specs
    - type, value, size, part_number
  - selected_component_ref (string) - Inventory document reference
  - notes (string) - Line-specific notes
- createdAt (timestamp)
- updatedAt (timestamp)
```

**3. `history` Collection**
```
Document Schema:
- action (string) - Action type (e.g., "make_boards")
- board_id (string) - Reference to board
- board_name (string) - Board name snapshot
- quantity (number) - Number of boards built
- timestamp (timestamp)
- bom_snapshot (array) - BOM state at time of action
```

### Component Categories

**Supported Component Types:**
1. Capacitor
2. Resistor
3. Inductor
4. IC (Integrated Circuit)
5. Connector
6. Diode
7. LED
8. Crystal
9. Other

---

## Feature Requirements

### 1. Inventory Management

#### 1.1 Core Inventory Features
- ✅ Real-time inventory tracking via Firestore synchronization
- ✅ Multi-column editable data grid with inline editing
- ✅ Sortable columns with multi-column sorting support
- ✅ Resizable columns with width persistence
- ✅ Frozen first column for always-visible reference
- ✅ Row context menu (right-click/long-press)
  - Copy document reference ID
  - Delete row

#### 1.2 Search & Filtering
- ✅ Multi-term AND search (comma-separated)
  - Example: "ind, 0805" finds inductors in 0805 package
- ✅ Filter chips with dynamic options:
  - **Type filter** - All component categories
  - **Package filter** - All package types (0201, 0402, 0603, 0805, 1206, SOIC, QFN, etc.)
  - **Location filter** - Physical storage locations
- ✅ Clear all filters button

#### 1.3 Data Entry Methods

**1.3.1 Manual Entry**
- ✅ Form-based item creation
- ✅ Type dropdown (9 component types)
- ✅ Conditional fields (value field only for passives)
- ✅ Price per unit tracking
- ✅ Vendor link support
- ✅ Field validation

**1.3.2 CSV Import**
- ✅ File picker or paste data
- ✅ Intelligent parsing from DigiKey/Mouser format
- ✅ Automatic part number extraction from URLs
- ✅ Type detection heuristics
- ✅ Value normalization (µF→u, 2u2→2.2u)
- ✅ Duplicate detection with merge strategies:
  - Skip duplicate
  - Add quantity to existing
  - Replace entire record
  - Cancel import
- ✅ Preview and edit before import
- ✅ Configurable default location and package

#### 1.4 Data Grid Specifications

**Column Configuration:**
| Field | Width (min) | Type | Editable | Sortable |
|-------|-------------|------|----------|----------|
| Part # | 180px | Text | Yes | Yes |
| Type | 120px | Enum | Yes | Yes |
| Value | 120px | Text | Yes | Yes |
| Package | 120px | Text | Yes | Yes |
| Description | 320px | Text | Yes | Yes |
| Qty | 84px | Integer | Yes | Yes |
| Location | 120px | Text | Yes | Yes |
| Price/Unit | 100px | Decimal | Yes | Yes |
| Notes | 320px | Text | Yes | Yes |
| Vendor Link | 220px | URL | Yes | No |
| Datasheet | 220px | URL | Yes | No |

**Grid Behavior:**
- Double-click to edit cells
- Auto-expand columns to fill available space
- Column widths persist to SharedPreferences
- Keyboard navigation support
- Context menu on row header

---

### 2. Board/Project Management

#### 2.1 Board Features
- ✅ Visual board gallery with card-based layout
- ✅ Board metadata editing:
  - Name (required)
  - Description
  - Category
  - Color coding (hex value)
  - Image URL (placeholder icon if not set)
- ✅ Board actions:
  - Edit
  - Duplicate
  - Make boards (production workflow)
  - Delete (placeholder)

#### 2.2 Bill of Materials (BOM) Management

**BOM Grid Columns:**
| Column | Type | Purpose |
|--------|------|---------|
| Selected Component | Reference | Link to inventory item |
| Designators | Text | PCB reference designators (C1, R2-R5) |
| Qty | Integer | Quantity required per board |
| Type | Enum | Component category |
| Value | Text | Component value |
| Size | Text | Package/footprint |
| Part # | Text | Manufacturer part number |
| Description | Text | Component description |
| Notes | Text | Line-specific notes |

**BOM Features:**
- ✅ Editable BOM grid
- ✅ Add BOM line manually
- ✅ KiCad BOM import (see 2.3)
- ✅ Component selection from inventory
- ✅ Required attributes tracking

#### 2.3 KiCad BOM Import

**Requirements:**
- ✅ CSV/TSV file upload or paste
- ✅ Automatic column detection (Reference, Quantity, Value, Footprint)
- ✅ Intelligent component type detection from designator prefix:
  - C → Capacitor
  - R → Resistor
  - L → Inductor
  - D → Diode
  - U/Q/IC → IC
  - J/P/X → Connector
- ✅ Package size extraction from footprint
- ✅ Value normalization
- ✅ **Automatic inventory matching** with status indicators:
  - ✅ Green - Exact match found
  - ⚠️ Orange - Multiple matches (user chooses)
  - ❌ Red - Not in inventory
- ✅ Manual search and assignment for unmatched parts
- ✅ Preview before import

**Supported Designator Prefixes:**
| Prefix | Component Type |
|--------|---------------|
| C | Capacitor |
| R | Resistor |
| L | Inductor |
| D | Diode |
| U, Q, IC | IC |
| J, P, X | Connector |
| LED | LED |
| Y | Crystal |

#### 2.4 Build Readiness Calculation

**Algorithm:**
1. Match BOM lines to inventory items using:
   - Exact match by `selected_component_ref` (user-assigned)
   - Match by part number
   - Match passives by type + value + package
2. Calculate available quantity for each BOM line
3. Determine maximum buildable boards (limiting component)
4. Calculate readiness percentage

**Outputs:**
- ✅ Buildable quantity (max boards possible)
- ✅ Readiness percentage (0-100%)
- ✅ Shortfall list (missing/insufficient parts)
- ✅ Total cost per board

**Visual Indicators:**
- Progress bar with color coding:
  - Green: ≥90% ready
  - Yellow: ≥70% ready
  - Orange: ≥50% ready
  - Red: <50% ready
- Shortfall warning on board card
- Buildable quantity badge

---

### 3. Production/Manufacturing

#### 3.1 "Make Boards" Workflow

**Requirements:**
1. ✅ User enters quantity to build (≤ buildable qty)
2. ✅ Show confirmation dialog with:
   - Board name
   - Quantity to build
   - Warning about inventory deduction
3. ✅ Execute Firestore batch write:
   - Decrement inventory quantities for all BOM components
   - Update `last_updated` timestamps
4. ✅ Create history record:
   - Action type: "make_boards"
   - Board ID and name
   - Quantity made
   - Timestamp
   - BOM snapshot
5. ✅ Show success notification with history link
6. ✅ Update UI to reflect new inventory levels

**Business Rules:**
- Cannot build more than buildable quantity
- Must have sufficient inventory for all BOM lines
- Inventory updates are atomic (batch write)
- History entry created for potential undo

---

### 4. User Interface Requirements

#### 4.1 Top Navigation Bar
- ✅ Large branding (icon + "SMD Inventory" title)
- ✅ Three tab navigation (Inventory, Boards, Admin)
- ✅ Active tab indicators (color, underline, bold)
- ✅ Fade transition between pages
- ✅ Responsive layout (95% width constraint)

#### 4.2 Visual Design Standards
- ✅ Material Design 3 theming
- ✅ Color scheme from blue-grey seed
- ✅ Compact visual density
- ✅ Card-based layouts
- ✅ Consistent iconography
- ✅ Elevation and shadows
- ✅ Responsive grid layouts

#### 4.3 State Management
- ✅ Dirty state tracking (warn on unsaved changes)
- ✅ Loading indicators (progress spinners)
- ✅ Error handling (snackbar notifications)
- ✅ Optimistic UI updates

#### 4.4 Accessibility
- ✅ Keyboard navigation
- ✅ Context menus (right-click and long-press)
- ✅ Clear visual feedback
- ✅ Consistent interaction patterns

---

## Data Processing Requirements

### Value Normalization

**Input → Output transformations:**
```
µF, µH → u (Unicode to ASCII)
2u2 → 2.2u (embedded decimal notation)
100n0 → 100n (trailing zero)
10uf → 10u (drop trailing 'f')
Whitespace removed
```

### Part Number Extraction

**DigiKey URL pattern:**
```
/detail/[^/]+/([^/]+)/
Example: https://digikey.com/detail/company/PART123/id → PART123
```

### Package Detection

**Regex patterns:**
```
Imperial sizes: (0201|0402|0603|0805|1206|1210|2512)
IC packages: (SOIC|QFP|QFN|DIP|TSSOP|VFQFPN|LQFP|TQFP)-?\d+
Connectors: JST[- ]?[A-Z]{2}[- ]?\d+P?
```

### Type Detection Heuristics

**Part number patterns:**
```
capacitor: CL, GRM, C[0-9]
resistor: RC, R[0-9], RES, ERJ
connector: CONN, JST, 609-, 691-
ic: IC, .*IC$, SOT-, TSSOP
```

---

## Integration Requirements

### 5.1 KiCad EDA Integration
- ✅ Accept KiCad BOM export format (CSV/TSV)
- ✅ Standard columns: Reference, Quantity, Value, Footprint
- ✅ Handle typical designator prefixes
- ✅ Compatible with grouped BOM output

### 5.2 Electronic Supplier Support
- ✅ DigiKey - URL parsing for part numbers
- ✅ Mouser - Link storage
- ✅ Generic vendor link support

### 5.3 Future Integration Points
- ⬜ Datasheet preview integration
- ⬜ Barcode scanning
- ⬜ Export to Excel/CSV
- ⬜ BOM cost analysis from vendor APIs
- ⬜ Octopart API for pricing

---

## Performance Requirements

### Response Time
- Inventory grid load: < 2 seconds
- Search/filter update: < 500ms
- CSV import preview: < 1 second
- Board save: < 1 second
- Make boards (batch write): < 3 seconds

### Scalability
- Support 10,000+ inventory items
- Support 100+ boards
- Support BOM with 500+ lines
- Real-time updates for concurrent users

### Optimization Techniques
- ✅ AutomaticKeepAliveClientMixin - Preserve grid state
- ✅ LayoutBuilder - Dynamic column sizing
- ✅ Column width caching
- ✅ Client-side filtering after fetch
- ✅ Firestore cache clearing on startup

---

## Security & Data Integrity

### Current State
- ⚠️ No user authentication
- ⚠️ No role-based permissions
- ⚠️ Single-user or shared team access model

### Data Validation
- ✅ Required field enforcement
- ✅ Type validation (integers, decimals)
- ✅ Duplicate detection
- ✅ Atomic batch writes
- ✅ Server timestamps

### Future Requirements
- ⬜ User authentication (Firebase Auth)
- ⬜ Role-based access control (admin, editor, viewer)
- ⬜ Audit trail UI
- ⬜ Data export for backup
- ⬜ Import validation and sanitization

---

## Known Limitations

### Current Gaps
1. ❌ No undo/redo implementation (history collection exists but unused)
2. ❌ No barcode scanning
3. ❌ No low-stock alerts
4. ❌ No audit trail UI
5. ❌ No export functionality
6. ❌ No datasheet preview
7. ❌ Image upload not implemented (URL field only)
8. ❌ No batch delete
9. ❌ No advanced reporting/analytics
10. ❌ Search is case-sensitive for some operations
11. ❌ Admin page is placeholder only
12. ❌ No multi-warehouse support

### Technical Debt
- Duplicate code in data sources (firebase vs list-based)
- Inconsistent error handling patterns
- Limited unit test coverage
- Manual state management (no state management library)

---

## Future Enhancements (Roadmap)

### Phase 1: Core Improvements
- ⬜ **History & Undo** - Transaction log with rollback capability
- ⬜ **Audit Inventory** - Physical count reconciliation workflow
- ⬜ **Low Stock Alerts** - Configurable thresholds with notifications
- ⬜ **Batch Operations** - Multi-select delete, location updates
- ⬜ **Advanced Search** - Regex, boolean operators, saved filters

### Phase 2: Multi-User & Security
- ⬜ **User Authentication** - Firebase Auth integration
- ⬜ **Role-Based Permissions** - Admin, editor, viewer roles
- ⬜ **Collaborative Editing** - Conflict resolution for concurrent edits
- ⬜ **Activity Feed** - Real-time updates of team actions

### Phase 3: Enhanced Functionality
- ⬜ **Barcode Support** - Label generation and scanning
- ⬜ **Automatic Reorder** - Vendor integration for ordering
- ⬜ **BOM Cost Optimization** - Substitute recommendations
- ⬜ **Project Time Tracking** - Build time estimates
- ⬜ **Advanced Reporting** - Analytics dashboard, charts
- ⬜ **Export/Import** - Excel, PDF export

### Phase 4: Mobile & Offline
- ⬜ **Mobile App** - Dedicated mobile UI
- ⬜ **Offline Mode** - Local database with sync
- ⬜ **Camera Integration** - Photo capture for components
- ⬜ **Voice Entry** - Voice-to-text for notes

### Phase 5: Enterprise Features
- ⬜ **Multi-Warehouse** - Location hierarchy support
- ⬜ **Vendor Management** - Purchase orders, receiving
- ⬜ **BOM Versioning** - Change tracking for boards
- ⬜ **Cost Tracking** - Project profitability analysis
- ⬜ **API Access** - RESTful API for integrations

---

## Configuration & Defaults

### Firebase Configuration
- **Project**: trt-smd-inventory
- **Region**: (not specified in config)
- **Auth**: None (currently)
- **Storage**: Not used

### Default Values
| Setting | Value | Purpose |
|---------|-------|---------|
| Default Package | 0603 | Most common SMD size |
| Default Qty (manual) | 0 | Explicit entry required |
| CSV Import Qty | 1 | Assume 1 if missing |
| Max Column Width | 95% | Responsive layout |

### SharedPreferences Keys
```
dg_widths:inventory_unified - Inventory grid column widths
dg_widths:bom_editor_{boardId} - BOM editor column widths
csv_import_preview - CSV import preview settings
```

---

## User Workflows

### Workflow 1: Adding Inventory via CSV
1. Navigate to Inventory page
2. Click "Add" → "Import from CSV"
3. Configure default location and package
4. Choose file or paste data
5. Review parsed data in preview grid
6. Edit any incorrect values
7. Click "Import N Items"
8. Resolve any duplicates with chosen strategy
9. Confirm successful import

### Workflow 2: Creating a Board from KiCad BOM
1. Design PCB in KiCad
2. Export BOM to CSV
3. Navigate to Boards → "New Board"
4. Fill board metadata (name, description, color)
5. Click "Import KiCad BOM"
6. Upload or paste BOM data
7. Review auto-matched components (green)
8. Resolve ambiguous matches (orange) via search
9. Note missing components (red) for later sourcing
10. Click "Import N Lines"
11. Review and edit BOM in grid
12. Click "Save Changes"
13. View board in gallery with readiness status

### Workflow 3: Building Boards
1. Navigate to Boards page
2. Review board card readiness status
3. If buildable > 0, click "Make"
4. Enter quantity (1 to max buildable)
5. Review confirmation dialog
6. Click "Confirm"
7. Wait for batch update to complete
8. View success notification
9. Verify inventory quantities updated

### Workflow 4: Searching Inventory
1. Type search terms in search bar
2. For AND logic, use comma separation
3. Click filter chips for Type/Package/Location
4. Select desired filter values
5. View filtered results in grid
6. Click "Clear Filters" to reset

---

## Development Standards

### Code Organization
```
lib/
├── data/ - Data layer (repositories, sources)
├── models/ - Data models and business objects
├── services/ - Business logic services
├── pages/ - Top-level page widgets
├── widgets/ - Reusable UI components
└── ui/ - UI utilities (colors, labels)
```

### Naming Conventions
- Files: `snake_case.dart`
- Classes: `PascalCase`
- Variables: `camelCase`
- Constants: `camelCase`
- Private members: `_leadingUnderscore`

### Best Practices
- ✅ Single responsibility per class
- ✅ Composition over inheritance
- ✅ Stateless widgets where possible
- ✅ Extract reusable widgets
- ✅ Use const constructors
- ✅ Dispose controllers and listeners
- ✅ Handle errors gracefully
- ✅ Provide user feedback for all actions

---

## Testing Requirements

### Current State
- ⚠️ No automated tests implemented

### Required Test Coverage
- ⬜ Unit tests for:
  - Data models (serialization, validation)
  - Services (readiness calculator, matching algorithm)
  - Normalization functions
  - Parsing utilities
- ⬜ Widget tests for:
  - Dialogs
  - Forms
  - Grid interactions
- ⬜ Integration tests for:
  - End-to-end workflows
  - Firestore integration
  - Import/export processes

---

## Deployment Requirements

### Build Targets
- ✅ Windows (primary)
- ✅ Web (Firebase Hosting)
- ✅ Android (Google Play ready)
- ✅ iOS (App Store ready)
- ✅ macOS
- ✅ Linux

### Environment Configuration
- ✅ Firebase config per platform
- ✅ App IDs registered
- ⬜ CI/CD pipeline
- ⬜ Automated builds
- ⬜ Version management

---

## Success Metrics

### Key Performance Indicators
1. **User Efficiency**
   - Time to add 100 inventory items: < 5 minutes (via CSV)
   - Time to create board from KiCad BOM: < 2 minutes
   - Auto-match rate for BOM import: > 80%

2. **System Performance**
   - Grid load time: < 2 seconds
   - Search response: < 500ms
   - Make boards operation: < 3 seconds

3. **Data Accuracy**
   - Duplicate detection rate: 100%
   - Part number extraction accuracy: > 95%
   - Type detection accuracy: > 85%

4. **User Satisfaction**
   - Successful BOM imports: > 90%
   - Inventory accuracy: > 98%
   - Build readiness accuracy: 100%

---

## Conclusion

SMD Inventory is a production-ready application that successfully addresses the core requirements of electronics component inventory management and PCB assembly planning. The application demonstrates:

- ✅ **Robust data management** with real-time synchronization
- ✅ **Intelligent automation** for BOM matching and type detection
- ✅ **Professional UI/UX** with advanced data grid capabilities
- ✅ **Industry integration** via KiCad BOM import
- ✅ **Production workflow** with inventory deduction and history tracking

**Key Differentiators:**
1. Automatic inventory-to-BOM matching
2. Build readiness calculation with shortfall analysis
3. Seamless KiCad integration
4. Flexible import options with smart parsing
5. Cross-platform deployment ready

The architecture is well-positioned for future enhancements including multi-user support, mobile deployment, barcode scanning, and advanced analytics.
