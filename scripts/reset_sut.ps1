<#
  reset_sut.ps1 — Đưa SUT về trạng thái sạch, xác định trước mỗi lần chạy kịch bản.

  VÌ SAO BẮT BUỘC:
  backend/database.js gọi initDatabase() ở mức module → mỗi lần khởi động lại
  server sẽ DROP TABLE toàn bộ rồi seed lại. Kết hợp với việc bảng `orders`
  KHÔNG có index trên user_id, nếu không reset thì mỗi kịch bản chạy sau sẽ
  làm việc trên bảng orders lớn hơn kịch bản trước → số liệu giữa các kịch bản
  không so sánh được với nhau (đã đo được: 21.404 đơn tồn đọng làm throughput
  tụt từ ~1830 xuống ~300 sample/s).

  Việc script làm:
    1. Dừng tiến trình node đang giữ cổng 3000.
    2. Khởi động lại backend (DB tự động được DROP + seed lại).
    3. Chờ tới khi /api/products trả 200.
    4. Nạp lại 60 tài khoản tải từ data/users.csv.
    5. Ghi PID của backend ra results/monitor/backend.pid để script giám sát
       tài nguyên bám đúng tiến trình.

  Dùng:  powershell -ExecutionPolicy Bypass -File scripts\reset_sut.ps1
#>
param(
  [string]$SutBackend = "D:\Kiem_thu\eshop-sut\backend",
  [string]$Repo       = "D:\Kiem_thu\HW5",
  [int]   $Port       = 3000
)

$ErrorActionPreference = "Stop"

Write-Host "[reset-sut] 1/5 Dung backend dang chay tren cong $Port ..."
$conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
foreach ($c in $conns) {
  try { Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop; Write-Host "           da dung PID $($c.OwningProcess)" } catch {}
}
Start-Sleep -Milliseconds 1000

Write-Host "[reset-sut] 2/5 Khoi dong lai backend (DB se duoc DROP + seed lai) ..."
New-Item -ItemType Directory -Force (Join-Path $Repo "results\monitor") | Out-Null
# Dung 'cmd /c start' de tach han tien trinh backend khoi phien PowerShell hien tai.
# Neu dung Start-Process -PassThru truc tiep, PowerShell cha se cho ca cay tien trinh
# con ket thuc va script nay se treo vinh vien (backend chay lien tuc, khong bao gio thoat).
Start-Process -FilePath "cmd.exe" `
  -ArgumentList "/c start `"eshop-backend`" /min node server.js" `
  -WorkingDirectory $SutBackend -WindowStyle Hidden

Write-Host "[reset-sut] 3/5 Cho backend san sang ..."
$ready = $false
foreach ($i in 1..40) {
  Start-Sleep -Milliseconds 500
  try {
    $r = Invoke-WebRequest -Uri "http://localhost:$Port/api/products" -UseBasicParsing -TimeoutSec 3
    if ($r.StatusCode -eq 200) { $ready = $true; break }
  } catch {}
}
if (-not $ready) { throw "Backend khong san sang sau 20 giay." }
$backendPid = (Get-NetTCPConnection -LocalPort $Port -State Listen | Select-Object -First 1).OwningProcess
Write-Host "           backend san sang, PID = $backendPid"

Write-Host "[reset-sut] 4/5 Nap lai tai khoan tai ..."
Push-Location $Repo
try { node scripts\seed_users.js } finally { Pop-Location }

Write-Host "[reset-sut] 5/5 Ghi PID ra results\monitor\backend.pid"
Set-Content -Path (Join-Path $Repo "results\monitor\backend.pid") -Value $backendPid -Encoding ascii

# Kiem tra lai trang thai DB de chac chan da that su sach
Push-Location $SutBackend
$counts = node -e "const s=require('sqlite3');const db=new s.Database('database.sqlite');db.get('SELECT (SELECT COUNT(*) FROM orders) o,(SELECT COUNT(*) FROM users) u',[],(e,r)=>{console.log('orders='+r.o+' users='+r.u);db.close();});"
Pop-Location
Write-Host "[reset-sut] Trang thai DB sau reset: $counts  (ky vong orders=0 users=62)"
Write-Host "[reset-sut] HOAN TAT."
