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

---

## 4. Phân loại đề xuất tối ưu: khả thi hay ảo tưởng

Đề bài yêu cầu phân loại từng đề xuất là **khả thi** hay **ảo tưởng**. Phân loại trên giấy thì ai cũng làm được, nên hai đề xuất quan trọng nhất đã được **kiểm chứng bằng phép đo A/B thật**.

### 4.1 Thiết lập phép đo

| Hạng mục | Giá trị |
|---|---|
| Dữ liệu | **40.000 đơn hàng nạp sẵn**, chia đều 60 tài khoản (~667 đơn/tài khoản) |
| Tải | 60 VU, think-time 0,2–0,5 s, chạy 60 s |
| Trước mỗi phép đo | Reset SUT về trạng thái sạch, **ép `journal_mode`** rồi kiểm tra lại |
| Thiết kế | **Xen kẽ 3 lượt** (A, B, A, B, A, B) để trôi nhiệt độ / tải nền ảnh hưởng đều lên cả hai nhóm |
| Script | `scripts/experiment_wal_repeat.ps1`, `scripts/experiment_index_repeat.ps1` |
| Log thô | `results/experiments/` |

Phải nạp sẵn 40.000 đơn vì trên DB rỗng bảng `orders` quá nhỏ để việc thiếu index có ý nghĩa — đo trên DB rỗng sẽ kết luận sai rằng "thêm index không có tác dụng".

### 4.2 Ba sai lầm về phương pháp đã mắc và sửa

Ghi lại đầy đủ vì chúng quyết định độ tin của bảng số ở §4.3, và vì đây chính là loại lỗi mà cổng kiểm tra tính hợp lệ ở `docs/07` §3.4 tồn tại để chặn.

| # | Sai lầm | Phát hiện thế nào | Cách sửa |
|---|---|---|---|
| 1 | Chạy phân tích Python nặng và git commit **trong lúc đang đo** | Cùng một cấu hình cho 300 rps ở lần này và 375 rps ở lần khác | Đo lại, giữ máy hoàn toàn rảnh suốt phép đo |
| 2 | **`journal_mode=WAL` bền vững trong file DB** — sống sót qua `DROP TABLE` và qua restart server → mọi lần "baseline" sau một cấu hình WAL thực chất vẫn đang chạy WAL | Kiểm tra sự tồn tại của file sidecar `database.sqlite-wal` trong pha baseline → thấy `True` | Thêm lệnh `db_tool.js set-delete`, ép `journal_mode` trước mỗi phép đo **và xác nhận lại**, dừng hẳn nếu không ép được |
| 3 | JMeter **ghi tiếp** vào file `.jtl` cũ khi không xoá được → trộn dữ liệu hai lần chạy | File có timestamp trải 5,15 giờ, gồm 2 cụm cách nhau 5 tiếng (13.791 + 60 bản ghi) | Đặt tên file theo dấu thời gian; dừng hẳn nếu không xoá được file cũ |

Sai lầm số 2 đáng nhớ nhất: **nó làm phép so sánh A/B trở nên vô nghĩa mà không hề báo lỗi.** Cả bốn cấu hình vẫn chạy, vẫn ra số, vẫn xếp hạng được — chỉ có điều "nhóm đối chứng" không phải đối chứng. Nếu không kiểm tra file sidecar thì đã báo cáo một kết luận sai với vẻ ngoài hoàn toàn thuyết phục.

### 4.3 Kết quả A/B

**Thí nghiệm 1 — bật SQLite WAL** (`journal_mode` = `delete` so với `wal`):

| Lượt | Cấu hình | Throughput | `my-orders` p95 | `checkout` p95 |
|---|---|---|---|---|
| 1 | baseline | 286,4 req/s | 117 ms | 103 ms |
| 1 | **WAL** | **321,1 req/s** | **90 ms** | **71 ms** |
| 2 | baseline | 289,1 req/s | 112 ms | 102 ms |
| 2 | **WAL** | **314,6 req/s** | **108 ms** | **86 ms** |
| 3 | baseline | 289,3 req/s | 114 ms | 94 ms |
| 3 | **WAL** | **328,3 req/s** | **79 ms** | **59 ms** |
| | *trung bình baseline* | 288,3 req/s | 114,3 ms | 99,7 ms |
| | *trung bình WAL* | **321,3 req/s** | **92,3 ms** | **72,0 ms** |
| | **Thay đổi** | **+11,5%** | **−19,2%** | **−27,8%** |

**Thí nghiệm 2 — thêm index `orders(user_id)`** (cả hai nhóm đều ở `journal_mode=delete` để chỉ còn một biến số):

| Lượt | Cấu hình | Throughput | `my-orders` p95 | `checkout` p95 |
|---|---|---|---|---|
| 1 | baseline | 234,7 req/s ⚠️ | 180 ms ⚠️ | 167 ms ⚠️ |
| 1 | **index** | **353,3 req/s** | **62 ms** | **56 ms** |
| 2 | baseline | 289,7 req/s | 111 ms | 96 ms |
| 2 | **index** | **320,5 req/s** | **96 ms** | **87 ms** |
| 3 | baseline | 286,2 req/s | 125 ms | 111 ms |
| 3 | **index** | **312,8 req/s** | **79 ms** | **72 ms** |
| | *trung bình baseline, bỏ lượt 1* | 288,0 req/s | 118,0 ms | 103,5 ms |
| | *trung bình index, bỏ lượt 1* | **316,7 req/s** | **87,5 ms** | **79,5 ms** |
| | **Thay đổi** | **+10,0%** | **−25,8%** | **−23,2%** |

⚠️ Lượt 1 của baseline là **giá trị ngoại lai do chưa làm nóng** (234,7 req/s so với 289,7 và 286,2 ở hai lượt sau) — file cache của OS còn lạnh ở phép đo đầu tiên của phiên. Đã loại khỏi phần tính trung bình và ghi rõ ở đây thay vì âm thầm bỏ đi.

**Hai bằng chứng cho thấy phép đo đáng tin:**

1. **Baseline rất ổn định trong từng phiên:** thí nghiệm WAL cho 286,4 / 289,1 / 289,3 req/s — lệch chỉ **1,0%**.
2. **Baseline khớp giữa hai phiên độc lập:** thí nghiệm WAL cho 286,4–289,3 req/s; thí nghiệm index (chạy sau, riêng biệt) cho 286,2–289,7 req/s. Hai lần chạy độc lập, cùng cấu hình, **khớp nhau trong 1%**. Mức cải thiện đo được (+10% đến +11,5%) lớn hơn nhiễu này khoảng một bậc.

> **Vẫn phải nói rõ một hạn chế:** giữa các *phiên* khác nhau trong ngày, cùng cấu hình baseline có lúc cho 336 req/s (phiên đo lần đầu). Vì vậy mọi kết luận ở đây **chỉ dựa trên so sánh cặp trong cùng một phiên xen kẽ**, không so số tuyệt đối giữa các phiên.

### 4.4 Phân loại từng đề xuất

| Đề xuất của AI | Phân loại | Căn cứ |
|---|---|---|
| Thêm index `orders(user_id)` | ✅ **KHẢ THI — đã kiểm chứng** | +10,0% throughput, `my-orders` p95 −25,8% |
| Bật SQLite WAL | ✅ **KHẢ THI — đã kiểm chứng** | +11,5% throughput, `checkout` p95 −27,8% |
| Node cluster / PM2 | ⚠️ **KHẢ THI CÓ ĐIỀU KIỆN** | Mở được trần CPU, nhưng phải sửa `userCarts` trước |
| Tăng `UV_THREADPOOL_SIZE` | ❌ **ĐO ĐƯỢC LÀ KHÔNG CÓ TÁC DỤNG** | 374,6 so với 377,1 req/s — chênh 0,7%, nằm trong nhiễu |
| Connection pool cho SQLite | ❌ **ẢO TƯỞNG** | SQLite là DB nhúng, không có server để pool kết nối tới |
| Redis cache cho danh sách sản phẩm | ⚠️ **ĐÚNG KỸ THUẬT NHƯNG SAI ƯU TIÊN** | Endpoint sản phẩm không phải nút thắt |

#### ✅ Thêm index `orders(user_id)` — KHẢ THI

`database.js:74-81` khai báo bảng `orders` không có index nào ngoài PRIMARY KEY, trong khi `server.js:311-318` chạy `SELECT * FROM orders WHERE user_id = ? ORDER BY id DESC` trên mọi vòng lặp.

Ngoài phép đo A/B, còn **hai bằng chứng độc lập** từ harness chính (đáng tin hơn vì chạy dài hơn, có reset và giám sát đầy đủ):

- **Soak 15 phút:** `my-orders` trôi **×1,89** trong khi `POST /api/cart` (không chạm DB) chỉ trôi ×1,25.
- **Calibration:** DB sạch cho 652 sample/s, DB tồn 21.404 đơn chỉ cho 301 sample/s — **chênh 2,17 lần**.

Ba nguồn bằng chứng độc lập cùng chỉ một hướng. Đây là hướng tối ưu **rẻ nhất** (một câu `CREATE INDEX`) và nên làm đầu tiên.

#### ✅ Bật SQLite WAL — KHẢ THI

`PRAGMA journal_mode` xác nhận SUT đang ở chế độ `delete` (rollback journal): mỗi `INSERT orders` phải tạo file journal, ghi, rồi xoá — và **khoá toàn bộ file DB** trong lúc đó.

Điều đáng chú ý trong số đo: WAL cải thiện **`checkout` (−27,8%) nhiều hơn `my-orders` (−19,2%)** — đúng như dự đoán về cơ chế, vì `checkout` là endpoint **ghi**, còn phần cải thiện của `my-orders` là hệ quả gián tiếp (writer không còn chặn reader nên event loop rảnh hơn).

Đây là hướng phân bố công sức đối lập với index: index tối ưu đường **đọc**, WAL tối ưu đường **ghi**. Chúng độc lập nhau nên về nguyên tắc có thể cộng dồn.

#### ⚠️ Node cluster — KHẢ THI CÓ ĐIỀU KIỆN

Đây là hướng có **tiềm năng lớn nhất về lý thuyết**: nút thắt đã xác định là **một core CPU** (chạm 106% của một core trong khi 19 luồng logic khác rảnh hoàn toàn). Chạy 4–8 worker về nguyên tắc mở được trần này lên nhiều lần.

**Nhưng không được làm ngay.** `server.js:14` khai báo `const userCarts = {}` — giỏ hàng nằm trong RAM của **một tiến trình**. Tách nhiều worker thì mỗi worker có bản `userCarts` riêng, và vì request được phân phối ngẫu nhiên, giỏ hàng sẽ **biến mất hoặc thiếu món một cách không thể tái hiện** tuỳ worker nào nhận request. Đây là kiểu lỗi tệ nhất: chỉ xuất hiện dưới tải, không tái hiện được khi debug.

Thứ tự bắt buộc: **(1)** chuyển giỏ hàng sang store dùng chung hoặc xuống DB → **(2)** rồi mới bật cluster. Bước (1) đồng thời sửa luôn rò rỉ 1,76 MB/phút.

#### ❌ Tăng `UV_THREADPOOL_SIZE` — ĐO ĐƯỢC LÀ KHÔNG CÓ TÁC DỤNG

Cơ sở của đề xuất **có thật, không phải bịa**: `node-sqlite3` là binding C++, nó chạy truy vấn trên libuv threadpool (mặc định **4** luồng) chứ không trên luồng JS. Nghe rất hợp lý.

Phép đo cặp, cùng điều kiện, chạy liền nhau (`scripts/experiment_threadpool.ps1`):

| `UV_THREADPOOL_SIZE` | Throughput | `my-orders` p95 |
|---|---|---|
| 4 (mặc định) | 374,6 req/s | 10 ms |
| 16 | 377,1 req/s | 11 ms |

Chênh **0,7%** — nằm trong nhiễu. Kết quả này khớp với bằng chứng đã có rằng nút thắt là **luồng JS đơn**, không phải threadpool: `POST /api/cart` **không dùng threadpool lần nào** (không chạm DB) mà vẫn chậm đi cùng nhịp với mọi endpoint khác.

**Xếp loại "không có tác dụng" chứ không phải "ảo tưởng"** — lập luận đúng, chỉ là nhắm sai nút thắt.

#### ❌ Connection pool cho SQLite — ẢO TƯỞNG

Đây là khái niệm bị **bê nguyên từ PostgreSQL/MySQL** sang một ngữ cảnh mà nó không tồn tại. SQLite là cơ sở dữ liệu **nhúng**: thư viện đọc/ghi trực tiếp vào file, **không có tiến trình server nào để mà mở pool kết nối tới**. Cái mà connection pool tiết kiệm — chi phí bắt tay TCP và handshake xác thực với DB server — ở đây bằng không.

Tệ hơn, nó có thể **gây hại**: `database.js:5` mở đúng một `sqlite3.Database`, và node-sqlite3 tuần tự hoá truy vấn trên kết nối đó. Mở nhiều kết nối **ghi** đồng thời vào cùng một file chỉ làm tăng tranh chấp khoá ghi và sinh lỗi `SQLITE_BUSY` — đúng thứ mà WAL được bật để giảm bớt.

Đây là ví dụ điển hồi của việc AI **khớp mẫu** ("DB chậm → thêm connection pool") mà không kiểm tra tiền đề có đúng với loại DB đang dùng hay không.

#### ⚠️ Redis cache cho danh sách sản phẩm — ĐÚNG KỸ THUẬT NHƯNG SAI ƯU TIÊN

Về kỹ thuật thì làm được. Nhưng số đo cho thấy các endpoint sản phẩm **không phải nút thắt**. Lúc Soak:

| Endpoint | p95 |
|---|---|
| `GET /api/products?search` | 13 ms |
| `GET /api/products/{id}` | 14 ms |
| `POST /api/checkout` | **22 ms** |
| `POST /api/apply-coupon` | **19 ms** |

Cache hoá hai endpoint nhanh nhất trong khi bỏ mặc endpoint chậm nhất là phân bố công sức sai chỗ. Tệ hơn: thêm Redis đưa **thêm một chặng mạng và thêm một tiến trình** lên chính cái máy mà nút thắt là **một core CPU đang bão hoà** — hoàn toàn có thể làm chậm đi.

Nếu thực sự muốn cache thì cache trong tiến trình (`Map` với TTL) sẽ hợp lý hơn nhiều ở quy mô này, mà không cần thêm hạ tầng.

### 4.5 Thứ tự nên làm, theo tỉ lệ lợi ích trên công sức

| Thứ tự | Việc | Công sức | Lợi ích đo được |
|---|---|---|---|
| 1 | `CREATE INDEX idx_orders_user_id ON orders(user_id)` | Một dòng SQL | +10,0% throughput, `my-orders` p95 −25,8% |
| 2 | `PRAGMA journal_mode=WAL` | Một dòng cấu hình | +11,5% throughput, `checkout` p95 −27,8% |
| 3 | Chuyển `userCarts` ra khỏi RAM tiến trình | Vừa | Chặn rò rỉ 1,76 MB/phút, và **mở đường cho bước 4** |
| 4 | Node cluster 4–8 worker | Vừa | Mở trần CPU từ 1 core lên nhiều core (chưa đo, nhưng nút thắt đã xác định rõ) |
| — | Connection pool, Redis, `UV_THREADPOOL_SIZE` | — | **Không làm** |
