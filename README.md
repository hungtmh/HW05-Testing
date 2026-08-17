# HW05 — Performance Testing (EShop SUT)

**MSSV:** 23127195 · **Ngày:** 2026-08-16 · **Máy chạy:** `DESKTOP-96ARBFL`
**SUT:** [EShop](https://github.com/ttbhanh/eshop-sut) — commit `85af3ba875c88283615e22cb108f13e2fccaf0e9`
**Công cụ:** Apache JMeter 5.6.3 · Windows Task Manager + PowerShell counters · Claude Opus 5 (phân tích log)

📄 **Báo cáo chính:** [`docs/00_MAIN_REPORT.md`](docs/00_MAIN_REPORT.md)
🎥 **Video demo (YouTube, unlisted):** *(dán link sau khi quay — kịch bản ở [`docs/09_demo_video_script.md`](docs/09_demo_video_script.md))*
🐛 **Bug report:** [GitHub Issues](https://github.com/hungtmh/HW05-Testing/issues) · [`docs/08_bug_report.md`](docs/08_bug_report.md)

---

## Test summary report

### Các kịch bản đã chạy

| Kịch bản | Test plan | VU | Thời lượng | Request HTTP | Lỗi | p95 | Throughput |
|---|---|---|---|---|---|---|---|
| **Load** | `23127195_Load_20260816.jmx` | 60 | 300 s | 18.749 | **0** | **9 ms** | 69,6 req/s |
| **Stress** | `23127195_Stress_20260816.jmx` | → 500 | 360 s | 108.740 | **0** | 442 ms | 458 req/s (đỉnh) |
| **Spike** | `23127195_Spike_20260816.jmx` | 40 + 300 | 240 s | 43.363 | **0** | 513 ms | 621 req/s (lúc sốc) |
| **Soak** | `23127195_Soak_20260816.jmx` | 150 | 900 s | 153.366 | **0** | 16 ms | 173,4 req/s |
| | | | | **324.218** | **0 (0,00%)** | | |

### Độ phủ nhóm endpoint

Cả bốn kịch bản chạy **cùng một workflow end-to-end**, tỉ lệ auth : read : transactional = **1 : 2 : 4**:

```
login → products?search → products/{id} → cart → apply-coupon → checkout → my-orders
```

| Nhóm | Endpoint | Số request / vòng lặp |
|---|---|---|
| **Auth-heavy** | `POST /api/login` | 1 |
| **Read-heavy** | `GET /api/products?search=`, `GET /api/products/{id}` | 2 |
| **Transactional** | `POST /api/cart`, `POST /api/apply-coupon`, `POST /api/checkout`, `GET /api/orders/my-orders` | 4 |

### Ngưỡng chịu đựng (số liệu cụ thể)

| Ngưỡng | Giá trị đo được |
|---|---|
| **Mức tải ổn định tối đa** | **150 VU ≈ 173 req/s ≈ 24,4 vòng lặp/s** — giữ 15 phút, 0 lỗi, p95 ≤ 22 ms |
| **Điểm gối (knee)** | **≈ 350 VU** — p95 nhảy 55 ms → 147 ms trong khi throughput gần như không tăng |
| **Trần throughput** | **458 req/s** (bảng `orders` ~13.000 dòng) · **621 req/s** (bảng ~600 dòng) |
| **Trần CPU** | **5,3% toàn hệ thống = 106% của một core** — bão hoà đúng giới hạn đơn luồng của Node |
| **Trần bộ nhớ** | **130 MB** sau 15 phút ở 150 VU |
| **Tốc độ rò rỉ bộ nhớ** | **1,76 MB/phút** = 1,05 KB mỗi vòng lặp (do `userCarts` không được giải phóng) |
| **Thời gian hồi phục sau sốc** | **10–15 giây** để p95 về lại đường cơ sở sau khi bỏ tải 340 VU |

**Nút thắt thật sự:** một core CPU duy nhất. Máy có 20 luồng logic và 13,75 GB RAM, nhưng backend là Node đơn luồng nên chỉ dùng được **1 core** và 130 MB RAM — 19 luồng còn lại rảnh hoàn toàn trong lúc hệ thống nghẹt.

### Số lỗi / vấn đề hiệu năng

| Loại | Số lượng | Chi tiết |
|---|---|---|
| Lỗi chức năng / bảo mật | **8** (4 nghiêm trọng) | [Issues](https://github.com/hungtmh/HW05-Testing/issues) · [`docs/08_bug_report.md`](docs/08_bug_report.md) |
| Vấn đề hiệu năng | **4** | Thiếu index `orders.user_id`; rò rỉ `userCarts`; SQLite không WAL; Node không cluster |

Bốn lỗi nghiêm trọng: mã giảm giá 10% làm **tăng tiền gấp 10 lần**; `GET /api/orders/:id` không xác thực (IDOR); người dùng thường **tự nâng quyền lên admin**; **SQL injection** ở `?search`.

---

### Kiểm chứng đề xuất tối ưu bằng thực nghiệm A/B

Xen kẽ 3 lượt, 40.000 đơn nạp sẵn, 60 VU × 60 s. Chi tiết: [`docs/06`](docs/06_ai_analysis_and_misinterpretation_hunt.md) §4.

| Đề xuất | Kết luận | Số đo |
|---|---|---|
| Index `orders(user_id)` | ✅ Khả thi | **+10,0%** throughput · `my-orders` p95 **−25,8%** |
| SQLite WAL | ✅ Khả thi | **+11,5%** throughput · `checkout` p95 **−27,8%** |
| `UV_THREADPOOL_SIZE` 4→16 | ❌ Không tác dụng | 374,6 → 377,1 req/s (0,7%, trong nhiễu) |
| Connection pool cho SQLite | ❌ Ảo tưởng | SQLite là DB nhúng, không có server để pool |
| Redis cache sản phẩm | ⚠️ Sai ưu tiên | Sản phẩm p95 13–14 ms, `checkout` 22 ms |
| Node cluster | ⚠️ Có điều kiện | Phải sửa `userCarts` trước |

---

## Ba phát hiện đáng chú ý nhất về phương pháp

1. **15,82% "lỗi" trong calibration không phải lỗi của SUT.** Log thô cho thấy `java.net.BindException — Address already in use`: máy chạy JMeter cạn ephemeral port (12.570 socket TIME_WAIT / 16.384 port khả dụng). Tin ngay con số đó là kết luận sai về SUT.
2. **Ô Total của HTML report báo p95 = 641 ms, p95 thật là 442 ms.** Ô đó dùng **cửa sổ trượt 20.000 mẫu gần nhất** chứ không phải toàn bộ lần chạy — đã kiểm chứng bằng thực nghiệm (p95 của 20.000 mẫu cuối = đúng 641 ms).
3. **Trần thông lượng không phải hằng số:** dao động 211–621 req/s tuỳ khối lượng dữ liệu trong bảng `orders`. Cùng một cấu hình, DB sạch cho 652 sample/s còn DB 21.404 đơn chỉ cho 301 sample/s — **chênh 2,17 lần**.

---

## Cấu trúc repo

| Thư mục | Nội dung |
|---|---|
| [`testplans/`](testplans/) | 4 test plan `.jmx` (Load / Stress / Spike / Soak) |
| [`data/`](data/) | 3 file CSV dữ liệu đầu vào |
| [`results/jtl/`](results/jtl/) | Log thô `.jtl` + log JMeter + số liệu tính lại (JSON) |
| [`results/html/`](results/html/) | 4 thư mục HTML report của JMeter |
| [`results/monitor/`](results/monitor/) | Log giám sát tài nguyên (2 s/mẫu) + tóm tắt từng lần chạy |
| [`results/experiments/`](results/experiments/) | Log của các thí nghiệm A/B kiểm chứng đề xuất tối ưu |
| [`docs/`](docs/) | Báo cáo chính, AI Audit Report, AI Critique, Task 2, Task 3 |
| [`scripts/`](scripts/) | Script reset môi trường, điều phối chạy, phân tích log, probe lỗi |
| [`skill/`](skill/) | **Agent Skill** `performance-testing-jmeter` tái sử dụng được |
| [`evidence/`](evidence/) | Ảnh chụp màn hình + báo cáo phần cứng |

## Cách chạy lại

```powershell
# 1. Khoi dong SUT va nap tai khoan tai (BAT BUOC truoc moi kich ban)
powershell -ExecutionPolicy Bypass -File scripts\reset_sut.ps1

# 2. Chay tung kich ban (tu dong reset, giam sat tai nguyen, xuat .jtl + HTML report)
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Load
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Stress
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Spike
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Soak

# 3. Phan tich log tho (doc lap voi HTML report cua JMeter)
python scripts\analyze_jtl.py results\jtl\23127195_Stress_20260816.jtl --concurrency-buckets 50

# 4. Kiem chung cac loi da bao cao
powershell -ExecutionPolicy Bypass -File scripts\probe_bugs.ps1
```

**Yêu cầu:** Apache JMeter 5.6.3 tại `D:\Kiem_thu\tools\apache-jmeter-5.6.3`, SUT tại `D:\Kiem_thu\eshop-sut`, Java 17, Node 22, Python 3.12.

---

## Bảng tự đánh giá

| No. | Criteria | Grade | Self-Assessed Grade |
|---|---|---|---|
| 1 | Task 1 — Load testing | 20 | **20** |
| 2 | Task 1 — Stress testing | 20 | **20** |
| 3 | Task 1 — Spike testing | 20 | **20** |
| 4 | Task 2 — AI analysis + misinterpretation hunt (with correct values from raw logs) | 10 | **10** |
| 5 | Task 3 — Continuous Performance Testing proposal (G9.6) | 10 | **10** |
| 6 | Agent Skills | 10 | **9** |
| | **Total** | **100** | **89** |

**Căn cứ tự chấm:**

- **Task 1 (60/60):** đủ 4 kịch bản (3 bắt buộc + 1 soak), cùng một workflow phủ đủ 3 nhóm endpoint, dữ liệu hoá bằng 3 CSV, 3 loại listener khác nhau, đặt tên đúng quy ước. 324.218 request với 0 lỗi, đủ log thô `.jtl` + HTML report + log giám sát tài nguyên. Tham số chọn từ calibration thật chứ không phỏng đoán. Phần rà soát của con người nêu 7 lỗi kèm bằng chứng đo được.
- **Task 2 (10/10):** 6 lỗi diễn giải, mỗi lỗi đều trích giá trị đúng từ log thô kèm **lệnh kiểm chứng chạy được**. Phát hiện cửa sổ trượt 20.000 mẫu được truy đến tận gốc bằng thực nghiệm. Các đề xuất tối ưu được phân loại **có kiểm chứng A/B**, không chỉ lập luận trên giấy.
- **Task 3 (10/10):** sơ đồ luồng đầy đủ, ba điểm khác biệt đều sinh ra từ sai lầm thực tế trong bài, chi phí và báo động giả được định lượng, có nêu cả phần bỏ lọt.
- **Agent Skill (9/10):** skill chạy được kèm 6 script, mã hoá sẵn các bẫy đã gặp. Trừ 1 điểm vì **chưa quay video demo riêng cho skill** như đề bài khuyến khích.
- **Trừ điểm chung:** video demo và ảnh chụp màn hình cần sinh viên tự thực hiện (xem [`evidence/README.md`](evidence/README.md) và [`docs/09_demo_video_script.md`](docs/09_demo_video_script.md)).

---

## Tuyên bố về AI

> **I use AI tools for the following tasks.**

Chi tiết đầy đủ 14 bước prompt, kèm đầu ra và số liệu từng bước: [`docs/AI_AUDIT_REPORT.md`](docs/AI_AUDIT_REPORT.md).
Bài phê bình AI (300 từ): [`docs/AI_CRITIQUE.md`](docs/AI_CRITIQUE.md).
