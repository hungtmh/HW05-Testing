<#
  gen_variants.ps1 — Sinh 3 test plan Stress / Spike / Soak từ plan Load.

  VÌ SAO LÀM THẾ NÀY:
  Đề bài yêu cầu cả ba kịch bản phải chạy CÙNG MỘT workflow end-to-end. Nếu chép
  tay bốn file .jmx thì chỉ cần sửa một assertion ở một file là bốn kịch bản không
  còn so sánh được với nhau nữa. Script này lấy đúng một nguồn sự thật
  (23127195_Load_20260816.jmx), giữ nguyên toàn bộ cây sampler/assertion/extractor,
  và chỉ thay đổi ba thứ: Thread Group, think-time, và loại listener.

  Chạy lại script này mỗi khi sửa workflow trong plan Load:
      powershell -ExecutionPolicy Bypass -File scripts\gen_variants.ps1
#>
param([string]$Repo = "D:\Kiem_thu\HW5")

$ErrorActionPreference = "Stop"
$plans = Join-Path $Repo "testplans"
$src   = Join-Path $plans "23127195_Load_20260816.jmx"
$text  = [System.IO.File]::ReadAllText($src)
# Chuan hoa ve LF de cac moc tach chuoi khong phu thuoc kieu xuong dong cua file nguon.
$text  = $text.Replace("`r`n", "`n")
$NL    = "`n"

# --- Tách file Load thành 3 phần: head | khối Thread Group | tail ---
$tgMark   = '      <ThreadGroup guiclass='
$tailMark = "    </hashTree>$NL  </hashTree>$NL</jmeterTestPlan>"
$iTG   = $text.IndexOf($tgMark)
$iTail = $text.LastIndexOf($tailMark)
if ($iTG -lt 0 -or $iTail -lt 0) { throw "Khong tach duoc cau truc file Load. Kiem tra lai dinh dang JMX." }

$head    = $text.Substring(0, $iTG)
$tgBlock = $text.Substring($iTG, $iTail - $iTG)
$tail    = $text.Substring($iTail)

# --- Tách listener ra khỏi khối Thread Group để mỗi biến thể tự gắn listener riêng ---
$iRC = $tgBlock.IndexOf('        <ResultCollector')
$iRCEnd = $tgBlock.IndexOf('<hashTree/>', $iRC) + '<hashTree/>'.Length
$tgCore = $tgBlock.Substring(0, $iRC) + $tgBlock.Substring($iRCEnd).TrimStart("`r", "`n")

function New-Listener {
  param([string]$GuiClass, [string]$Name, [string]$Indent = '        ')
  $saveCfg = @'
__IND__  <boolProp name="ResultCollector.error_logging">__ERRLOG__</boolProp>
__IND__  <objProp>
__IND__    <name>saveConfig</name>
__IND__    <value class="SampleSaveConfiguration">
__IND__      <time>true</time><latency>true</latency><timestamp>true</timestamp><success>true</success>
__IND__      <label>true</label><code>true</code><message>true</message><threadName>true</threadName>
__IND__      <dataType>true</dataType><encoding>false</encoding><assertions>true</assertions>
__IND__      <subresults>true</subresults><responseData>false</responseData><samplerData>false</samplerData>
__IND__      <xml>false</xml><fieldNames>true</fieldNames><responseHeaders>false</responseHeaders>
__IND__      <requestHeaders>false</requestHeaders><responseDataOnError>false</responseDataOnError>
__IND__      <saveAssertionResultsFailureMessage>true</saveAssertionResultsFailureMessage>
__IND__      <assertionsResultsToSave>0</assertionsResultsToSave><bytes>true</bytes><sentBytes>true</sentBytes>
__IND__      <url>true</url><threadCounts>true</threadCounts><idleTime>true</idleTime><connectTime>true</connectTime>
__IND__    </value>
__IND__  </objProp>
__IND__  <stringProp name="filename"></stringProp>
'@
  # View Results Tree duoi tai cao se an toan bo nho neu giu moi mau -> chi giu mau LOI.
  $errLog = if ($GuiClass -eq 'ViewResultsFullVisualizer') { 'true' } else { 'false' }
  $body = $saveCfg.Replace('__IND__', $Indent).Replace('__ERRLOG__', $errLog)
  return @"
$Indent<ResultCollector guiclass="$GuiClass" testclass="ResultCollector" testname="$Name" enabled="true">
$body
$Indent</ResultCollector>
$Indent<hashTree/>
"@
}

# =====================================================================
# 1) STRESS — tang tai tuyen tinh toi 500 VU de tim diem gay
# =====================================================================
$stress = $head + $tgCore + $tail
$stress = $stress.Replace('23127195_Load_20260816', '23127195_Stress_20260816')
$stress = $stress.Replace('TG - LOAD - ', 'TG - STRESS - ')
$stress = $stress.Replace('${__P(threads,60)}',  '${__P(threads,500)}')
$stress = $stress.Replace('${__P(rampup,60)}',   '${__P(rampup,300)}')
$stress = $stress.Replace('${__P(duration,300)}','${__P(duration,360)}')
$stressComment = @'
HW05 - STRESS TEST - MSSV 23127195 - SUT: EShop backend API (http://localhost:3000)
Cung workflow E2E voi ban Load, chi khac hinh dang tai.
Tham so mac dinh: 500 VU, ramp-up 300s (tang TUYEN TINH ~1.67 VU/giay), hold 60s (tong 360s), think-time 1-3s.
Can cu: calibration do duoc tran ~65 vong lap/s tren DB sach. 500 VU voi think-time 1-3s
tao tai chao ~80 vong lap/s, tuc VUOT tran ~23% -> chac chan cham nguong gay trong lan chay.
Ramp-up dai 300s co chu dich: no bien lan chay thanh mot phep quet lien tuc theo do dong thoi,
nho cot allThreads trong .jtl co the dung lai duong cong do tre theo so VU va tim diem goi (knee).
Listener: AGGREGATE REPORT (loai report view rieng cua ban Stress).
'@
$stress = [regex]::Replace($stress, '(?s)<stringProp name="TestPlan\.comments">.*?</stringProp>',
          ('<stringProp name="TestPlan.comments">' + $stressComment.Trim() + '</stringProp>'), 1)

$stress = $stress.Replace($tail.TrimEnd(), (New-Listener -GuiClass 'StatVisualizer' -Name 'REPORT VIEW 2/4 - Aggregate Report') + $NL + $tail.TrimEnd())
[System.IO.File]::WriteAllText((Join-Path $plans "23127195_Stress_20260816.jmx"), $stress)
Write-Host "[gen] da tao 23127195_Stress_20260816.jmx"

# =====================================================================
# 2) SOAK — tai on dinh 15 phut de tim nguong chiu dung
# =====================================================================
$soak = $head + $tgCore + $tail
$soak = $soak.Replace('23127195_Load_20260816', '23127195_Soak_20260816')
$soak = $soak.Replace('TG - LOAD - ', 'TG - SOAK - ')
$soak = $soak.Replace('${__P(threads,60)}',  '${__P(threads,150)}')
$soak = $soak.Replace('${__P(rampup,60)}',   '${__P(rampup,30)}')
$soak = $soak.Replace('${__P(duration,300)}','${__P(duration,900)}')
$soakComment = @'
HW05 - ENDURANCE / SOAK TEST - MSSV 23127195 - SUT: EShop backend API (http://localhost:3000)
Cung workflow E2E voi ban Load.
Tham so mac dinh: 150 VU, ramp-up 30s, giu tai 870s (tong 900s = 15 phut), think-time 1-3s.
Can cu chon 150 VU: ~24 vong lap/s = ~37% cong suat tren DB sach. Muc nay du thap de he thong
BAT DAU o trang thai on dinh, nhung du cao de hai co che tich luy lo ra trong 15 phut:
  (a) userCarts trong server.js khong bao gio duoc giai phong sau checkout -> ro ri bo nho;
  (b) bang orders phinh len ma khong co index tren user_id -> /api/orders/my-orders cham dan.
Muc tieu: tim thoi diem p95 vuot nguong va tran bo nho cua tien trinh backend.
Listener: AGGREGATE GRAPH (loai report view thu 4, khong trung 3 loai da dung).
'@
$soak = [regex]::Replace($soak, '(?s)<stringProp name="TestPlan\.comments">.*?</stringProp>',
        ('<stringProp name="TestPlan.comments">' + $soakComment.Trim() + '</stringProp>'), 1)
$soak = $soak.Replace($tail.TrimEnd(), (New-Listener -GuiClass 'StatGraphVisualizer' -Name 'REPORT VIEW 4/4 - Aggregate Graph') + $NL + $tail.TrimEnd())
[System.IO.File]::WriteAllText((Join-Path $plans "23127195_Soak_20260816.jmx"), $soak)
Write-Host "[gen] da tao 23127195_Soak_20260816.jmx"

# =====================================================================
# 3) SPIKE — nen tai nen 40 VU + cu soc 300 VU trong 60s
# =====================================================================
# Nhom nen: chay suot 240s de quan sat CA luc bi soc LAN luc hoi phuc.
$base = $tgCore
$base = $base.Replace('TG - LOAD - ${__P(threads,60)} VU', 'TG - SPIKE A - tai nen ${__P(basethreads,40)} VU')
$base = $base.Replace('${__P(threads,60)}',   '${__P(basethreads,40)}')
$base = $base.Replace('${__P(rampup,60)}',    '${__P(baserampup,20)}')
$base = $base.Replace('${__P(duration,300)}', '${__P(basedur,240)}')

# Nhom soc: khoi dong tre 90s, dung gan nhu tuc thoi (ramp 5s), giu 60s, think-time rat ngan.
$spikeTg = $tgCore
$spikeTg = $spikeTg.Replace('TG - LOAD - ${__P(threads,60)} VU', 'TG - SPIKE B - cu soc ${__P(spikethreads,300)} VU')
$spikeTg = $spikeTg.Replace('${__P(threads,60)}',   '${__P(spikethreads,300)}')
$spikeTg = $spikeTg.Replace('${__P(rampup,60)}',    '${__P(spikerampup,5)}')
$spikeTg = $spikeTg.Replace('${__P(duration,300)}', '${__P(spikedur,60)}')
$spikeTg = $spikeTg.Replace('<stringProp name="ThreadGroup.delay">0</stringProp>',
                            '<stringProp name="ThreadGroup.delay">${__P(spikedelay,90)}</stringProp>')
$spikeTg = $spikeTg.Replace('${__P(thinkmin,1000)}',  '${__P(spikethinkmin,300)}')
$spikeTg = $spikeTg.Replace('${__P(thinkrange,2000)}','${__P(spikethinkrange,500)}')

$spike = $head + $base + $spikeTg + (New-Listener -GuiClass 'ViewResultsFullVisualizer' -Name 'REPORT VIEW 3/4 - View Results Tree (chi ghi mau LOI)' -Indent '      ') + $NL + $tail
$spike = $spike.Replace('23127195_Load_20260816', '23127195_Spike_20260816')
$spikeComment = @'
HW05 - SPIKE TEST - MSSV 23127195 - SUT: EShop backend API (http://localhost:3000)
Cung workflow E2E voi ban Load, chay bang HAI Thread Group chong nhau:
  - TG - SPIKE A (tai nen): 40 VU, ramp 20s, chay suot 240s, think-time 1-3s.
  - TG - SPIKE B (cu soc):  300 VU, KHOI DONG TRE 90s, ramp chi 5s, giu 60s, think-time 0.3-0.8s.
Nho do trong mot lan chay quan sat duoc du ba pha: on dinh (0-90s) -> soc (90-150s) -> hoi phuc (150-240s).
Tai nen van chay tiep sau khi cu soc ket thuc chinh la de do THOI GIAN HOI PHUC, thu ma
mot Thread Group don le khong the do duoc.
Can cu: 300 VU voi think-time 0.3-0.8s tao ~176 vong lap/s, gap ~2.7 lan tran do duoc (~65/s).
Listener: VIEW RESULTS TREE, cau hinh "Log/Display Only: Errors" (error_logging=true).
LUU Y: neu de View Results Tree giu MOI mau o muc tai nay, JMeter se an het heap va treo GUI;
day la loi cau hinh ma ban ke hoach do AI sinh ra lan dau mac phai (xem docs/03).
'@
$spike = [regex]::Replace($spike, '(?s)<stringProp name="TestPlan\.comments">.*?</stringProp>',
         ('<stringProp name="TestPlan.comments">' + $spikeComment.Trim() + '</stringProp>'), 1)
[System.IO.File]::WriteAllText((Join-Path $plans "23127195_Spike_20260816.jmx"), $spike)
Write-Host "[gen] da tao 23127195_Spike_20260816.jmx"

Write-Host "[gen] HOAN TAT. Kiem tra bang: jmeter -n -t <file> voi -Jduration ngan truoc khi chay that."
