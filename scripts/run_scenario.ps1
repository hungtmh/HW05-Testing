<#
  run_scenario.ps1 — Chạy một kịch bản performance từ đầu tới cuối và thu đủ bằng chứng.

  Mỗi lần chạy sẽ tự động:
    1. Đưa SUT về trạng thái sạch (restart backend -> DB được DROP + seed lại, nạp lại 60 tài khoản).
       Bắt buộc, vì bảng orders không có index: nếu không reset, kịch bản chạy sau luôn
       làm việc trên bảng lớn hơn kịch bản trước và số liệu không so sánh được.
    2. Gỡ khoá mọi tài khoản còn bị lockout từ lần chạy trước.
    3. Bật giám sát tài nguyên (CPU / RAM của tiến trình backend VÀ của chính JMeter)
       chạy song song, lấy mẫu mỗi 2 giây.
    4. Chạy JMeter ở chế độ CLI, xuất .jtl thô + thư mục HTML report.
    5. Ghi lại số đơn hàng trong DB trước/sau để biết khối lượng dữ liệu phát sinh.
    6. Xuất một file tóm tắt lần chạy.

  Dùng:
    powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Load
    powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Stress
    powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Spike
    powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Soak
#>
param(
  [Parameter(Mandatory = $true)][ValidateSet("Load", "Stress", "Spike", "Soak")][string]$Scenario,
  [string]$Repo       = "D:\Kiem_thu\HW5",
  [string]$JMeterBat  = "D:\Kiem_thu\tools\apache-jmeter-5.6.3\bin\jmeter.bat",
  [string]$SutBackend = "D:\Kiem_thu\eshop-sut\backend",
  [string]$StudentId  = "23127195",
  [string]$RunDate    = "20260816",
  [int]   $SampleSec  = 2,
  [switch]$SkipReset
)

$ErrorActionPreference = "Stop"
$name    = "${StudentId}_${Scenario}_${RunDate}"
$jmx     = Join-Path $Repo "testplans\$name.jmx"
$jtl     = Join-Path $Repo "results\jtl\$name.jtl"
$jmlog   = Join-Path $Repo "results\jtl\$name.jmeter.log"
$html    = Join-Path $Repo "results\html\$name"
$moncsv  = Join-Path $Repo "results\monitor\${name}_resources.csv"
$summary = Join-Path $Repo "results\monitor\${name}_run_summary.txt"

if (-not (Test-Path $jmx)) { throw "Khong tim thay test plan: $jmx" }

Write-Host "==================================================================="
Write-Host " KICH BAN: $Scenario   |   Test plan: $name.jmx"
Write-Host "==================================================================="

# ---------- 1. Dua SUT ve trang thai sach ----------
if (-not $SkipReset) {
  & powershell -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\reset_sut.ps1")
  if ($LASTEXITCODE -ne 0) { throw "reset_sut.ps1 that bai" }
} else {
  Write-Host "[run] Bo qua buoc reset theo yeu cau (-SkipReset)."
}

# ---------- 2. Go khoa tai khoan con sot ----------
Push-Location $Repo
try { node scripts\reset_lockout.js } finally { Pop-Location }

$backendPid = [int](Get-Content (Join-Path $Repo "results\monitor\backend.pid"))
Write-Host "[run] Backend PID = $backendPid"

function Get-OrderCount {
  Push-Location $SutBackend
  try {
    $out = node -e "const s=require('sqlite3');const db=new s.Database('database.sqlite');db.get('SELECT COUNT(*) c FROM orders',[],(e,r)=>{console.log(r.c);db.close();});"
    return [int]($out | Select-Object -Last 1)
  } finally { Pop-Location }
}
$ordersBefore = Get-OrderCount
Write-Host "[run] So don hang truoc khi chay: $ordersBefore"

# ---------- 3. Bat giam sat tai nguyen song song ----------
# Dung Start-Job de tien trinh lay mau song hanh voi JMeter trong cung mot phien.
New-Item -ItemType Directory -Force (Split-Path $moncsv) | Out-Null
$monitor = Start-Job -ScriptBlock {
  param($BackendPid, $OutCsv, $IntervalSec)
  $cpuCount = [Environment]::ProcessorCount
  "timestamp,elapsed_s,backend_cpu_pct,backend_rss_mb,backend_private_mb,backend_threads,backend_handles,jmeter_cpu_pct,jmeter_rss_mb,system_avail_mb,tcp_established_3000" |
    Out-File -FilePath $OutCsv -Encoding utf8
  $t0 = Get-Date
  $prevB = $null; $prevJ = $null; $prevT = $t0
  while ($true) {
    Start-Sleep -Seconds $IntervalSec
    $now = Get-Date
    $dt  = ($now - $prevT).TotalSeconds
    if ($dt -le 0) { continue }
    $b = Get-Process -Id $BackendPid -ErrorAction SilentlyContinue
    if (-not $b) { break }
    $j = Get-Process -Name java -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 1

    $bCpu = if ($prevB -ne $null) { [math]::Round((($b.TotalProcessorTime.TotalSeconds - $prevB) / $dt / $cpuCount) * 100, 1) } else { 0 }
    $jCpu = if ($j -and $prevJ -ne $null) { [math]::Round((($j.TotalProcessorTime.TotalSeconds - $prevJ) / $dt / $cpuCount) * 100, 1) } else { 0 }
    $prevB = $b.TotalProcessorTime.TotalSeconds
    if ($j) { $prevJ = $j.TotalProcessorTime.TotalSeconds }
    $prevT = $now

    $availMb = try { [math]::Round((Get-Counter '\Memory\Available MBytes' -ErrorAction Stop).CounterSamples[0].CookedValue, 0) } catch { -1 }
    $estab   = try { (Get-NetTCPConnection -RemotePort 3000 -State Established -ErrorAction SilentlyContinue | Measure-Object).Count } catch { -1 }

    "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10}" -f `
      $now.ToString("yyyy-MM-dd HH:mm:ss"),
      [math]::Round(($now - $t0).TotalSeconds, 0),
      $bCpu,
      [math]::Round($b.WorkingSet64 / 1MB, 1),
      [math]::Round($b.PrivateMemorySize64 / 1MB, 1),
      $b.Threads.Count,
      $b.HandleCount,
      $jCpu,
      $(if ($j) { [math]::Round($j.WorkingSet64 / 1MB, 1) } else { 0 }),
      $availMb,
      $estab | Out-File -FilePath $OutCsv -Append -Encoding utf8
  }
} -ArgumentList $backendPid, $moncsv, $SampleSec

Write-Host "[run] Da bat giam sat tai nguyen (lay mau moi ${SampleSec}s) -> $moncsv"

# ---------- 4. Chay JMeter ----------
Remove-Item $jtl   -ErrorAction SilentlyContinue
Remove-Item $html  -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Split-Path $jtl) | Out-Null

$env:JVM_ARGS = "-Xms1g -Xmx3g"
$startedAt = Get-Date
Write-Host "[run] Bat dau JMeter luc $($startedAt.ToString('HH:mm:ss')) ..."
& $JMeterBat -n -t $jmx -l $jtl -j $jmlog -e -o $html | Tee-Object -Variable jmOut | Select-String "^summary" | ForEach-Object { Write-Host "      $_" }
$finishedAt = Get-Date

# ---------- 5. Dung giam sat, thu ket qua ----------
Stop-Job $monitor -ErrorAction SilentlyContinue | Out-Null
Remove-Job $monitor -Force -ErrorAction SilentlyContinue | Out-Null
Write-Host "[run] Da dung giam sat tai nguyen."

$ordersAfter = Get-OrderCount

# ---------- 6. Tom tat lan chay ----------
$rows = @(Import-Csv $moncsv)
$peakRss  = ($rows | Measure-Object backend_rss_mb -Maximum).Maximum
$startRss = if ($rows.Count -gt 0) { [double]$rows[0].backend_rss_mb } else { 0 }
$avgCpu   = if ($rows.Count -gt 0) { [math]::Round(($rows | Measure-Object backend_cpu_pct -Average).Average, 1) } else { 0 }
$peakCpu  = ($rows | Measure-Object backend_cpu_pct -Maximum).Maximum
$avgJmCpu = if ($rows.Count -gt 0) { [math]::Round(($rows | Measure-Object jmeter_cpu_pct -Average).Average, 1) } else { 0 }

$txt = @"
=== TOM TAT LAN CHAY: $name ===
Test plan      : $jmx
Bat dau        : $($startedAt.ToString('yyyy-MM-dd HH:mm:ss'))
Ket thuc       : $($finishedAt.ToString('yyyy-MM-dd HH:mm:ss'))
Thoi luong     : $([math]::Round(($finishedAt - $startedAt).TotalSeconds,0)) giay
May chay       : $env:COMPUTERNAME
Backend PID    : $backendPid

--- Du lieu DB ---
So don hang truoc : $ordersBefore
So don hang sau   : $ordersAfter
Don hang phat sinh: $($ordersAfter - $ordersBefore)

--- Tai nguyen tien trinh backend (node.exe) ---
RSS luc bat dau      : $startRss MB
RSS dinh             : $peakRss MB
Muc tang RSS         : $([math]::Round($peakRss - $startRss,1)) MB
CPU trung binh       : $avgCpu %  (tren tong $([Environment]::ProcessorCount) luong logic)
CPU dinh             : $peakCpu %

--- Tai nguyen tien trinh JMeter (java.exe) ---
CPU trung binh       : $avgJmCpu %
(Neu CPU cua JMeter cao xap xi CPU backend thi phai nghi ngo client la nut that co chai,
 khong phai SUT — xem docs/03_human_review_and_fixes.md)

--- Tep ket qua ---
Log tho    : $jtl
HTML report: $html
Giam sat   : $moncsv
Log JMeter : $jmlog
"@
$txt | Out-File -FilePath $summary -Encoding utf8
Write-Host $txt
Write-Host "[run] HOAN TAT kich ban $Scenario."
