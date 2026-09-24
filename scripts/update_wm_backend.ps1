$ErrorActionPreference = 'Stop'

$root = 'C:\laragon\www\dn.seascapesurveys.com'
$app = Join-Path $root 'application'

$modelPath = Join-Path $app 'models\MWarehousemovement.php'
$webControllerPath = Join-Path $app 'controllers\backend\admin\dan\Warehousemovement.php'
$apiControllerPath = Join-Path $app 'controllers\backend\Apicontroller.php'
$routesPath = Join-Path $app 'config\routes.php'
$viewsDir = Join-Path $app 'views\frontend\admin\warehouse_movement'
$listViewPath = Join-Path $viewsDir 'wm.twig'
$addViewPath = Join-Path $viewsDir 'wm_add.twig'
$detailViewPath = Join-Path $viewsDir 'wm_detail.twig'

New-Item -ItemType Directory -Force -Path $viewsDir | Out-Null

if (!(Test-Path "$apiControllerPath.bak-wm-codex")) {
    Copy-Item $apiControllerPath "$apiControllerPath.bak-wm-codex"
}
if (!(Test-Path "$routesPath.bak-wm-codex")) {
    Copy-Item $routesPath "$routesPath.bak-wm-codex"
}

$modelContent = @'
<?php

defined('BASEPATH') or exit('No direct script access allowed');

class MWarehousemovement extends CI_Model
{
    public function __construct()
    {
        parent::__construct();
        $this->dbit = $this->load->database('itracks', TRUE);
    }

    public function schemaReady()
    {
        return $this->dbit->table_exists('warehouse_movements')
            && $this->dbit->table_exists('warehouse_movement_items')
            && $this->dbit->table_exists('warehouse_movement_types')
            && $this->dbit->table_exists('warehouse_movement_purposes')
            && $this->dbit->table_exists('warehouse_movement_statuses');
    }

    public function getCreateData($requester = null)
    {
        return [
            'transaction_types' => $this->getTransactionTypes(),
            'purposes' => $this->getPurposes(),
            'locations' => $this->getLocations(),
            'projects' => $this->getProjects(),
            'requester' => $this->normalizeRequester($requester),
        ];
    }

    public function getMovementList($filters = [])
    {
        if (!$this->schemaReady()) {
            return [
                'items' => [],
                'page' => intval(isset($filters['page']) ? $filters['page'] : 1),
                'limit' => intval(isset($filters['limit']) ? $filters['limit'] : 20),
                'total' => 0,
            ];
        }

        $page = max(1, intval(isset($filters['page']) ? $filters['page'] : 1));
        $limit = max(1, min(100, intval(isset($filters['limit']) ? $filters['limit'] : 20)));
        $offset = ($page - 1) * $limit;
        $search = trim(isset($filters['search']) ? $filters['search'] : '');
        $status = trim(isset($filters['status']) ? $filters['status'] : '');
        $transactionType = trim(isset($filters['transaction_type']) ? $filters['transaction_type'] : '');

        $builder = $this->baseListBuilder($search, $status, $transactionType);
        $countBuilder = clone $builder;
        $total = intval($countBuilder->count_all_results());

        $items = $builder
            ->select("
                wm.uuid,
                wm.movement_number,
                wmt.code AS transaction_type,
                wmt.name AS transaction_type_text,
                wmp.code AS purpose,
                wmp.name AS purpose_text,
                COALESCE(p.job_number, '-') AS project_name,
                COALESCE(src.inventory_location, '-') AS source_location_name,
                COALESCE(dst.inventory_location, '-') AS destination_location_name,
                wms.code AS status,
                wms.name AS status_text,
                wm.movement_date,
                (
                    SELECT COUNT(*)
                    FROM warehouse_movement_items wmi
                    WHERE wmi.movement_id = wm.id
                ) AS item_count
            ", false)
            ->order_by('wm.id', 'DESC')
            ->limit($limit, $offset)
            ->get()
            ->result_array();

        return [
            'items' => $items,
            'page' => $page,
            'limit' => $limit,
            'total' => $total,
        ];
    }

    public function getMovementDetail($uuid)
    {
        if (!$this->schemaReady()) {
            return null;
        }

        $movement = $this->dbit
            ->select("
                wm.id,
                wm.uuid,
                wm.movement_number,
                wmt.code AS transaction_type,
                wmt.name AS transaction_type_text,
                wmp.code AS purpose,
                wmp.name AS purpose_text,
                wm.source_location_id,
                COALESCE(src.inventory_location, '-') AS source_location_name,
                wm.destination_location_id,
                COALESCE(dst.inventory_location, '-') AS destination_location_name,
                wm.project_id,
                COALESCE(p.job_number, '-') AS project_name,
                wm.requester_id,
                wm.movement_date,
                wm.required_date,
                wms.code AS status,
                wms.name AS status_text,
                wm.reference_number,
                wm.notes,
                wm.issued_date,
                wm.received_date
            ", false)
            ->from('warehouse_movements wm')
            ->join('warehouse_movement_types wmt', 'wmt.id = wm.movement_type_id', 'left')
            ->join('warehouse_movement_purposes wmp', 'wmp.id = wm.purpose_id', 'left')
            ->join('warehouse_movement_statuses wms', 'wms.id = wm.status_id', 'left')
            ->join('inventory_location src', 'src.id = wm.source_location_id', 'left')
            ->join('inventory_location dst', 'dst.id = wm.destination_location_id', 'left')
            ->join('data_job_number p', 'p.id = wm.project_id', 'left')
            ->where('wm.uuid', $uuid)
            ->where('wm.deleted_at IS NULL', null, false)
            ->get()
            ->row_array();

        if (!$movement) {
            return null;
        }

        $items = $this->dbit
            ->select('id, item_type, inventory_id, asset_code, serial_number, item_code, item_name, brand_name, model_name, category_name, qty, uom, stock_before, stock_after, remarks')
            ->from('warehouse_movement_items')
            ->where('movement_id', $movement['id'])
            ->order_by('id', 'ASC')
            ->get()
            ->result_array();

        $logs = $this->dbit
            ->select('id, action, action_label, action_by, action_at, notes')
            ->from('warehouse_movement_logs')
            ->where('movement_id', $movement['id'])
            ->order_by('id', 'DESC')
            ->get()
            ->result_array();

        return [
            'movement' => $movement,
            'items' => $items,
            'logs' => $logs,
        ];
    }

    public function createMovement($payload, $requester = null)
    {
        if (!$this->schemaReady()) {
            return [
                'status' => false,
                'message' => 'Warehouse Movement tables are not ready yet.',
            ];
        }

        $transactionType = trim(isset($payload['transaction_type']) ? $payload['transaction_type'] : '');
        $purpose = trim(isset($payload['purpose']) ? $payload['purpose'] : '');
        $sourceLocationId = intval(isset($payload['source_location_id']) ? $payload['source_location_id'] : 0);
        $destinationLocationId = intval(isset($payload['destination_location_id']) ? $payload['destination_location_id'] : 0);
        $projectId = isset($payload['project_id']) && $payload['project_id'] !== '' ? intval($payload['project_id']) : null;
        $movementDate = !empty($payload['movement_date']) ? $payload['movement_date'] : date('Y-m-d');
        $requiredDate = !empty($payload['required_date']) ? $payload['required_date'] : null;
        $referenceNumber = !empty($payload['reference_number']) ? $payload['reference_number'] : null;
        $notes = !empty($payload['notes']) ? $payload['notes'] : null;

        if ($transactionType === '' || $purpose === '' || $sourceLocationId <= 0 || $movementDate === '') {
            return [
                'status' => false,
                'message' => 'transaction_type, purpose, source_location_id, and movement_date are required.',
            ];
        }

        $typeId = $this->getMasterId('warehouse_movement_types', $transactionType);
        $purposeId = $this->getMasterId('warehouse_movement_purposes', $purpose);
        $statusId = $this->getMasterId('warehouse_movement_statuses', 'draft');

        if (!$typeId || !$purposeId || !$statusId) {
            return [
                'status' => false,
                'message' => 'Warehouse movement master data is incomplete.',
            ];
        }

        $uuid = bin2hex(random_bytes(16));
        $movementNumber = $this->generateMovementNumber($transactionType, $movementDate);
        $requesterId = $this->extractRequesterId($requester);
        $createdBy = $this->extractRequesterId($requester);
        if ($createdBy <= 0) {
            $createdBy = 0;
        }

        $insert = [
            'uuid' => $uuid,
            'movement_number' => $movementNumber,
            'movement_type_id' => $typeId,
            'purpose_id' => $purposeId,
            'source_location_id' => $sourceLocationId,
            'destination_location_id' => $destinationLocationId > 0 ? $destinationLocationId : null,
            'project_id' => $projectId,
            'requester_id' => $requesterId > 0 ? $requesterId : null,
            'status_id' => $statusId,
            'movement_date' => $movementDate,
            'required_date' => $requiredDate,
            'reference_number' => $referenceNumber,
            'notes' => $notes,
            'created_by' => $createdBy,
            'created_at' => date('Y-m-d H:i:s'),
        ];

        $this->dbit->insert('warehouse_movements', $insert);
        $movementId = intval($this->dbit->insert_id());

        if ($movementId <= 0) {
            return [
                'status' => false,
                'message' => 'Failed to create warehouse movement.',
            ];
        }

        $this->insertLog($movementId, 'created', 'Created', $createdBy, 'Warehouse movement created.');

        return [
            'status' => true,
            'message' => 'Movement created',
            'data' => [
                'uuid' => $uuid,
                'movement_number' => $movementNumber,
                'status' => 'draft',
            ],
        ];
    }

    public function getCreateDataForWeb()
    {
        $requesterName = function_exists('sess_data') ? sess_data('name') : '';
        $requesterId = function_exists('sess_data') ? sess_data('id') : '';

        return $this->getCreateData([
            'id' => $requesterId,
            'name' => $requesterName,
        ]);
    }

    private function baseListBuilder($search, $status, $transactionType)
    {
        $builder = $this->dbit
            ->from('warehouse_movements wm')
            ->join('warehouse_movement_types wmt', 'wmt.id = wm.movement_type_id', 'left')
            ->join('warehouse_movement_purposes wmp', 'wmp.id = wm.purpose_id', 'left')
            ->join('warehouse_movement_statuses wms', 'wms.id = wm.status_id', 'left')
            ->join('inventory_location src', 'src.id = wm.source_location_id', 'left')
            ->join('inventory_location dst', 'dst.id = wm.destination_location_id', 'left')
            ->join('data_job_number p', 'p.id = wm.project_id', 'left')
            ->where('wm.deleted_at IS NULL', null, false);

        if ($search !== '') {
            $builder->group_start()
                ->like('wm.movement_number', $search)
                ->or_like('p.job_number', $search)
                ->or_like('src.inventory_location', $search)
                ->or_like('dst.inventory_location', $search)
                ->group_end();
        }

        if ($status !== '') {
            $builder->where('wms.code', $status);
        }

        if ($transactionType !== '') {
            $builder->where('wmt.code', $transactionType);
        }

        return $builder;
    }

    private function getTransactionTypes()
    {
        if ($this->dbit->table_exists('warehouse_movement_types')) {
            return $this->dbit
                ->select('code AS id, name')
                ->from('warehouse_movement_types')
                ->where('is_active', 1)
                ->order_by('sort_order', 'ASC')
                ->get()
                ->result_array();
        }

        return [
            ['id' => 'issue_out', 'name' => 'Issue Out'],
            ['id' => 'return_in', 'name' => 'Return In'],
            ['id' => 'transfer', 'name' => 'Transfer'],
        ];
    }

    private function getPurposes()
    {
        if ($this->dbit->table_exists('warehouse_movement_purposes')) {
            return $this->dbit
                ->select('code AS id, name')
                ->from('warehouse_movement_purposes')
                ->where('is_active', 1)
                ->order_by('sort_order', 'ASC')
                ->get()
                ->result_array();
        }

        return [
            ['id' => 'project', 'name' => 'Project'],
            ['id' => 'office', 'name' => 'Office'],
            ['id' => 'warehouse_use', 'name' => 'Warehouse Use'],
            ['id' => 'maintenance', 'name' => 'Maintenance'],
            ['id' => 'other', 'name' => 'Other'],
        ];
    }

    private function getLocations()
    {
        return $this->dbit
            ->select('id, inventory_location AS name')
            ->from('inventory_location')
            ->where('delete_status', 'f')
            ->order_by('inventory_location', 'ASC')
            ->get()
            ->result_array();
    }

    private function getProjects()
    {
        return $this->dbit
            ->select('id, job_number, job_number AS name')
            ->from('data_job_number')
            ->where('delete_status', 'f')
            ->order_by('job_number', 'DESC')
            ->get()
            ->result_array();
    }

    private function normalizeRequester($requester)
    {
        if (is_array($requester)) {
            return [
                'id' => isset($requester['id']) ? $requester['id'] : '',
                'name' => isset($requester['name']) && $requester['name'] !== '' ? $requester['name'] : (isset($requester['username']) ? $requester['username'] : '-'),
            ];
        }

        if (is_object($requester)) {
            return [
                'id' => isset($requester->id) ? $requester->id : '',
                'name' => isset($requester->name) && $requester->name !== '' ? $requester->name : (isset($requester->username) ? $requester->username : '-'),
            ];
        }

        return [
            'id' => '',
            'name' => '-',
        ];
    }

    private function extractRequesterId($requester)
    {
        if (is_array($requester) && isset($requester['id']) && is_numeric($requester['id'])) {
            return intval($requester['id']);
        }

        if (is_object($requester) && isset($requester->id) && is_numeric($requester->id)) {
            return intval($requester->id);
        }

        return 0;
    }

    private function getMasterId($table, $code)
    {
        $row = $this->dbit
            ->select('id')
            ->from($table)
            ->where('code', $code)
            ->limit(1)
            ->get()
            ->row_array();

        return !empty($row['id']) ? intval($row['id']) : 0;
    }

    private function generateMovementNumber($transactionType, $movementDate)
    {
        $date = strtotime($movementDate);
        if ($date === false) {
            $date = time();
        }

        $prefixMap = [
            'issue_out' => 'OUT',
            'return_in' => 'RET',
            'transfer' => 'TRF',
            'request' => 'REQ',
        ];

        $prefix = isset($prefixMap[$transactionType]) ? $prefixMap[$transactionType] : 'GEN';
        $ym = date('ym', $date);
        $startDate = date('Y-m-01 00:00:00', $date);
        $endDate = date('Y-m-t 23:59:59', $date);

        $count = 0;
        if ($this->schemaReady()) {
            $row = $this->dbit
                ->select('COUNT(*) AS total', false)
                ->from('warehouse_movements wm')
                ->join('warehouse_movement_types wmt', 'wmt.id = wm.movement_type_id', 'left')
                ->where('wmt.code', $transactionType)
                ->where('wm.created_at >=', $startDate)
                ->where('wm.created_at <=', $endDate)
                ->where('wm.deleted_at IS NULL', null, false)
                ->get()
                ->row_array();
            $count = intval(isset($row['total']) ? $row['total'] : 0);
        }

        $counter = str_pad(strval($count + 1), 4, '0', STR_PAD_LEFT);
        return 'WM-' . $prefix . '-' . $ym . '-' . $counter;
    }

    private function insertLog($movementId, $action, $actionLabel, $actionBy, $notes = null)
    {
        if (!$this->dbit->table_exists('warehouse_movement_logs')) {
            return;
        }

        $this->dbit->insert('warehouse_movement_logs', [
            'movement_id' => $movementId,
            'action' => $action,
            'action_label' => $actionLabel,
            'action_by' => $actionBy,
            'action_at' => date('Y-m-d H:i:s'),
            'notes' => $notes,
        ]);
    }
}
'@

$webControllerContent = @'
<?php

defined('BASEPATH') or exit('No direct script access allowed');

class Warehousemovement extends MY_Controller
{
    public function __construct()
    {
        parent::__construct();
        is_login();
        $this->load->model('MWarehousemovement', 'mwarehousemovement');
    }

    public function index()
    {
        $data = [
            'schema_ready' => $this->mwarehousemovement->schemaReady(),
            'list' => $this->mwarehousemovement->getMovementList([
                'page' => 1,
                'limit' => 50,
            ]),
        ];

        $this->twig->display('admin/warehouse_movement/wm.twig', $data);
    }

    public function add()
    {
        $data = [
            'schema_ready' => $this->mwarehousemovement->schemaReady(),
            'createData' => $this->mwarehousemovement->getCreateDataForWeb(),
        ];

        $this->twig->display('admin/warehouse_movement/wm_add.twig', $data);
    }

    public function create()
    {
        $payload = [
            'transaction_type' => $this->input->post('transaction_type'),
            'purpose' => $this->input->post('purpose'),
            'source_location_id' => $this->input->post('source_location_id'),
            'destination_location_id' => $this->input->post('destination_location_id'),
            'project_id' => $this->input->post('project_id'),
            'movement_date' => $this->input->post('movement_date'),
            'required_date' => $this->input->post('required_date'),
            'reference_number' => $this->input->post('reference_number'),
            'notes' => $this->input->post('notes'),
        ];

        $result = $this->mwarehousemovement->createMovement($payload, [
            'id' => function_exists('sess_data') ? sess_data('id') : '',
            'name' => function_exists('sess_data') ? sess_data('name') : '',
        ]);

        if (empty($result['status'])) {
            $this->session->set_flashdata('alert', set_alert('danger', isset($result['message']) ? $result['message'] : 'Failed to create warehouse movement'));
            redirect(base_url('warehouse-movement/add'));
            return;
        }

        $this->session->set_flashdata('alert', set_alert('success', 'Warehouse movement created successfully'));
        redirect(base_url('warehouse-movement/detail/' . $result['data']['uuid']));
    }

    public function detail($uuid)
    {
        $detail = $this->mwarehousemovement->getMovementDetail($uuid);
        if (!$detail) {
            $this->session->set_flashdata('alert', set_alert('danger', 'Warehouse movement not found'));
            redirect(base_url('warehouse-movement'));
            return;
        }

        $data = [
            'schema_ready' => $this->mwarehousemovement->schemaReady(),
            'detail' => $detail,
        ];

        $this->twig->display('admin/warehouse_movement/wm_detail.twig', $data);
    }

    public function api()
    {
        $result = $this->mwarehousemovement->getMovementList([
            'search' => $this->input->get('search'),
            'status' => $this->input->get('status'),
            'transaction_type' => $this->input->get('transaction_type'),
            'page' => $this->input->get('page'),
            'limit' => $this->input->get('limit'),
        ]);

        $this->output
            ->set_content_type('application/json')
            ->set_output(json_encode([
                'status' => true,
                'message' => 'Success',
                'data' => $result,
            ]));
    }
}
'@

$listViewContent = @'
{% extends "layout/page/page-public.twig" %}

{% block content %}
<div class="app-content content">
    <div class="content-wrapper">
        <div class="content-header row">
            <div class="content-header-left col-md-6 col-12 mb-2 breadcrumb-new">
                <h3 class="content-header-title mb-0 d-inline-block">Warehouse Movement</h3>
                <div class="row breadcrumbs-top d-inline-block">
                    <div class="breadcrumb-wrapper col-12">
                        <ol class="breadcrumb">
                            <li class="breadcrumb-item"><a href="{{ base_url() }}">Home</a></li>
                            <li class="breadcrumb-item active">Warehouse Movement</li>
                        </ol>
                    </div>
                </div>
            </div>
            <div class="content-header-right col-md-6 col-12">
                <div class="dropdown float-md-right">
                    <a href="{{ base_url('warehouse-movement/add') }}" class="btn btn-primary btn-glow px-2">Create Movement</a>
                </div>
            </div>
        </div>

        <div class="content-body">
            <section id="configuration">
                <div class="row">
                    <div class="col-12">
                        {% if not schema_ready %}
                            <div class="alert alert-warning">
                                Warehouse Movement tables are not ready yet. Please run the SQL schema first.
                            </div>
                        {% endif %}
                        {{ get_flashdata('alert')|raw }}
                        <div class="card">
                            <div class="card-header">
                                <h4 class="card-title">Movement List</h4>
                            </div>
                            <div class="card-content collapse show">
                                <div class="card-body card-dashboard">
                                    <table class="table table-striped table-bordered">
                                        <thead>
                                            <tr>
                                                <th>No</th>
                                                <th>Movement Number</th>
                                                <th>Transaction Type</th>
                                                <th>Purpose</th>
                                                <th>Project / Office</th>
                                                <th>Source</th>
                                                <th>Destination</th>
                                                <th>Status</th>
                                                <th>Date</th>
                                                <th>Items</th>
                                                <th>Action</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            {% if list.items is empty %}
                                                <tr>
                                                    <td colspan="11" class="text-center">No warehouse movement data yet.</td>
                                                </tr>
                                            {% else %}
                                                {% for row in list.items %}
                                                    <tr>
                                                        <td>{{ loop.index }}</td>
                                                        <td>{{ row.movement_number }}</td>
                                                        <td>{{ row.transaction_type_text }}</td>
                                                        <td>{{ row.purpose_text }}</td>
                                                        <td>{{ row.project_name }}</td>
                                                        <td>{{ row.source_location_name }}</td>
                                                        <td>{{ row.destination_location_name }}</td>
                                                        <td>{{ row.status_text }}</td>
                                                        <td>{{ row.movement_date }}</td>
                                                        <td>{{ row.item_count }}</td>
                                                        <td>
                                                            <a href="{{ base_url('warehouse-movement/detail/' ~ row.uuid) }}" class="btn btn-sm btn-outline-primary">Detail</a>
                                                        </td>
                                                    </tr>
                                                {% endfor %}
                                            {% endif %}
                                        </tbody>
                                    </table>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </section>
        </div>
    </div>
</div>
{% endblock %}
'@

$addViewContent = @'
{% extends "layout/page/page-public.twig" %}

{% block content %}
<div class="app-content content">
    <div class="content-wrapper">
        <div class="content-header row">
            <div class="content-header-left col-md-6 col-12 mb-2 breadcrumb-new">
                <h3 class="content-header-title mb-0 d-inline-block">Create Warehouse Movement</h3>
                <div class="row breadcrumbs-top d-inline-block">
                    <div class="breadcrumb-wrapper col-12">
                        <ol class="breadcrumb">
                            <li class="breadcrumb-item"><a href="{{ base_url() }}">Home</a></li>
                            <li class="breadcrumb-item"><a href="{{ base_url('warehouse-movement') }}">Warehouse Movement</a></li>
                            <li class="breadcrumb-item active">Create</li>
                        </ol>
                    </div>
                </div>
            </div>
        </div>

        <div class="content-body">
            <section id="configuration">
                <div class="row">
                    <div class="col-12">
                        {% if not schema_ready %}
                            <div class="alert alert-warning">
                                Warehouse Movement tables are not ready yet. Please run the SQL schema first.
                            </div>
                        {% endif %}
                        {{ get_flashdata('alert')|raw }}
                        <div class="card">
                            <div class="card-content collapse show">
                                <div class="card-body card-dashboard">
                                    {{ form_open('warehouse-movement/create', {'accept-charset':'utf-8', 'autocomplete': 'off', 'class' : 'form-horizontal'})|raw }}
                                    <div class="form-body">
                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Transaction Type</label>
                                            <div class="col-md-4">
                                                <select name="transaction_type" class="form-control" required>
                                                    <option value="">Select Transaction Type</option>
                                                    {% for row in createData.transaction_types %}
                                                        <option value="{{ row.id }}">{{ row.name }}</option>
                                                    {% endfor %}
                                                </select>
                                            </div>
                                        </div>

                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Purpose</label>
                                            <div class="col-md-4">
                                                <select name="purpose" class="form-control" required>
                                                    <option value="">Select Purpose</option>
                                                    {% for row in createData.purposes %}
                                                        <option value="{{ row.id }}">{{ row.name }}</option>
                                                    {% endfor %}
                                                </select>
                                            </div>
                                        </div>

                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Source Location</label>
                                            <div class="col-md-4">
                                                <select name="source_location_id" class="form-control" required>
                                                    <option value="">Select Source Location</option>
                                                    {% for row in createData.locations %}
                                                        <option value="{{ row.id }}">{{ row.name }}</option>
                                                    {% endfor %}
                                                </select>
                                            </div>
                                        </div>

                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Destination Location</label>
                                            <div class="col-md-4">
                                                <select name="destination_location_id" class="form-control">
                                                    <option value="">Select Destination Location</option>
                                                    {% for row in createData.locations %}
                                                        <option value="{{ row.id }}">{{ row.name }}</option>
                                                    {% endfor %}
                                                </select>
                                            </div>
                                        </div>

                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Project</label>
                                            <div class="col-md-4">
                                                <select name="project_id" class="form-control">
                                                    <option value="">Select Project</option>
                                                    {% for row in createData.projects %}
                                                        <option value="{{ row.id }}">{{ row.name }}</option>
                                                    {% endfor %}
                                                </select>
                                            </div>
                                        </div>

                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Requester</label>
                                            <div class="col-md-4">
                                                <input type="text" class="form-control" value="{{ createData.requester.name }}" readonly>
                                            </div>
                                        </div>

                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Movement Date</label>
                                            <div class="col-md-4">
                                                <input type="date" name="movement_date" class="form-control" value="{{ 'now'|date('Y-m-d') }}" required>
                                            </div>
                                        </div>

                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Required Date</label>
                                            <div class="col-md-4">
                                                <input type="date" name="required_date" class="form-control">
                                            </div>
                                        </div>

                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Reference Number</label>
                                            <div class="col-md-4">
                                                <input type="text" name="reference_number" class="form-control">
                                            </div>
                                        </div>

                                        <div class="form-group row">
                                            <label class="col-md-2 label-control text-left">Notes</label>
                                            <div class="col-md-6">
                                                <textarea name="notes" class="form-control" rows="4"></textarea>
                                            </div>
                                        </div>
                                    </div>

                                    <div class="form-actions">
                                        <button type="submit" class="btn btn-primary btn-min-width mr-1 mb-1">Save Draft</button>
                                        <a href="{{ base_url('warehouse-movement') }}" class="btn btn-warning btn-min-width mr-1 mb-1">Cancel</a>
                                    </div>
                                    {{ form_close()|raw }}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </section>
        </div>
    </div>
</div>
{% endblock %}
'@

$detailViewContent = @'
{% extends "layout/page/page-public.twig" %}

{% block content %}
<div class="app-content content">
    <div class="content-wrapper">
        <div class="content-header row">
            <div class="content-header-left col-md-6 col-12 mb-2 breadcrumb-new">
                <h3 class="content-header-title mb-0 d-inline-block">{{ detail.movement.movement_number }}</h3>
                <div class="row breadcrumbs-top d-inline-block">
                    <div class="breadcrumb-wrapper col-12">
                        <ol class="breadcrumb">
                            <li class="breadcrumb-item"><a href="{{ base_url() }}">Home</a></li>
                            <li class="breadcrumb-item"><a href="{{ base_url('warehouse-movement') }}">Warehouse Movement</a></li>
                            <li class="breadcrumb-item active">Detail</li>
                        </ol>
                    </div>
                </div>
            </div>
        </div>

        <div class="content-body">
            {{ get_flashdata('alert')|raw }}
            <section id="configuration">
                <div class="row">
                    <div class="col-md-6 col-12">
                        <div class="card">
                            <div class="card-header"><h4 class="card-title">Summary</h4></div>
                            <div class="card-body">
                                <table class="table table-borderless">
                                    <tr><th>Movement Number</th><td>{{ detail.movement.movement_number }}</td></tr>
                                    <tr><th>Transaction Type</th><td>{{ detail.movement.transaction_type_text }}</td></tr>
                                    <tr><th>Purpose</th><td>{{ detail.movement.purpose_text }}</td></tr>
                                    <tr><th>Source</th><td>{{ detail.movement.source_location_name }}</td></tr>
                                    <tr><th>Destination</th><td>{{ detail.movement.destination_location_name }}</td></tr>
                                    <tr><th>Project</th><td>{{ detail.movement.project_name }}</td></tr>
                                    <tr><th>Status</th><td>{{ detail.movement.status_text }}</td></tr>
                                    <tr><th>Movement Date</th><td>{{ detail.movement.movement_date }}</td></tr>
                                    <tr><th>Notes</th><td>{{ detail.movement.notes ?: '-' }}</td></tr>
                                </table>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-6 col-12">
                        <div class="card">
                            <div class="card-header"><h4 class="card-title">Logs</h4></div>
                            <div class="card-body">
                                <table class="table table-striped table-bordered">
                                    <thead>
                                        <tr>
                                            <th>Action</th>
                                            <th>Date</th>
                                            <th>Notes</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {% if detail.logs is empty %}
                                            <tr><td colspan="3" class="text-center">No logs yet.</td></tr>
                                        {% else %}
                                            {% for row in detail.logs %}
                                                <tr>
                                                    <td>{{ row.action_label ?: row.action }}</td>
                                                    <td>{{ row.action_at }}</td>
                                                    <td>{{ row.notes ?: '-' }}</td>
                                                </tr>
                                            {% endfor %}
                                        {% endif %}
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                    <div class="col-12">
                        <div class="card">
                            <div class="card-header"><h4 class="card-title">Items</h4></div>
                            <div class="card-body">
                                <table class="table table-striped table-bordered">
                                    <thead>
                                        <tr>
                                            <th>No</th>
                                            <th>Type</th>
                                            <th>Item Name</th>
                                            <th>Asset Code</th>
                                            <th>Serial Number</th>
                                            <th>Qty</th>
                                            <th>UOM</th>
                                            <th>Remarks</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {% if detail.items is empty %}
                                            <tr><td colspan="8" class="text-center">No movement items yet.</td></tr>
                                        {% else %}
                                            {% for row in detail.items %}
                                                <tr>
                                                    <td>{{ loop.index }}</td>
                                                    <td>{{ row.item_type }}</td>
                                                    <td>{{ row.item_name }}</td>
                                                    <td>{{ row.asset_code ?: '-' }}</td>
                                                    <td>{{ row.serial_number ?: '-' }}</td>
                                                    <td>{{ row.qty }}</td>
                                                    <td>{{ row.uom ?: '-' }}</td>
                                                    <td>{{ row.remarks ?: '-' }}</td>
                                                </tr>
                                            {% endfor %}
                                        {% endif %}
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
            </section>
        </div>
    </div>
</div>
{% endblock %}
'@

Set-Content -Path $modelPath -Value $modelContent -Encoding UTF8
Set-Content -Path $webControllerPath -Value $webControllerContent -Encoding UTF8
Set-Content -Path $listViewPath -Value $listViewContent -Encoding UTF8
Set-Content -Path $addViewPath -Value $addViewContent -Encoding UTF8
Set-Content -Path $detailViewPath -Value $detailViewContent -Encoding UTF8

$routesContent = Get-Content -Path $routesPath -Raw
if ($routesContent -notmatch "warehouse-movement' = 'backend/admin/dan/Warehousemovement'") {
    $webRoutes = @"

// Warehouse Movement
\$route['warehouse-movement'] = 'backend/admin/dan/Warehousemovement';
\$route['warehouse-movement/add'] = 'backend/admin/dan/Warehousemovement/add';
\$route['warehouse-movement/create'] = 'backend/admin/dan/Warehousemovement/create';
\$route['warehouse-movement/detail/(:any)'] = 'backend/admin/dan/Warehousemovement/detail/\$1';
\$route['warehouse-movement/api/data'] = 'backend/admin/dan/Warehousemovement/api';
"@
    $routesContent = $routesContent -replace "//LOAD IMAGE", ($webRoutes + "`r`n//LOAD IMAGE")
}

if ($routesContent -notmatch "api/warehouse-movement/create-data") {
    $apiRoutes = @"

\$route['api/warehouse-movement/create-data'] = 'backend/Apicontroller/apiWarehouseMovementCreateData';
\$route['api/warehouse-movement/list'] = 'backend/Apicontroller/apiWarehouseMovementList';
\$route['api/warehouse-movement/create'] = 'backend/Apicontroller/apiWarehouseMovementCreate';
\$route['api/warehouse-movement/detail/(:any)'] = 'backend/Apicontroller/apiWarehouseMovementDetail/\$1';
"@
    $routesContent = $routesContent.Replace("`$route['api/stats/data']", $apiRoutes + "`r`n`$route['api/stats/data']")
}
Set-Content -Path $routesPath -Value $routesContent -Encoding UTF8

$apiContent = Get-Content -Path $apiControllerPath -Raw
if ($apiContent -notmatch "MWarehousemovement', 'mwarehousemovement'") {
    $apiContent = $apiContent -replace "\$this->load->model\('Mdancons', 'mdancons'\);", "\$this->load->model('Mdancons', 'mdancons');`r`n        \$this->load->model('MWarehousemovement', 'mwarehousemovement');"
}

if ($apiContent -notmatch "function apiWarehouseMovementCreateData") {
    $wmMethods = @'

public function apiWarehouseMovementCreateData()
{
    $user = $this->dnCurrentUser();
    if (!$user && !$this->dnHasApiSecret()) {
        return $this->dnReply(['status' => false, 'message' => 'Invalid token'], 401);
    }

    $data = $this->mwarehousemovement->getCreateData($user);
    return $this->dnReply([
        'status' => true,
        'message' => 'Success',
        'data' => $data,
    ]);
}

public function apiWarehouseMovementList()
{
    $user = $this->dnCurrentUser();
    if (!$user && !$this->dnHasApiSecret()) {
        return $this->dnReply(['status' => false, 'message' => 'Invalid token'], 401);
    }

    $result = $this->mwarehousemovement->getMovementList([
        'search' => $this->input->get('search'),
        'status' => $this->input->get('status'),
        'transaction_type' => $this->input->get('transaction_type'),
        'page' => $this->input->get('page'),
        'limit' => $this->input->get('limit'),
    ]);

    return $this->dnReply([
        'status' => true,
        'message' => 'Success',
        'data' => $result,
    ]);
}

public function apiWarehouseMovementCreate()
{
    $user = $this->dnCurrentUser();
    if (!$user && !$this->dnHasApiSecret()) {
        return $this->dnReply(['status' => false, 'message' => 'Invalid token'], 401);
    }
    if (!$user) {
        $user = ['id' => 0, 'name' => 'Mobile API'];
    }

    $payload = $this->dnJsonInput();
    $result = $this->mwarehousemovement->createMovement($payload, $user);
    if (empty($result['status'])) {
        return $this->dnReply([
            'status' => false,
            'message' => isset($result['message']) ? $result['message'] : 'Failed to create movement',
        ], 400);
    }

    return $this->dnReply($result, 200);
}

public function apiWarehouseMovementDetail($uuid)
{
    $user = $this->dnCurrentUser();
    if (!$user && !$this->dnHasApiSecret()) {
        return $this->dnReply(['status' => false, 'message' => 'Invalid token'], 401);
    }

    $detail = $this->mwarehousemovement->getMovementDetail($uuid);
    if (!$detail) {
        return $this->dnReply([
            'status' => false,
            'message' => 'Warehouse movement not found',
        ], 404);
    }

    return $this->dnReply([
        'status' => true,
        'message' => 'Success',
        'data' => $detail,
    ], 200);
}
'@
    $apiContent = $apiContent -replace "}\s*$", ($wmMethods + "`r`n}")
}

Set-Content -Path $apiControllerPath -Value $apiContent -Encoding UTF8

Write-Output 'Warehouse Movement backend patch applied.'
