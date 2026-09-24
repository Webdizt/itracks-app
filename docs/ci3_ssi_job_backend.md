# Backend CodeIgniter 3 — SSI-JOB API

> Dokumen ini berisi script lengkap untuk backend CI3 agar Flutter SSI-JOB bisa tersimpan ke database.  
> **Rekomendasi: tabel SSI-JOB dipisah dari tabel DAN**, karena domain bisnisnya berbeda (DAN = delivery/pengiriman, SSI-JOB = assignment asset ke project).

---

## 1. Database Migration (SQL)

Jalankan query ini di MySQL untuk membuat tabel `ssi_jobs` (header) dan `ssi_job_items` (detail):

```sql
-- Tabel Header SSI-JOB
CREATE TABLE IF NOT EXISTS `ssi_jobs` (
  `id` INT(11) UNSIGNED NOT NULL AUTO_INCREMENT,
  `job_number` VARCHAR(100) NOT NULL,
  `project_ref` VARCHAR(100) DEFAULT NULL COMMENT 'contoh: SSI-2506',
  `project_id` INT(11) UNSIGNED DEFAULT NULL,
  `client` VARCHAR(255) DEFAULT NULL,
  `location` VARCHAR(255) DEFAULT NULL,
  `status` ENUM('draft','ongoing','completed','cancelled') DEFAULT 'draft',
  `created_by` VARCHAR(100) DEFAULT NULL,
  `created_date` DATETIME DEFAULT NULL,
  `modified_date` DATETIME DEFAULT NULL,
  `delete_status` CHAR(1) DEFAULT 'f',
  PRIMARY KEY (`id`),
  UNIQUE KEY `job_number` (`job_number`),
  KEY `project_ref` (`project_ref`),
  KEY `status` (`status`),
  KEY `delete_status` (`delete_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Tabel Detail Item SSI-JOB
CREATE TABLE IF NOT EXISTS `ssi_job_items` (
  `id` INT(11) UNSIGNED NOT NULL AUTO_INCREMENT,
  `ssi_job_id` INT(11) UNSIGNED NOT NULL,
  `inventory_id` VARCHAR(255) DEFAULT NULL COMMENT 'bisa encrypted atau decrypted ID inventory',
  `asset_code` VARCHAR(100) NOT NULL,
  `asset_name` VARCHAR(255) NOT NULL,
  `serial_number` VARCHAR(255) DEFAULT NULL,
  `qty` INT(11) UNSIGNED DEFAULT 1,
  `created_date` DATETIME DEFAULT NULL,
  `modified_date` DATETIME DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `ssi_job_id` (`ssi_job_id`),
  KEY `asset_code` (`asset_code`),
  CONSTRAINT `fk_ssi_job_items_job` FOREIGN KEY (`ssi_job_id`) REFERENCES `ssi_jobs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## 2. Model CI3

Buat file: `application/models/M_ssi_job.php`

```php
<?php
defined('BASEPATH') OR exit('No direct script access allowed');

class M_ssi_job extends CI_Model {

    private $table = 'ssi_jobs';
    private $items_table = 'ssi_job_items';

    public function __construct() {
        parent::__construct();
        $this->dbit = $this->load->database('itracks', TRUE);
    }

    public function get_list($search = null, $limit = 20, $offset = 0) {
        $this->dbit->select('*');
        $this->dbit->from($this->table);
        $this->dbit->where('delete_status', 'f');
        if (!empty($search)) {
            $this->dbit->group_start();
            $this->dbit->like('job_number', $search);
            $this->dbit->or_like('project_ref', $search);
            $this->dbit->or_like('client', $search);
            $this->dbit->group_end();
        }
        $this->dbit->order_by('created_date', 'DESC');
        $this->dbit->limit($limit, $offset);
        $jobs = $this->dbit->get()->result_array();

        foreach ($jobs as &$job) {
            $job['encrypted_id'] = encrypt_url($job['id']);
            $job['items'] = $this->get_items_by_job_id($job['id']);
        }
        return $jobs;
    }

    public function get_count($search = null) {
        $this->dbit->from($this->table);
        $this->dbit->where('delete_status', 'f');
        if (!empty($search)) {
            $this->dbit->group_start();
            $this->dbit->like('job_number', $search);
            $this->dbit->or_like('project_ref', $search);
            $this->dbit->or_like('client', $search);
            $this->dbit->group_end();
        }
        return $this->dbit->count_all_results();
    }

    public function get_by_id($id) {
        $job = $this->dbit->get_where($this->table, ['id' => $id, 'delete_status' => 'f'])->row_array();
        if ($job) {
            $job['encrypted_id'] = encrypt_url($job['id']);
            $job['items'] = $this->get_items_by_job_id($id);
        }
        return $job;
    }

    public function get_items_by_job_id($job_id) {
        return $this->dbit->get_where($this->items_table, ['ssi_job_id' => $job_id])->result_array();
    }

    public function exists($job_number) {
        return $this->dbit->where('job_number', $job_number)
                          ->where('delete_status', 'f')
                          ->count_all_results($this->table) > 0;
    }

    public function insert_job($data) {
        $this->dbit->insert($this->table, $data);
        return $this->dbit->insert_id();
    }

    public function update_job($id, $data) {
        $this->dbit->where('id', $id);
        return $this->dbit->update($this->table, $data);
    }

    public function insert_item($data) {
        return $this->dbit->insert($this->items_table, $data);
    }

    public function delete_items_by_job_id($job_id) {
        $this->dbit->where('ssi_job_id', $job_id);
        return $this->dbit->delete($this->items_table);
    }
}
```

---

## 3. Controller CI3

Buat file: `application/controllers/api/Ssi_job.php`

```php
<?php
defined('BASEPATH') OR exit('No direct script access allowed');

class Ssi_job extends CI_Controller {

    public function __construct() {
        parent::__construct();
        $this->load->model('M_ssi_job', 'm_ssi_job');
        $this->dbit = $this->load->database('itracks', TRUE);
    }

    /* =========================================================
       Helper: Response JSON (sama pola dengan Apicontroller)
       ========================================================= */
    private function response($data, $http_code = 200) {
        $this->output
            ->set_content_type('application/json')
            ->set_status_header($http_code)
            ->set_output(json_encode($data))
            ->_display();
        exit;
    }

    /* =========================================================
       Helper: Ambil token dari header Authorization
       ========================================================= */
    private function _getAuthToken() {
        $authHeader = $this->input->get_request_header('Authorization');
        return preg_replace('/^Bearer\s*/', '', $authHeader);
    }

    /* =========================================================
       Helper: Validasi token (sama persis dengan Apicontroller)
       ========================================================= */
    private function validToken($headers) {
        $secret_key = "59nupkeebrcb6iud4po53k2e94141nm5";
        if ($secret_key === $headers) {
            return true;
        } else {
            return false;
        }
    }

    /* =========================================================
       Helper: Ambil user dari token (sama dengan Apicontroller)
       ========================================================= */
    private function getUserFromToken($token) {
        if (empty($token)) {
            return null;
        }
        return $this->db->where('sess_id', $token)->get('users')->row();
    }

    /* =========================================================
       Helper: Cek autentikasi
       ========================================================= */
    private function _checkAuth() {
        $token = $this->_getAuthToken();
        if ($this->validToken($token) === false) {
            $this->response([
                'status' => false,
                'message' => 'invalid'
            ], 401);
            return false;
        }
        return true;
    }

    /* =========================================================
       Helper: Format response job supaya cocok dengan Flutter
       ========================================================= */
    private function _formatJob($job) {
        if (empty($job)) return null;
        return [
            'id' => (string) $job['id'],
            'encrypted_id' => $job['encrypted_id'],
            'job_number' => $job['job_number'],
            'project' => [
                'job_number' => $job['project_ref'] ?? '',
                'client' => $job['client'] ?? '-',
                'location' => $job['location'] ?? '-',
            ],
            'status' => $job['status'],
            'items' => array_map(function ($item) {
                return [
                    'id' => (string) $item['id'],
                    'asset_code' => $item['asset_code'],
                    'asset_name' => $item['asset_name'],
                    'serial_number' => $item['serial_number'] ?? '-',
                    'qty' => (int) $item['qty'],
                    'inventory_id' => $item['inventory_id'] ?? null,
                ];
            }, $job['items'] ?? []),
            'created_at' => $job['created_date'],
            'updated_at' => $job['modified_date'],
        ];
    }

    /* =========================================================
       GET  /api/ssi-jobs
       ========================================================= */
    public function index() {
        if (!$this->_checkAuth()) return;

        $page  = (int) ($this->input->get('page') ?: 1);
        $limit = (int) ($this->input->get('limit') ?: 20);
        $search = $this->input->get('search');
        $offset = ($page - 1) * $limit;

        $jobs = $this->m_ssi_job->get_list($search, $limit, $offset);
        $total = $this->m_ssi_job->get_count($search);

        $formatted = array_map([$this, '_formatJob'], $jobs);

        $this->response([
            'status' => true,
            'message' => 'SSI-JOB list retrieved',
            'data' => $formatted,
            'meta' => [
                'current_page' => $page,
                'last_page' => (int) ceil($total / $limit),
                'total' => (int) $total,
            ]
        ], 200);
    }

    /* =========================================================
       POST /api/ssi-jobs
       ========================================================= */
    public function create() {
        if (!$this->_checkAuth()) return;

        $input_raw = file_get_contents('php://input');
        $input = json_decode($input_raw, true);

        // Validasi minimal
        if (empty($input['job_number']) || empty($input['project']['job_number']) || empty($input['items'])) {
            $this->response([
                'status' => false,
                'message' => 'job_number, project, and items are required'
            ], 400);
            return;
        }

        $job_number = $input['job_number'];

        // Cek duplikat job_number
        if ($this->m_ssi_job->exists($job_number)) {
            $this->response([
                'status' => false,
                'message' => 'Job number already exists'
            ], 409);
            return;
        }

        $project = $input['project'];
        $now = date('Y-m-d H:i:s');
        $user = $this->getUserFromToken($this->_getAuthToken());

        $this->dbit->trans_begin();

        $job_data = [
            'job_number' => $job_number,
            'project_ref' => $project['job_number'],
            'client' => $project['client'] ?? '-',
            'location' => $project['location'] ?? null,
            'status' => $input['status'] ?? 'draft',
            'created_by' => $user ? ($user->name ?? $user->username ?? 'API') : 'API',
            'created_date' => $now,
            'modified_date' => $now,
            'delete_status' => 'f',
        ];

        $job_id = $this->m_ssi_job->insert_job($job_data);

        foreach ($input['items'] as $item) {
            $inv_id_raw = $item['inventory_id'] ?? null;
            // Coba decrypt jika dari Flutter dikirim encrypted ID
            $inv_id = $inv_id_raw ? decrypt_url($inv_id_raw) : null;

            $this->m_ssi_job->insert_item([
                'ssi_job_id' => $job_id,
                'inventory_id' => !empty($inv_id) ? $inv_id : $inv_id_raw,
                'asset_code' => $item['asset_code'],
                'asset_name' => $item['asset_name'],
                'serial_number' => $item['serial_number'] ?? '-',
                'qty' => $item['qty'] ?? 1,
                'created_date' => $now,
                'modified_date' => $now,
            ]);
        }

        if ($this->dbit->trans_status() === FALSE) {
            $this->dbit->trans_rollback();
            $this->response([
                'status' => false,
                'message' => 'Database transaction failed'
            ], 500);
        } else {
            $this->dbit->trans_commit();
            $job = $this->m_ssi_job->get_by_id($job_id);
            $this->response([
                'status' => true,
                'message' => 'SSI-JOB created successfully',
                'data' => $this->_formatJob($job)
            ], 201);
        }
    }

    /* =========================================================
       GET /api/ssi-jobs/detail/{id}
       ========================================================= */
    public function detail($id = null) {
        if (!$this->_checkAuth()) return;
        if (!$id) {
            $this->response([
                'status' => false,
                'message' => 'ID is required'
            ], 400);
            return;
        }

        $decrypted_id = decrypt_url($id);
        $job = $this->m_ssi_job->get_by_id($decrypted_id);

        if (!$job) {
            $this->response([
                'status' => false,
                'message' => 'SSI-JOB not found'
            ], 404);
            return;
        }

        $this->response([
            'status' => true,
            'message' => 'SSI-JOB detail retrieved',
            'data' => $this->_formatJob($job)
        ], 200);
    }

    /* =========================================================
       POST /api/ssi-jobs/update/{id}
       ========================================================= */
    public function update($id = null) {
        if (!$this->_checkAuth()) return;
        if (!$id) {
            $this->response([
                'status' => false,
                'message' => 'ID is required'
            ], 400);
            return;
        }

        $decrypted_id = decrypt_url($id);
        $job = $this->m_ssi_job->get_by_id($decrypted_id);
        if (!$job) {
            $this->response([
                'status' => false,
                'message' => 'SSI-JOB not found'
            ], 404);
            return;
        }

        $input_raw = file_get_contents('php://input');
        $input = json_decode($input_raw, true);
        $now = date('Y-m-d H:i:s');

        $this->dbit->trans_begin();

        $update_data = ['modified_date' => $now];

        if (!empty($input['job_number'])) {
            if ($input['job_number'] !== $job['job_number'] && $this->m_ssi_job->exists($input['job_number'])) {
                $this->response([
                    'status' => false,
                    'message' => 'Job number already exists'
                ], 409);
                return;
            }
            $update_data['job_number'] = $input['job_number'];
        }

        if (!empty($input['project'])) {
            $update_data['project_ref'] = $input['project']['job_number'];
            $update_data['client'] = $input['project']['client'] ?? $job['client'];
            $update_data['location'] = $input['project']['location'] ?? $job['location'];
        }

        if (!empty($input['status'])) {
            $update_data['status'] = $input['status'];
        }

        $this->m_ssi_job->update_job($decrypted_id, $update_data);

        if (!empty($input['items'])) {
            $this->m_ssi_job->delete_items_by_job_id($decrypted_id);
            foreach ($input['items'] as $item) {
                $inv_id_raw = $item['inventory_id'] ?? null;
                $inv_id = $inv_id_raw ? decrypt_url($inv_id_raw) : null;

                $this->m_ssi_job->insert_item([
                    'ssi_job_id' => $decrypted_id,
                    'inventory_id' => !empty($inv_id) ? $inv_id : $inv_id_raw,
                    'asset_code' => $item['asset_code'],
                    'asset_name' => $item['asset_name'],
                    'serial_number' => $item['serial_number'] ?? '-',
                    'qty' => $item['qty'] ?? 1,
                    'created_date' => $now,
                    'modified_date' => $now,
                ]);
            }
        }

        if ($this->dbit->trans_status() === FALSE) {
            $this->dbit->trans_rollback();
            $this->response([
                'status' => false,
                'message' => 'Database transaction failed'
            ], 500);
        } else {
            $this->dbit->trans_commit();
            $updated = $this->m_ssi_job->get_by_id($decrypted_id);
            $this->response([
                'status' => true,
                'message' => 'SSI-JOB updated successfully',
                'data' => $this->_formatJob($updated)
            ], 200);
        }
    }
}
```

---

## 4. Routes

Tambahkan di file `application/config/routes.php`:

```php
// ==================== SSI-JOB API ====================
$route['api/ssi-jobs']                = 'api/ssi_job/index';
$route['api/ssi-jobs/detail/(:any)'] = 'api/ssi_job/detail/$1';
$route['api/ssi-jobs/update/(:any)'] = 'api/ssi_job/update/$1';
```

---

## 5. Integrasi dengan Flutter yang Sudah Dibuat

Di Flutter, endpoint sudah diatur sebagai berikut:

| Aksi Flutter | Endpoint CI3 | Method |
|--------------|--------------|--------|
| Ambil daftar project | `/api/projects/list` atau `/apiProjectOnline/{sess_id}` | GET |
| Simpan SSI-JOB baru | `/api/ssi-jobs` | POST |
| Update SSI-JOB | `/api/ssi-jobs/update/{id}` | POST |
| Lihat daftar SSI-JOB | `/api/ssi-jobs` | GET |
| Lihat detail SSI-JOB | `/api/ssi-jobs/detail/{id}` | GET |

Payload JSON dari Flutter (contoh):

```json
{
  "job_number": "SSI-JOB-2506-1",
  "project": {
    "job_number": "SSI-2506",
    "client": "PT. Seascape Surveys Indonesia",
    "location": "Balikpapan",
    "next_sequence": 2
  },
  "status": "ongoing",
  "items": [
    {
      "asset_code": "SSI-IT-0101",
      "asset_name": "Dell - Latitude 5420",
      "serial_number": "SN123456",
      "qty": 1,
      "inventory_id": "encrypted_or_plain_id"
    }
  ]
}
```

---

## 6. Checklist Deploy

1. [ ] Jalankan SQL migration di atas di database `itracks`.
2. [ ] Copy model `M_ssi_job.php` ke `application/models/`.
3. [ ] Copy controller `Ssi_job.php` ke `application/controllers/api/` (buat folder `api` jika belum ada).
4. [ ] Tambahkan route di `application/config/routes.php`.
5. [ ] Pastikan helper `encrypt_url()` dan `decrypt_url()` sudah tersedia (biasanya di `application/helpers/`).
6. [ ] Test dengan Postman atau langsung dari Flutter.

Jika ada error setelah deploy, silakan share error log-nya.
