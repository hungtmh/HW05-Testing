---
name: performance-testing-jmeter
description: Thiết kế, chạy và phân tích performance test (Load / Stress / Spike / Soak) bằng Apache JMeter cho một nhóm endpoint REST API, kèm giám sát tài nguyên và kiểm tra tính hợp lệ của phép đo. Dùng khi cần đo hiệu năng một API mới, tìm ngưỡng chịu tải của một service, phân tích file .jtl, hoặc điều tra nghi vấn suy giảm hiệu năng. Kích hoạt với các từ khoá "performance test", "load test", "stress test", "spike test", "soak test", "kiểm thử hiệu năng", "JMeter", "file .jtl", "p95", "throughput", "tìm ngưỡng chịu tải".
---

# Performance testing một nhóm endpoint bằng JMeter

Skill này gói lại quy trình đã dùng trong HW05 để có thể áp lại cho **bất kỳ nhóm endpoint nào khác**. Điều làm nó khác một hướng dẫn JMeter thông thường: nó mã hoá sẵn **những cái bẫy đã thực sự mắc phải** và bắt kiểm chứng trước khi tin vào bất kỳ con số nào.

## Nguyên tắc bất di bất dịch

1. **Không tin mô tả, chỉ tin phép đo.** Tài liệu API và đề bài đều có thể sai. Đọc mã nguồn handler, rồi probe endpoint thật trước khi thiết kế.
2. **Không tin tham số do suy đoán.** Mọi số VU / ramp-up phải quy chiếu về trần công suất đo được, không phải số tròn cho đẹp.
3. **Nghi ngờ công cụ đo trước khi kết luận về SUT.** Tỉ lệ lỗi tăng vọt thường là lỗi client, không phải server sập.
4. **Không so sánh hai lần chạy trên hai trạng thái dữ liệu khác nhau.**

---

## Quy trình 8 bước

### Bước 1 — Khảo sát SUT (không bỏ qua)

Đọc mã nguồn handler của từng endpoint và ghi lại **thao tác DB thật sự**, không phải mô tả trong tài liệu. Cần trả lời được:

- Endpoint nào **ghi đĩa**? Đó gần như luôn là nút thắt.
- Có index cho các cột dùng trong `WHERE` / `ORDER BY` không?
- Chế độ journal của DB (SQLite có bật WAL không? PostgreSQL cấu hình `synchronous_commit` ra sao?)
- Có trạng thái nào giữ trong RAM và **không bao giờ được giải phóng** không? (nguồn rò rỉ)
- Mô hình đồng thời của runtime: single-thread (Node) hay thread pool? Trần thông lượng bị chặn bởi 1 core hay N core?
- Có logic **chặn tài khoản / rate limit** nào sẽ kích hoạt giữa lúc chạy test không?

> **Bẫy đã gặp:** một SUT được mô tả là "khoá sau 3 lần sai" thực tế cộng `login_attempts + 2` mỗi lần sai nên khoá ngay ở lần **thứ hai**. Chỉ probe thật mới phát hiện được.

### Bước 2 — Chọn 3 nhóm endpoint và ghép thành một workflow

Chọn theo **chi phí tài nguyên**, không theo mức độ phổ biến:

| Nhóm | Chọn endpoint nào | Vì sao |
|---|---|---|
| auth-heavy | Endpoint auth có ghi DB (cập nhật bộ đếm đăng nhập / phiên) | Vừa đọc vừa ghi trên mọi request |
| read-heavy | Một truy vấn **đắt** (LIKE / JOIN / không index) đặt cạnh một truy vấn **rẻ** (khoá chính) | Tạo cặp đối chứng trong cùng một lần chạy |
| transactional | Chuỗi ghi kết thúc bằng một lần **ghi đĩa** | Đây là nơi hệ thống serialize hoá |

Ghép thành một workflow end-to-end mà người dùng thật sẽ đi qua. Giữ **tỉ lệ request giữa ba nhóm cố định** ở mọi kịch bản, nếu không thì không so sánh được các kịch bản với nhau.

### Bước 3 — Dữ liệu hoá bằng CSV

Mỗi thứ thay đổi theo người dùng đều phải nằm trong CSV: credential, từ khoá tìm kiếm, payload đơn hàng. Cấu hình `recycle=true`, `shareMode=all`, `ignoreFirstLine=true`.

**Bắt buộc có script seed + verify:** tự đăng ký tài khoản test, rồi **đăng nhập thử vài tài khoản** và trả exit code khác 0 nếu hỏng. Nếu dữ liệu test sai thì mọi request sau đó hỏng dây chuyền và log gần như không đọc được.

### Bước 4 — Calibration trước khi chốt tham số

Chạy chính test plan đó với **think-time = 0** ở các mức 25 / 50 / 100 / 200 VU, mỗi mức 40 giây, trên **DB vừa reset**.

Đọc kết quả theo đúng thứ tự này:

1. **Error rate có tăng không?** Nếu có, **mở `.jtl` thô xem cột `responseCode`**. Nếu thấy `BindException`, `Connection reset`, `NoHttpResponseException` → đó là **client**, không phải server. Sửa client rồi đo lại. (Trên Windows: kiểm tra `netsh int ipv4 show dynamicport tcp` và số socket TIME_WAIT.)
2. **Throughput có đứng yên trong khi latency tăng tuyến tính theo VU không?** Đó là bão hoà. Trần = giá trị throughput đứng yên đó.
3. **Trần này ứng với bao nhiêu vòng lặp/giây?** Chia cho số sample mỗi vòng lặp.

Sau đó chọn tham số theo **phần trăm công suất có chủ đích**:

| Kịch bản | % công suất | Mục đích |
|---|---|---|
| Load | 15–30% | Đường cơ sở khoẻ mạnh |
| Stress | 120%+ | Chắc chắn chạm điểm gãy |
| Spike | 250%+ trong thời gian ngắn | Đo thời gian hồi phục |
| Soak | 30–40%, chạy 15 phút trở lên | Bộc lộ rò rỉ và suy giảm tích luỹ |

Công thức tải chào: `số VU / (tổng think-time + thời gian phản hồi ước tính của một vòng lặp)`.

### Bước 5 — Dựng test plan

Bắt buộc có:

- **Transaction Controller theo từng nhóm endpoint**, đặt `includeTimers=false` (nếu không, think-time bị cộng vào thời gian giao dịch).
- **JSON Extractor có default value** cho mọi biến trích xuất. Không có default thì lỗi trích xuất diễn ra âm thầm.
- **Assertion cho từng sampler**, và ở những bước có nhiều kiểu hỏng khác nhau thì dùng **JSR223 Assertion (Groovy, `cacheKey=true`) để gắn nhãn phân biệt**. Ví dụ: 401 = lỗi dữ liệu test, 403 = nhiễm trạng thái, 200-nhưng-thiếu-trường = lỗi thật của SUT. Cột `failureMessage` sau đó tự phân loại được.
- **`same_user_on_next_iteration=true`** khi API dùng token trong header (không dùng cookie phiên): giữ keep-alive, tránh cạn ephemeral port phía client.
- **Tham số hoá bằng `${__P(tên,mặc_định)}`** cho số VU, ramp-up, thời lượng, think-time — để calibration không phải sửa file.
- **Listener khác nhau cho từng kịch bản**, và View Results Tree thì **luôn** đặt `error_logging=true` (chỉ giữ mẫu lỗi), nếu không sẽ ăn hết heap ở tải cao.

Sinh các biến thể bằng **script từ một file nguồn duy nhất** — chép tay nhiều file `.jmx` là bảo đảm chúng sẽ lệch nhau.

### Bước 6 — Chạy có kỷ luật

Mỗi lần chạy **bắt buộc**:

1. **Reset SUT về trạng thái dữ liệu cố định.** Ghi lại số bản ghi trước/sau.
2. Xoá mọi trạng thái chặn (lockout / rate-limit) còn sót lại.
3. **Giám sát song song CPU + RAM của cả tiến trình SUT LẪN tiến trình sinh tải**, lấy mẫu mỗi 2 giây.
4. Chạy JMeter ở chế độ CLI (`-n`), xuất `.jtl` thô **và** HTML report (`-e -o`).

> **Đọc CPU cho đúng:** với runtime single-thread trên máy N nhân, CPU của tiến trình đó đo theo "% toàn hệ thống" sẽ có **trần là 100/N %**. Trên máy 20 luồng, "5% CPU" đã là **bão hoà hoàn toàn một core**. Nhìn số 5% rồi kết luận "server đang rảnh" là sai lầm phổ biến nhất khi đọc log tài nguyên.

### Bước 7 — Phân tích log thô (không chỉ nhìn HTML report)

Dùng `scripts/analyze_jtl.py`. Ba điều bắt buộc lưu ý:

1. **Sample của Transaction Controller cũng nằm trong `.jtl`.** Nếu cộng gộp, throughput bị thổi phồng theo tỉ lệ `(số request + số TC) / số request`. Luôn tách riêng.
2. **`elapsed` ≠ `Latency` ≠ `Connect`.** Lần lượt là: tổng thời gian phản hồi, thời gian tới byte đầu tiên, thời gian bắt tay TCP.
3. **Throughput tính trên cả thời gian ramp-up sẽ thấp hơn throughput ở trạng thái ổn định.** Luôn nói rõ đang trích số của cửa sổ nào.

Với stress test, gom theo cột `allThreads` để dựng lại đường cong latency-theo-độ-đồng-thời và tìm điểm gối.

### Bước 8 — Cổng kiểm tra tính hợp lệ trước khi kết luận

**Không được báo cáo bất kỳ kết luận nào về SUT** trước khi trả lời xong:

- [ ] Có `BindException` / `Connection reset` / `NoHttpResponse` trong `.jtl` không? → nếu có, phép đo hỏng, sửa client rồi đo lại.
- [ ] CPU của tiến trình sinh tải có gần bằng hoặc vượt CPU của SUT không? → nếu có, client là nút thắt.
- [ ] Bộ nhớ khả dụng của máy có tụt xuống mức nguy hiểm không?
- [ ] Trạng thái dữ liệu lúc bắt đầu có giống các lần chạy khác không?
- [ ] Ramp-up đã bị loại khỏi số liệu trạng thái ổn định chưa?
- [ ] Có cơ chế chặn nào (lockout / rate-limit) kích hoạt giữa chừng và bóp méo số liệu không?

---

## Các script kèm theo

| Script | Việc |
|---|---|
| `scripts/reset_sut.ps1` | Đưa SUT về trạng thái sạch, xác định; ghi PID ra file |
| `scripts/seed_users.js` | Nạp tài khoản test qua API và **verify đăng nhập** |
| `scripts/reset_lockout.js` | Gỡ khoá tài khoản bằng cách ghi thẳng DB |
| `scripts/run_scenario.ps1` | Điều phối trọn một lần chạy + giám sát tài nguyên song song |
| `scripts/gen_variants.ps1` | Sinh Stress/Spike/Soak từ một file nguồn duy nhất |
| `scripts/analyze_jtl.py` | Tính lại số liệu từ `.jtl` thô, tách sample TC, gom theo thời gian / độ đồng thời |

Khi áp cho SUT khác, chỉ cần sửa: đường dẫn SUT trong `reset_sut.ps1`, các endpoint trong file `.jmx` nguồn, và các file CSV. Toàn bộ phần kỷ luật đo đạc giữ nguyên.

## Cách áp cho một nhóm endpoint mới

1. Chạy Bước 1–2 để chọn endpoint và dựng workflow.
2. Sao chép file `.jmx` nguồn, thay các sampler bằng endpoint mới, giữ nguyên cấu trúc Transaction Controller / assertion / extractor.
3. Chạy Bước 4 (calibration) — **không được bỏ qua**, vì trần công suất khác nhau ở mỗi nhóm endpoint.
4. Chạy `gen_variants.ps1` để sinh 3 biến thể còn lại.
5. Chạy `run_scenario.ps1` cho từng kịch bản.
6. Chạy `analyze_jtl.py`, rồi đi qua checklist ở Bước 8 **trước khi** viết bất kỳ kết luận nào.
