# Warehouse Movement Feature Spec

## Overview

`Warehouse Movement` is a stock and equipment movement feature for both mobile and web.

It is intended to handle:
- goods issued from warehouse
- goods returned to warehouse
- transfers between locations
- requests for project or office use
- stock updates for consumables
- location and assignment updates for equipment

This feature is separate from Delivery Note (`DN`), but its workflow is intentionally similar so users can learn it quickly.

## Goals

1. Users can request items or take items from the warehouse for project or office needs.
2. Items can be added by QR scan, SN scan, or manual search.
3. Items are divided into two categories:
   - `Equipment`
   - `Consumable`
4. Destination and purpose must be recorded.
5. Equipment movement updates item location and project assignment.
6. Consumable movement updates stock quantity.
7. Both mobile and web should use the same business rules and statuses.

## Recommended Feature Name

Use:

- `Warehouse Movement`

Alternative labels if needed:

- `Issue / Return`
- `Inventory Movement`
- `Material Movement`

## Transaction Types

### MVP

1. `Issue Out`
2. `Return In`

### Phase 2

3. `Transfer`
4. `Request`

## Purpose Values

- `Project`
- `Office`
- `Warehouse Use`
- `Maintenance`
- `Other`

### Rules

- If purpose is `Project`, `project_id` is required.
- If purpose is `Office`, `destination_location_id` is required.
- If transaction type is `Transfer`, both source and destination are required.

## Item Types

### Equipment

Characteristics:
- can have QR code
- can have Serial Number
- unique item tracking
- location tracking
- project assignment tracking
- status tracking

Input methods:
- scan QR
- scan SN
- manual search by asset code / SN / name

### Consumable

Characteristics:
- quantity based
- stock based
- no per-unit tracking
- QR and SN optional

Input methods:
- manual search
- optional barcode/QR if available

## Shared Status Flow

### MVP Statuses

1. `Draft`
2. `Submitted`
3. `Issued`
4. `Received`
5. `Completed`
6. `Cancelled`

### Optional Extended Statuses

1. `Draft`
2. `Submitted`
3. `Approved`
4. `Picked`
5. `Issued`
6. `Received`
7. `Returned`
8. `Completed`
9. `Cancelled`

## Core Business Rules

### Equipment - Issue Out

When equipment is issued:
- update `current_location`
- update `project_id` if purpose is `Project`
- update `holder_type`
- update `holder_reference`
- update `status`

Recommended status mapping:
- to project -> `On Project`
- to office -> `In Use`
- to warehouse transfer -> `In Transit` or destination-specific

### Equipment - Return In

When equipment is returned:
- set `current_location = warehouse`
- set `project_id = null` if no longer assigned
- set `status = Available`

### Consumable - Issue Out

When consumable is issued:
- reduce stock quantity

### Consumable - Return In

When consumable is returned:
- increase stock quantity

## Required Validations

1. Equipment with the same SN cannot be issued twice while active in another movement.
2. Consumable stock cannot go below zero.
3. If purpose is `Project`, project must be selected.
4. Quantity must be greater than zero.
5. Equipment must resolve to a valid asset record.
6. Return flow should validate the last known location and assignment.

## Mobile Flow

### 1. Movement List

Display:
- Movement Number
- Transaction Type
- Purpose
- Project / Office / Destination
- Status
- Date
- Item Count

Actions:
- search
- filter by status
- filter by type
- create new movement

### 2. Create Movement

Fields:
- Transaction Type
- Purpose
- Source Location
- Destination Location
- Project
- Requester
- Movement Date
- Notes

### 3. Add Items

Tabs:
- `Equipment`
- `Consumable`

Equipment actions:
- scan QR
- scan SN
- manual search

Consumable actions:
- search item
- select qty

### 4. Review Movement

Display:
- movement summary
- source and destination
- project / office
- notes
- item list
- submit button

### 5. Movement Detail

Display:
- full movement data
- status timeline
- items
- source / destination
- audit / action history

Actions:
- issue
- receive
- cancel

### 6. Receive / Return

Used to confirm:
- item received
- item returned
- partial receive if needed

## Web Backend Flow

### Main Menu

Add a new backend menu:

- `Warehouse Movement`

Suggested submenus:
- `Movement List`
- `Create Movement`
- `Pending Approval`
- `Issue / Receive`
- `History`
- `Reports`

### Web Pages

#### 1. Movement List

Functions:
- search by movement number, project, requester
- filter by status
- filter by type
- open detail
- export report

#### 2. Create / Edit Movement

Sections:
- movement header
- source / destination
- project / office target
- requester
- notes
- item section

#### 3. Add Equipment Modal

Functions:
- search by asset code
- search by SN
- scan integration if browser scanner exists
- select matched equipment

#### 4. Add Consumable Modal

Functions:
- search item
- show available stock
- enter qty

#### 5. Review / Submit Page

Functions:
- validate movement
- submit
- print slip

#### 6. Issue / Receive Page

Functions:
- mark movement as issued
- mark movement as received
- track handler and timestamps

## Suggested Database Tables

### 1. `warehouse_movements`

Fields:
- `id`
- `uuid`
- `movement_number`
- `transaction_type`
- `purpose`
- `source_location_id`
- `destination_location_id`
- `project_id`
- `requester_id`
- `movement_date`
- `status`
- `notes`
- `created_by`
- `created_at`
- `updated_by`
- `updated_at`

### 2. `warehouse_movement_items`

Fields:
- `id`
- `movement_id`
- `item_type`
- `inventory_id`
- `asset_code`
- `serial_number`
- `item_name`
- `qty`
- `uom`
- `stock_before`
- `stock_after`
- `remarks`

### 3. `warehouse_movement_logs`

Fields:
- `id`
- `movement_id`
- `action`
- `action_by`
- `action_at`
- `notes`

### 4. Optional `warehouse_movement_approvals`

Fields:
- `id`
- `movement_id`
- `approval_stage`
- `approved_by`
- `approved_at`
- `status`
- `notes`

## Equipment State Fields

Existing inventory/equipment records should support:
- `current_location_id`
- `project_id`
- `holder_type`
- `holder_reference`
- `asset_status`

Suggested `asset_status` values:
- `Available`
- `In Use`
- `On Project`
- `In Transit`
- `Maintenance`

## Consumable Stock Fields

Consumable inventory records should support:
- `stock_on_hand`
- `minimum_stock`
- `uom`
- `warehouse_location_id`

## API Proposal

### Header / List

- `GET /api/warehouse-movement/list`
- `GET /api/warehouse-movement/detail/{uuid}`
- `POST /api/warehouse-movement/create`
- `POST /api/warehouse-movement/update`
- `POST /api/warehouse-movement/submit`
- `POST /api/warehouse-movement/cancel`

### Item Handling

- `GET /api/warehouse-movement/item-search-equipment`
- `GET /api/warehouse-movement/item-search-consumable`
- `POST /api/warehouse-movement/item-add`
- `POST /api/warehouse-movement/item-update`
- `POST /api/warehouse-movement/item-delete`

### Process Actions

- `POST /api/warehouse-movement/issue`
- `POST /api/warehouse-movement/receive`
- `POST /api/warehouse-movement/return`

### Reference Data

- `GET /api/warehouse-movement/create-data`
- `GET /api/warehouse-movement/projects`
- `GET /api/warehouse-movement/locations`

## Response Requirements

All movement detail endpoints should return enriched item data for both web and mobile:

- `item_name`
- `asset_code`
- `serial_number`
- `item_type`
- `qty`
- `uom`
- `inventory_id`
- `current_location_name`
- `project_name`

This is important so the mobile and web UIs do not have to guess names from partial references.

## Recommended QR Rules

### Equipment QR

QR may contain:
- asset code
- serial number
- department hint
- location hint

Mobile and web should:
- parse QR data
- search inventory by asset code first
- validate serial number if present

### Consumable QR

If used:
- QR should resolve to item code / stock item

## Reporting

Suggested web reports:
- issue out report
- return in report
- movement history by item
- movement history by project
- warehouse stock usage report

## Suggested MVP Delivery Order

### Phase 1

1. database tables
2. backend API create/list/detail
3. mobile movement list
4. mobile create movement
5. add equipment
6. add consumable
7. review and submit

### Phase 2

1. issue action
2. receive action
3. stock/location update automation
4. backend web pages
5. reporting

### Phase 3

1. approval flow
2. transfer flow
3. partial receive
4. printable movement slip

## Notes

- DN should remain focused on delivery documentation.
- Warehouse Movement should become the operational transaction feature for stock and equipment movement.
- Both mobile and web must use the same status flow and data model to avoid mismatch.
