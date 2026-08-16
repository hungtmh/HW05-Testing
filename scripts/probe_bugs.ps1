<#
  probe_bugs.ps1 — Kiểm chứng bằng thực nghiệm các lỗi phát hiện khi đọc mã nguồn SUT.

  Mọi lỗi báo cáo trong docs/08_bug_report.md đều phải chạy qua script này trước, để
  bảo đảm đó là lỗi THẬT quan sát được qua API, chứ không phải suy đoán từ việc đọc code.

  Script chỉ ĐỌC và tạo dữ liệu test riêng của nó; không xoá dữ liệu nào của SUT.
  Chạy sau khi đã có backend chạy và đã seed tài khoản (scripts/reset_sut.ps1).

  Dùng:  powershell -ExecutionPolicy Bypass -File scripts\probe_bugs.ps1
#>
param([string]$BaseUrl = "http://localhost:3000")

$ErrorActionPreference = "Continue"
function Say([string]$s) { Write-Host $s }
function Hr()  { Write-Host ("-" * 78) }

function Invoke-Api {
  param([string]$Method, [string]$Path, $Body = $null, [string]$Token = $null)
  $headers = @{}
  if ($Token) { $headers["Authorization"] = "Bearer $Token" }
  $args = @{ Uri = "$BaseUrl$Path"; Method = $Method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 10 }
  if ($Body -ne $null) { $args.ContentType = "application/json"; $args.Body = ($Body | ConvertTo-Json -Compress) }
  try {
    $r = Invoke-WebRequest @args
    return @{ Code = $r.StatusCode; Body = $r.Content }
  } catch {
    $code = -1; $body = $_.Exception.Message
    if ($_.Exception.Response) {
      $code = [int]$_.Exception.Response.StatusCode
      try { $body = (New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch {}
    }
    return @{ Code = $code; Body = $body }
  }
}

Say "=== PROBE LOI SUT - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $BaseUrl ==="

# Tai khoan dung cho probe
$u = Invoke-Api -Method POST -Path "/api/login" -Body @{ email = "perf01@eshop.test"; password = "Perf1234!" }
$userTok = ($u.Body | ConvertFrom-Json).token
$userId  = ($u.Body | ConvertFrom-Json).user.id
Say "Token nguoi dung thuong: $(if ($userTok) { 'OK, user id=' + $userId } else { 'THAT BAI' })"

Hr
Say "BUG-01 | Nguong khoa tai khoan la 2 lan sai, khong phai 3 (server.js:54 cong +2)"
$probeEmail = "bugprobe_$(Get-Random)@eshop.test"
Invoke-Api -Method POST -Path "/api/register" -Body @{ name = "BugProbe"; email = $probeEmail; password = "Probe1234!" } | Out-Null
foreach ($i in 1..3) {
  $r = Invoke-Api -Method POST -Path "/api/login" -Body @{ email = $probeEmail; password = "SAI_MAT_KHAU" }
  Say ("  lan sai thu {0}: HTTP {1}" -f $i, $r.Code)
}
$r = Invoke-Api -Method POST -Path "/api/login" -Body @{ email = $probeEmail; password = "Probe1234!" }
Say ("  dang nhap bang MAT KHAU DUNG: HTTP {0}  -> {1}" -f $r.Code, $(if ($r.Code -eq 403) { "DA BI KHOA (chi sau 2 lan sai)" } else { "khong bi khoa" }))

Hr
Say "BUG-02 | Cong thuc giam gia theo phan tram bi sai dau (server.js:399)"
Say "         discount = floor(total * (1 - discount_value)) thay vi total * discount_value/100"
$r = Invoke-Api -Method POST -Path "/api/apply-coupon" -Body @{ code = "SAVE10"; total_amount = 1000000 }
Say "  POST /api/apply-coupon {code:SAVE10, total_amount:1000000}"
Say "  HTTP $($r.Code) | $($r.Body)"
try {
  $j = $r.Body | ConvertFrom-Json
  Say ("  -> discount_amount = {0} (ky vong 100000), final_amount = {1} (ky vong 900000)" -f $j.discount_amount, $j.final_amount)
  if ($j.final_amount -gt 1000000) { Say "  -> KHACH HANG BI TINH TIEN NHIEU HON sau khi ap ma GIAM GIA" }
} catch {}

Hr
Say "BUG-03 | GET /api/orders/:id KHONG co middleware xac thuc (server.js:344)"
$mine = Invoke-Api -Method POST -Path "/api/checkout" -Body @{ total_amount = 999999; shipping_address = "probe" } -Token $userTok
$oid = ($mine.Body | ConvertFrom-Json).orderId
Say "  Da tao don hang id=$oid bang tai khoan perf01"
$r = Invoke-Api -Method GET -Path "/api/orders/$oid"   # KHONG gui token
Say "  GET /api/orders/$oid KHONG kem token: HTTP $($r.Code)"
Say "  Body: $($r.Body)"
if ($r.Code -eq 200) { Say "  -> LO DU LIEU: doc duoc don hang cua nguoi khac ma khong can dang nhap (IDOR)" }

Hr
Say "BUG-04 | PUT /api/users/me cho phep tu nang quyen len admin (server.js:119-129)"
$before = (Invoke-Api -Method GET -Path "/api/users/me" -Token $userTok).Body | ConvertFrom-Json
Say "  role truoc: $($before.role)"
Invoke-Api -Method PUT -Path "/api/users/me" -Body @{ name = $before.name; shipping_address = "x"; phone = "0900000000"; role = "admin" } -Token $userTok | Out-Null
$after = (Invoke-Api -Method GET -Path "/api/users/me" -Token $userTok).Body | ConvertFrom-Json
Say "  role sau : $($after.role)"
if ($after.role -eq "admin") { Say "  -> LEO THANG DAC QUYEN: nguoi dung thuong tu dat minh thanh admin" }
# Tra lai trang thai cu de khong anh huong cac lan chay sau
Invoke-Api -Method PUT -Path "/api/users/me" -Body @{ name = $before.name; shipping_address = $before.shipping_address; phone = $before.phone; role = "user" } -Token $userTok | Out-Null
Say "  (da tra role ve 'user')"

Hr
Say "BUG-05 | GET /api/products/:id tra 200 kem body rong cho id khong ton tai (server.js:161)"
$r = Invoke-Api -Method GET -Path "/api/products/999999"
Say "  GET /api/products/999999 -> HTTP $($r.Code) | body: '$($r.Body)'  (ky vong 404)"

Hr
Say "BUG-06 | Kieu du lieu price khong nhat quan theo tinh chan le cua id (server.js:162)"
foreach ($id in @(1, 2, 3, 4)) {
  $r = Invoke-Api -Method GET -Path "/api/products/$id"
  $raw = $r.Body
  $m = [regex]::Match($raw, '"price"\s*:\s*("?)([0-9]+)\1')
  $isString = $m.Groups[1].Value -eq '"'
  Say ("  id={0} (id {1}) -> price tra ve kieu {2}" -f $id, $(if ($id % 2 -eq 0) { "chan" } else { "le " }), $(if ($isString) { "CHUOI" } else { "SO" }))
}

Hr
Say "BUG-07 | May trang thai don hang cho phep chuyen canceled -> delivered (server.js:550)"
$adm = Invoke-Api -Method POST -Path "/api/login" -Body @{ email = "admin@eshop.com"; password = "Admin123!" }
$admTok = ($adm.Body | ConvertFrom-Json).token
$o = Invoke-Api -Method POST -Path "/api/checkout" -Body @{ total_amount = 500000; shipping_address = "probe-state" } -Token $userTok
$oid2 = ($o.Body | ConvertFrom-Json).orderId
Invoke-Api -Method PUT -Path "/api/orders/$oid2/cancel" -Token $userTok | Out-Null
$st = (Invoke-Api -Method GET -Path "/api/orders/$oid2").Body | ConvertFrom-Json
Say "  Don $oid2 sau khi huy: status = $($st.status)"
$r = Invoke-Api -Method PUT -Path "/api/admin/orders/$oid2/status" -Body @{ status = "delivered" } -Token $admTok
Say "  Chuyen canceled -> delivered: HTTP $($r.Code) | $($r.Body)"
$st2 = (Invoke-Api -Method GET -Path "/api/orders/$oid2").Body | ConvertFrom-Json
Say "  status hien tai: $($st2.status)"
if ($st2.status -eq "delivered") { Say "  -> SAI LOGIC: don da HUY van chuyen sang DA GIAO duoc" }

Hr
Say "BUG-08 | SQL injection o GET /api/products?search (server.js:144 noi chuoi truc tiep)"
$normal = (Invoke-Api -Method GET -Path "/api/products?search=iPhone").Body | ConvertFrom-Json
Say "  ?search=iPhone            -> $($normal.Count) san pham"
$inj = (Invoke-Api -Method GET -Path "/api/products?search=%25%27%20OR%20%271%27%3D%271").Body
try {
  $injJson = $inj | ConvertFrom-Json
  Say "  ?search=%' OR '1'='1     -> $($injJson.Count) san pham"
  if ($injJson.Count -gt $normal.Count) { Say "  -> INJECTION THANH CONG: menh de WHERE bi vo hieu hoa, tra ve toan bo bang" }
} catch {
  Say "  Phan hoi khong phai JSON (co the la trang loi SQL): $($inj.Substring(0, [Math]::Min(160, $inj.Length)))"
}

Hr
Say "=== KET THUC PROBE ==="
