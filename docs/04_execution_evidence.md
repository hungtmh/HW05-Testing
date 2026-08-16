# 04 — Bằng chứng thực thi

**MSSV:** 23127195 · **Ngày chạy:** 2026-08-16 · **Máy:** `DESKTOP-96ARBFL`

---

## 1. Môi trường kiểm thử

### 1.1 Cấu hình phần cứng

| Hạng mục | Thông số |
|---|---|
| **Hostname** | `DESKTOP-96ARBFL` *(trùng với hostname đã dùng ở các bài tập trước)* |
| Nhà sản xuất / Model | LENOVO 83E0 |
| CPU | 13th Gen Intel® Core™ i7-13700H |
| Số nhân / luồng | **14 nhân / 20 luồng logic** |
| Xung nhịp cơ bản | 2.400 MHz |
| RAM | **13,75 GB** |
| GPU | Intel® Iris® Xe Graphics |
| Ổ đĩa | WD PC SN740 SDDPMQD-512G-1101 (477 GB NVMe SSD) |
| Hệ điều hành | Microsoft Windows 11 Home Single Language, phiên bản 10.0.26200 (Build 26200) |

> Ảnh chụp `dxdiag` nằm ở `evidence/hardware/` cùng file kết xuất `dxdiag_report.txt`.

### 1.2 Phần mềm

| Thành phần | Phiên bản |
|---|---|
| Apache JMeter | **5.6.3** |
| Java (chạy JMeter) | OpenJDK 17.0.17 (Temurin 17.0.17+10) |
| Node.js (chạy SUT) | v22.20.0 |
| Python (script phân tích) | 3.12.10 |
| Heap của JMeter khi chạy | `-Xms1g -Xmx3g` |

### 1.3 System Under Test

| Hạng mục | Giá trị |
|---|---|
| Repo | https://github.com/ttbhanh/eshop-sut |
| Commit đã dùng | `85af3ba875c88283615e22cb108f13e2fccaf0e9` ("first upload", 2026-05-15) |
| Thành phần chạy | Chỉ `backend/` (`node server.js`), cổng 3000 |
| Cơ sở dữ liệu | SQLite, journal mode `delete` (**không bật WAL**), không có index ngoài PRIMARY KEY |

### 1.4 Điểm quan trọng về tính hợp lệ của phép đo

SUT và JMeter **chạy trên cùng một máy**. Đây là hạn chế đã biết, nhưng đã kiểm chứng là **không làm hỏng kết quả** vì:

- Backend là Node **đơn luồng** → trần của nó là **1 core**, tương đương **5% CPU toàn hệ thống** trên máy 20 luồng.
- CPU của tiến trình JMeter được ghi lại song song ở mọi lần chạy, và luôn ở mức thấp (trung bình 0,4%–1,4%), tức còn dư **rất nhiều** trong 20 luồng logic.
- Ở lần chạy nặng nhất (Stress, 500 VU), backend chạm **5,3%** CPU toàn hệ thống — tức **106% của một core**, đã bão hoà đúng giới hạn lý thuyết — trong khi JMeter chỉ dùng 0,8%. Máy còn thừa hơn 18 luồng rảnh.

Kết luận: **nút thắt nằm ở mô hình đơn luồng của SUT, không phải ở tài nguyên máy test hay ở công cụ sinh tải.**

---

## 2. Quy trình chạy mỗi kịch bản

Mỗi lần chạy đều đi qua đúng các bước sau, tự động hoá trong `scripts/run_scenario.ps1`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Load
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Stress
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Spike
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Soak
```

| Bước | Việc | Vì sao bắt buộc |
|---|---|---|
| 1 | Dừng backend, khởi động lại → `initDatabase()` tự `DROP TABLE` và seed lại | Đưa khối lượng dữ liệu về 0. Nếu không, kịch bản sau chạy trên bảng `orders` lớn hơn kịch bản trước (đã đo: chênh 2,17 lần) |
| 2 | Chờ `GET /api/products` trả 200 | Không đo lẫn thời gian khởi động |
| 3 | `node scripts/seed_users.js` — nạp 60 tài khoản + **verify đăng nhập 3 tài khoản** | Dữ liệu test sai sẽ làm hỏng dây chuyền từ request đầu tiên |
| 4 | `node scripts/reset_lockout.js` — gỡ khoá tài khoản còn sót | Xem §3 |
| 5 | Bật giám sát tài nguyên song song, lấy mẫu 2 giây/lần | Bằng chứng bắt buộc + để kiểm tra client có phải nút thắt không |
| 6 | Chạy JMeter CLI `-n`, xuất `.jtl` thô **và** HTML report `-e -o` | |
| 7 | Đếm số đơn trong DB trước/sau | Chứng minh trạng thái xuất phát giống nhau giữa các lần chạy |
| 8 | Xuất file tóm tắt lần chạy | |

---

## 3. Xử lý khoá tài khoản (account lockout) giữa các lần chạy

### 3.1 Hành vi thật của SUT

`server.js:54` cộng `login_attempts + 2` mỗi lần đăng nhập sai, ngưỡng khoá là `>= 3`, thời gian khoá **180.000 ms = 180 giây**. Nghĩa là tài khoản bị khoá **ngay ở lần sai thứ hai**, không phải lần thứ ba như đề bài mô tả. Bằng chứng probe đầy đủ: `docs/01_scope_and_endpoint_selection.md` §4.

### 3.2 Vì sao Stress/Spike có nguy cơ kích hoạt lockout

Ở tải cao, bước login có thể trả về mã khác 200 vì nhiều lý do (quá tải, timeout, kết nối bị đóng). Nếu bất kỳ lý do nào khiến server coi đó là "sai mật khẩu", bộ đếm `login_attempts` của tài khoản đó tăng lên và **chỉ cần hai lần là tài khoản chết trong 180 giây** — dài hơn cả kịch bản Spike (240 giây tổng, cú sốc chỉ 60 giây). Trạng thái khoá sẽ **nhiễm sang lần chạy kế tiếp**.

### 3.3 Các bước reset (đã tự động hoá, chạy trước MỖI kịch bản)

```powershell
# Buoc 1 — go khoa bang cach ghi thang vao SQLite
node scripts\reset_lockout.js

# Ket qua in ra:
#   [reset] Truoc khi reset: N tai khoan co login_attempts > 0 hoac dang bi khoa
#           id=.. email=.. attempts=.. locked_until=..
#   [reset] Da go khoa / dat lai bo dem cho 62 ban ghi users.
#   [reset] Kiem tra lai: con 0 tai khoan bi khoa (ky vong 0).
```

**Vì sao phải ghi thẳng vào DB thay vì gọi API:** SUT chỉ đặt lại `login_attempts = 0` khi **đăng nhập thành công** (`server.js:47-50`). Nhưng khi đang bị khoá thì mọi lần đăng nhập đều bị chặn ở `server.js:40-44` trước khi kiểm tra mật khẩu — nên **không tồn tại đường HTTP nào để tự gỡ khoá**. Cách duy nhất là `UPDATE users SET login_attempts = 0, locked_until = NULL`.

Trên thực tế, vì bước reset môi trường (§2 bước 1) đã `DROP TABLE users` rồi seed lại, nên lockout gần như luôn được xoá sạch từ trước; bước `reset_lockout.js` đóng vai trò **lưới an toàn** và, quan trọng hơn, **in ra bằng chứng** rằng không còn tài khoản nào bị khoá khi bắt đầu đo. Nhật ký của cả bốn lần chạy đều xác nhận `còn 0 tài khoản bị khoá`.

### 3.4 Kết quả thực tế

Trong cả bốn lần chạy chính thức, **không có bất kỳ lỗi `LOCKOUT_403` nào** xuất hiện trong `.jtl`. Có thể kiểm chứng bằng:

```powershell
Select-String -Path results\jtl\*.jtl -Pattern "LOCKOUT_403" | Measure-Object
```

Điều này chứng minh assertion phân biệt 401/403 đã hoạt động đúng và môi trường sạch ở mọi lần chạy.

---

## 4. Bằng chứng theo từng lần chạy

Mỗi lần chạy có đủ 5 artefact:

| Artefact | Đường dẫn |
|---|---|
| Log thô `.jtl` | `results/jtl/23127195_{Scenario}_20260816.jtl` |
| Log của JMeter | `results/jtl/23127195_{Scenario}_20260816.jmeter.log` |
| Thư mục HTML report | `results/html/23127195_{Scenario}_20260816/` |
| Log giám sát tài nguyên (2 s/mẫu) | `results/monitor/23127195_{Scenario}_20260816_resources.csv` |
| Tóm tắt lần chạy | `results/monitor/23127195_{Scenario}_20260816_run_summary.txt` |
| Số liệu tính lại từ log thô | `results/jtl/23127195_{Scenario}_20260816_stats.json` |

### 4.1 Bảng tổng hợp bốn lần chạy

| | **Load** | **Stress** | **Spike** | **Soak** |
|---|---|---|---|---|
| Bắt đầu | 21:14:32 | 21:21:00 | *(xem tóm tắt)* | *(xem tóm tắt)* |
| Thời lượng | 304 s | 366 s | 245 s | 906 s |
| VU tối đa | 60 | 500 | 340 (40 nền + 300 sốc) | 150 |
| Request HTTP | 18.749 | 108.740 | *(xem §4.4)* | *(xem §4.5)* |
| Lỗi | **0 (0,00%)** | **0 (0,00%)** | *(xem §4.4)* | *(xem §4.5)* |
| p95 tổng | **9 ms** | 442 ms | *(xem §4.4)* | *(xem §4.5)* |
| Throughput ổn định | 69,6 req/s | 458 req/s (đỉnh) | *(xem §4.4)* | *(xem §4.5)* |
| Đơn hàng phát sinh | 2.663 | 15.402 | *(xem §4.4)* | *(xem §4.5)* |
| Backend RSS đầu → đỉnh | 69,7 → 106,0 MB | 69,4 → 156,7 MB | *(xem §4.4)* | *(xem §4.5)* |
| Backend CPU đỉnh (toàn hệ thống / một core) | 1,2% / **24%** | 5,3% / **106%** | *(xem §4.4)* | *(xem §4.5)* |
| JMeter CPU trung bình | 0,4% | 0,8% | *(xem §4.4)* | *(xem §4.5)* |

> **Cách đọc cột CPU:** cột giám sát ghi CPU theo **phần trăm toàn bộ 20 luồng logic**. Vì backend là Node đơn luồng, trần lý thuyết của nó là 1/20 = **5%**. Nhân với 20 để ra "phần trăm của một core". Con số 5,3% ở Stress tương đương **106% một core** — tức đã bão hoà hoàn toàn. Đây là chỉ số **cực dễ bị đọc sai thành "server đang rảnh"**; xem `docs/06` §2.

---

## 5. Danh mục ảnh chụp màn hình cần có trong `evidence/`

Các ảnh dưới đây phải do sinh viên tự chụp trong lúc chạy (không thể sinh tự động), và là bằng chứng bắt buộc theo mục 11 của đề bài:

| Tệp | Nội dung bắt buộc thấy được |
|---|---|
| `evidence/hardware/dxdiag.png` | Cửa sổ DxDiag, thấy rõ **hostname `DESKTOP-96ARBFL`**, CPU, RAM |
| `evidence/load/jmeter_load.png` | JMeter (GUI hoặc console) **và** Task Manager trong **cùng một khung hình**, thấy tiến trình `node.exe` |
| `evidence/stress/jmeter_stress.png` | Như trên, lúc đang ở gần 500 VU |
| `evidence/spike/jmeter_spike.png` | Như trên, chụp đúng lúc cú sốc đang diễn ra (giây thứ 90–150) |
| `evidence/soak/jmeter_soak.png` | Như trên, chụp ở phút thứ 12–15 |
| `evidence/*/taskmanager_*.png` | Tab Details của Task Manager, cột CPU và Memory của `node.exe` |

Xem `evidence/README.md` để biết cách chụp và các mốc thời gian nên chụp.
