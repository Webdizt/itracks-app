# Warehouse Movement API Contract

## Overview

This document defines the initial API contract for the `Warehouse Movement` feature.

The goal is:
- one contract for mobile and web
- consistent movement status handling
- consistent enriched item data for equipment and consumables

Base style follows the current DN and inventory APIs:
- JSON request / response
- token-based authentication
- `status`, `message`, and `data` keys in responses

## Common Response Shape

### Success

```json
{
  "status": true,
  "message": "Success",
  "data": {}
}
```

### Error

```json
{
  "status": false,
  "message": "Validation failed",
  "errors": {
    "project_id": "Project is required"
  }
}
```

## Enum Values

### transaction_type

- `issue_out`
- `return_in`
- `transfer`
- `request`

### purpose

- `project`
- `office`
- `warehouse_use`
- `maintenance`
- `other`

### item_type

- `equipment`
- `consumable`

### status

- `draft`
- `submitted`
- `issued`
- `received`
- `completed`
- `cancelled`

## 1. Create Data

### GET `/api/warehouse-movement/create-data`

Used by both mobile and web to load:
- transaction types
- purposes
- warehouse / location options
- project options
- office options
- requester defaults

### Response

```json
{
  "status": true,
  "message": "Success",
  "data": {
    "transaction_types": [
      { "id": "issue_out", "name": "Issue Out" },
      { "id": "return_in", "name": "Return In" }
    ],
    "purposes": [
      { "id": "project", "name": "Project" },
      { "id": "office", "name": "Office" }
    ],
    "locations": [
      { "id": 1, "name": "Main Warehouse" },
      { "id": 2, "name": "Balikpapan Office" }
    ],
    "projects": [
      { "id": 10, "job_number": "SSI-2605", "name": "SSI-2605" }
    ],
    "requester": {
      "id": 88,
      "name": "Duwi Irwanto"
    }
  }
}
```

## 2. Movement List

### GET `/api/warehouse-movement/list`

### Query Parameters

- `search`
- `status`
- `transaction_type`
- `page`
- `limit`

### Response

```json
{
  "status": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "uuid": "wm-uuid",
        "movement_number": "WM-OUT-2605-0001",
        "transaction_type": "issue_out",
        "transaction_type_text": "Issue Out",
        "purpose": "project",
        "purpose_text": "Project",
        "project_name": "SSI-2605",
        "source_location_name": "Main Warehouse",
        "destination_location_name": "Project Vessel",
        "status": "draft",
        "status_text": "Draft",
        "movement_date": "2026-05-05",
        "item_count": 3
      }
    ],
    "page": 1,
    "limit": 20,
    "total": 1
  }
}
```

## 3. Create Movement

### POST `/api/warehouse-movement/create`

### Request

```json
{
  "transaction_type": "issue_out",
  "purpose": "project",
  "source_location_id": 1,
  "destination_location_id": 5,
  "project_id": 10,
  "movement_date": "2026-05-05",
  "notes": "Equipment issue for project setup"
}
```

### Response

```json
{
  "status": true,
  "message": "Movement created",
  "data": {
    "uuid": "wm-uuid",
    "movement_number": "WM-OUT-2605-0001",
    "status": "draft"
  }
}
```

## 4. Update Header

### POST `/api/warehouse-movement/update`

### Request

```json
{
  "uuid": "wm-uuid",
  "purpose": "office",
  "destination_location_id": 3,
  "project_id": null,
  "notes": "Updated destination"
}
```

## 5. Movement Detail

### GET `/api/warehouse-movement/detail/{uuid}`

### Response

```json
{
  "status": true,
  "message": "Success",
  "data": {
    "movement": {
      "uuid": "wm-uuid",
      "movement_number": "WM-OUT-2605-0001",
      "transaction_type": "issue_out",
      "transaction_type_text": "Issue Out",
      "purpose": "project",
      "purpose_text": "Project",
      "source_location_id": 1,
      "source_location_name": "Main Warehouse",
      "destination_location_id": 5,
      "destination_location_name": "Project Vessel",
      "project_id": 10,
      "project_name": "SSI-2605",
      "requester_id": 88,
      "requester_name": "Duwi Irwanto",
      "movement_date": "2026-05-05",
      "status": "draft",
      "status_text": "Draft",
      "notes": "Equipment issue for project setup"
    },
    "items": [
      {
        "id": 101,
        "item_type": "equipment",
        "inventory_id": 9001,
        "item_name": "TTL Connector",
        "asset_code": "SSI02082000001",
        "serial_number": "GFDGFDGFDG",
        "qty": 1,
        "uom": "pcs",
        "current_location_name": "Main Warehouse",
        "project_name": null
      },
      {
        "id": 102,
        "item_type": "consumable",
        "inventory_id": 3002,
        "item_name": "Cable Tie",
        "asset_code": "",
        "serial_number": "",
        "qty": 20,
        "uom": "pcs",
        "current_location_name": "Main Warehouse",
        "project_name": null
      }
    ],
    "logs": [
      {
        "action": "created",
        "action_by": "Duwi Irwanto",
        "action_at": "2026-05-05 08:00:00",
        "notes": "Movement draft created"
      }
    ]
  }
}
```

## 6. Search Equipment

### GET `/api/warehouse-movement/item-search-equipment`

### Query Parameters

- `search`

### Response

```json
{
  "status": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "inventory_id": 9001,
        "item_type": "equipment",
        "item_name": "TTL Connector",
        "asset_code": "SSI02082000001",
        "serial_number": "GFDGFDGFDG",
        "brand": "PPS Box",
        "model": "TTL Connector",
        "category_name": "IT Equipment",
        "current_location_id": 1,
        "current_location_name": "Main Warehouse",
        "project_id": null,
        "project_name": null,
        "asset_status": "Available",
        "qr_value": "SSI-IT-0602-0725080\nSN : 9S2026A77169\nAsset of IT Department"
      }
    ]
  }
}
```

## 7. Search Consumable

### GET `/api/warehouse-movement/item-search-consumable`

### Query Parameters

- `search`

### Response

```json
{
  "status": true,
  "message": "Success",
  "data": {
    "items": [
      {
        "inventory_id": 3002,
        "item_type": "consumable",
        "item_name": "Cable Tie",
        "uom": "pcs",
        "stock_on_hand": 200,
        "minimum_stock": 20,
        "warehouse_location_id": 1,
        "warehouse_location_name": "Main Warehouse"
      }
    ]
  }
}
```

## 8. Add Item

### POST `/api/warehouse-movement/item-add`

### Equipment Request

```json
{
  "uuid": "wm-uuid",
  "item_type": "equipment",
  "inventory_id": 9001,
  "qty": 1,
  "remarks": "Handle with care"
}
```

### Consumable Request

```json
{
  "uuid": "wm-uuid",
  "item_type": "consumable",
  "inventory_id": 3002,
  "qty": 20,
  "remarks": "For field setup"
}
```

### Response

```json
{
  "status": true,
  "message": "Item added",
  "data": {
    "item_id": 101
  }
}
```

## 9. Update Item

### POST `/api/warehouse-movement/item-update`

### Request

```json
{
  "uuid": "wm-uuid",
  "item_id": 101,
  "qty": 2,
  "remarks": "Updated quantity"
}
```

## 10. Delete Item

### POST `/api/warehouse-movement/item-delete`

### Request

```json
{
  "uuid": "wm-uuid",
  "item_id": 101
}
```

## 11. Submit Movement

### POST `/api/warehouse-movement/submit`

### Request

```json
{
  "uuid": "wm-uuid"
}
```

### Rules

- movement must have at least one item
- required header fields must be valid
- stock validation must pass

## 12. Issue Movement

### POST `/api/warehouse-movement/issue`

### Request

```json
{
  "uuid": "wm-uuid"
}
```

### Expected Server Actions

- update equipment location/status
- update consumable stock
- write movement logs
- update movement status to `issued`

## 13. Receive Movement

### POST `/api/warehouse-movement/receive`

### Request

```json
{
  "uuid": "wm-uuid"
}
```

### Expected Server Actions

- confirm receipt
- update movement status to `received` or `completed`
- update destination state if needed

## 14. Return Movement

### POST `/api/warehouse-movement/return`

### Request

```json
{
  "uuid": "wm-uuid"
}
```

### Expected Server Actions

- return equipment to warehouse
- restore consumable quantity if business rules allow
- write movement logs

## 15. Cancel Movement

### POST `/api/warehouse-movement/cancel`

### Request

```json
{
  "uuid": "wm-uuid",
  "reason": "Request created by mistake"
}
```

### Rules

- only allowed before issue, unless admin override exists

## Required Enriched Fields for Mobile and Web

Any detail response containing movement items must already include:

- `item_name`
- `asset_code`
- `serial_number`
- `brand`
- `model`
- `category_name`
- `current_location_name`
- `project_name`

This is critical so both web and mobile do not lose display values after reload.

## Error Handling Rules

### Equipment already active

```json
{
  "status": false,
  "message": "Equipment with this serial number is already assigned to another active movement."
}
```

### Consumable stock not enough

```json
{
  "status": false,
  "message": "Insufficient stock for the selected consumable item."
}
```

### Invalid project selection

```json
{
  "status": false,
  "message": "Project is required for project movement."
}
```

## Web and Mobile Notes

- Mobile and web should both use `/detail/{uuid}` as the single source of truth.
- Search APIs should be optimized for scan-first and manual search-first flows.
- Display values must not depend on client-side guessing when server can enrich them.
