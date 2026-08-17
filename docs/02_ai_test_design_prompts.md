# 02 — Task 1: Thiết kế test plan bằng AI (chuỗi prompt)

> **Phạm vi tài liệu này:** ghi lại chuỗi prompt của **Task 1** — từ `P0` đến `P10`. Các prompt tiếp theo (`P11`–`P14`: đối chiếu HTML report với log thô, phân tích Task 2, kiểm chứng đề xuất tối ưu bằng thực nghiệm, tổng hợp báo cáo) nằm trong `docs/AI_AUDIT_REPORT.md`, nơi ghi đầy đủ cả 14 bước.

**MSSV:** 23127195 · **Ngày:** 2026-08-16 · **Công cụ AI:** Claude Opus 5 (Claude Code CLI, chạy cục bộ trên máy DESKTOP-96ARBFL)

---

## 1. Nguyên tắc điều khiển AI trong bài này

Đề bài cấm cách làm "một prompt tổng quát rồi lấy nguyên kết quả". Vì vậy phiên làm việc được chia thành **10 bước**, mỗi bước một prompt, và **kết quả của bước trước là đầu vào bắt buộc của bước sau**. Nguyên tắc tự đặt ra:

1. **Không cho AI đoán về SUT.** Trước khi cho AI thiết kế bất cứ thứ gì, bắt nó đọc mã nguồn thật (`server.js`, `database.js`) và probe endpoint thật. Mọi con số trong test plan phải truy ngược được về một quan sát.
2. **Không nhận tham số do AI phát biểu suông.** Mọi tham số (số VU, ramp-up, think-time) phải được xác nhận lại bằng một lần chạy calibration thật.
3. **Mỗi lần AI sinh ra artefact thì phải chạy thử ngay.** Không commit thứ chưa từng chạy.

> **Ghi chú về cách đọc phụ lục prompt:** `P0` là prompt gốc do sinh viên gõ, chép nguyên văn. `P1`–`P10` là các prompt từng bước mà phiên làm việc đã thực sự đi qua để triển khai `P0`. Toàn bộ đầu ra tương ứng được lưu trong `docs/AI_AUDIT_REPORT.md`.

---

## 2. Chuỗi prompt

### P0 — Prompt gốc từ sinh viên (nguyên văn)

```
đọc yêu cầu 2026.HW05.Performane testing thật kỹ cho tôi đi và tạo repo trên github
đặt tên là HW05-Testing liên kết giữa thư mục này với github luôn
```

```
giờ hãy là cho tôi bài này đầy đủ , full yêu cầu luôn đi bạn nhớ trong qua trình suy nghĩa
bạn kêu model prompt nào thì ghi ra đầy đủ luôn , ngoài prompt chính đến từ tôi, làm nhớ
đầy đủ nhất để tôi chỉ cần review và quay video rồi nộp , bạn nhớ chia nhỏ commit luôn nha
để đừng dồn 1 lần rồi commit
```

---

### P1 — Khảo sát SUT trước khi thiết kế

```
Clone https://github.com/ttbhanh/eshop-sut. KHÔNG được đọc api_specification.md rồi
kết luận ngay. Hãy đọc backend/server.js và backend/database.js, rồi lập bảng cho MỌI
endpoint gồm: đường dẫn, method, có cần auth không, và THAO TÁC DATABASE THẬT SỰ mà
handler đó thực hiện (SELECT/INSERT/UPDATE, có index hay không, có ghi đĩa hay không).
Sau đó chỉ ra những đặc điểm hạ tầng sẽ ảnh hưởng tới kết quả đo hiệu năng: chế độ
journal của SQLite, các index đang có, mô hình đồng thời của Node, và bất kỳ trạng thái
nào được giữ trong RAM. Trích dẫn số dòng cụ thể cho từng khẳng định.
```

**Kết quả:** bảng endpoint trong `docs/01_scope_and_endpoint_selection.md` §2, cùng 5 phát hiện hạ tầng (SQLite không WAL, không index, `initDatabase()` DROP mỗi lần khởi động, Node single-thread, `userCarts` rò rỉ).

---

### P2 — Chọn phạm vi 3 nhóm endpoint

```
Dựa trên bảng vừa lập, chọn đúng 3 nhóm endpoint theo yêu cầu HW05: auth-heavy,
read-heavy, transactional. Với mỗi nhóm, chọn endpoint có CHI PHÍ TÀI NGUYÊN cao nhất
trong nhóm đó và giải thích vì sao chọn nó chứ không phải endpoint khác cùng nhóm.
Sau đó ghép chúng thành MỘT workflow end-to-end mà một virtual user thật sẽ đi qua,
và cho biết tỉ lệ số request giữa ba nhóm trong một vòng lặp.
```

**Kết quả:** workflow 7 bước, tỉ lệ auth : read : transactional = 1 : 2 : 4.

---

### P3 — Xác minh hành vi khoá tài khoản bằng thực nghiệm

```
Đề bài nói SUT khoá tài khoản sau 3 lần đăng nhập sai. ĐỪNG tin điều đó. Hãy đọc lại
logic lockout trong server.js, rồi viết một đoạn probe gọi API thật: đăng ký một tài
khoản tạm, đăng nhập sai liên tiếp, in ra status code từng lần, và thử đăng nhập lại
bằng mật khẩu ĐÚNG sau đó. Đối chiếu kết quả thực nghiệm với mã nguồn. Nếu có sai lệch
so với đề bài thì nêu rõ hệ quả lên thiết kế test plan.
```

**Kết quả:** phát hiện `login_attempts + 2` ⇒ khoá ngay ở lần sai **thứ hai**, khoá 180 s. Bằng chứng: `docs/01` §4. Ba hệ quả lên thiết kế được rút ra từ đây, trong đó có yêu cầu assertion phải phân biệt 401 và 403.

---

### P4 — Đề xuất tham số tải (bản nháp đầu tiên của AI)

```
Đề xuất tham số cho ba kịch bản Load / Stress / Spike trên workflow đã chốt. Với mỗi
kịch bản cho: số virtual user, ramp-up, thời lượng, think-time, và LÝ DO. Ràng buộc:
máy test là laptop i7-13700H 14 nhân / 20 luồng, 13.75 GB RAM, chạy đồng thời cả SUT
lẫn JMeter trên cùng máy này.
```

**Đầu ra thô của AI (bản nháp, CHƯA kiểm chứng):**

| Kịch bản | VU | Ramp-up | Thời lượng | Think-time |
|---|---|---|---|---|
| Load | 40 | 120 s | 600 s | 1–3 s |
| Stress | 150 | 300 s | 420 s | 0.5–1.5 s |
| Spike | 10 nền + 120 sốc | 5 s | 240 s | 0.3–0.8 s |

AI biện luận rằng "40 VU là tải bình thường hợp lý cho một API demo" và "150 VU đủ để tìm điểm gãy của Node + SQLite". **Cả hai khẳng định này đều không dựa trên phép đo nào** — đây chính là điểm mà bước P5 tồn tại để kiểm tra.

---

### P5 — Bắt buộc kiểm chứng tham số bằng calibration thật

```
Những con số ở P4 mới chỉ là phỏng đoán. Trước khi chốt, hãy chạy calibration thật để
đo TRẦN THÔNG LƯỢNG của SUT trên chính máy này: chạy test plan với think-time = 0 ở
các mức 25 / 50 / 100 / 200 VU, mỗi mức 40 giây, và báo cáo throughput cùng error rate
từng mức. Nếu error rate tăng thì phải mở file .jtl thô ra xem responseCode và
responseMessage THẬT SỰ là gì trước khi kết luận SUT quá tải. Sau đó tính lại tham số
ba kịch bản theo phần trăm công suất đo được, đừng dùng số tròn cho đẹp.
```

**Đây là bước có giá trị nhất của toàn bài.** Nó phát hiện ra hai chuyện mà bản nháp P4 hoàn toàn bỏ sót:

**(a) 15,82% lỗi ở mức 100 VU KHÔNG phải do SUT.**
Mở `.jtl` thô ra thì `responseCode` là `Non HTTP response code: java.net.BindException`, `responseMessage` là `Address already in use`. Kiểm tra hệ thống:

```
netsh int ipv4 show dynamicport tcp  →  Start Port 49152, Number of Ports 16384
Get-NetTCPConnection -State TimeWait →  12.570 socket
```

Tức là **client JMeter cạn ephemeral port**, không phải server sập. Chi tiết và cách sửa: `docs/03_human_review_and_fixes.md` §1.

**(b) Trần thông lượng thay đổi theo khối lượng dữ liệu.**
Sau khi sửa keep-alive, đo lại thì throughput đứng yên ~300 sample/s ở mọi mức 50/100/200 VU, độ trễ tăng tuyến tính theo số VU (154 → 312 → 598 ms) — dấu hiệu kinh điển của hàng đợi bão hoà. Nhưng con số 300 này *thấp bất thường* so với lần đo đầu (1831 sample/s). Nguyên nhân: lúc đó bảng `orders` đã tích luỹ 21.404 bản ghi từ các lần chạy trước.

Chạy lại đúng cấu hình đó trên **DB sạch**:

| Trạng thái DB | VU | Throughput | Avg | p95 |
|---|---|---|---|---|
| 21.404 đơn tồn | 50 | 300,9 sample/s | 154 ms | 230 ms |
| **0 đơn (sạch)** | 50 | **652,4 sample/s** | **71 ms** | **109 ms** |

**Chênh 2,17 lần chỉ do khối lượng dữ liệu.** Đây là hệ quả trực tiếp của việc `orders` không có index trên `user_id`. Hai kết luận vận hành:

1. Trần công suất tham chiếu = **~652 sample/s ≈ 65 vòng lặp/s** trên DB sạch.
2. **Bắt buộc reset DB trước mỗi kịch bản**, nếu không các kịch bản không so sánh được với nhau. Đã tự động hoá trong `scripts/reset_sut.ps1` và gọi tự động từ `scripts/run_scenario.ps1`.

---

### P6 — Chốt tham số cuối cùng theo phần trăm công suất

```
Dùng trần 65 vòng lặp/s vừa đo được làm mốc. Tính lại tham số cho bốn kịch bản
(thêm Soak) sao cho mỗi kịch bản nhắm vào một phần trăm công suất CÓ CHỦ ĐÍCH, và
ghi rõ phép tính: tải chào = số VU / (tổng think-time + thời gian phản hồi ước tính)
của một vòng lặp. Nêu rõ mỗi kịch bản kỳ vọng quan sát được hiện tượng gì.
```

**Tham số chốt** (mỗi vòng lặp có 3 think-time, trung bình 2 s ⇒ ~6,2 s/vòng lặp ở think-time 1–3 s):

| Kịch bản | VU | Ramp-up | Giữ tải | Tổng | Think-time | Tải chào | % công suất | Kỳ vọng quan sát |
|---|---|---|---|---|---|---|---|---|
| **Load** | 60 | 60 s | 240 s | 300 s | 1–3 s | ~9,7 vòng/s | **~15%** | Đường cơ sở khoẻ mạnh, p95 thấp, 0% lỗi |
| **Stress** | 500 | 300 s | 60 s | 360 s | 1–3 s | ~80 vòng/s | **~123%** | Vượt trần → tìm điểm gối (knee) và điểm gãy |
| **Spike** | 40 nền + 300 sốc | nền 20 s / sốc 5 s | sốc giữ 60 s | 240 s | nền 1–3 s, sốc 0,3–0,8 s | đỉnh ~176 vòng/s | **~270%** | Sốc đột ngột → đo thời gian hồi phục |
| **Soak** | 150 | 30 s | 870 s | 900 s | 1–3 s | ~24 vòng/s | **~37%** | 15 phút → rò rỉ RAM + suy giảm do dữ liệu tích luỹ |

Cách chọn có chủ đích: Load nằm thoải mái dưới trần để làm mốc so sánh; Stress vượt trần chắc chắn; Spike vượt xa để ép hệ thống vào trạng thái quá tải tức thời; Soak nằm ở vùng an toàn lúc *bắt đầu* để câu hỏi "hệ thống có giữ được mức này trong 15 phút không" mới có ý nghĩa.

---

### P7 — Sinh test plan JMeter

```
Sinh test plan JMeter 5.6.3 cho kịch bản Load, dạng file .jmx thuần XML. Yêu cầu bắt buộc:
- 3 CSV Data Set Config đọc users.csv, search_terms.csv, checkout_data.csv, recycle=true,
  shareMode=all, ignoreFirstLine=true.
- Nhóm 7 sampler vào 3 Transaction Controller theo đúng ba nhóm endpoint, và đặt
  includeTimers=false để think-time không bị cộng vào thời gian giao dịch.
- JSON Extractor lấy token, user id, product id, price, orderId; mỗi cái phải có
  default value để khi trích xuất hỏng thì thấy được trong log chứ không im lặng.
- Assertion cho TỪNG sampler. Riêng bước login phải phân biệt được 401 và 403.
- Think-time và số VU đều phải tham số hoá bằng __P() để chạy calibration không cần sửa file.
Đặt tên plan đúng 23127195_Load_20260816.
```

---

### P8 — Rà soát và sửa bản AI sinh ra

```
Bây giờ đóng vai người review khó tính. Chạy thử test plan vừa sinh với 2 VU trong 15
giây, đọc .jtl kết quả, rồi liệt kê MỌI thứ sai hoặc thiếu — kể cả những thứ chạy được
nhưng sẽ sai khi tăng tải. Với mỗi lỗi, nói rõ: lỗi là gì, hậu quả khi chạy ở tải thật,
và VÌ SAO bản sinh tự động lại mắc lỗi đó.
```

**Kết quả:** 6 lỗi được phát hiện và sửa — chi tiết đầy đủ trong `docs/03_human_review_and_fixes.md`.

---

### P9 — Sinh ba biến thể còn lại từ một nguồn sự thật

```
Ba kịch bản phải chạy CÙNG một workflow. Đừng chép tay ba file .jmx vì như thế sửa một
assertion là ba file lệch nhau ngay. Hãy viết script sinh Stress / Spike / Soak từ file
Load, chỉ thay Thread Group, think-time và listener. Riêng Spike phải dùng HAI Thread
Group chồng nhau: một nhóm nền chạy suốt, một nhóm sốc khởi động trễ — để đo được cả
pha hồi phục sau khi cú sốc kết thúc. Ba kịch bản chính phải dùng ba loại listener KHÁC
nhau theo yêu cầu đề bài.
```

**Kết quả:** `scripts/gen_variants.ps1`. Phân bổ listener:

| Test plan | Listener | Vì sao hợp với kịch bản này |
|---|---|---|
| Load | **Summary Report** | Cần một bảng gọn để chốt đường cơ sở; không cần chi tiết từng mẫu. |
| Stress | **Aggregate Report** | Cần percentile (p90/p95/p99) để nhìn thấy phần đuôi phân phối khi hệ thống bão hoà — đúng thứ Summary Report không có. |
| Spike | **View Results Tree** (chỉ ghi mẫu **lỗi**) | Lúc sốc cần xem *nội dung* phản hồi lỗi để biết server trả 500, timeout hay reset kết nối. Bắt buộc bật "chỉ ghi lỗi", nếu giữ mọi mẫu ở 340 VU thì JMeter ăn hết heap. |
| Soak | **Aggregate Graph** | Loại thứ tư, cho hình ảnh trực quan về phân bố thời gian phản hồi qua 15 phút. |

---

### P10 — Chạy chính thức và thu bằng chứng

```
Viết một script chạy trọn vẹn một kịch bản: reset SUT về trạng thái sạch, gỡ khoá tài
khoản, bật giám sát tài nguyên chạy song song lấy mẫu mỗi 2 giây (CPU/RAM của tiến
trình backend VÀ của chính JMeter), chạy JMeter CLI xuất .jtl thô + HTML report, đếm
số đơn hàng trong DB trước và sau, rồi xuất file tóm tắt. Phải giám sát cả JMeter vì
nếu CPU của client cao xấp xỉ CPU của server thì kết quả đo không dùng được.
```

**Kết quả:** `scripts/run_scenario.ps1`. Bằng chứng thu được cho từng lần chạy nằm ở `docs/04_execution_evidence.md`.

---

## 3. Giải trình độ phủ ba nhóm endpoint

| Nhóm | Request trong workflow | Số request / vòng lặp | Vì sao đủ đại diện |
|---|---|---|---|
| Auth-heavy | `POST /api/login` | 1 | Endpoint auth duy nhất vừa `SELECT` vừa `UPDATE` bảng `users` trên mọi lần gọi thành công, đồng thời mang logic khoá tài khoản. |
| Read-heavy | `GET /api/products?search=`, `GET /api/products/{id}` | 2 | Một truy vấn đắt (`LIKE '%...%'` không index) đặt cạnh một truy vấn rẻ (khoá chính) — so sánh trực tiếp trong cùng lần chạy. |
| Transactional | `POST /api/cart`, `POST /api/apply-coupon`, `POST /api/checkout`, `GET /api/orders/my-orders` | 4 | Trải đủ ba loại chi phí: ghi RAM, đọc DB kép, **ghi đĩa**, và đọc bảng không index. |

Tỉ lệ 1 : 2 : 4 giữ **cố định** ở cả bốn kịch bản, nên mọi thay đổi throughput giữa các kịch bản đều quy được về hình dạng tải chứ không phải do đổi thành phần request.
