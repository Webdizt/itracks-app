-- Warehouse Movement schema draft
-- Target: MySQL / MariaDB
-- Notes:
-- 1. Adjust referenced table names if your existing master tables use different names.
-- 2. Foreign keys to existing tables are added as optional comments when table names are uncertain.
-- 3. This script is safe to review first; do not run blindly in production without checking existing schema.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS warehouse_movement_types (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(100) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NULL DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_wm_types_code (code),
    KEY idx_wm_types_active (is_active),
    KEY idx_wm_types_sort (sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS warehouse_movement_purposes (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(100) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NULL DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_wm_purposes_code (code),
    KEY idx_wm_purposes_active (is_active),
    KEY idx_wm_purposes_sort (sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS warehouse_movement_statuses (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(100) NOT NULL,
    sort_order INT NOT NULL DEFAULT 0,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NULL DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_wm_statuses_code (code),
    KEY idx_wm_statuses_active (is_active),
    KEY idx_wm_statuses_sort (sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS warehouse_movements (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid VARCHAR(64) NOT NULL,
    movement_number VARCHAR(50) NOT NULL,
    movement_type_id BIGINT UNSIGNED NOT NULL,
    purpose_id BIGINT UNSIGNED NOT NULL,
    source_location_id BIGINT UNSIGNED NOT NULL,
    destination_location_id BIGINT UNSIGNED NULL,
    project_id BIGINT UNSIGNED NULL,
    requester_id BIGINT UNSIGNED NULL,
    status_id BIGINT UNSIGNED NOT NULL,
    movement_date DATE NOT NULL,
    required_date DATE NULL,
    issued_date DATETIME NULL,
    received_date DATETIME NULL,
    reference_number VARCHAR(100) NULL,
    notes TEXT NULL,
    approved_by BIGINT UNSIGNED NULL,
    approved_at DATETIME NULL,
    issued_by BIGINT UNSIGNED NULL,
    received_by BIGINT UNSIGNED NULL,
    created_by BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT UNSIGNED NULL,
    updated_at DATETIME NULL DEFAULT NULL,
    deleted_at DATETIME NULL DEFAULT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_wm_uuid (uuid),
    UNIQUE KEY uq_wm_number (movement_number),
    KEY idx_wm_type_id (movement_type_id),
    KEY idx_wm_purpose_id (purpose_id),
    KEY idx_wm_source_location (source_location_id),
    KEY idx_wm_destination_location (destination_location_id),
    KEY idx_wm_project_id (project_id),
    KEY idx_wm_requester_id (requester_id),
    KEY idx_wm_status_id (status_id),
    KEY idx_wm_movement_date (movement_date),
    KEY idx_wm_required_date (required_date),
    KEY idx_wm_created_at (created_at),
    KEY idx_wm_deleted_at (deleted_at),
    CONSTRAINT fk_wm_type
        FOREIGN KEY (movement_type_id) REFERENCES warehouse_movement_types (id),
    CONSTRAINT fk_wm_purpose
        FOREIGN KEY (purpose_id) REFERENCES warehouse_movement_purposes (id),
    CONSTRAINT fk_wm_status
        FOREIGN KEY (status_id) REFERENCES warehouse_movement_statuses (id)
    -- Optional foreign keys to existing masters:
    -- ,CONSTRAINT fk_wm_source_location FOREIGN KEY (source_location_id) REFERENCES inventory_location (id)
    -- ,CONSTRAINT fk_wm_destination_location FOREIGN KEY (destination_location_id) REFERENCES inventory_location (id)
    -- ,CONSTRAINT fk_wm_project FOREIGN KEY (project_id) REFERENCES data_job_number (id)
    -- ,CONSTRAINT fk_wm_requester FOREIGN KEY (requester_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS warehouse_movement_items (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    movement_id BIGINT UNSIGNED NOT NULL,
    item_type VARCHAR(20) NOT NULL,
    inventory_id BIGINT UNSIGNED NULL,
    asset_code VARCHAR(100) NULL,
    serial_number VARCHAR(100) NULL,
    item_code VARCHAR(100) NULL,
    item_name VARCHAR(255) NOT NULL,
    brand_name VARCHAR(255) NULL,
    model_name VARCHAR(255) NULL,
    category_name VARCHAR(255) NULL,
    qty DECIMAL(18,2) NOT NULL DEFAULT 1.00,
    uom VARCHAR(30) NULL,
    stock_before DECIMAL(18,2) NULL,
    stock_after DECIMAL(18,2) NULL,
    source_location_id BIGINT UNSIGNED NULL,
    destination_location_id BIGINT UNSIGNED NULL,
    current_project_id BIGINT UNSIGNED NULL,
    target_project_id BIGINT UNSIGNED NULL,
    remarks TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NULL DEFAULT NULL,
    PRIMARY KEY (id),
    KEY idx_wmi_movement_id (movement_id),
    KEY idx_wmi_item_type (item_type),
    KEY idx_wmi_inventory_id (inventory_id),
    KEY idx_wmi_asset_code (asset_code),
    KEY idx_wmi_serial_number (serial_number),
    KEY idx_wmi_item_code (item_code),
    CONSTRAINT fk_wmi_movement
        FOREIGN KEY (movement_id) REFERENCES warehouse_movements (id)
        ON DELETE CASCADE
    -- Optional foreign key to existing inventory master:
    -- ,CONSTRAINT fk_wmi_inventory FOREIGN KEY (inventory_id) REFERENCES inventory (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS warehouse_movement_logs (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    movement_id BIGINT UNSIGNED NOT NULL,
    action VARCHAR(50) NOT NULL,
    action_label VARCHAR(100) NULL,
    action_by BIGINT UNSIGNED NOT NULL,
    action_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes TEXT NULL,
    payload_json LONGTEXT NULL,
    PRIMARY KEY (id),
    KEY idx_wml_movement_id (movement_id),
    KEY idx_wml_action (action),
    KEY idx_wml_action_at (action_at),
    CONSTRAINT fk_wml_movement
        FOREIGN KEY (movement_id) REFERENCES warehouse_movements (id)
        ON DELETE CASCADE
    -- Optional foreign key:
    -- ,CONSTRAINT fk_wml_action_by FOREIGN KEY (action_by) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS warehouse_movement_approvals (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    movement_id BIGINT UNSIGNED NOT NULL,
    approval_stage VARCHAR(30) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    approved_by BIGINT UNSIGNED NULL,
    approved_at DATETIME NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NULL DEFAULT NULL,
    PRIMARY KEY (id),
    KEY idx_wma_movement_id (movement_id),
    KEY idx_wma_stage (approval_stage),
    KEY idx_wma_status (status),
    CONSTRAINT fk_wma_movement
        FOREIGN KEY (movement_id) REFERENCES warehouse_movements (id)
        ON DELETE CASCADE
    -- Optional foreign key:
    -- ,CONSTRAINT fk_wma_approved_by FOREIGN KEY (approved_by) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO warehouse_movement_types (code, name, sort_order, is_active)
VALUES
    ('issue_out', 'Issue Out', 1, 1),
    ('return_in', 'Return In', 2, 1),
    ('transfer', 'Transfer', 3, 1),
    ('request', 'Request', 4, 1)
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    sort_order = VALUES(sort_order),
    is_active = VALUES(is_active);

INSERT INTO warehouse_movement_purposes (code, name, sort_order, is_active)
VALUES
    ('project', 'Project', 1, 1),
    ('office', 'Office', 2, 1),
    ('warehouse_use', 'Warehouse Use', 3, 1),
    ('maintenance', 'Maintenance', 4, 1),
    ('other', 'Other', 5, 1)
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    sort_order = VALUES(sort_order),
    is_active = VALUES(is_active);

INSERT INTO warehouse_movement_statuses (code, name, sort_order, is_active)
VALUES
    ('draft', 'Draft', 1, 1),
    ('submitted', 'Submitted', 2, 1),
    ('approved', 'Approved', 3, 1),
    ('issued', 'Issued', 4, 1),
    ('received', 'Received', 5, 1),
    ('completed', 'Completed', 6, 1),
    ('cancelled', 'Cancelled', 7, 1)
ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    sort_order = VALUES(sort_order),
    is_active = VALUES(is_active);

SET FOREIGN_KEY_CHECKS = 1;

-- Suggested numbering format:
-- WM-OUT-2605-0001
-- WM-RET-2605-0001
-- WM-TRF-2605-0001
-- WM-REQ-2605-0001

-- Suggested business notes:
-- 1. item_type = 'equipment' should update current item location / project assignment.
-- 2. item_type = 'consumable' should update stock_on_hand using qty.
-- 3. Keep asset_code / serial_number / item_name snapshots for historical reporting.
