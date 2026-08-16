<#
  experiment_optimizations.ps1 — Kiểm chứng BẰNG THỰC NGHIỆM các đề xuất tối ưu của AI.

  Task 2 yêu cầu phân loại từng đề xuất tối ưu là khả thi hay ảo tưởng. Phân loại trên
  giấy thì ai cũng nói được; script này đo A/B thật để có con số.

  Bốn cấu hình, mỗi cấu hình đo trên CÙNG một khối lượng dữ liệu (40.000 đơn hàng
  nạp sẵn, chia đều cho 60 tài khoản tải):

    1. baseline  — nguyên trạng SUT
    2. index     — thêm CREATE INDEX idx_orders_user_id ON orders(user_id)
    3. wal       — bật PRAGMA journal_mode=WAL
    4. both      — cả hai

  Vì sao phải nạp sẵn 40.000 đơn: trên DB rỗng thì bảng orders quá nhỏ để thiếu index
  gây ảnh hưởng, và phép đo sẽ kết luận sai rằng "thêm index không có tác dụng".

  Mọi thay đổi đều chỉ áp lên file SQLite cục bộ và bị xoá sạch ở lần reset kế tiếp
  (initDatabase() DROP TABLE khi khởi động) — KHÔNG sửa mã nguồn SUT.

  Dùng:  powershell -ExecutionPolicy Bypass -File scripts\experiment_optimizations.ps1
#>
param(
  [string]$Repo       = "D:\Kiem_thu\HW5",
  [string]$SutBackend = "D:\Kiem_thu\eshop-sut\backend",
  [string]$JMeterBat  = "D:\Kiem_thu\tools\apache-jmeter-5.6.3\bin\jmeter.bat",
  [int]   $SeedOrders = 40000,
  [int]   $Vu         = 60,
  [int]   $DurationS  = 60
)

$ErrorActionPreference = "Stop"
$outDir = Join-Path $Repo "results\experiments"
New-Item -ItemType Directory -Force $outDir | Out-Null
$db = Join-Path $SutBackend "database.sqlite"

function Invoke-Sqlite([string]$Sql) {
  Push-Location $SutBackend
  try {
    $escaped = $Sql.Replace('"', '\"')
    node -e "const s=require('sqlite3');const db=new s.Database('database.sqlite');db.exec(\"$escaped\",(e)=>{if(e){console.error('SQLERR '+e.message);process.exit(1)}db.close();});"
  } finally { Pop-Location }
}

function Add-SeedOrders([int]$N) {
  Push-Location $SutBackend
  try {
    node -e @"
const s = require('sqlite3');
const db = new s.Database('database.sqlite');
db.serialize(() => {
  db.all('SELECT id FROM users WHERE email LIKE ?', ['perf%'], (e, rows) => {
    if (e || !rows.length) { console.error('Khong tim thay tai khoan perf'); process.exit(1); }
    const ids = rows.map(r => r.id);
    db.run('BEGIN TRANSACTION');
    const st = db.prepare('INSERT INTO orders (user_id, total_amount, status, shipping_address) VALUES (?,?,?,?)');
    for (let i = 0; i < $N; i++) st.run(ids[i % ids.length], 1000000 + i, 'pending', 'seed ' + i);
    st.finalize(() => db.run('COMMIT', () => {
      db.get('SELECT COUNT(*) c FROM orders', [], (e2, r) => { console.log('orders=' + r.c); db.close(); });
    }));
  });
});
"@
  } finally { Pop-Location }
}

function Measure-Config([string]$Name) {
  $jtl = Join-Path $outDir "exp_$Name.jtl"
  Remove-Item $jtl -ErrorAction SilentlyContinue
  $env:JVM_ARGS = "-Xms1g -Xmx2g"
  & $JMeterBat -n -t (Join-Path $Repo "testplans\23127195_Load_20260816.jmx") `
      -l $jtl -j (Join-Path $outDir "exp_$Name.jmeter.log") `
      "-Jthreads=$Vu" "-Jrampup=5" "-Jduration=$DurationS" "-Jthinkmin=200" "-Jthinkrange=300" | Out-Null
  return $jtl
}

$configs = @(
  @{ Name = "1_baseline"; Index = $false; Wal = $false; Desc = "Nguyen trang" },
  @{ Name = "2_index";    Index = $true;  Wal = $false; Desc = "Them index orders(user_id)" },
  @{ Name = "3_wal";      Index = $false; Wal = $true;  Desc = "Bat SQLite WAL" },
  @{ Name = "4_both";     Index = $true;  Wal = $true;  Desc = "Ca hai" }
)

foreach ($c in $configs) {
  Write-Host ""
  Write-Host "=================================================================="
  Write-Host " CAU HINH: $($c.Name)  —  $($c.Desc)"
  Write-Host "=================================================================="

  # 1. Reset ve trang thai sach (DB bi DROP + seed lai, moi index/pragma cu bi xoa)
  & powershell -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\reset_sut.ps1") | Out-Null

  # 2. Bat WAL TRUOC khi nap du lieu (journal_mode la thuoc tinh ben vung cua file DB)
  if ($c.Wal) {
    Invoke-Sqlite "PRAGMA journal_mode=WAL;"
    Push-Location $SutBackend
    $mode = node -e "const s=require('sqlite3');const db=new s.Database('database.sqlite');db.get('PRAGMA journal_mode',[],(e,r)=>{console.log(r.journal_mode);db.close();});"
    Pop-Location
    Write-Host "  journal_mode = $mode"
  }

  # 3. Nap san 40.000 don de bang orders du lon cho viec thieu index co y nghia
  $cnt = Add-SeedOrders -N $SeedOrders
  Write-Host "  da nap du lieu: $cnt"

  # 4. Them index (sau khi nap du lieu, giong tinh huong that khi vao production)
  if ($c.Index) {
    Invoke-Sqlite "CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);"
    Write-Host "  da tao index idx_orders_user_id"
  }

  # 5. Do
  Write-Host "  dang do ($Vu VU trong ${DurationS}s) ..."
  $jtl = Measure-Config -Name $c.Name
  Write-Host "  xong -> $jtl"
}

Write-Host ""
Write-Host "=================================================================="
Write-Host " KET QUA SO SANH"
Write-Host "=================================================================="
foreach ($c in $configs) {
  $jtl = Join-Path $outDir "exp_$($c.Name).jtl"
  if (-not (Test-Path $jtl)) { continue }
  $rows = Import-Csv $jtl | Where-Object { $_.label -notlike "TC-*" }
  $tot = $rows.Count
  $span = ([long](($rows | Measure-Object timeStamp -Maximum).Maximum) - [long](($rows | Measure-Object timeStamp -Minimum).Minimum)) / 1000.0
  $line = "{0,-12} tong={1,6}  rps={2,7:N1}" -f $c.Name, $tot, ($tot / [math]::Max($span, 1))
  foreach ($lbl in @("07 GET /api/orders/my-orders", "06 POST /api/checkout")) {
    $e = $rows | Where-Object { $_.label -eq $lbl } | ForEach-Object { [int]$_.elapsed } | Sort-Object
    if ($e.Count -gt 0) {
      $p95 = $e[[math]::Max(0, [int][math]::Ceiling(0.95 * $e.Count) - 1)]
      $avg = [math]::Round(($e | Measure-Object -Average).Average, 1)
      $short = if ($lbl -like "*my-orders*") { "my-orders" } else { "checkout" }
      $line += "  |  $short avg=$avg p95=$p95"
    }
  }
  Write-Host $line
}
Write-Host ""
Write-Host "Log tho cua tung cau hinh nam trong: $outDir"
