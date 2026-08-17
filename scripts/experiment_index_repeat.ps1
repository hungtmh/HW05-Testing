<#
  experiment_index_repeat.ps1 - Lap lai phep do baseline va INDEX de kiem tra tinh tai lap.

  VÌ SAO CẦN: lần đo đầu tiên cho thấy bật WAL KHÔNG cải thiện gì, thậm chí hơi xấu đi.
  Kết luận này đi ngược với khuyến nghị phổ biến, nên không được phép dựa trên một
  phép đo duy nhất. Script này chạy lại xen kẽ baseline / WAL hai lượt để:
    (a) ước lượng mức nhiễu giữa các lần chạy;
    (b) xác nhận kết luận về WAL có tái lập được không.

  Chạy xen kẽ (baseline, wal, baseline, wal) thay vì (baseline, baseline, wal, wal)
  để nếu máy có trôi nhiệt độ / tải nền thì nó ảnh hưởng đều lên cả hai nhóm.

  Cũng kiểm tra sự tồn tại của file sidecar database.sqlite-wal trong lúc chạy —
  đó là bằng chứng trực tiếp rằng WAL đang thực sự hoạt động, chứ không chỉ là
  giá trị PRAGMA đã đặt.

  Dùng:  powershell -ExecutionPolicy Bypass -File scripts\experiment_wal_repeat.ps1
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
# Moi lan chay dung mot hau to thoi gian rieng: neu file .jtl cu bi khoa va khong xoa duoc
# thi JMeter se GHI TIEP vao do, tron lan du lieu cua hai lan chay khac nhau.
$stamp  = Get-Date -Format "HHmmss"
New-Item -ItemType Directory -Force $outDir | Out-Null

function Db([string]$Cmd, [string]$Arg = "") {
  if ($Arg -ne "") { return (node (Join-Path $Repo "scripts\db_tool.js") $Cmd $Arg | Select-Object -Last 1) }
  return (node (Join-Path $Repo "scripts\db_tool.js") $Cmd | Select-Object -Last 1)
}

function Measure-Run([string]$Name) {
  $jtl = Join-Path $outDir "exp_${Name}_$stamp.jtl"
  Remove-Item $jtl -ErrorAction SilentlyContinue
  if (Test-Path $jtl) { throw "Khong xoa duoc file cu $jtl - dung lai de tranh tron du lieu" }
  $env:JVM_ARGS = "-Xms1g -Xmx2g"
  & $JMeterBat -n -t (Join-Path $Repo "testplans\23127195_Load_20260816.jmx") `
      -l $jtl -j (Join-Path $outDir "exp_${Name}_$stamp.jmeter.log") `
      "-Jthreads=$Vu" "-Jrampup=5" "-Jduration=$DurationS" "-Jthinkmin=200" "-Jthinkrange=300" | Out-Null
  $rows = Import-Csv $jtl | Where-Object { $_.label -notlike "TC-*" }
  $span = ([long](($rows | Measure-Object timeStamp -Maximum).Maximum) - [long](($rows | Measure-Object timeStamp -Minimum).Minimum)) / 1000.0
  $res = [ordered]@{ Name = $Name; Total = $rows.Count; Rps = [math]::Round($rows.Count / [math]::Max($span, 1), 1) }
  foreach ($pair in @(@("07 GET /api/orders/my-orders", "myorders"), @("06 POST /api/checkout", "checkout"))) {
    $e = $rows | Where-Object { $_.label -eq $pair[0] } | ForEach-Object { [int]$_.elapsed } | Sort-Object
    if ($e.Count) {
      $res["$($pair[1])_avg"] = [math]::Round(($e | Measure-Object -Average).Average, 1)
      $res["$($pair[1])_p95"] = $e[[math]::Max(0, [int][math]::Ceiling(0.95 * $e.Count) - 1)]
    }
  }
  return [PSCustomObject]$res
}

$results = @()
foreach ($lap in 1..3) {
  foreach ($mode in @("baseline", "index")) {
    $name = "7_${mode}_lap$lap"
    Write-Host ""
    Write-Host "=== $name ==="
    # Doi journal_mode can khoa DOC QUYEN tren file DB, ma server dang giu ket noi
    # mo thi khong lay duoc -> phai dung server TRUOC, doi mode, roi moi khoi dong lai.
    Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue |
      ForEach-Object { try { Stop-Process -Id $_.OwningProcess -Force } catch {} }
    Start-Sleep -Milliseconds 1200

    # journal_mode ben vung trong file DB (song sot qua DROP TABLE va qua restart),
    # nen PHAI ep ve DELETE truoc moi lan do baseline. Neu khong, mot cau hinh WAL
    # chay truoc do se am tham lam nhiem TAT CA cac phep do sau.
    # Ca hai cau hinh deu chay o journal_mode DELETE de chi con MOT bien so la index.
    Db "set-delete" | Out-Null
    $modeNow = Db "journal-mode"
    Write-Host "  journal_mode truoc khi khoi dong server = $modeNow"
    if ($modeNow -ne "delete") { throw "Khong ep duoc ve DELETE" }

    & powershell -ExecutionPolicy Bypass -File (Join-Path $Repo "scripts\reset_sut.ps1") | Out-Null
    Db "seed-orders" "$SeedOrders" | Out-Null
    # Tao index SAU khi nap du lieu, giong tinh huong that khi them index vao production
    if ($mode -eq "index") { Db "create-index" | Out-Null; Write-Host "  da tao idx_orders_user_id" }

    $results += (Measure-Run -Name $name)
  }
}

Write-Host ""
Write-Host "=== KET QUA LAP LAI ==="
$results | Format-Table -AutoSize
Write-Host ""
foreach ($mode in @("baseline", "index")) {
  $r = $results | Where-Object { $_.Name -like "*_${mode}_*" }
  $rps = $r | ForEach-Object { $_.Rps }
  $p95 = $r | ForEach-Object { $_.myorders_p95 }
  Write-Host ("{0,-9} rps: {1}  |  my-orders p95: {2}" -f $mode, ($rps -join ' / '), ($p95 -join ' / '))
}
