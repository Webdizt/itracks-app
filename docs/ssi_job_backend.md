# Backend Schema & API Design — SSI-JOB (Project Job)

> Referensi: DAN (Delivery Not Out Going)  
> Bedanya: DAN = pengiriman/dispatch antar lokasi. SSI-JOB = assignment asset ke project/job.

## 1. Rekomendasi: Dipisah atau Digabung?

**Jawaban: DIPISAH tabelnya.**

Alasannya:
- **Domain berbeda**: DAN adalah dokumen pengiriman (Delivery Note), SSI-JOB adalah pekerjaan/assignment asset ke project.
- **Lifecycle berbeda**: DAN punya alur `Draft → Sent → Received`. SSI-JOB punya alur `Draft / Disusun → Ongoing → Completed`.
- **Reporting terpisah**: Project manager butuh laporan asset per job (SSI-JOB), sementara logistik butuh laporan pengiriman (DAN).
- **Maintenance lebih mudah**: perubahan requirement DAN tidak akan mengganggu SSI-JOB dan sebaliknya.

---

## 2. Database Schema (Laravel Migration)

### 2.1 Tabel Header: `ssi_jobs`

```php
<?php
// database/migrations/xxxx_create_ssi_jobs_table.php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('ssi_jobs', function (Blueprint $table) {
            $table->id();
            $table->string('job_number')->unique()->index(); // e.g. SSI-JOB-2506-1
            $table->string('project_ref');                    // e.g. SSI-2506
            $table->unsignedBigInteger('project_id')->nullable();
            $table->string('client');
            $table->string('location')->nullable();
            $table->enum('status', ['draft', 'ongoing', 'completed', 'cancelled'])
                  ->default('draft');
            $table->unsignedBigInteger('created_by')->nullable();
            $table->timestamps();

            $table->index(['project_ref', 'status']);
            $table->index('created_by');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ssi_jobs');
    }
};
```

### 2.2 Tabel Detail: `ssi_job_items`

```php
<?php
// database/migrations/xxxx_create_ssi_job_items_table.php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('ssi_job_items', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('ssi_job_id');
            $table->unsignedBigInteger('inventory_id')->nullable();
            $table->string('asset_code');
            $table->string('asset_name');
            $table->string('serial_number')->nullable();
            $table->unsignedInteger('qty')->default(1);
            $table->timestamps();

            $table->foreign('ssi_job_id')
                  ->references('id')
                  ->on('ssi_jobs')
                  ->onDelete('cascade');

            $table->index(['ssi_job_id', 'asset_code']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ssi_job_items');
    }
};
```

---

## 3. Eloquent Models

### `app/Models/SsiJob.php`

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class SsiJob extends Model
{
    use HasFactory;

    protected $fillable = [
        'job_number',
        'project_ref',
        'project_id',
        'client',
        'location',
        'status',
        'created_by',
    ];

    public function items(): HasMany
    {
        return $this->hasMany(SsiJobItem::class, 'ssi_job_id');
    }
}
```

### `app/Models/SsiJobItem.php`

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SsiJobItem extends Model
{
    use HasFactory;

    protected $fillable = [
        'ssi_job_id',
        'inventory_id',
        'asset_code',
        'asset_name',
        'serial_number',
        'qty',
    ];

    public function ssiJob(): BelongsTo
    {
        return $this->belongsTo(SsiJob::class, 'ssi_job_id');
    }
}
```

---

## 4. API Controller (Laravel)

### `app/Http/Controllers/Api/SsiJobController.php`

```php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SsiJob;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class SsiJobController extends Controller
{
    /**
     * GET /api/ssi-jobs
     */
    public function index(Request $request): JsonResponse
    {
        $query = SsiJob::with('items')
            ->orderByDesc('created_at');

        if ($request->filled('search')) {
            $search = $request->input('search');
            $query->where(function ($q) use ($search) {
                $q->where('job_number', 'like', "%{$search}%")
                  ->orWhere('project_ref', 'like', "%{$search}%")
                  ->orWhere('client', 'like', "%{$search}%");
            });
        }

        $limit = (int) $request->input('limit', 20);
        $jobs = $query->paginate($limit);

        return response()->json([
            'status' => true,
            'message' => 'SSI-JOB list retrieved',
            'data' => $jobs->items(),
            'meta' => [
                'current_page' => $jobs->currentPage(),
                'last_page' => $jobs->lastPage(),
                'total' => $jobs->total(),
            ],
        ]);
    }

    /**
     * POST /api/ssi-jobs
     */
    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'job_number' => 'required|string|max:100|unique:ssi_jobs,job_number',
            'project.job_number' => 'required|string|max:100',
            'project.client' => 'required|string|max:255',
            'project.location' => 'nullable|string|max:255',
            'status' => 'nullable|in:draft,ongoing,completed,cancelled',
            'items' => 'required|array|min:1',
            'items.*.asset_code' => 'required|string|max:100',
            'items.*.asset_name' => 'required|string|max:255',
            'items.*.serial_number' => 'nullable|string|max:255',
            'items.*.qty' => 'required|integer|min:1',
            'items.*.inventory_id' => 'nullable|integer|exists:inventory,id',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => false,
                'message' => 'Validation error',
                'errors' => $validator->errors(),
            ], 422);
        }

        DB::beginTransaction();
        try {
            $project = $request->input('project');

            $job = SsiJob::create([
                'job_number' => $request->input('job_number'),
                'project_ref' => $project['job_number'],
                'client' => $project['client'],
                'location' => $project['location'] ?? null,
                'status' => $request->input('status', 'draft'),
                'created_by' => auth()->id(),
            ]);

            foreach ($request->input('items') as $item) {
                $job->items()->create([
                    'inventory_id' => $item['inventory_id'] ?? null,
                    'asset_code' => $item['asset_code'],
                    'asset_name' => $item['asset_name'],
                    'serial_number' => $item['serial_number'] ?? null,
                    'qty' => $item['qty'],
                ]);
            }

            DB::commit();

            return response()->json([
                'status' => true,
                'message' => 'SSI-JOB created successfully',
                'data' => $job->load('items'),
            ], 201);
        } catch (\Throwable $e) {
            DB::rollBack();
            return response()->json([
                'status' => false,
                'message' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * GET /api/ssi-jobs/detail/{id}
     */
    public function show(string $id): JsonResponse
    {
        $job = SsiJob::with('items')->findOrFail($id);

        return response()->json([
            'status' => true,
            'message' => 'SSI-JOB detail retrieved',
            'data' => $job,
        ]);
    }

    /**
     * POST /api/ssi-jobs/update/{id}
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $job = SsiJob::with('items')->findOrFail($id);

        $validator = Validator::make($request->all(), [
            'job_number' => 'sometimes|string|max:100|unique:ssi_jobs,job_number,' . $job->id,
            'project.job_number' => 'sometimes|string|max:100',
            'project.client' => 'sometimes|string|max:255',
            'project.location' => 'nullable|string|max:255',
            'status' => 'nullable|in:draft,ongoing,completed,cancelled',
            'items' => 'sometimes|array',
            'items.*.asset_code' => 'required_with:items|string|max:100',
            'items.*.asset_name' => 'required_with:items|string|max:255',
            'items.*.serial_number' => 'nullable|string|max:255',
            'items.*.qty' => 'required_with:items|integer|min:1',
            'items.*.inventory_id' => 'nullable|integer|exists:inventory,id',
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => false,
                'message' => 'Validation error',
                'errors' => $validator->errors(),
            ], 422);
        }

        DB::beginTransaction();
        try {
            if ($request->has('job_number')) {
                $job->job_number = $request->input('job_number');
            }

            if ($request->has('project')) {
                $project = $request->input('project');
                $job->project_ref = $project['job_number'];
                $job->client = $project['client'];
                $job->location = $project['location'] ?? $job->location;
            }

            if ($request->has('status')) {
                $job->status = $request->input('status');
            }

            $job->save();

            if ($request->has('items')) {
                $job->items()->delete();
                foreach ($request->input('items') as $item) {
                    $job->items()->create([
                        'inventory_id' => $item['inventory_id'] ?? null,
                        'asset_code' => $item['asset_code'],
                        'asset_name' => $item['asset_name'],
                        'serial_number' => $item['serial_number'] ?? null,
                        'qty' => $item['qty'],
                    ]);
                }
            }

            DB::commit();

            return response()->json([
                'status' => true,
                'message' => 'SSI-JOB updated successfully',
                'data' => $job->load('items'),
            ]);
        } catch (\Throwable $e) {
            DB::rollBack();
            return response()->json([
                'status' => false,
                'message' => $e->getMessage(),
            ], 500);
        }
    }
}
```

---

## 5. Routes

Tambahkan di `routes/api.php`:

```php
use App\Http\Controllers\Api\SsiJobController;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/ssi-jobs', [SsiJobController::class, 'index']);
    Route::post('/ssi-jobs', [SsiJobController::class, 'store']);
    Route::get('/ssi-jobs/detail/{id}', [SsiJobController::class, 'show']);
    Route::post('/ssi-jobs/update/{id}', [SsiJobController::class, 'update']);
});
```

---

## 6. Ringkasan Integrasi Flutter ↔ Backend

| Aksi Flutter | Endpoint Laravel | Method |
|--------------|------------------|--------|
| Ambil daftar project | `/api/projects/list` | GET |
| Simpan SSI-JOB baru | `/api/ssi-jobs` | POST |
| Update SSI-JOB | `/api/ssi-jobs/update/{id}` | POST |
| Lihat daftar SSI-JOB | `/api/ssi-jobs` | GET |
| Lihat detail SSI-JOB | `/api/ssi-jobs/detail/{id}` | GET |

Jika ada pertanyaan atau butuh bantuan menjalankan `php artisan migrate`, silakan kabari.
