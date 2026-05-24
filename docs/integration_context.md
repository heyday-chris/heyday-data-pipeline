# Heyday Data Pipeline — Integration Context

**Last updated:** 2026-05-20
**Status:** Phase 1 in progress — FlavorStudio → BigQuery raw ingestion

---

## Purpose

This document captures the end-to-end production and inventory process designed for Heyday's
co-manufacturing relationship, including Cin7 Core configuration, QuickBooks transaction
creation, and the FlavorStudio → Cin7 BOM sync pipeline.

---

## Open Questions

- [ ] Are we tracking batch#/lot# on production orders in Cin7? Do we need to track on the pull?
- [ ] Accounts in Cin7 for items (particularly COGS) don't appear to be set up — assumed because
      accounting is tracked in QB. What are the considerations here?
- [ ] Items in Cin7 are set to FIFO Costing. Is QuickBooks actually using FIFO or Average Costing?
- [ ] What are the actual `process_step` values in FlavorStudio for kettle vs fill steps?
      Run a spot-check query on `recipeversionrows_json` after first sync to confirm.
- [ ] Confirm `recipe_code` naming convention matches Cin7 item codes for BOM mapping.
- [ ] Confirm all co-man ingredients are identifiable in FlavorStudio before building
      `ingredient_mapping` seed.
- [ ] Stock Transfer Setting is currently **Manual** — confirm with team before switching
      to Automatic.

---

## Background & Constraints

Heyday contracts with a co-man for production. The key operational constraints that shaped
this design are:

- Heyday owns all raw materials **except** cans, case packaging, and some ingredients (e.g. beans)
- The co-man is paid only when Heyday **pulls product** from the co-man's warehouse
- The co-man invoice does not break down details on tolling, canning, and other fees — the
  single line-item charge is inclusive of these and is added as a landed cost at the unit level
  in Cin7, but does not track cost components (tolling, cans, etc.) individually
- A **single pull (and the resulting co-man invoice)** may cover multiple production runs
- Three production phases exist: Kettle, Fill, and Finished Good — all three are tracked in
  Cin7 via a two-step sequenced Production BOM for Fill, and a separate Assembly BOM for
  Finished Good
- Heyday uses **QuickBooks Online** for accounting, integrated with Cin7 Core
- After each production run, Honee Bear provides a **production packet** showing actual
  ingredient consumption per step and actual cans produced. Production runs in Cin7 are not
  started until this packet is received.

---

## Tech Stack

| System | Role |
|---|---|
| **FlavorStudio** | Recipe source of truth |
| **Cin7 Core** | Inventory, production orders, BOM execution |
| **QuickBooks Online** | Accounting |
| **Google BigQuery** | Data warehouse, transformation layer, audit log |
| **dbt** | SQL transformation, business logic, data quality tests (Phase 2) |
| **n8n** | Workflow orchestration, API calls, approval routing |

---

## Cin7 Item Master Structure

Four item tiers are required:

### 1. Raw Materials
Ingredients, labels, and all items owned and managed by Heyday.

### 2. Kettle WIP Intermediate
One item per product variant (e.g. `CCCH-KETTLE-WIP`). Stock item used exclusively as a
virtual intermediate within the Fill Sub-Assembly Production BOM. Never purchased, sold, or
held independently in inventory. Measured in **lbs**. Flows as the Output of Step 1 (Kettle)
and the Input of Step 2 (Fill) within the same production order. Stock quantity nets to zero
after every completed production run.

### 3. Fill Sub-Assembly
One SKU per product variant (e.g. `FILL-CCCH-15OZ`). Stock item with a two-step sequenced
Production BOM. Yield loss and wastage at both kettle and fill stages are captured here via
the production order.

### 4. Finished Good
One SKU per sellable unit (e.g. `HEYDAY-CCCH-15OZ`). Assembly item (not a production order).
BOM contains the fill sub-assembly and Heyday-owned labels. Co-man-owned costs (cans,
packaging, beans, tolling) are not in the BOM — applied via landed cost / service purchase.

---

## Production BOM Structure — Fill Sub-Assembly

Two-step sequenced Production BOM built around the full kettle batch size. Both operations
are **Type: Manufacturing** (not co-manufacturing).

**Quantity to Produce:** Full kettle batch yield in cans (e.g. 7,882 cans)

**Work Center:** Honee Bear standard manufacturing work center (Co-Man and Purchase Co-Man
both unchecked). Consumption Bin: HB Shop Floor. Output Bin: HB — Filled Goods.

### Step 1 — Kettle Operation

- **Type:** Manufacturing
- **Components:** All Heyday-owned kettle ingredients at full batch quantities
  (e.g. coconut cream, corn stock, spices), consumed from HB Shop Floor
- **Output:** Kettle WIP Intermediate (e.g. `CCCH-KETTLE-WIP`) — full kettle batch weight
  in lbs (e.g. 3,804.5 lbs)
- Actual output quantity entered manually from production packet to capture kettle-stage yield

### Step 2 — Fill Operation

- **Type:** Manufacturing
- **Input:** Kettle WIP Intermediate (e.g. 3,804.5 lbs) — must equal Step 1 actual output.
  Any kettle lbs not converted to cans are recorded as **wastage on this Input line**
  (Consumed + Wastage = Step 1 output)
- **Components:** All Heyday-owned fill-stage ingredients at full batch quantities
  (e.g. corn, potatoes), consumed from HB Shop Floor
- **Finished Product:** Fill Sub-Assembly (actual cans produced, entered from production packet)

**Component Issue Method:**
- **Current state:** Backflush — inventory relieved proportionally based on actual can output
  vs. BOM ratio. Periodic reconciliation used to true up variances. Use this until full
  pick/return data is available from Honee Bear.
- **Future state:** Full Manual issue once Honee Bear provides per-ingredient picked and
  returned quantities on the production packet. Consumed + Wastage per ingredient will equal
  total picked minus returned.

**Wastage Cost Treatment:** Included into production cost (not posted to separate expense account)

**BOM Quantity to Produce Basis:** Full kettle batch (e.g. 7,882 cans). All ingredient
quantities expressed at full batch scale to avoid rounding errors.

---

## Cin7 Location Structure

| Location | Type | Purpose |
|---|---|---|
| PL Cold | Warehouse | Frozen raw material storage, physically separate from co-packer facility |
| HB Raw Material Warehouse | Warehouse | Ambient raw material storage within Honee Bear facility. Heyday-owned ingredients staged here before production |
| HB Shop Floor | Shop Floor | Active production area at Honee Bear. Components transferred here before each production run |
| HB — Filled Goods | Warehouse | Fill sub-assemblies that have passed QA, awaiting Heyday pull |
| HB Hold | Warehouse | Fill sub-assemblies (britestacks) on QA hold at Honee Bear, pending QA release before transfer to HB — Filled Goods |
| In Transit | Warehouse | Finished goods under Heyday's control, not yet arrived at a warehouse |
| Heyday Warehouse / 3PL | Warehouse | Finished goods under Heyday's control |

---

## Logistics Path Configuration

Configured on the **HB Shop Floor** location record in
**Settings → Reference Books → Stock → Locations & Bins**.

| Field | Value |
|---|---|
| Components | HB Raw Material Warehouse |
| Shop Floor | HB Shop Floor |
| Demand | HB — Filled Goods |

Enables Cin7 to automatically generate transfer orders from HB Raw Material Warehouse →
HB Shop Floor when components are needed for a production run.

**Stock Transfer Setting:** Currently **Manual** — transfer orders from HB Raw Material
Warehouse → HB Shop Floor must be manually created. To be confirmed with team before
switching to Automatic.

---

## Work Center Configuration

| Field | Value |
|---|---|
| Name | Honee Bear (mapped to Honee Bear Canning supplier record) |
| Co-Man | Unchecked |
| Purchase Co-Man | Unchecked |
| Mode | Standard manufacturing (no co-manufacturing procurement mode) |
| Consumption Bin | HB Shop Floor |
| Output Bin | HB — Filled Goods |

**Rationale:** Co-manufacturing operation types in Cin7 are incompatible with the
Input/Output intermediate product mechanism required for the two-step BOM, and generate
unwanted purchase orders for finished output. Type: Manufacturing with a standard work
center is the correct configuration for step-level ingredient tracking.

---

## Production Workflow

### Pre-Production — Inventory Allocation and Transfer

1. A **production order** is raised in Cin7 against the Fill Sub-Assembly SKU and
   **released/authorized** to allocate inventory
2. Release allocates components across both HB Raw Material Warehouse (ambient) and
   PL Cold (frozen)
3. For frozen components at PL Cold: a **manual transfer order** is created in Cin7 and
   executed a few days before production to move frozen items to HB Raw Material Warehouse
   (freight-triggered)
4. Before the production run starts: a **manual stock transfer** moves all required components
   from HB Raw Material Warehouse → HB Shop Floor

### Stage 1 — Fill Production Run (Two-Step)

Triggered when the **production packet is received** from Honee Bear after production
completes. The production run is started and completed in one session using the production
packet as the source of actuals.

**Step 1 (Kettle):**
- Enter actual quantities **Consumed** and **Wastage** per kettle ingredient
  (Consumed + Wastage = total picked from shop floor)
- Enter actual **Output** quantity for Kettle WIP Intermediate in lbs

**Step 2 (Fill):**
- Enter actual **Consumed** and **Wastage** for the Kettle WIP Input
  (Consumed + Wastage must equal Step 1 actual output — no kettle intermediate left in inventory)
- Enter actual quantities **Consumed** and **Wastage** per fill-stage ingredient
- Enter actual **Finished Product** quantity (cans produced)

On completion, the Fill Sub-Assembly is automatically transferred to **HB — Filled Goods**
(or **HB Hold** if product is placed on QA hold pending review).

### Stage 2 — QA Hold (if applicable)

If fill output is placed on QA hold by Honee Bear:
- Fill sub-assembly is received into **HB Hold** location
- Inventory remains in HB Hold until QA is resolved
- On QA release: a **stock transfer** moves units from HB Hold → HB — Filled Goods

### Stage 3 — Finished Good Assembly Order

Triggered each time Heyday pulls product from Honee Bear's warehouse.

- An **assembly order** is raised in Cin7 against the Finished Good SKU
- Fill sub-assembly is consumed from **HB — Filled Goods**
- Labels are consumed from Heyday's inventory
- Finished good is produced into the **In Transit** warehouse location
- Each assembly order covers **a single SKU** — multiple SKUs pulled in one shipment
  require separate assembly orders
- The **Pull Number** custom field is populated to tie assembly orders to the shipment

### Pull Number — Custom Field

Custom field (`CustomField1` in Cin7, labelled "Pull Number") on the Finished Goods assembly
order. Format:

```
PULL-YYYYMMDD-001
```

This number is the common key that ties together:
- All assembly orders in a single pull (even across different SKUs)
- The co-man's invoice referencing that pull
- The Cin7 service purchase created for cost allocation

---

## Cost Allocation Workflow

### The Problem

The co-man charges Heyday for items Heyday does not own (cans, case packaging, beans) and
for services (tolling fee). These costs must be reflected in Cin7's per-unit inventory cost
for the finished good — they cannot simply be expensed to P&L, as this would result in
inaccurate unit costing and understate COGS.

### The Mechanism

1. Create a **Service Purchase** in Cin7
2. Enter co-man charges as **Additional Costs**
3. Authorize the purchase
4. Click the **Expenses** button that appears post-authorization
5. Allocate the expense to the relevant assembly orders (one or many)
6. Use **Auto-allocate** (proportional by quantity) or enter manually
7. Save

This updates the cost of the finished good in Cin7 and flows through to COGS when units
are sold. The authorized Cin7 service purchase invoice is picked up by the QuickBooks
integration, recording the AP liability against the co-man vendor automatically.

### Charge Types

| Charge | Owned By | How It Enters Cost |
|---|---|---|
| Tolling fee | Co-man | Service purchase additional cost |
| Can fee | Co-man | Service purchase additional cost |
| Case packaging | Co-man | Service purchase additional cost |
| Beans / other co-man ingredients | Co-man | Service purchase additional cost |
| Labels | Heyday | Assembly BOM (consumed at assembly) |
| Fill sub-assembly | Heyday | Assembly BOM (consumed at assembly) |

---

## FlavorStudio → Cin7 BOM Sync

FlavorStudio is the **recipe source of truth**. Cin7 Production BOMs are synchronized from
FlavorStudio via an automated pipeline.

### Recipe Structure in FlavorStudio

- **Kettle recipe:** Built to full batch scale (e.g. 3,804.5 lbs) → maps directly to
  Step 1 components
- **Fill recipe:** Built to a single can (e.g. 425g) → converted to full batch scale for
  Step 2 components via `kettle_batch_config` table
- Each step is a **separate recipe** in FlavorStudio
- Co-packer owned ingredients are present in FlavorStudio recipes but must be excluded from
  Cin7 BOMs

### Pipeline Architecture

```
FlavorStudio → BigQuery (raw) → dbt (transform + tests) → BigQuery (marts) → n8n → Cin7
```

### Key Rules
- Co-packer owned ingredients filtered out via `ingredient_mapping` table (`owner = 'coman'`)
- Human approval step required before any BOM update is pushed to Cin7
- New BOM versions created on each update — existing BOMs not overwritten, preserving
  historical costing on in-progress orders

---

## FlavorStudio API Notes

- **Base URL:** `https://app.flavorstudio.com/`
- **Authentication:** HTTP Basic Auth — public key as username, private key as password
- **Enable via:** Admin → Settings → API section in FlavorStudio
- **Keys** are regenerated each time the API is enabled — store in n8n credential store,
  never in Git
- **Rate limits:**
  - General endpoints: 1,000 calls/day
  - Ingredient endpoints: 2,000 calls/day
  - Monitor via `remaining_daily_api_requests` in every response
- **Max page size:** 100 records per request (`step=100`)

### Key Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /api/v2/get/recipes` | Paginated recipe list with full ingredient rows |
| `GET /api/v2/get/recipe/{id}` | Single recipe detail (not needed for BOM sync) |
| `GET /api/v2/get/ingredients` | Paginated ingredient master |

### Critical Field: `recipeversionrows`

Each recipe version contains a `recipeversionrows` array. Each element has:

| Field | Description |
|---|---|
| `ingredient` | Ingredient display name |
| `custom_ingredient_name` | Custom name override for this recipe row |
| `custom_ingredient_id` | Unique ingredient ID — foreign key to ingredient master |
| `quantity` | Quantity in this recipe |
| `unit` | Unit of measure |
| `process_step` | Step identifier — **verify actual values in your account** |
| `supplier` | Supplier name |
| `costcode` | Cost code |
| `percentage` | Percentage of total recipe weight |

---

## BigQuery Raw Layer

### Tables

| Table | Purpose |
|---|---|
| `heyday_raw.flavorstudio_recipes_raw` | One row per recipe version per sync run. Ingredient rows stored as JSON string in `recipeversionrows_json` |
| `heyday_raw.flavorstudio_ingredients_raw` | Ingredient master — all ingredients from FlavorStudio |
| `heyday_raw.flavorstudio_sync_log` | One row per n8n run — audit trail and rate limit monitor |

### Design Decisions
- **Append-only raw tables** — preserves full history; deduplication handled in dbt staging
- **`recipeversionrows` stored as JSON string** — defer unnesting to dbt; keeps raw layer
  simple and replayable
- **All fields stored as STRING in raw layer** — avoids type casting failures on ingest;
  casting handled in dbt staging

---

## dbt Models (Phase 2)

### Seeds
- `ingredient_mapping.csv` — maps FlavorStudio ingredient IDs to Cin7 item codes, flags
  `owner = 'coman'` for exclusion
- `kettle_batch_config.csv` — batch size and can count per SKU, used for fill recipe scaling

### Staging
- `stg_flavorstudio__recipes` — unnests `recipeversionrows_json` into one row per ingredient line
- `stg_flavorstudio__ingredients` — deduplicated ingredient master
- `stg_cin7__boms` — current Cin7 BOM state for diff comparison

### Intermediate
- `int_recipes__heyday_ingredients_only` — filters out co-man ingredients via
  `ingredient_mapping`
- `int_recipes__batch_scaled` — scales fill recipe from per-can to full batch using
  `kettle_batch_config`
- `int_boms__change_detection` — diffs FlavorStudio recipe state against current Cin7 BOMs

### Marts
- `mart_cin7__bom_payload` — Cin7-ready BOM payload consumed by n8n
- `mart_bom__pending_changes` — diff output for Slack approval notification
- `mart_landed_cost__coman_ingredient_value` — theoretical co-man ingredient value for
  landed cost variance reporting

### Key Tests
- `no_coman_ingredients_in_payload` — hard guarantee co-man ingredients never reach Cin7
- `kettle_step1_output_matches_batch_config` — Step 1 output lbs matches expected batch size
- Referential integrity on `ingredient_mapping` — catches unmapped ingredients before Cin7

---

## Accounting Needs (Open)

1. Creation of a WIP inventory asset account
2. Creation of an In Transit inventory location
3. Confirmation on cost allocation method and COGS account settings

---

## Decisions Log

| Date | Decision | Reason |
|---|---|---|
| 2026-05-20 | Work center set to Type: Manufacturing, not Co-Manufacturing | Co-manufacturing operation types incompatible with Input/Output intermediate mechanism; generate unwanted POs |
| 2026-05-20 | Component issue method: Backflush for now, Manual later | Full pick/return data not yet available from Honee Bear |
| 2026-05-20 | Co-man costs applied as landed cost, not in BOM | Heyday does not own cans, packaging, or some ingredients; these are co-man-supplied |
| 2026-05-20 | Pull Number custom field on assembly orders | Single key to tie multi-SKU pulls to one co-man invoice |
| 2026-05-20 | Store `recipeversionrows` as JSON string in raw layer | Defer unnesting to dbt; keeps raw layer simple and replayable |
| 2026-05-20 | Append-only raw tables in BigQuery | Preserves full history; deduplication handled in dbt staging layer |
| 2026-05-20 | Skip dbt for Phase 1 MVP | Prove ingestion works first; add transformation once data is confirmed correct |
| 2026-05-20 | Use `git config --local` for identity | Isolates work GitHub account to this repo only |
## FlavorStudio API Reference

- Base URL: `https://app.flavorstudio.com/`
- Auth: HTTP Basic Auth (public key = username, private key = password)
- API version: v2
- Full docs: https://www.flavorstudio.com/api

### Endpoints Used by This Pipeline

| Purpose | Endpoint |
|---|---|
| List all recipes | `GET /api/v2/get/recipes?step=100` |
| Get single recipe | `GET /api/v2/get/recipe/{id}` |
| List all ingredients | `GET /api/v2/get/ingredients?step=100` |

### Notes
- `recipeversionrows[].process_step` distinguishes kettle vs fill steps — verify actual values against CCCH recipe before Phase 2
- `remaining_daily_api_requests` returned on every response — log to `flavorstudio_sync_log`
- Pagination: max `step=100` per page, use `page` param for larger datasets