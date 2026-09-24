$apiControllerPath = 'C:\laragon\www\dn.seascapesurveys.com\application\controllers\backend\Apicontroller.php'

if (!(Test-Path $apiControllerPath)) {
    Write-Error "Apicontroller.php not found at $apiControllerPath"
    exit 1
}

$apiContent = Get-Content -Path $apiControllerPath -Raw

$apiContent = $apiContent -replace '\$user = \$this->dnRequireUser\(\);\r?\n\s*if \(!\$user\) return;\r?\n\r?\n\s*\$result = \$this->mwarehousemovement->getMovementList\(\[', @'
$user = $this->dnCurrentUser();
    if (!$user && !$this->dnHasApiSecret()) {
        return $this->dnReply(['status' => false, 'message' => 'Invalid token'], 401);
    }

    $result = $this->mwarehousemovement->getMovementList([
'@

$apiContent = $apiContent -replace '\$user = \$this->dnRequireUser\(\);\r?\n\s*if \(!\$user\) return;\r?\n\r?\n\s*\$payload = \$this->dnJsonInput\(\);', @'
$user = $this->dnCurrentUser();
    if (!$user && !$this->dnHasApiSecret()) {
        return $this->dnReply(['status' => false, 'message' => 'Invalid token'], 401);
    }
    if (!$user) {
        $user = ['id' => 0, 'name' => 'Mobile API'];
    }

    $payload = $this->dnJsonInput();
'@

$apiContent = $apiContent -replace '\$user = \$this->dnRequireUser\(\);\r?\n\s*if \(!\$user\) return;\r?\n\r?\n\s*\$detail = \$this->mwarehousemovement->getMovementDetail\(\$uuid\);', @'
$user = $this->dnCurrentUser();
    if (!$user && !$this->dnHasApiSecret()) {
        return $this->dnReply(['status' => false, 'message' => 'Invalid token'], 401);
    }

    $detail = $this->mwarehousemovement->getMovementDetail($uuid);
'@

Set-Content -Path $apiControllerPath -Value $apiContent -Encoding UTF8
Write-Output 'Warehouse Movement API auth repaired.'
