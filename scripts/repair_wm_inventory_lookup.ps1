$modelPath = 'C:\laragon\www\dn.seascapesurveys.com\application\models\MWarehousemovement.php'

if (!(Test-Path $modelPath)) {
    Write-Error "MWarehousemovement.php not found at $modelPath"
    exit 1
}

$lines = [System.Collections.Generic.List[string]](Get-Content -Path $modelPath)
$inSnapshot = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'private function getInventorySnapshot\(\$inventoryId\)') {
        $inSnapshot = $true
        continue
    }
    if ($inSnapshot -and $lines[$i] -match '^\s*private function ') {
        break
    }
    if ($inSnapshot -and $lines[$i] -match "->where\('inventory\.delete_status', 'f'\)") {
        $lines[$i] = '            ->where("(inventory.delete_status = ''f'' OR inventory.delete_status IS NULL OR inventory.delete_status = '''')", null, false)'
        break
    }
}

$model = $lines -join "`r`n"

$newBlock = @'
            if ($inventoryId <= 0 && !empty($payload['asset_code'])) {
                $inventoryId = $this->findInventoryIdByAssetCode($payload['asset_code']);
            }
            if ($inventoryId <= 0 && !empty($payload['serial_number'])) {
                $inventoryId = $this->findInventoryIdBySerialNumber($payload['serial_number']);
            }
            if ($inventoryId <= 0) {
'@

if (!$model.Contains('findInventoryIdBySerialNumber')) {
    $model = $model -replace '(?s)\s*if \(\$inventoryId <= 0 && !empty\(\$payload\[''asset_code''\]\)\) \{\s*\$inventoryId = \$this->findInventoryIdByAssetCode\(\$payload\[''asset_code''\]\);\s*\}\s*if \(\$inventoryId <= 0\) \{', "`r`n$newBlock"
}

$oldLookup = @'
    private function findInventoryIdByAssetCode($assetCode)
    {
        $row = $this->dbit
            ->select('inventory.id')
            ->from('inventory')
            ->where('inventory.asset_code', trim((string) $assetCode))
            ->where('inventory.delete_status', 'f')
            ->limit(1)
            ->get()
            ->row_array();

        return isset($row['id']) ? intval($row['id']) : 0;
    }
'@

$newLookup = @'
    private function findInventoryIdByAssetCode($assetCode)
    {
        $row = $this->dbit
            ->select('inventory.id')
            ->from('inventory')
            ->where('inventory.asset_code', trim((string) $assetCode))
            ->where("(inventory.delete_status = 'f' OR inventory.delete_status IS NULL OR inventory.delete_status = '')", null, false)
            ->limit(1)
            ->get()
            ->row_array();

        return isset($row['id']) ? intval($row['id']) : 0;
    }

    private function findInventoryIdBySerialNumber($serialNumber)
    {
        $row = $this->dbit
            ->select('inventory.id')
            ->from('inventory')
            ->where('inventory.sn', trim((string) $serialNumber))
            ->where("(inventory.delete_status = 'f' OR inventory.delete_status IS NULL OR inventory.delete_status = '')", null, false)
            ->limit(1)
            ->get()
            ->row_array();

        return isset($row['id']) ? intval($row['id']) : 0;
    }
'@

$model = $model.Replace($oldLookup, $newLookup)

Set-Content -Path $modelPath -Value $model -Encoding UTF8
Write-Output 'Warehouse Movement inventory lookup repaired.'
