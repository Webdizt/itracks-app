# Warehouse Movement Database Schema

## Overview

This document proposes the database structure for the `Warehouse Movement` feature.

It is designed for:
- movement header/detail transactions
- stock updates for consumables
- location/project updates for equipment
- audit logs

## 1. Main Tables

### Table: `warehouse_movements`

Stores movement header data.

| Field | Type | Notes |
|---|---|---|
| id | bigint PK | auto increment |
| uuid | varchar(64) | unique identifier |
| movement_number | varchar(50) | human-readable document number |
| transaction_type | varchar(20) | `issue_out`, `return_in`, `transfer`, `request` |
| purpose | varchar(30) | `project`, `office`, `warehouse_use`, `maintenance`, `other` |
| source_location_id | bigint | source warehouse/location |
| destination_location_id | bigint | destination warehouse/location |
| project_id | bigint nullable | target project if purpose = project |
| requester_id | bigint nullable | user creating/requesting movement |
| movement_date | date | transaction date |
| status | varchar(20) | `draft`, `submitted`, `issued`, `received`, `completed`, `cancelled` |
| notes | text nullable | free text notes |
| created_by | bigint | user id |
| created_at | datetime | created timestamp |
| updated_by | bigint nullable | user id |
| updated_at | datetime nullable | updated timestamp |
| deleted_at | datetime nullable | soft delete if needed |

### Suggested Indexes

- unique index on `uuid`
- unique index on `movement_number`
- index on `transaction_type`
- index on `purpose`
- index on `status`
- index on `project_id`
- index on `movement_date`

## Table: `warehouse_movement_items`

Stores item details under each movement.

| Field | Type | Notes |
|---|---|---|
| id | bigint PK | auto increment |
| movement_id | bigint FK | references `warehouse_movements.id` |
| item_type | varchar(20) | `equipment` or `consumable` |
| inventory_id | bigint | references inventory master |
| asset_code | varchar(100) nullable | stored snapshot for display/reporting |
| serial_number | varchar(100) nullable | stored snapshot for display/reporting |
| item_name | varchar(255) | display name snapshot |
| qty | decimal(18,2) | issued or returned qty |
| uom | varchar(20) nullable | unit of measure |
| stock_before | decimal(18,2) nullable | for consumable |
| stock_after | decimal(18,2) nullable | for consumable |
| remarks | text nullable | item remarks |
| created_at | datetime | created timestamp |
| updated_at | datetime nullable | updated timestamp |

### Suggested Indexes

- index on `movement_id`
- index on `item_type`
- index on `inventory_id`
- index on `asset_code`
- index on `serial_number`

## Table: `warehouse_movement_logs`

Stores audit trail for status and user actions.

| Field | Type | Notes |
|---|---|---|
| id | bigint PK | auto increment |
| movement_id | bigint FK | references movement |
| action | varchar(50) | `created`, `updated`, `submitted`, `issued`, `received`, `cancelled` |
| action_by | bigint | user id |
| action_at | datetime | action timestamp |
| notes | text nullable | action notes |

### Suggested Indexes

- index on `movement_id`
- index on `action`
- index on `action_at`

## 2. Optional Approval Table

### Table: `warehouse_movement_approvals`

Use this if approval flow is needed later.

| Field | Type | Notes |
|---|---|---|
| id | bigint PK | auto increment |
| movement_id | bigint FK | references movement |
| approval_stage | varchar(30) | stage name |
| approved_by | bigint nullable | user id |
| approved_at | datetime nullable | approval time |
| status | varchar(20) | `pending`, `approved`, `rejected` |
| notes | text nullable | approval notes |

## 3. Inventory Master Dependencies

The movement feature assumes existing inventory master data already exists.

### Equipment inventory should support

- `id`
- `asset_code`
- `sn`
- `name` or resolved display fields
- `current_location_id`
- `project_id`
- `asset_status`
- `holder_type`
- `holder_reference`

### Consumable inventory should support

- `id`
- `item_code`
- `item_name`
- `uom`
- `stock_on_hand`
- `minimum_stock`
- `warehouse_location_id`

## 4. Suggested Reference Tables

### `warehouse_locations`

| Field | Type | Notes |
|---|---|---|
| id | bigint PK | location id |
| name | varchar(255) | location name |
| location_type | varchar(30) | `warehouse`, `office`, `project`, `field` |
| is_active | tinyint | active flag |

### `warehouse_movement_statuses` (optional)

Can be hardcoded first, but this table may help later.

| Field | Type | Notes |
|---|---|---|
| id | bigint PK | status id |
| code | varchar(30) | `draft`, `submitted`, etc. |
| name | varchar(100) | display label |
| sort_order | int | UI order |

## 5. Suggested SQL Draft

```sql
CREATE TABLE warehouse_movements (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    uuid VARCHAR(64) NOT NULL UNIQUE,
    movement_number VARCHAR(50) NOT NULL UNIQUE,
    transaction_type VARCHAR(20) NOT NULL,
    purpose VARCHAR(30) NOT NULL,
    source_location_id BIGINT NOT NULL,
    destination_location_id BIGINT NULL,
    project_id BIGINT NULL,
    requester_id BIGINT NULL,
    movement_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    notes TEXT NULL,
    created_by BIGINT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT NULL,
    updated_at DATETIME NULL DEFAULT NULL,
    deleted_at DATETIME NULL DEFAULT NULL,
    INDEX idx_wm_type (transaction_type),
    INDEX idx_wm_purpose (purpose),
    INDEX idx_wm_status (status),
    INDEX idx_wm_project (project_id),
    INDEX idx_wm_date (movement_date)
);
```

```sql
CREATE TABLE warehouse_movement_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    movement_id BIGINT NOT NULL,
    item_type VARCHAR(20) NOT NULL,
    inventory_id BIGINT NOT NULL,
    asset_code VARCHAR(100) NULL,
    serial_number VARCHAR(100) NULL,
    item_name VARCHAR(255) NOT NULL,
    qty DECIMAL(18,2) NOT NULL DEFAULT 1,
    uom VARCHAR(20) NULL,
    stock_before DECIMAL(18,2) NULL,
    stock_after DECIMAL(18,2) NULL,
    remarks TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NULL DEFAULT NULL,
    INDEX idx_wmi_movement (movement_id),
    INDEX idx_wmi_type (item_type),
    INDEX idx_wmi_inventory (inventory_id),
    INDEX idx_wmi_asset_code (asset_code),
    INDEX idx_wmi_serial_number (serial_number)
);
```

```sql
CREATE TABLE warehouse_movement_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    movement_id BIGINT NOT NULL,
    action VARCHAR(50) NOT NULL,
    action_by BIGINT NOT NULL,
    action_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes TEXT NULL,
    INDEX idx_wml_movement (movement_id),
    INDEX idx_wml_action (action),
    INDEX idx_wml_action_at (action_at)
);
```

## 6. Equipment Update Rules

When `transaction_type = issue_out` and `item_type = equipment`:
- update equipment location
- update project assignment if purpose = project
- update status to `On Project` or `In Use`

When `transaction_type = return_in` and `item_type = equipment`:
- set location back to warehouse
- clear project assignment if applicable
- set status to `Available`

## 7. Consumable Update Rules

When `transaction_type = issue_out` and `item_type = consumable`:
- subtract stock

When `transaction_type = return_in` and `item_type = consumable`:
- add stock, if business rules allow consumable returns

## 8. Reporting Support

Keep snapshot fields (`item_name`, `asset_code`, `serial_number`) in detail rows so reports stay stable even if inventory master changes later.
