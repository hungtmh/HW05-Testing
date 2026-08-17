# Báo cáo chính — HW05: Performance Testing

**Môn:** Kiểm thử phần mềm · **Bài tập:** HW05-AI — Performance Testing
**MSSV:** 23127195 · **Ngày thực hiện:** 2026-08-16 · **Máy:** `DESKTOP-96ARBFL`
**Repo:** https://github.com/hungtmh/HW05-Testing
**Video demo (YouTube, unlisted):** *(dán link sau khi quay — xem `docs/09_demo_video_script.md`)*

---

## Tóm tắt điều hành

Bài này kiểm thử hiệu năng backend API của **EShop** bằng **Apache JMeter 5.6.3**, qua **bốn kịch bản** (Load, Stress, Spike, Soak) chạy **cùng một workflow end-to-end** phủ đủ ba nhóm endpoint: auth-heavy, read-heavy, transactional.

**Bốn con số quan trọng nhất:**

| Kết luận | Số liệu |
|---|---|
| Mức tải ổn định tối đa | **150 VU ≈ 173 req/s**, giữ 15 phút, 0 lỗi, p95 ≤ 22 ms |
| Điểm gãy (knee) | **≈ 350 VU** — p95 nhảy từ 55 ms lên 147 ms |
| Nút thắt thật sự | **Một core CPU duy nhất** (Node đơn luồng) — chạm 106% của một core trong khi 19 luồng logic còn lại rảnh hoàn toàn |
| Rò rỉ bộ nhớ | **1,76 MB/phút** ở 150 VU, do `userCarts` không được giải phóng sau checkout |

**Ba phát hiện về phương pháp — giá trị hơn cả các con số trên:**

1. **15,82% "lỗi" trong lần calibration hoá ra không phải lỗi của SUT** mà là `java.net.BindException` — máy chạy JMeter cạn ephemeral port (12.570 socket TIME_WAIT trên 16.384 port). Nếu tin ngay con số, cả bài đã kết luận sai.
2. **Ô Total của HTML report báo p95 = 641 ms, trong khi p95 thật là 442 ms** — vì ô đó dùng cửa sổ trượt 20.000 mẫu gần nhất chứ không phải toàn bộ lần chạy. Đã truy ra bằng thực nghiệm.
3. **Trần thông lượng không phải hằng số**: dao động 211–621 req/s tuỳ khối lượng dữ liệu trong bảng `orders`, do bảng này không có index trên `user_id`.

---

## 1. Hệ thống được kiểm thử và phạm vi

**SUT:** EShop backend (Node.js + Express + SQLite), commit `85af3ba875c88283615e22cb108f13e2fccaf0e9`, chạy cục bộ ở `http://localhost:3000`.

**Ba nhóm endpoint đã chọn** *(chi tiết: `docs/01_scope_and_endpoint_selection.md`)*:

| Nhóm | Endpoint | Lý do chọn |
|---|---|---|
| Auth-heavy | `POST /api/login` | Endpoint auth duy nhất vừa `SELECT` vừa `UPDATE` trên mọi lần gọi thành công, lại mang logic khoá tài khoản |
| Read-heavy | `GET /api/products?search=`, `GET /api/products/{id}` | Một truy vấn đắt (`LIKE` không index) đặt cạnh một truy vấn rẻ (khoá chính) để so sánh trực tiếp |
| Transactional | `POST /api/cart` → `POST /api/apply-coupon` → `POST /api/checkout` → `GET /api/orders/my-orders` | Trải đủ: ghi RAM → đọc DB → **ghi đĩa** → đọc bảng không index |

**Workflow chung của cả bốn kịch bản** (tỉ lệ auth : read : transactional = **1 : 2 : 4**, giữ cố định để các kịch bản so sánh được với nhau):

```
login → products?search → products/{id} → cart → apply-coupon → checkout → my-orders
```

Toàn bộ được dữ liệu hoá bằng **3 file CSV**: `users.csv` (60 tài khoản), `search_terms.csv` (10 từ khoá), `checkout_data.csv` (10 bộ dữ liệu đơn hàng).

---

## 2. Task 1 — Thiết kế, rà soát và thực thi

### 2.1 Cách điều khiển AI (chi tiết: `docs/02_ai_test_design_prompts.md`)

AI được điều khiển qua **14 prompt từng bước**, không phải một prompt tổng quát. Bước quan trọng nhất là **P5 — bắt buộc kiểm chứng tham số bằng calibration thật** thay vì tin con số AI đề xuất ở P4. Chính bước này lật ngược hai giả định sai và cho ra trần công suất tham chiếu.

### 2.2 Tham số bốn kịch bản, chọn theo phần trăm công suất đo được

Trần tham chiếu đo được trên DB sạch: **~65 vòng lặp/s**. Mỗi vòng lặp có 3 think-time (trung bình 2 s) ⇒ ~6,2 s/vòng lặp.

| Kịch bản | VU | Ramp-up | Giữ tải | Think-time | % công suất | Listener |
|---|---|---|---|---|---|---|
| **Load** | 60 | 60 s | 240 s | 1–3 s | ~15% | **Summary Report** |
| **Stress** | 500 | 300 s | 60 s | 1–3 s | ~123% | **Aggregate Report** |
| **Spike** | 40 nền + 300 sốc | nền 20 s / sốc 5 s | sốc 60 s | nền 1–3 s, sốc 0,3–0,8 s | ~270% lúc đỉnh | **View Results Tree** |
| **Soak** | 150 | 30 s | 870 s | 1–3 s | ~37% | **Aggregate Graph** |

Ba kịch bản chính dùng **ba loại listener khác nhau** đúng yêu cầu đề bài; Soak dùng loại thứ tư.

### 2.3 Rà soát của con người — 7 lỗi đã sửa (chi tiết: `docs/03_human_review_and_fixes.md`)

| # | Lỗi | Mức | Nhóm nguyên nhân |
|---|---|---|---|
| 1 | `same_user_on_next_iteration=false` → client cạn ephemeral port, bị đọc nhầm thành SUT quá tải | Nghiêm trọng | Giới hạn mô hình |
| 2 | Không reset môi trường giữa các lần chạy → dữ liệu tồn làm throughput tụt 2,17 lần | Nghiêm trọng | Giới hạn mô hình |
| 3 | Ngưỡng lockout thực tế là 2 lần sai, không phải 3 như đề bài mô tả | Nghiêm trọng | Chất lượng prompt |
| 4 | Assertion login quá yếu, không phân biệt 401 với 403 | Trung bình | Đặc thù SUT |
| 5 | View Results Tree giữ mọi mẫu sẽ ăn hết heap ở 340 VU | Trung bình | Giới hạn mô hình |
| 6 | Sample của Transaction Controller nằm trong `.jtl` thô → thổi phồng 43% nếu tự đếm | Trung bình | Đặc thù công cụ |
| 7 | Ba lỗi kỹ thuật khi sinh tự động (treo script, CRLF/LF, kiểu `price`) | Nhỏ | Đặc thù SUT |

**Nguyên tắc rút ra:** AI mạnh ở phần *cấu trúc* (cây sampler, extractor, khuôn XML — gần như không phải sửa), yếu ở phần *tiếp đất* — mọi chỗ mà độ đúng phụ thuộc hành vi thật của hệ thống này, trên máy này, ở mức tải này.

### 2.4 Kết quả bốn lần chạy (chi tiết: `docs/04_execution_evidence.md`)

| | **Load** | **Stress** | **Spike** | **Soak** |
|---|---|---|---|---|
| Thời lượng | 304 s | 366 s | 245 s | 906 s |
| VU tối đa | 60 | 500 | 340 | 150 |
| Request HTTP | 18.749 | 108.740 | 43.363 | 153.366 |
| **Lỗi** | **0** | **0** | **0** | **0** |
| p95 | 9 ms | 442 ms | 513 ms | 16 ms |
| p99 | 15 ms | 639 ms | 654 ms | 27 ms |
| Throughput ổn định | 69,6 req/s | 458 req/s (đỉnh) | 621 req/s (lúc sốc) | 173,4 req/s |
| Đơn phát sinh | 2.663 | 15.402 | 6.084 | 21.865 |
| Backend RSS | 69,7 → 106,0 MB | 69,4 → 156,7 MB | 70,1 → 146,0 MB | 69,7 → 130,0 MB |
| CPU đỉnh (hệ thống / một core) | 1,2% / 24% | **5,3% / 106%** | 5,7% / **114%** | 2,7% / 54% |
| CPU JMeter | 0,4% | 0,8% | 0,6% | 0,4% |

**Điểm đáng chú ý: không một lỗi nào trong tổng 324.218 request**, kể cả ở 500 VU. Hệ thống suy giảm một cách có kiểm soát chứ không sập — nhưng "không sập" khác hẳn "dùng được", xem §3.

**Đường cong Stress theo độ đồng thời** (dựng lại từ cột `allThreads` của log thô):

| VU | Throughput | Avg | p95 |
|---|---|---|---|
| 250–299 | 45,0 req/s | 11,6 ms | 29 ms |
| 300–349 | 62,7 req/s | 17,9 ms | 55 ms |
| **350–399** | 82,9 req/s | 48,3 ms | **147 ms** ← điểm gối |
| 400–449 | 112,6 req/s | 104,5 ms | 276 ms |
| 450–499 | 164,1 req/s | 157,0 ms | 443 ms |

**Spike — ba pha tách bạch trong một lần chạy:**

| Pha | Khoảng thời gian | VU | Throughput | Avg | p95 |
|---|---|---|---|---|---|
| Ổn định | 0–90 s | 40 | 46 req/s | 3,6 ms | 9 ms |
| Sốc | 90–150 s | 340 | 621 req/s | 311 ms | 604 ms |
| **Hồi phục** | 150–155 s | 40 | 44 req/s | 8,0 ms | 23 ms |
| Đã hồi phục hoàn toàn | 160–165 s | 40 | 48 req/s | 3,6 ms | 9 ms |

**Thời gian hồi phục: 10–15 giây.** Chỉ đo được nhờ thiết kế hai Thread Group chồng nhau — tải nền vẫn chạy tiếp sau khi cú sốc kết thúc.

### 2.5 Ngưỡng chịu đựng (chi tiết: `docs/05_endurance_threshold.md`)

Soak 150 VU × 15 phút: throughput **giữ nguyên** 173 req/s, nhưng hai chỉ số trôi đều dù tải hoàn toàn cố định:

- **Bộ nhớ:** sau khi tải ổn định, RSS vẫn tăng 106,4 → 129,3 MB = **1,76 MB/phút** = **1,05 KB mỗi vòng lặp**. Số handle đứng yên ở 359 → không rò rỉ file descriptor, đúng là rò rỉ heap từ `userCarts`.
- **Độ trễ:** avg 4,5 → 7,4 ms (**+64%**).

**Tách nguyên nhân suy giảm** bằng cách so p95 đầu/cuối theo từng endpoint:

| Endpoint | Hệ số trôi | Chạm DB? |
|---|---|---|
| `my-orders` | **×1,89** | Đọc `orders` — không index |
| `cart` | **×1,25** | **Không chạm DB** ← mức trôi nền |
| `checkout` | ×1,11 | Ghi đĩa |

Vì `cart` không chạm DB, ×1,25 chính là mức trôi nền do event loop và GC. Phần vượt lên của `my-orders` quy được về khối lượng dữ liệu. Đồng thời, việc `checkout` (ghi đĩa) trôi **ít nhất** bác bỏ giả thuyết "nút thắt là I/O ghi đĩa".

---

## 3. Task 2 — Phân tích bằng AI và săn lỗi diễn giải

Chi tiết đầy đủ, kèm lệnh kiểm chứng chạy được: `docs/06_ai_analysis_and_misinterpretation_hunt.md`.

Khi chỉ được đưa số liệu tóm tắt, AI đưa ra 6 nhận định — **5 trong số đó sai hoặc gây hiểu lầm**:

| # | AI nói | Giá trị đúng từ log thô | Mức |
|---|---|---|---|
| M1 | p95 = 641 ms | **442 ms** (ô Total dùng cửa sổ trượt 20.000 mẫu) | Trung bình |
| M2 | CPU 5,3% → không phải nút thắt | **106% của một core → chính là nút thắt** | **Nghiêm trọng** |
| M3 | 0% lỗi → chịu được 500 VU | p95 xấu đi **49 lần**; điểm gối ở ~350 VU | **Nghiêm trọng** |
| M4 | Rò rỉ bộ nhớ nghiêm trọng | Có rò rỉ nhưng chậm; suy ra từ kịch bản có tải biến thiên là sai phương pháp | Trung bình |
| M5 | Trần throughput 302 req/s | 211–621 req/s tuỳ khối lượng dữ liệu | Trung bình |
| M6 | *(bẫy chưa bung)* | Đếm dòng `.jtl` cho 155.696 thay vì 108.740 request thật | Trung bình |

**M2 là lỗi tai hại nhất** vì nó chỉ sai hướng điều tra. Bằng chứng bác bỏ mạnh nhất nằm ngay trong log thô: `POST /api/cart` **không chạm cơ sở dữ liệu lần nào** mà p95 vẫn lên 194 ms lúc Stress — độ trễ đó không thể là I/O, nó là thời gian xếp hàng chờ event loop.

### Phân loại đề xuất tối ưu — có kiểm chứng A/B thực nghiệm

Thiết kế: 40.000 đơn nạp sẵn, 60 VU × 60 s, **xen kẽ 3 lượt** A/B/A/B/A/B, ép `journal_mode` và xác nhận lại trước mỗi phép đo. Chi tiết: `docs/06` §4.

| Đề xuất | Phân loại | Số đo |
|---|---|---|
| Thêm index `orders(user_id)` | ✅ **Khả thi — đã kiểm chứng** | **+10,0%** throughput · `my-orders` p95 **−25,8%** |
| Bật SQLite WAL | ✅ **Khả thi — đã kiểm chứng** | **+11,5%** throughput · `checkout` p95 **−27,8%** |
| Node cluster | ⚠️ Khả thi **có điều kiện** | Phải chuyển `userCarts` ra khỏi RAM tiến trình trước, nếu không giỏ hàng sẽ mất ngẫu nhiên theo worker |
| Tăng `UV_THREADPOOL_SIZE` | ❌ **Đo được là không có tác dụng** | 374,6 → 377,1 req/s (chênh 0,7%, nằm trong nhiễu) |
| Connection pool cho SQLite | ❌ **Ảo tưởng** | SQLite là DB nhúng — không có server để pool kết nối tới |
| Redis cache cho sản phẩm | ⚠️ Đúng kỹ thuật, **sai ưu tiên** | Endpoint sản phẩm p95 13–14 ms, còn `checkout` 22 ms |

**Độ tin cậy của phép đo:** baseline lệch chỉ **1,0%** trong từng phiên, và hai phiên độc lập cho baseline khớp nhau trong **1%** (286,4–289,3 so với 286,2–289,7 req/s). Mức cải thiện đo được lớn hơn nhiễu này khoảng một bậc.

### Ba sai lầm về phương pháp đã mắc và sửa

Ghi lại vì chúng quyết định độ tin của bảng trên — và vì đây đúng là loại lỗi mà cổng kiểm tra tính hợp lệ ở Task 3 tồn tại để chặn:

1. **Chạy phân tích nặng trong lúc đang đo** → cùng cấu hình cho 300 req/s ở lần này và 375 req/s ở lần khác.
2. **`journal_mode=WAL` bền vững trong file DB** — sống sót qua `DROP TABLE` và qua restart, nên mọi lần "baseline" sau một cấu hình WAL thực chất **vẫn đang chạy WAL**. Phát hiện bằng cách kiểm tra file sidecar `database.sqlite-wal`. Đây là loại lỗi **làm phép so sánh A/B vô nghĩa mà không hề báo lỗi**: cả bốn cấu hình vẫn chạy, vẫn ra số, vẫn xếp hạng được.
3. **JMeter ghi tiếp vào file `.jtl` cũ** khi không xoá được → trộn dữ liệu hai lần chạy (một file có timestamp trải 5,15 giờ).

---

## 4. Task 3 — Đề xuất kiểm thử hiệu năng liên tục

Chi tiết + sơ đồ luồng: `docs/07_continuous_performance_testing.md`.

Mô hình ba tầng (smoke perf mỗi PR → load đầy đủ mỗi lần merge → soak/stress hằng đêm), với **ba điểm khác biệt sinh ra trực tiếp từ sai lầm đã mắc trong bài này**:

1. **Cổng kiểm tra tính hợp lệ của phép đo đặt TRƯỚC bước so ngưỡng.** Nếu thấy `BindException` hoặc CPU của máy sinh tải quá cao thì đánh dấu lần chạy là *không dùng được* và **tuyệt đối không báo động về hiệu năng**. Không có cổng này, lần calibration 100 VU đã bị pipeline báo cáo thành "SUT suy giảm nghiêm trọng".
2. **Reset dữ liệu là một phần của phép đo**, không phải việc dọn dẹp — có con số 2,17 lần để chứng minh.
3. **Pipeline tự giám sát chính nó**: tài nguyên của máy sinh tải được ghi lại ngang hàng với tài nguyên của SUT.

Phát hiện suy giảm dùng **baseline động** (50 lần chạy gần nhất trên `main`) với điều kiện kép: vượt 1,2 lần **và** vượt 3 độ lệch chuẩn, xác nhận 2 trong 3 lần lặp. Chi phí ước tính **~8,5 giờ runner/tuần**, kèm 4 hướng cắt giảm xếp theo hiệu quả.

---

## 5. Lỗi phát hiện được

Chi tiết: `docs/08_bug_report.md`. GitHub Issues: https://github.com/hungtmh/HW05-Testing/issues

**8 lỗi chức năng / bảo mật**, tất cả đã kiểm chứng qua API thật bằng `scripts/probe_bugs.ps1`:

| ID | Lỗi | Mức |
|---|---|---|
| BUG-02 | Mã giảm giá 10% làm số tiền phải trả **tăng gấp 10 lần** | Nghiêm trọng |
| BUG-03 | `GET /api/orders/:id` không xác thực → đọc được đơn của bất kỳ ai (IDOR) | Nghiêm trọng |
| BUG-04 | Người dùng thường tự nâng quyền lên admin bằng một request | Nghiêm trọng |
| BUG-08 | SQL injection ở `GET /api/products?search` | Nghiêm trọng |
| BUG-01 | Khoá tài khoản sau 2 lần sai thay vì 3 | Trung bình |
| BUG-06 | Kiểu `price` đổi theo tính chẵn lẻ của id | Trung bình |
| BUG-07 | Đơn đã huỷ vẫn chuyển sang "đã giao" được | Trung bình |
| BUG-05 | Sản phẩm không tồn tại trả HTTP 200 kèm body rỗng | Thấp |

**4 vấn đề hiệu năng:** thiếu index trên `orders.user_id`; rò rỉ `userCarts`; SQLite không bật WAL; Node đơn luồng không cluster.

---

## 6. Danh mục tài liệu

| Tài liệu | Nội dung |
|---|---|
| `docs/01_scope_and_endpoint_selection.md` | Khảo sát SUT, chọn 3 nhóm endpoint, probe lockout |
| `docs/02_ai_test_design_prompts.md` | Chuỗi 14 prompt điều khiển AI + calibration |
| `docs/03_human_review_and_fixes.md` | 7 lỗi của bản AI sinh ra và cách sửa |
| `docs/04_execution_evidence.md` | Cấu hình phần cứng, quy trình chạy, xử lý lockout |
| `docs/05_endurance_threshold.md` | Ngưỡng chịu đựng, rò rỉ bộ nhớ, tách nguyên nhân suy giảm |
| `docs/06_ai_analysis_and_misinterpretation_hunt.md` | **Task 2** — săn lỗi diễn giải + phân loại đề xuất tối ưu |
| `docs/07_continuous_performance_testing.md` | **Task 3** — mô hình CI hiệu năng + sơ đồ luồng |
| `docs/08_bug_report.md` | 8 lỗi + 4 vấn đề hiệu năng |
| `docs/09_demo_video_script.md` | Kịch bản thuyết minh video demo |
| `docs/AI_AUDIT_REPORT.md` | **Phụ lục bắt buộc** — nhật ký dùng AI |
| `docs/AI_CRITIQUE.md` | **Bắt buộc** — phê bình AI, 300 từ |
| `skill/performance-testing-jmeter/` | **Agent Skill** tái sử dụng được |
| `git_commit_log.txt` | Nhật ký commit |
