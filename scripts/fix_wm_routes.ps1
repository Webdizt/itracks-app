$ErrorActionPreference = 'Stop'

$routesPath = 'C:\laragon\www\dn.seascapesurveys.com\application\config\routes.php'
$backupPath = 'C:\laragon\www\dn.seascapesurveys.com\application\config\routes.php.bak-wm-codex'

Copy-Item $backupPath $routesPath -Force
$routes = Get-Content -Path $routesPath -Raw

$webRoutes = @'
// Warehouse Movement
$route['warehouse-movement'] = 'backend/admin/dan/Warehousemovement';
$route['warehouse-movement/add'] = 'backend/admin/dan/Warehousemovement/add';
$route['warehouse-movement/create'] = 'backend/admin/dan/Warehousemovement/create';
$route['warehouse-movement/detail/(:any)'] = 'backend/admin/dan/Warehousemovement/detail/$1';
$route['warehouse-movement/api/data'] = 'backend/admin/dan/Warehousemovement/api';

'@

$apiRoutes = @'
$route['api/warehouse-movement/create-data'] = 'backend/Apicontroller/apiWarehouseMovementCreateData';
$route['api/warehouse-movement/list'] = 'backend/Apicontroller/apiWarehouseMovementList';
$route['api/warehouse-movement/create'] = 'backend/Apicontroller/apiWarehouseMovementCreate';
$route['api/warehouse-movement/detail/(:any)'] = 'backend/Apicontroller/apiWarehouseMovementDetail/$1';

'@

$routes = $routes.Replace('//LOAD IMAGE', $webRoutes + '//LOAD IMAGE')
$routes = $routes.Replace("`$route['api/stats/data']", $apiRoutes + "`$route['api/stats/data']")

Set-Content -Path $routesPath -Value $routes -Encoding UTF8
Write-Output 'WM routes repaired.'
