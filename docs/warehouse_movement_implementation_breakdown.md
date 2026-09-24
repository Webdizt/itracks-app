# Warehouse Movement Implementation Breakdown

## Overview

This document breaks implementation into:
- backend API
- backend web/admin
- mobile Flutter

It is intended to be the practical build order after the feature spec is approved.

## 1. Backend API Modules

### A. Reference Data

Build first:
- `create-data`
- `projects`
- `locations`
- `equipment search`
- `consumable search`

Reason:
- both web and mobile depend on these for forms

### B. Header Transaction

Build next:
- create movement
- update movement
- list movement
- detail movement

Reason:
- this establishes movement number, header, and review screens

### C. Item Transaction

Build next:
- add equipment item
- add consumable item
- update item
- delete item

Important:
- detail API must always return enriched item display fields

### D. Process Action

Build next:
- submit
- issue
- receive
- cancel

Reason:
- this is where stock and location updates happen

## 2. Backend Admin Web Modules

### Menu Structure

Add admin menu:
- `Warehouse Movement`

Submenus:
- `Movement List`
- `Create Movement`
- `Issue / Receive`
- `History`

### Page 1: Movement List

Needs:
- search input
- filters
- table/grid
- status badge
- action buttons

Columns:
- Movement Number
- Type
- Purpose
- Project / Destination
- Date
- Status
- Item Count
- Actions

### Page 2: Create / Edit Movement

Sections:
- header information
- source/destination
- purpose/project
- notes
- item section

Actions:
- save draft
- submit

### Page 3: Add Equipment Modal

Needs:
- asset code search
- SN search
- result table
- select row
- add button

Columns:
- Asset Code
- Item Name
- Serial Number
- Current Location
- Status

### Page 4: Add Consumable Modal

Needs:
- item search
- available stock
- qty input
- add button

Columns:
- Item Name
- UOM
- Available Stock
- Warehouse

### Page 5: Movement Detail

Needs:
- status timeline
- item list
- audit logs
- action buttons for issue/receive/cancel

## 3. Mobile Flutter Modules

### Suggested Folder Structure

```text
lib/features/warehouse_movement/
  data/
    datasources/
    models/
    repositories/
  domain/
    entities/
    repositories/
    usecases/
  presentation/
    pages/
    widgets/
    controllers/
```

### Suggested Pages

#### `wm_list_page.dart`

Responsibilities:
- load movement list
- search
- filter
- open detail
- open create

#### `wm_create_page.dart`

Responsibilities:
- create movement header
- choose type/purpose/source/destination/project
- save draft
- continue to add items

#### `wm_equipment_page.dart`

Responsibilities:
- search equipment
- scan QR/SN
- add selected equipment to movement

#### `wm_consumable_page.dart`

Responsibilities:
- search consumables
- add qty-based items

#### `wm_review_page.dart`

Responsibilities:
- display full movement
- validate before submit
- submit movement

#### `wm_detail_page.dart`

Responsibilities:
- show header
- show items
- show status timeline
- issue / receive actions

## 4. Mobile Entity Suggestions

### `warehouse_movement.dart`

Fields:
- uuid
- movementNumber
- transactionType
- transactionTypeText
- purpose
- purposeText
- sourceLocationName
- destinationLocationName
- projectName
- requesterName
- movementDate
- status
- statusText
- notes
- itemCount

### `warehouse_movement_item.dart`

Fields:
- id
- itemType
- inventoryId
- itemName
- assetCode
- serialNumber
- qty
- uom
- currentLocationName
- projectName

## 5. API Build Order

### Sprint 1

- `GET /api/warehouse-movement/create-data`
- `POST /api/warehouse-movement/create`
- `GET /api/warehouse-movement/list`
- `GET /api/warehouse-movement/detail/{uuid}`

### Sprint 2

- `GET /api/warehouse-movement/item-search-equipment`
- `GET /api/warehouse-movement/item-search-consumable`
- `POST /api/warehouse-movement/item-add`
- `POST /api/warehouse-movement/item-delete`

### Sprint 3

- `POST /api/warehouse-movement/submit`
- `POST /api/warehouse-movement/issue`
- `POST /api/warehouse-movement/receive`
- `POST /api/warehouse-movement/cancel`

## 6. UI Build Order

### Mobile MVP

1. list page
2. create page
3. add equipment
4. add consumable
5. review page
6. detail page

### Web MVP

1. movement list
2. create movement form
3. add item modal
4. detail page
5. issue / receive actions

## 7. Status Button Rules

### Draft

Allowed:
- edit header
- add item
- delete item
- submit
- cancel

### Submitted

Allowed:
- issue
- cancel

### Issued

Allowed:
- receive

### Received

Allowed:
- complete

### Completed

Allowed:
- view only

### Cancelled

Allowed:
- view only

## 8. Validation Order

Before submit:
1. header required fields
2. item count > 0
3. stock validation
4. serial validation

Before issue:
1. movement status must be `submitted`
2. equipment must still be available
3. consumable stock must still be enough

Before receive:
1. movement status must be `issued`

## 9. Recommended Web Backend Controller Split

### API Controller

- `WarehouseMovementApiController`

Suggested methods:
- `createData()`
- `list()`
- `detail($uuid)`
- `create()`
- `update()`
- `searchEquipment()`
- `searchConsumable()`
- `addItem()`
- `deleteItem()`
- `submit()`
- `issue()`
- `receive()`
- `cancel()`

### Admin Web Controller

- `WarehouseMovementController`

Suggested methods:
- `index()`
- `create()`
- `edit($uuid)`
- `detail($uuid)`
- `issue($uuid)`
- `receive($uuid)`
- `history()`

## 10. Recommended Service / Business Layer

If backend codebase supports services, split critical logic into:

- `MovementNumberService`
- `MovementValidationService`
- `EquipmentMovementService`
- `ConsumableMovementService`
- `MovementStatusService`

This helps mobile and web stay consistent because all rules live in one place.

## 11. Risks to Watch

1. equipment detail may reload without enriched display fields
2. stock may change between draft and issue
3. SN-based equipment may be double issued without lock/validation
4. transfer flow may need stricter source/destination validation

## 12. Recommended Immediate Next Step

Start with:
1. SQL migration
2. backend API `create-data`, `create`, `list`, `detail`
3. mobile list/create/review pages
4. web list/create/detail pages

This gives a usable end-to-end draft flow quickly.
