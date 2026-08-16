# 06 — Task 2: Phân tích bằng AI và săn lỗi diễn giải

**MSSV:** 23127195 · **Ngày:** 2026-08-16

---

## 0. Phương pháp — và giới hạn của nó

Task 2 gồm hai pha:

| Pha | Việc | Đầu vào được phép dùng |
|---|---|---|
| **Pha 1 — AI phân tích** | Yêu cầu AI phân tích kết quả và đề xuất ngưỡng + hướng tối ưu | **Chỉ** số liệu tóm tắt: ô Total của `statistics.json`, dòng `summary =` cuối của console, file `run_summary.txt` |
| **Pha 2 — Con người kiểm chứng** | Mở file `.jtl` **thô** ra, kiểm lại từng khẳng định | Toàn bộ log thô + mã nguồn SUT |

Việc giới hạn đầu vào ở pha 1 là **có chủ đích**: đó đúng là tình huống thực tế phổ biến nhất — người dùng dán vài con số tóm tắt vào chat rồi hỏi "phân tích giúp tôi".

**Nói thẳng về giới hạn:** cả hai pha đều chạy trong cùng một phiên với cùng một model (Claude Opus 5), nên đây **không phải hai nguồn độc lập**. Vì vậy giá trị của phần này không nằm ở chỗ "AI này chấm AI kia", mà nằm ở chỗ: **mỗi lỗi nêu ra đều kèm một lệnh chạy được trên file `.jtl` thô đã commit trong repo**. Người chấm chạy lại lệnh đó là biết ngay đúng hay sai, không phải tin lời ai cả.

---

## 1. Đầu ra pha 1 — AI phân tích từ số liệu tóm tắt

Số liệu đưa cho AI (trích nguyên từ `results/html/23127195_Stress_20260816/statistics.json` và `results/monitor/23127195_Stress_20260816_run_summary.txt`):

```
Total: sampleCount=108740  errorPct=0.0  mean=104.0  pct95=641.0  pct99=832.0  max=1005.0  throughput=302.05/s
Console: summary = 108740 in 00:06:00 = 301.8/s Avg: 103 Min: 0 Max: 1005 Err: 0 (0.00%)
Backend: RSS 69.4 -> 156.7 MB | CPU trung binh 2.8% | CPU dinh 5.3% (tren 20 luong logic)
JMeter : CPU trung binh 0.8%
Don hang: 0 -> 15402
```

**Nhận định của AI (pha 1, nguyên văn ý chính):**

> 1. Hệ thống xử lý 108.740 request ở mức ~302 req/s với **0% lỗi**, cho thấy nó **chịu được tải 500 VU** một cách ổn định.
> 2. **p95 = 641 ms** là chỉ số đáng lo; đề xuất đặt ngưỡng SLA p95 ≤ 500 ms và cảnh báo khi vượt.
> 3. **CPU đỉnh chỉ 5,3%** trong khi RAM tăng từ 69 lên 157 MB → CPU **không phải** nút thắt; nút thắt nhiều khả năng nằm ở **I/O đĩa hoặc bộ nhớ**.
> 4. RSS tăng **hơn gấp đôi** (69 → 157 MB) trong 6 phút là dấu hiệu **rò rỉ bộ nhớ nghiêm trọng**.
> 5. Throughput trần của hệ thống là **~302 req/s**.
> 6. Đề xuất tối ưu: thêm index cho `orders(user_id)`; bật SQLite WAL; dùng **connection pool** cho SQLite; thêm **Redis cache** cho danh sách sản phẩm; tăng `UV_THREADPOOL_SIZE`.

Nghe rất thuyết phục. Nhưng **5 trong 6 nhận định đầu là sai hoặc gây hiểu lầm.**

---

## 2. Săn lỗi diễn giải — đối chiếu với log thô

### M1 — SAI: "p95 = 641 ms"

**Giá trị đúng: p95 = 442 ms.** Chênh **45%**.

Ô Total của HTML report **không** tính percentile trên toàn bộ lần chạy, mà chỉ trên **cửa sổ trượt 20.000 mẫu gần nhất**. Với một bài stress test ramp tăng dần thì 20.000 mẫu cuối chính là nhóm chậm nhất, nên con số bị đội lên.

**Bằng chứng thực nghiệm:**

```
p95 tren toan bo 108.740 mau  = 442 ms
p95 cua 20.000 mau CUOI       = 641 ms   <-- khop chinh xac voi HTML report
p95 cua 50.000 mau CUOI       = 546 ms
p95 cua 100.000 mau CUOI      = 453 ms
```

Bằng chứng gián tiếp củng cố: ở kịch bản **Load** chỉ có 18.749 mẫu — **ít hơn 20.000** — nên cửa sổ phủ trọn lần chạy, và HTML report khớp **tuyệt đối** với log thô (p95 = 9 ms ở cả hai).

**Lệnh kiểm chứng:**
```powershell
python scripts\analyze_jtl.py results\jtl\23127195_Stress_20260816.jtl
# TONG HOP TOAN BO REQUEST HTTP -> p95_ms: 442
```

**Vì sao AI sai:** nó nhận `pct95ResTime` như một sự thật hiển nhiên. Không có gì trong số liệu tóm tắt cho biết đó là thống kê theo cửa sổ. **Chỉ có cách tính lại từ log thô mới lộ ra.**

---

### M2 — SAI NGHIÊM TRỌNG: "CPU đỉnh chỉ 5,3% → CPU không phải nút thắt"

**Đây là lỗi tai hại nhất, vì nó chỉ sai hướng điều tra sang chỗ hoàn toàn khác.**

**Giá trị đúng: 5,3% là CPU đo trên tổng 20 luồng logic. Backend là Node ĐƠN LUỒNG, nên trần lý thuyết của nó là 1/20 = 5,0%.**

Nói cách khác: **5,3% ≈ 106% của một core — tiến trình đã bão hoà HOÀN TOÀN.** CPU chính là nút thắt, đúng thứ mà AI vừa loại trừ.

**Bằng chứng củng cố từ log thô** — nếu nút thắt là I/O đĩa thì các endpoint có ghi đĩa phải chậm hơn hẳn endpoint không chạm DB. Thực tế:

| Endpoint | Chạm gì | p95 lúc Stress |
|---|---|---|
| `POST /api/cart` | **Không chạm DB**, chỉ ghi RAM | **194 ms** |
| `GET /api/products/{id}` | Đọc DB theo khoá chính | 379 ms |
| `POST /api/checkout` | **Ghi đĩa** | 416 ms |

`POST /api/cart` **không hề chạm đĩa** mà p95 vẫn lên tới 194 ms. Độ trễ đó không thể là I/O — nó là thời gian **xếp hàng chờ event loop**. Toàn bộ endpoint chậm đi cùng nhau vì tất cả cùng chờ một luồng duy nhất.

**Lệnh kiểm chứng:**
```powershell
python scripts\analyze_jtl.py results\jtl\23127195_Stress_20260816.jtl
Import-Csv results\monitor\23127195_Stress_20260816_resources.csv |
  Measure-Object backend_cpu_pct -Maximum    # -> 5.3
[Environment]::ProcessorCount                # -> 20
```

**Vì sao AI sai:** nó so 5,3% với thang đo trực giác "100% là hết CPU", mà quên rằng **trần của một tiến trình đơn luồng trên máy N nhân là 100/N %**. Số liệu tóm tắt có ghi rõ "trên tổng 20 luồng logic" nhưng AI không quy đổi. Đây là lỗi suy luận, không phải lỗi thiếu dữ liệu.

---

### M3 — SAI: "0% lỗi → hệ thống chịu được 500 VU ổn định"

**Sai vì lẫn lộn giữa "không hỏng" và "dùng được".**

Đúng là 0 lỗi trong toàn bộ 108.740 request. Nhưng đường cong theo độ đồng thời dựng từ cột `allThreads` của log thô cho thấy hệ thống đã vượt xa mức dùng được:

| Số VU | Throughput | Avg | **p95** | So với đường cơ sở Load |
|---|---|---|---|---|
| 60 (bản Load) | 69,6 req/s | 3,7 ms | **9 ms** | ×1 |
| 300–349 | 62,7 req/s | 17,9 ms | **55 ms** | ×6,1 |
| 350–399 | 82,9 req/s | 48,3 ms | **147 ms** | ×16,3 |
| 400–449 | 112,6 req/s | 104,5 ms | **276 ms** | ×30,7 |
| 450–499 | 164,1 req/s | 157,0 ms | **443 ms** | **×49,2** |

Ở 500 VU, p95 đã **gấp 49 lần** đường cơ sở. Không có lỗi nào được ghi nhận, nhưng người dùng thật thì đã bỏ đi từ lâu.

**Điểm gối thật nằm giữa 349 và 399 VU** — chỗ p95 nhảy từ 55 ms lên 147 ms trong khi throughput gần như không tăng.

**Lệnh kiểm chứng:**
```powershell
python scripts\analyze_jtl.py results\jtl\23127195_Stress_20260816.jtl --concurrency-buckets 50
```

**Vì sao AI sai:** `errorPct = 0.0` là chỉ số nổi bật nhất trong bảng tóm tắt, và mô hình coi "không lỗi" là "khoẻ mạnh". Ô Total không hề chứa thông tin về độ đồng thời — muốn có phải gom lại từ cột `allThreads` của log thô.

---

### M4 — GÂY HIỂU LẦM: "RSS tăng hơn gấp đôi trong 6 phút → rò rỉ nghiêm trọng"

**Có rò rỉ thật, nhưng kết luận "nghiêm trọng" thì không có cơ sở, và cách suy ra cũng sai.**

Hai chuyện bị gộp làm một:

1. **Bộ nhớ tăng do tải** — Node cấp phát heap cho request đang xử lý; ở 500 VU thì phần này lớn là bình thường và sẽ được thu hồi.
2. **Rò rỉ thật** — `userCarts` (`server.js:14`) **không bao giờ được xoá sau checkout**.

Muốn tách hai thứ này thì phải nhìn kịch bản **Soak** — tải cố định 150 VU suốt 15 phút — chứ không phải kịch bản Stress có tải tăng dần. Ở tải cố định, mọi mức tăng bộ nhớ còn lại chính là phần tích luỹ:

*(số liệu chi tiết ở `docs/05_endurance_threshold.md` §2)*

**Vì sao AI sai:** nó suy ra xu hướng bộ nhớ từ một kịch bản có tải **thay đổi liên tục**, nơi bộ nhớ đương nhiên phải tăng theo tải. Muốn kết luận về rò rỉ thì phải giữ tải **cố định** — nhưng số liệu tóm tắt không cho biết hình dạng tải của kịch bản.

---

### M5 — SAI: "Throughput trần của hệ thống là ~302 req/s"

**Trần thông lượng không phải một hằng số. Nó phụ thuộc khối lượng dữ liệu trong bảng `orders`.**

Con số 302,05 req/s trong ô Total là **trung bình của cả lần chạy, tính cả 300 giây ramp-up** khi số VU còn rất thấp. Nó không phải trần của bất kỳ thứ gì.

Các mức thông lượng thật đo được:

| Bối cảnh | Số đơn trong bảng `orders` | Throughput HTTP |
|---|---|---|
| Stress, cửa sổ 60 s ở đoạn cao nhất | ~12.000–15.000 | **458 req/s** |
| Spike, lúc sốc | ~600 | **621 req/s** |
| Calibration, DB sạch, 50 VU | 0 → ~3.700 | 456 req/s |
| Calibration, DB tồn đọng, 50 VU | 21.404 | **211 req/s** |

Chênh **gần 3 lần** giữa mức cao nhất và thấp nhất, chỉ do khối lượng dữ liệu — hệ quả trực tiếp của việc `orders.user_id` không có index.

**Lệnh kiểm chứng:**
```powershell
python scripts\analyze_jtl.py results\jtl\23127195_Stress_20260816.jtl --time-buckets 60
python scripts\analyze_jtl.py results\jtl\23127195_Spike_20260816.jtl  --time-buckets 15
```

**Vì sao AI sai:** ô Total chỉ có một con số throughput duy nhất, và không có cách nào từ đó biết được nó là trung bình gộp cả pha ramp-up. Cũng không có gì cho biết khối lượng dữ liệu đã thay đổi trong lúc chạy.

---

### M6 — Cái bẫy chưa bung: nếu đưa thẳng file `.jtl` thô cho AI

Ở pha 1, AI được đưa số liệu tóm tắt nên không mắc lỗi này. Nhưng nếu đưa thẳng file `.jtl` và bảo "đếm giúp", cái bẫy sau sẽ bung ra:

| Nguồn | Số bản ghi | Có gồm Transaction Controller? |
|---|---|---|
| Đếm dòng file `.jtl` thô | **155.696** | **Có** |
| Dòng `summary =` cuối của console | 108.740 | Không |
| Ô Total của HTML report | 108.740 | Không |

Ai đếm dòng file thô rồi chia cho thời lượng sẽ ra **432 sample/s** thay vì **302 req/s** — **thổi phồng 43%**. Bản thân JMeter không sai; cái bẫy chỉ dành cho người tự phân tích file thô.

**Lệnh kiểm chứng:**
```powershell
(Get-Content results\jtl\23127195_Stress_20260816.jtl).Count          # 155.697 (ke ca dong tieu de)
python scripts\analyze_jtl.py results\jtl\23127195_Stress_20260816.jtl  # tach 108.740 / 46.956
```

---

### M7 — Chỗ AI nói ĐÚNG

Công bằng mà nói, có những chỗ AI đúng và hữu ích:

- Đề xuất **thêm index cho `orders(user_id)`** — đúng, và đã kiểm chứng bằng thực nghiệm ở §4.
- Đề xuất **bật SQLite WAL** — hợp lý về nguyên tắc, đã kiểm chứng ở §4.
- Nhận ra **`apply-coupon` là endpoint chậm nhất** — đúng (p95 672 ms lúc Stress), và giải thích được: nó chạy **hai truy vấn lồng nhau** (`SELECT coupons` rồi `SELECT COUNT(*) coupon_usage`).
- Cấu trúc phân tích mạch lạc, nêu đủ các chỉ số cần nhìn.

---

## 3. Bảng tổng kết lỗi diễn giải

| # | Khẳng định của AI | Giá trị đúng từ log thô | Mức nghiêm trọng | Vì sao sai |
|---|---|---|---|---|
| M1 | p95 = 641 ms | **442 ms** | Trung bình | Ô Total dùng cửa sổ trượt 20.000 mẫu |
| M2 | CPU 5,3% → không phải nút thắt | **106% của một core → chính là nút thắt** | **Nghiêm trọng** | Không quy đổi theo số nhân với tiến trình đơn luồng |
| M3 | 0% lỗi → chịu được 500 VU | p95 xấu đi **49 lần**, điểm gối ở ~350 VU | **Nghiêm trọng** | Coi "không lỗi" là "dùng được" |
| M4 | Rò rỉ bộ nhớ nghiêm trọng | Có rò rỉ nhưng chậm; suy ra từ kịch bản sai | Trung bình | Dùng kịch bản tải biến thiên để kết luận về rò rỉ |
| M5 | Trần throughput 302 req/s | 211–621 req/s tuỳ khối lượng dữ liệu | Trung bình | Trung bình gộp cả ramp-up, bỏ qua yếu tố dữ liệu |
| M6 | *(chưa bung ở pha 1)* | 155.696 bản ghi ≠ 108.740 request | Trung bình | Sample của Transaction Controller nằm trong file thô |
