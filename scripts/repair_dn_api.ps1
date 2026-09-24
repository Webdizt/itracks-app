$apiPath = 'C:\laragon\www\dn.seascapesurveys.com\application\controllers\backend\Apicontroller.php'
$routesPath = 'C:\laragon\www\dn.seascapesurveys.com\application\config\routes.php'

$apiContent = Get-Content -Raw -Path $apiPath

$replacement = @'
public function apiDnDetail($uuid)
{
    $user = $this->dnRequireUser();
    if (!$user) return;

    $dn = $this->dbit
        ->select('dan_proforma.*, data_job_number.job_number as job_number_text, data_cost_code.cost_code as cost_code_text, dan_proforma_status.dan_status as status_text')
        ->from('dan_proforma')
        ->join('data_job_number', 'data_job_number.id = dan_proforma.job_number', 'left')
        ->join('data_cost_code', 'data_cost_code.id = dan_proforma.cost_code', 'left')
        ->join('dan_proforma_status', 'dan_proforma_status.id = dan_proforma.dan_status', 'left')
        ->where('dan_proforma.uuid', $uuid)
        ->where('dan_proforma.delete_status', 'f')
        ->get()->row_array();

    if (!$dn) {
        return $this->dnReply(['status' => false, 'message' => 'DN not found'], 404);
    }

    $boxes = $this->dbit->select('*')
        ->from('dan_proforma_box')
        ->where('dan_proforma_id', $uuid)
        ->order_by('box_number', 'ASC')
        ->get()->result_array();

    foreach ($boxes as &$box) {
        $box['items'] = $this->dbit
            ->select('dan_proforma_equipments.id, dan_proforma_equipments.equipment_list, dan_proforma_equipments.equipment_name, dan_proforma_equipments.equipment_sn, dan_proforma_equipments.equipment_qty, dan_proforma_equipments.equipment_value, dan_proforma_equipments.equipment_notes, dan_proforma_equipments.flag_eq, inventory.asset_code, inventory.sn, inventory_group.inventory_group, inventory_model.inventory_model, inventory_manufacture.inventory_manufacture')
            ->from('dan_proforma_equipments')
            ->join('inventory', 'inventory.id = dan_proforma_equipments.equipment_list', 'left')
            ->join('inventory_group', 'inventory_group.id = inventory.eq_group', 'left')
            ->join('inventory_model', 'inventory_model.id = inventory.model', 'left')
            ->join('inventory_manufacture', 'inventory_manufacture.id = inventory.brand', 'left')
            ->where('dan_proforma_equipments.dan_proforma_id', $uuid)
            ->where('dan_proforma_equipments.box_number', $box['box_number'])
            ->get()->result_array();
    }
    unset($box);

    $meta = $this->dnMetaPayload($dn, $boxes);

    return $this->dnReply([
        'status' => true,
        'data' => [
            'dn' => $meta['dn'],
            'boxes' => $boxes,
            'meta' => $meta['meta'],
        ],
    ]);
}

private function dnJoinAddressParts($address, $address1 = '', $address2 = '', $address3 = '', $address4 = '', $address5 = '')
{
    $address = trim((string) $address);
    if ($address !== '') {
        return $address;
    }

    $parts = array_filter([
        trim((string) $address1),
        trim((string) $address2),
        trim((string) $address3),
        trim((string) $address4),
        trim((string) $address5),
    ]);

    return implode("\n", $parts);
}

private function dnAddressById($id)
{
    if (!$id) {
        return null;
    }

    return $this->dbit
        ->select('id, company_name, address, address1, address2, address3, address4, address5, telephone as telp, fax, sender, receiver')
        ->from('dan_proforma_common_address')
        ->where('id', $id)
        ->where('delete_status', 'f')
        ->get()
        ->row_array();
}

private function dnPdfData($uuid)
{
    $maxBox = $this->mdanequipment->getMaxBox($uuid);
    $dataProforma = $this->mdanproforma->getProformaData($uuid);

    return [
        'data' => array($this->mdanproforma->getVersion($uuid), $uuid),
        'maxBox' => $maxBox,
        'proforma' => $dataProforma,
        'dataProforma' => $this->mdanequipment->getDataProforma($uuid),
        'boxDan' => $this->mdanbox->getboxDan($uuid),
        'sender' => $this->dbit->select('*')->from('dan_proforma_common_address')->where('delete_status', 'f')->where('sender', 2)->order_by('company_name', 'ASC')->get()->result_array(),
        'receiver' => $this->dbit->select('*')->from('dan_proforma_common_address')->where('delete_status', 'f')->where('receiver', 2)->order_by('company_name', 'ASC')->get()->result_array(),
        'invUsage' => $this->dbit->select('*')->from('inventory_usage')->where('delete_status', 'f')->order_by('inventory_usage', 'ASC')->get()->result_array(),
        'proformaName' => $this->mdanproforma->getProformaName(),
        'proformaCurrency' => $this->mdanproforma->getProformaCurrency(),
        'proformaCounter' => $this->mdanproforma->getLastCounter($dataProforma['dan_number_company'], $dataProforma['job_number']),
    ];
}

private function dnPdfConfig($kind, $proforma)
{
    $map = [
        'dan-form' => [
            'view' => 'frontend/admin/dan/dan_form_pdf',
            'title' => 'DAN FORM ' . $proforma['dan_number'],
            'filename' => $proforma['dan_number'] . '.pdf',
        ],
        'dan-proforma' => [
            'view' => 'frontend/admin/dan/dan_proforma_pdf',
            'title' => 'DAN PROFORMA ' . $proforma['dan_number'],
            'filename' => (!empty($proforma['proforma_number']) ? $proforma['proforma_number'] : $proforma['dan_number']) . '.pdf',
        ],
        'dan-label' => [
            'view' => 'frontend/admin/dan/dan_label_pdf',
            'title' => 'DAN LABEL ' . $proforma['dan_number'],
            'filename' => $proforma['dan_number'] . '-Label.pdf',
        ],
    ];

    return isset($map[$kind]) ? $map[$kind] : null;
}

private function dnMetaPayload($dn, $boxes)
{
    $sender = $this->dnAddressById(isset($dn['sender_seascape']) ? $dn['sender_seascape'] : null);
    $receiver = $this->dnAddressById(isset($dn['delivery_seascape']) ? $dn['delivery_seascape'] : null);

    $totalWeight = 0;
    foreach ($boxes as $box) {
        $totalWeight += floatval(isset($box['box_weight']) ? $box['box_weight'] : 0);
    }

    $dn['sender_name'] = !empty($sender['company_name']) ? $sender['company_name'] : '';
    $dn['receiver_name'] = !empty($receiver['company_name']) ? $receiver['company_name'] : '';
    $dn['sender_address_text'] = $this->dnJoinAddressParts(
        isset($dn['sender_address']) ? $dn['sender_address'] : '',
        isset($sender['address1']) ? $sender['address1'] : '',
        isset($sender['address2']) ? $sender['address2'] : '',
        isset($sender['address3']) ? $sender['address3'] : '',
        isset($sender['address4']) ? $sender['address4'] : '',
        isset($sender['address5']) ? $sender['address5'] : ''
    );
    $dn['delivery_address_text'] = $this->dnJoinAddressParts(
        isset($dn['delivery_address']) ? $dn['delivery_address'] : '',
        isset($receiver['address1']) ? $receiver['address1'] : '',
        isset($receiver['address2']) ? $receiver['address2'] : '',
        isset($receiver['address3']) ? $receiver['address3'] : '',
        isset($receiver['address4']) ? $receiver['address4'] : '',
        isset($receiver['address5']) ? $receiver['address5'] : ''
    );
    $dn['dispatch_by_name'] = function_exists('getname') ? getname($dn['dispatch_by']) : $dn['dispatch_by'];
    $dn['received_by_name'] = function_exists('getname') ? getname($dn['received_by']) : $dn['received_by'];
    $dn['usage_text'] = function_exists('getSingle') ? getSingle('inventory_usage', 'inventory_usage', 'id', $dn['eq_usage']) : '';
    $dn['location_text'] = function_exists('getSingle') ? getSingle('inventory_location', 'inventory_location', 'id', $dn['eq_location']) : '';
    $dn['department_text'] = function_exists('getdepartment') ? getdepartment($dn['dan_number_department'], 'acronym', 'description') : '';

    return [
        'dn' => $dn,
        'meta' => [
            'dn_qr_url' => base_url('box-qrcode/' . $dn['uuid']),
            'total_box' => count($boxes),
            'total_weight' => $totalWeight,
            'download_urls' => [
                'dan_form' => base_url('api/dn/download/dan-form/' . $dn['uuid']),
                'dan_proforma' => base_url('api/dn/download/dan-proforma/' . $dn['uuid']),
                'dan_label' => base_url('api/dn/download/dan-label/' . $dn['uuid']),
            ],
        ],
    ];
}

public function apiDnDownload($kind, $uuid)
{
    $user = $this->dnCurrentUser();
    if (!$user && !$this->dnHasApiSecret()) {
        return $this->dnReply(['status' => false, 'message' => 'Invalid token'], 401);
    }

    $proforma = $this->mdanproforma->getProformaData($uuid);
    if (!$proforma) {
        return $this->dnReply(['status' => false, 'message' => 'DN not found'], 404);
    }

    $config = $this->dnPdfConfig($kind, $proforma);
    if (!$config) {
        return $this->dnReply(['status' => false, 'message' => 'Invalid download type'], 400);
    }

    $data = $this->dnPdfData($uuid);

    ob_start();
    $this->load->view($config['view'], $data);
    $html = ob_get_clean();

    try {
        $pdf = new HTML2PDF('P', 'A4', 'en', true, 'UTF-8', 3);
        $pdf->pdf->SetDisplayMode('fullpage');
        $pdf->pdf->SetAuthor('itracks.seascapesurveys.com');
        $pdf->pdf->SetTitle($config['title']);
        $pdf->pdf->SetProtection(array('annot-forms', 'print'), '', 'SS!#D4n202!');
        $pdf->WriteHTML($html, isset($_GET['vuehtml']));
        $output = $pdf->Output($config['filename'], 'S');

        return $this->output
            ->set_content_type('application/pdf')
            ->set_header('Content-Disposition: attachment; filename="' . $config['filename'] . '"')
            ->set_output($output);
    } catch (HTML2PDF_exception $e) {
        return $this->dnReply(['status' => false, 'message' => $e->getMessage()], 500);
    }
}

public function apiDnAddBox()
'@

$pattern = '(?s)public function apiDnDetail\(\$uuid\).*?public function apiDnAddBox\(\)'
$apiContent = [regex]::Replace($apiContent, $pattern, $replacement)
Set-Content -Path $apiPath -Value $apiContent -Encoding UTF8

$routesContent = Get-Content -Raw -Path $routesPath
if ($routesContent -notmatch [regex]::Escape("\$route['api/dn/download/(:any)/(:any)'] = 'backend/Apicontroller/apiDnDownload/\$1/\$2';")) {
  $routesContent = $routesContent -replace [regex]::Escape("`$route['api/dn/dispatch/finish'] = 'backend/Apicontroller/apiDnFinish';"), "`$route['api/dn/dispatch/finish'] = 'backend/Apicontroller/apiDnFinish';`r`n`$route['api/dn/download/(:any)/(:any)'] = 'backend/Apicontroller/apiDnDownload/`$1/`$2';"
  Set-Content -Path $routesPath -Value $routesContent -Encoding UTF8
}

Write-Output 'DN API repair complete.'
