<#
  experiment_threadpool.ps1 — Kiểm chứng đề xuất "tăng UV_THREADPOOL_SIZE".

  Cơ sở của đề xuất: node-sqlite3 là binding C++, nó chạy truy vấn trên libuv
  threadpool chứ không phải trên luồng JS. Threadpool mặc định chỉ có 4 luồng,
  nên trên lý thuyết đó có thể là chỗ nghẽn khi nhiều truy vấn chạy đồng thời.

  Giả thuyết ngược lại (dựa trên số liệu đã có): nút thắt thật là luồng JS đơn
  của Node, chứ không phải threadpool — vì POST /api/cart KHÔNG hề chạm DB
  (không dùng threadpool) mà vẫn chậm đi cùng nhịp với mọi endpoint khác.

  Nếu giả thuyết ngược đúng thì tăng threadpool sẽ cải thiện rất ít.
  Script này đo để biết, thay vì đoán.

  Dùng:  powershell -ExecutionPolicy Bypass -File scripts\experiment_threadpool.ps1
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

function Start-Backend([int]$PoolSize) {
  Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { try { Stop-Process -Id $_.OwningProcess -Force } catch {} }
  Start-Sleep -Milliseconds 800
  # Truyen bien moi truong cho tien trinh con qua 'cmd /c set ... && node'
  Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c start `"eshop-backend`" /min cmd /c `"set UV_THREADPOOL_SIZE=$PoolSize && node server.js`"" `
    -WorkingDirectory $SutBackend -WindowStyle Hidden
  foreach ($i in 1..40) {
    Start-Sleep -Milliseconds 500
    try { if ((Invoke-WebRequest -Uri "http://localhost:3000/api/products" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { return } } catch {}
  }
  throw "Backend khong san sang"
}

function Measure-Run([string]$Name) {
  $jtl = Join-Path $outDir "exp_$Name.jtl"
  Remove-Item $jtl -ErrorAction SilentlyContinue
  $env:JVM_ARGS = "-Xms1g -Xmx2g"
  & $JMeterBat -n -t (Join-Path $Repo "testplans\23127195_Load_20260816.jmx") `
      -l $jtl -j (Join-Path $outDir "exp_$Name.jmeter.log") `
      "-Jthreads=$Vu" "-Jrampup=5" "-Jduration=$DurationS" "-Jthinkmin=200" "-Jthinkrange=300" | Out-Null
  $rows = Import-Csv $jtl | Where-Object { $_.label -notlike "TC-*" }
  $span = ([long](($rows | Measure-Object timeStamp -Maximum).Maximum) - [long](($rows | Measure-Object timeStamp -Minimum).Minimum)) / 1000.0
  $res = [ordered]@{ Name = $Name; Total = $rows.Count; Rps = [math]::Round($rows.Count / [math]::Max($span, 1), 1) }
  foreach ($pair in @(@("07 GET /api/orders/my-orders", "myorders"), @("06 POST /api/checkout", "checkout"), @("04 POST /api/cart", "cart"))) {
    $e = $rows | Where-Object { $_.label -eq $pair[0] } | ForEach-Object { [int]$_.elapsed } | Sort-Object
    if ($e.Count) {
      $res["$($pair[1])_avg"] = [math]::Round(($e | Measure-Object -Average).Average, 1)
      $res["$($pair[1])_p95"] = $e[[math]::Max(0, [int][math]::Ceiling(0.95 * $e.Count) - 1)]
    }
  }
  return [PSCustomObject]$res
}

$results = @()
foreach ($pool in @(4, 16)) {
  Write-Host ""
  Write-Host "=== UV_THREADPOOL_SIZE = $pool ==="
  Start-Backend -PoolSize $pool
  Push-Location $Repo; node scripts\seed_users.js | Out-Null; Pop-Location
  $cnt = node (Join-Path $Repo "scripts\db_tool.js") seed-orders $SeedOrders | Select-Object -Last 1
  Write-Host "  da nap $cnt don hang, dang do ..."
  $results += (Measure-Run -Name "5_threadpool_$pool")
}

Write-Host ""
Write-Host "=== KET QUA ==="
$results | Format-Table -AutoSize
