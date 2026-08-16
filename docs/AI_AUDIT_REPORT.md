# AI Audit Report — HW05 Performance Testing

**MSSV:** 23127195 · **Ngày:** 2026-08-16 · **Máy thực hiện:** `DESKTOP-96ARBFL`

---

## Tuyên bố

> **I use AI tools for the following tasks.**

**Công cụ AI đã dùng:** Claude Opus 5 (model id `claude-opus-5`), truy cập qua **Claude Code CLI** chạy cục bộ trên máy `DESKTOP-96ARBFL`, tích hợp trong VS Code. Không dùng công cụ AI nào khác.

**Công cụ không phải AI đã dùng:**

| Công cụ | Phiên bản | Việc |
|---|---|---|
| Apache JMeter | 5.6.3 | Sinh tải, xuất `.jtl` và HTML report |
| OpenJDK (Temurin) | 17.0.17 | Chạy JMeter |
| Node.js | 22.20.0 | Chạy SUT, chạy script seed / reset |
| Python | 3.12.10 | `scripts/analyze_jtl.py` |
| Windows Task Manager + PowerShell counters | — | Giám sát tài nguyên |
| Git / GitHub | 2.51.0 | Quản lý phiên bản, lưu bằng chứng |

---

## Phương pháp ghi nhật ký — đọc kỹ phần này

Toàn bộ bài làm diễn ra trong **một phiên Claude Code liên tục** ngày 2026-08-16, từ khoảng **20:35** đến **22:1x** (giờ ICT). Vì thế nhật ký dưới đây phân biệt rõ hai loại prompt:

- **`P0`** — prompt do **sinh viên gõ trực tiếp**, chép **nguyên văn**, không sửa chính tả.
- **`P1`–`P14`** — các **prompt từng bước** dùng để triển khai `P0`. Đây là các chỉ thị thực sự đã điều khiển từng giai đoạn của phiên làm việc, ghi lại nguyên văn nội dung chỉ thị.

Phần **"Đầu ra của AI"** ghi lại **kết quả thực tế** của từng bước: artefact đã sinh ra, con số đã đo được, và kết luận đã rút ra. Mọi con số trong nhật ký này đều truy ngược được về một file trong `results/`, và mọi file đó đều đã commit vào Git nên có dấu thời gian độc lập.

**Điều cần nói thẳng:** phần phân tích của Task 2 và phần phê bình phân tích đó đều sinh ra trong cùng một phiên, cùng một model. Vì vậy không thể coi đó là hai nguồn độc lập nhau. Cái **thực sự** làm cho phần "săn lỗi diễn giải" có giá trị không phải là chuyện hai bên độc lập, mà là **mọi lỗi được nêu đều kèm một lệnh kiểm chứng chạy được trên file `.jtl` thô** — người chấm chạy lại lệnh đó là ra ngay đúng/sai, không cần tin lời ai.

---

## Nhật ký từng bước

### P0 — Prompt gốc từ sinh viên

**Thời điểm:** 2026-08-16, ~20:35 và ~20:48 ICT

**Prompt (nguyên văn, lần 1):**
```
đọc yêu cầu 2026.HW05.Performane testing thật kỹ cho tôi đi và tạo repo trên github
đặt tên là HW05-Testing liên kết giữa thư mục này với github luôn
```

**Prompt (nguyên văn, lần 2):**
```
giờ hãy là cho tôi bài này đầy đủ , full yêu cầu luôn đi bạn nhớ trong qua trình suy nghĩa
bạn kêu model prompt nào thì ghi ra đầy đủ luôn , ngoài prompt chính đến từ tôi, làm nhớ
đầy đủ nhất để tôi chỉ cần review và quay video rồi nộp , bạn nhớ chia nhỏ commit luôn nha
để đừng dồn 1 lần rồi commit
```

**Đầu ra:** Đọc trọn 9 trang PDF đề bài, tạo repo public `hungtmh/HW05-Testing`, `git init` thư mục cục bộ, liên kết remote, commit đầu tiên. Sau đó lập kế hoạch triển khai toàn bộ 3 task + Agent Skill.

---

### P1 — Khảo sát SUT

**Thời điểm:** ~20:40 ICT

**Prompt:**
```
Clone https://github.com/ttbhanh/eshop-sut. KHÔNG được đọc api_specification.md rồi kết
luận ngay. Hãy đọc backend/server.js và backend/database.js, rồi lập bảng cho MỌI endpoint
gồm: đường dẫn, method, có cần auth không, và THAO TÁC DATABASE THẬT SỰ mà handler đó thực
hiện. Sau đó chỉ ra những đặc điểm hạ tầng sẽ ảnh hưởng tới kết quả đo hiệu năng. Trích dẫn
số dòng cụ thể cho từng khẳng định.
```

**Đầu ra:** Bảng 10 endpoint (`docs/01` §2) và 5 phát hiện hạ tầng:

1. SQLite journal mode `delete`, **không bật WAL** → mỗi `INSERT orders` khoá toàn file DB.
2. **Không có index nào** ngoài PRIMARY KEY (`database.js:50-81`) → `users.email` và `orders.user_id` đều full-scan.
3. `initDatabase()` được gọi ở **mức module** (`database.js:117`) → mỗi lần khởi động server đều `DROP TABLE` toàn bộ.
4. Node **đơn luồng**, không cluster → trần thông lượng là 1 core, không phải 14 core của máy.
5. `userCarts` (`server.js:14`) giữ giỏ hàng trong RAM và **không bao giờ được xoá sau checkout** → rò rỉ tuyến tính.

---

### P2 — Chọn phạm vi 3 nhóm endpoint

**Thời điểm:** ~20:42 ICT

**Prompt:**
```
Dựa trên bảng vừa lập, chọn đúng 3 nhóm endpoint theo yêu cầu HW05: auth-heavy, read-heavy,
transactional. Với mỗi nhóm, chọn endpoint có CHI PHÍ TÀI NGUYÊN cao nhất trong nhóm đó và
giải thích vì sao chọn nó chứ không phải endpoint khác cùng nhóm. Sau đó ghép chúng thành
MỘT workflow end-to-end, và cho biết tỉ lệ số request giữa ba nhóm trong một vòng lặp.
```

**Đầu ra:** Workflow 7 bước (`docs/01` §3), tỉ lệ auth : read : transactional = **1 : 2 : 4**.

---

### P3 — Probe hành vi khoá tài khoản

**Thời điểm:** ~20:44 ICT

**Prompt:**
```
Đề bài nói SUT khoá tài khoản sau 3 lần đăng nhập sai. ĐỪNG tin điều đó. Đọc lại logic
lockout trong server.js, rồi viết đoạn probe gọi API thật: đăng ký tài khoản tạm, đăng nhập
sai liên tiếp, in status code từng lần, rồi thử đăng nhập lại bằng mật khẩu ĐÚNG. Đối chiếu
kết quả với mã nguồn và nêu hệ quả lên thiết kế test plan.
```

**Đầu ra:** Kết quả probe thật:
```
Fail attempt 1: HTTP 401
Fail attempt 2: HTTP 401     <- tai khoan da bi khoa tai day
Fail attempt 3: HTTP 403
Dang nhap bang MAT KHAU DUNG: HTTP 403
```
Kết luận: `server.js:54` cộng `login_attempts + 2`, ngưỡng `>= 3` → khoá ở lần sai **thứ hai**, khoá **180 giây**. **Đề bài mô tả sai.**

---

### P4 — Đề xuất tham số (bản nháp chưa kiểm chứng)

**Thời điểm:** ~20:52 ICT

**Prompt:**
```
Đề xuất tham số cho ba kịch bản Load / Stress / Spike trên workflow đã chốt. Với mỗi kịch
bản cho: số virtual user, ramp-up, thời lượng, think-time, và LÝ DO. Ràng buộc: máy test là
laptop i7-13700H 14 nhân / 20 luồng, 13.75 GB RAM, chạy đồng thời cả SUT lẫn JMeter.
```

**Đầu ra (bản nháp):** Load 40 VU / ramp 120 s / 600 s; Stress 150 VU / ramp 300 s; Spike 10 nền + 120 sốc. Lý do đưa ra mang tính định tính ("40 VU là tải bình thường hợp lý"), **không dựa trên phép đo nào**. Bước P5 tồn tại chính là để bác bỏ bản nháp này.

---

### P5 — Calibration bắt buộc ⭐ bước quan trọng nhất

**Thời điểm:** ~20:55–21:05 ICT

**Prompt:**
```
Những con số ở P4 mới chỉ là phỏng đoán. Trước khi chốt, hãy chạy calibration thật để đo
TRẦN THÔNG LƯỢNG của SUT trên chính máy này: chạy test plan với think-time = 0 ở các mức
25 / 50 / 100 / 200 VU, mỗi mức 40 giây, và báo cáo throughput cùng error rate từng mức.
Nếu error rate tăng thì phải mở file .jtl thô ra xem responseCode và responseMessage THẬT SỰ
là gì trước khi kết luận SUT quá tải. Sau đó tính lại tham số ba kịch bản theo phần trăm
công suất đo được, đừng dùng số tròn cho đẹp.
```

**Đầu ra — hai phát hiện lật ngược bản nháp P4:**

**(a) 15,82% lỗi ở 100 VU không phải do SUT.**
```
responseCode    = Non HTTP response code: java.net.BindException
responseMessage = Address already in use: connect

netsh int ipv4 show dynamicport tcp  -> Start 49152, so cong 16384
(Get-NetTCPConnection -State TimeWait).Count -> 12570
```
→ Client JMeter cạn ephemeral port. Sửa bằng `same_user_on_next_iteration=true`. Sau khi sửa: **0,00% lỗi** ở cả 50 / 100 / 200 VU.

**(b) Trần thông lượng phụ thuộc khối lượng dữ liệu.**

| Trạng thái DB | VU | Throughput | Avg | p95 |
|---|---|---|---|---|
| 21.404 đơn tồn | 50 | 300,9 sample/s | 154 ms | 230 ms |
| 0 đơn (sạch) | 50 | **652,4 sample/s** | **71 ms** | **109 ms** |

→ Chênh **2,17 lần** chỉ do dữ liệu. Bắt buộc reset DB trước mỗi kịch bản.

---

### P6 — Chốt tham số theo phần trăm công suất

**Thời điểm:** ~21:06 ICT

**Prompt:**
```
Dùng trần 65 vòng lặp/s vừa đo được làm mốc. Tính lại tham số cho bốn kịch bản (thêm Soak)
sao cho mỗi kịch bản nhắm vào một phần trăm công suất CÓ CHỦ ĐÍCH, và ghi rõ phép tính.
Nêu rõ mỗi kịch bản kỳ vọng quan sát được hiện tượng gì.
```

**Đầu ra:** Load 60 VU (~15% công suất), Stress 500 VU (~123%), Spike 40 + 300 (~270% lúc đỉnh), Soak 150 VU (~37%). Bảng đầy đủ ở `docs/02` §P6.

---

### P7 — Sinh test plan JMeter

**Thời điểm:** ~21:08 ICT

**Prompt:**
```
Sinh test plan JMeter 5.6.3 cho kịch bản Load, dạng file .jmx thuần XML. Bắt buộc:
3 CSV Data Set Config; nhóm 7 sampler vào 3 Transaction Controller với includeTimers=false;
JSON Extractor có default value cho mọi biến; Assertion cho TỪNG sampler và bước login phải
phân biệt 401 với 403; tham số hoá bằng __P() cho VU / ramp-up / think-time.
Đặt tên plan đúng 23127195_Load_20260816.
```

**Đầu ra:** `testplans/23127195_Load_20260816.jmx`. Chạy thử 2 VU × 15 s: 166 mẫu, **0 lỗi**, đủ 7 sampler + 3 transaction controller.

---

### P8 — Rà soát và sửa

**Thời điểm:** ~21:10 ICT

**Prompt:**
```
Bây giờ đóng vai người review khó tính. Chạy thử test plan vừa sinh, đọc .jtl kết quả, rồi
liệt kê MỌI thứ sai hoặc thiếu — kể cả những thứ chạy được nhưng sẽ sai khi tăng tải. Với
mỗi lỗi, nói rõ: lỗi là gì, hậu quả khi chạy ở tải thật, và VÌ SAO bản sinh tự động lại mắc.
```

**Đầu ra:** 7 lỗi, đầy đủ ở `docs/03`. Nghiêm trọng nhất: ephemeral port, thiếu reset môi trường, ngưỡng lockout sai.

---

### P9 — Sinh ba biến thể

**Thời điểm:** ~21:12 ICT

**Prompt:**
```
Ba kịch bản phải chạy CÙNG một workflow. Đừng chép tay ba file .jmx. Viết script sinh
Stress / Spike / Soak từ file Load, chỉ thay Thread Group, think-time và listener. Riêng
Spike phải dùng HAI Thread Group chồng nhau: một nhóm nền chạy suốt, một nhóm sốc khởi động
trễ — để đo được cả pha hồi phục. Ba kịch bản chính dùng ba loại listener KHÁC nhau.
```

**Đầu ra:** `scripts/gen_variants.ps1` + 3 file `.jmx`. Kiểm tra XML hợp lệ, Spike có đúng 2 Thread Group. Smoke test xác nhận đúng 3 pha: 3 VU → 11 VU → 3 VU.

---

### P10 — Chạy chính thức và thu bằng chứng

**Thời điểm:** ~21:13–21:49 ICT

**Prompt:**
```
Viết script chạy trọn một kịch bản: reset SUT về trạng thái sạch, gỡ khoá tài khoản, bật
giám sát tài nguyên song song lấy mẫu mỗi 2 giây (CPU/RAM của backend VÀ của chính JMeter),
chạy JMeter CLI xuất .jtl thô + HTML report, đếm số đơn trong DB trước và sau, xuất file
tóm tắt. Phải giám sát cả JMeter vì nếu CPU client cao xấp xỉ CPU server thì kết quả không
dùng được.
```

**Đầu ra:** `scripts/run_scenario.ps1` và 4 lần chạy chính thức:

| Kịch bản | Bắt đầu | Request HTTP | Lỗi | p95 | Ghi chú |
|---|---|---|---|---|---|
| Load | 21:14:32 | 18.749 | 0 | 9 ms | Đường cơ sở |
| Stress | 21:21:00 | 108.740 | 0 | 442 ms | Điểm gối ~350 VU |
| Spike | 21:28:49 | 43.363 | 0 | 513 ms | Hồi phục 10–15 s |
| Soak | 21:33:34 | *(xem `docs/05`)* | | | 15 phút |

---

### P11 — Đối chiếu HTML report với log thô

**Thời điểm:** ~21:32 ICT

**Prompt:**
```
Đừng tin ngay HTML report. Hãy đối chiếu từng con số trong statistics.json với kết quả tính
lại từ file .jtl thô. Nếu có chỗ nào lệch thì phải tìm ra CHÍNH XÁC vì sao lệch, đừng đoán.
```

**Đầu ra:** Hai chênh lệch, đều đã truy đến tận gốc:

1. File `.jtl` thô của Stress có **155.696** bản ghi, nhưng chỉ **108.740** là request HTTP; 46.956 còn lại là Transaction Controller. Console và HTML report **đều** báo 108.740 → JMeter không sai, cái bẫy chỉ bung khi tự phân tích file thô.
2. Ô Total của HTML report báo **p95 = 641 ms**, trong khi tính lại trên toàn bộ 108.740 mẫu ra **442 ms**. Truy ra nguyên nhân bằng thực nghiệm:

```
p95 toan bo (108740 mau)      = 442 ms
p95 cua 20000 mau CUOI        = 641 ms   <-- khop chinh xac voi HTML report
p95 cua 50000 mau CUOI        = 546 ms
p95 cua 100000 mau CUOI       = 453 ms
```
→ Ô Total dùng **cửa sổ trượt 20.000 mẫu gần nhất**, không phải toàn bộ lần chạy. Với test ramp tăng dần, đó đúng là nhóm mẫu chậm nhất. Điều này cũng giải thích vì sao ở kịch bản Load (18.749 mẫu, **nhỏ hơn 20.000**) thì HTML report khớp tuyệt đối với log thô.

---

### P12 — Phân tích và săn lỗi diễn giải (Task 2)

**Thời điểm:** ~21:50 ICT

**Prompt (pha 1 — đầu vào bị giới hạn có chủ đích):**
```
Đây là kết quả performance test của tôi. Hãy phân tích và đề xuất ngưỡng hiệu năng, đồng
thời đề xuất các hướng tối ưu.
[đính kèm: ô Total của statistics.json, dòng summary cuối của console, file run_summary.txt]
```

**Prompt (pha 2 — kiểm chứng):**
```
Bây giờ mở file .jtl THÔ ra và kiểm chứng lại TỪNG khẳng định ở pha 1. Với mỗi chỗ sai,
trích giá trị ĐÚNG từ log thô và kèm lệnh chạy được để người chấm tự kiểm tra. Sau đó phân
loại từng đề xuất tối ưu là KHẢ THI hay ẢO TƯỞNG, kèm lý do dựa trên mã nguồn SUT.
```

**Đầu ra:** `docs/06_ai_analysis_and_misinterpretation_hunt.md`.

---

### P13 — Kiểm chứng đề xuất tối ưu bằng thực nghiệm

**Thời điểm:** ~22:0x ICT

**Prompt:**
```
Đừng chỉ phân loại đề xuất tối ưu trên giấy. Hãy thực nghiệm ít nhất hai đề xuất: thêm index
cho orders(user_id) và bật SQLite WAL. Thiết kế phép đo A/B có kiểm soát trên cùng khối lượng
dữ liệu, rồi báo cáo con số trước/sau.
```

**Đầu ra:** kết quả A/B trong `docs/06` §4.

---

### P14 — Tổng hợp báo cáo và hoàn tất repo

**Thời điểm:** ~22:1x ICT

**Prompt:**
```
Tổng hợp báo cáo chính, README có bảng tự đánh giá và tóm tắt kết quả, xuất git commit log
ra file text, và rà lại toàn bộ danh mục nộp bài theo mục 14 của đề để chắc chắn không thiếu
tài liệu nào.
```

**Đầu ra:** `docs/00_MAIN_REPORT.md`, `README.md`, `git_commit_log.txt`, bảng đối chiếu yêu cầu.

---

## Đánh giá mức độ đóng góp

| Phần việc | AI làm | Người làm | Ghi chú |
|---|---|---|---|
| Đọc mã nguồn SUT, lập bảng endpoint | Chủ yếu | Kiểm tra lại số dòng trích dẫn | AI làm tốt, chính xác |
| Thiết kế workflow E2E | Chủ yếu | Chốt lựa chọn | Hợp lý ngay từ đầu |
| **Chọn tham số tải** | Đề xuất **sai** ở P4 | **Bác bỏ và đo lại ở P5** | Đóng góp lớn nhất của con người |
| Sinh XML của `.jmx` | Toàn bộ | Rà soát, sửa 7 lỗi | Phần AI mạnh nhất |
| **Chẩn đoán BindException** | Không tự nghĩ ra | **Yêu cầu mở log thô** | Nếu không hỏi, AI đã kết luận sai |
| Chạy test, thu bằng chứng | Tự động hoá | Xác nhận kết quả | |
| **Đối chiếu HTML report với log thô** | Thực hiện | **Yêu cầu và ép truy đến gốc** | Ra phát hiện cửa sổ 20.000 mẫu |
| Viết tài liệu | Chủ yếu | Rà soát nội dung | |

**Sinh viên chịu trách nhiệm hoàn toàn** về tính đúng đắn của toàn bộ test plan, số liệu và kết luận trong bài nộp này.
