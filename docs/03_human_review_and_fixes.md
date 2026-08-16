# 03 — Task 1: Rà soát của con người và các lỗi đã sửa

**MSSV:** 23127195 · **Ngày:** 2026-08-16

Đề bài yêu cầu nêu rõ **AI làm sai hoặc bỏ sót cái gì**, và **vì sao** nó bỏ sót. Dưới đây là 7 lỗi thực tế phát hiện được khi rà soát bản test plan do AI sinh ra, xếp theo mức nghiêm trọng. Mỗi lỗi đều kèm bằng chứng đo được, không phải nhận định chung chung.

Tôi chịu trách nhiệm về bản test plan cuối cùng.

---

## Lỗi 1 — Nghiêm trọng: client cạn ephemeral port, bị đọc nhầm thành "SUT quá tải"

**Bản AI sinh ra:** `ThreadGroup.same_user_on_next_iteration = false`.

**Triệu chứng:** calibration ở mức 100 VU cho **15,82% lỗi**. Nếu dừng ở đây thì kết luận tự nhiên là "SUT gãy ở khoảng 100 VU".

**Kết luận đó SAI.** Mở `.jtl` thô ra, cột `responseCode` không phải mã HTTP:

```
Non HTTP response code: java.net.BindException
Non HTTP response message: Address already in use: connect
```

Kiểm tra ở mức hệ điều hành ngay sau lần chạy:

```
netsh int ipv4 show dynamicport tcp
    Start Port      : 49152
    Number of Ports : 16384

(Get-NetTCPConnection -State TimeWait).Count
    12570
```

12.570 socket nằm ở TIME_WAIT trên tổng 16.384 port khả dụng — **máy chạy JMeter hết cổng để mở kết nối mới**. Lỗi nằm ở phía sinh tải, không phải phía SUT.

**Nguyên nhân gốc:** khi `same_user_on_next_iteration = false`, JMeter coi mỗi vòng lặp là một "người dùng mới" và đặt lại trạng thái HTTP client, nên kết nối keep-alive không được dùng lại qua các vòng lặp. Ở tốc độ hơn 1.000 request/giây, mỗi vòng lặp mở kết nối TCP mới → cổng bị đốt nhanh hơn tốc độ TIME_WAIT giải phóng.

**Cách sửa:** đặt `same_user_on_next_iteration = true`. Việc này hợp lệ về mặt mô hình hoá ở đây vì SUT dùng **JWT trong header**, không dùng cookie phiên — nên "dùng lại người dùng" không hề rò rỉ trạng thái phiên giữa các vòng lặp; nó chỉ giữ lại kết nối TCP, đúng như trình duyệt thật vẫn làm.

**Kết quả sau khi sửa** (cùng máy, cùng test plan, think-time = 0):

| VU | Trước khi sửa | Sau khi sửa |
|---|---|---|
| 50 | — | 300,9 sample/s · **0,00% lỗi** |
| 100 | 1193 sample/s · **15,82% lỗi** | 297,0 sample/s · **0,00% lỗi** |
| 200 | — | 309,7 sample/s · **0,00% lỗi** |

**Vì sao AI bỏ sót:** đây là ràng buộc ở tầng hệ điều hành của **máy sinh tải**, hoàn toàn vô hình trong bản thân file test plan. Mô hình suy luận về SUT — thứ được mô tả trong prompt — chứ không suy luận về vòng đời socket của chính công cụ đo, lại càng không về giá trị mặc định của dải cổng động trên Windows. Không prompt nào ở bước thiết kế nhắc tới hệ điều hành của máy test, nên thông tin đó chưa từng bước vào ngữ cảnh. **Chỉ có việc chạy thật rồi mở log thô ra mới lộ được.**

> Đây cũng chính là "cái bẫy" số một của Task 2: một AI được đưa cho file `.jtl` này và hỏi "phân tích giúp" gần như chắc chắn sẽ báo cáo "tỉ lệ lỗi 15,82%, hệ thống quá tải ở 100 VU".

---

## Lỗi 2 — Nghiêm trọng: không reset môi trường giữa các lần chạy

**Bản AI sinh ra:** không có bước reset nào. Chạy lần lượt các kịch bản trên cùng một database đang chạy.

**Triệu chứng:** cùng một cấu hình (50 VU, think-time = 0, 40 giây) cho hai kết quả lệch nhau hơn hai lần:

| Trạng thái DB lúc bắt đầu | Throughput | Avg | p95 |
|---|---|---|---|
| 21.404 đơn tồn đọng | 300,9 sample/s | 154 ms | 230 ms |
| 0 đơn (vừa reset) | **652,4 sample/s** | **71 ms** | **109 ms** |

**Nguyên nhân gốc:** `GET /api/orders/my-orders` chạy `SELECT * FROM orders WHERE user_id = ? ORDER BY id DESC`, mà bảng `orders` **không có index trên `user_id`** (`database.js:74-81` chỉ khai báo PRIMARY KEY). Mỗi lần chạy kịch bản lại bơm thêm hàng nghìn đơn, làm kịch bản kế tiếp phải quét bảng lớn hơn. Không reset thì Load / Stress / Spike **không so sánh được với nhau** — mỗi kịch bản chạy trên một SUT khác nhau về hiệu năng.

**Cách sửa:** `scripts/reset_sut.ps1`, được `run_scenario.ps1` gọi tự động trước mỗi kịch bản: dừng backend → khởi động lại (`initDatabase()` tự `DROP TABLE` và seed lại) → chờ health check → nạp lại 60 tài khoản → ghi PID ra file. Số đơn trước/sau mỗi lần chạy đều được ghi vào file tóm tắt để kiểm chứng.

**Vì sao AI bỏ sót:** phải ghép ba mẩu thông tin nằm rải rác mới thấy được: (1) `initDatabase()` được gọi ở *mức module* nên có tác dụng phụ khi khởi động; (2) bảng `orders` thiếu index; (3) chính bài test là thứ sinh ra dữ liệu làm hỏng lần chạy sau. Đây là suy luận bậc hai về *tương tác giữa các lần chạy*, trong khi mô hình được hỏi về *một* test plan tại một thời điểm.

---

## Lỗi 3 — Nghiêm trọng: ngưỡng khoá tài khoản sai so với đề bài

**Bản AI sinh ra (và cả đề bài):** giả định khoá sau **3** lần đăng nhập sai.

**Thực tế đo được:** khoá ngay ở lần sai **thứ hai**. `server.js:54` cộng `login_attempts + 2` mỗi lần sai, trong khi ngưỡng là `>= 3`, nên dãy là 0 → 2 → 4. Bằng chứng probe đầy đủ ở `docs/01` §4.

**Hệ quả lên thiết kế, đã xử lý hết:**

1. Không dòng nào trong `users.csv` được phép sai mật khẩu. `seed_users.js` verify đăng nhập 3 tài khoản (đầu / giữa / cuối) sau khi nạp, và trả exit code khác 0 nếu hỏng — hỏng ở đây thì dừng ngay, không chạy tiếp.
2. Thời gian khoá là **180 giây, dài hơn cả kịch bản Spike (240 s) tính từ lúc sốc**. Lockout xảy ra giữa chừng sẽ không tự hết trong lần chạy đó → phải có `scripts/reset_lockout.js` ghi thẳng vào SQLite (không có endpoint HTTP nào gỡ khoá được, vì muốn gỡ thì phải đăng nhập thành công, mà đang khoá thì không đăng nhập được).
3. Assertion phải phân biệt 401 với 403 — xem Lỗi 4.

**Vì sao AI bỏ sót:** prompt ban đầu chép mô tả "3-fail lockout" từ đề bài, và mô hình nhận đó là tiền đề đúng. Phép cộng `+2` là một lỗi *của SUT*, không phải hành vi được ghi trong tài liệu; chỉ đọc `api_specification.md` thì không đời nào thấy. Bài học: **khi đề bài và mã nguồn mâu thuẫn, mã nguồn thắng — và phải probe để xác nhận.**

---

## Lỗi 4 — Trung bình: assertion quá yếu ở bước login

**Bản AI sinh ra:** một Response Assertion duy nhất, `response_code == 200`.

**Vì sao chưa đủ:** đúng là nó bắt được lỗi, nhưng khi mở `.jtl` ra thì mọi thất bại đều trông giống nhau. Ở tải cao, bước login có thể hỏng vì ba lý do khác hẳn nhau, và cách xử lý cũng khác hẳn nhau:

| Mã | Ý nghĩa thật | Phải làm gì |
|---|---|---|
| 401 | Sai credential | Lỗi **dữ liệu test** — `users.csv` lệch với DB, phải chạy lại `seed_users.js` |
| 403 | Tài khoản đang bị khoá | **Nhiễm trạng thái** từ lần chạy trước — phải chạy `reset_lockout.js` |
| 200 nhưng không có `token` | Server trả 200 rỗng | **Lỗi thật của SUT** — phải báo cáo |

**Cách sửa:** thay bằng JSR223 Assertion (Groovy, `cacheKey=true` để chỉ biên dịch một lần) gắn nhãn từng trường hợp bằng tiền tố riêng: `LOCKOUT_403:`, `AUTH_401:`, `LOGIN_NO_TOKEN:`. Nhờ đó cột `failureMessage` trong `.jtl` tự phân loại được nguyên nhân, chỉ cần group theo prefix là ra.

**Vì sao AI bỏ sót:** "assert response code = 200" là khuôn mẫu mặc định phổ biến nhất trong mọi tài liệu JMeter. Muốn biết 403 mang nghĩa riêng thì phải đã đọc `server.js:40-44` **và** đã kết nối nó với việc lockout sẽ nhiễm sang các lần chạy sau. Mô hình sinh ra thứ thống kê phổ biến nhất, chứ không phải thứ đúng nhất với SUT này.

---

## Lỗi 5 — Trung bình: View Results Tree giữ mọi mẫu sẽ làm sập JMeter

**Bản AI sinh ra:** View Results Tree với `error_logging = false` (giữ **mọi** mẫu).

**Vì sao nguy hiểm:** kịch bản Spike chạy tới 340 VU đồng thời. View Results Tree giữ toàn bộ request và response **trong bộ nhớ**. Ở tốc độ vài nghìn mẫu mỗi phút, heap của JMeter sẽ bị ăn sạch, GUI treo, và — nghiêm trọng nhất — **chính công cụ đo trở thành nguồn nhiễu cho số liệu nó đang đo**.

**Cách sửa:** đặt `error_logging = true` (chỉ giữ mẫu **lỗi**). Vẫn giữ nguyên giá trị của listener này trong kịch bản Spike — lúc sốc điều cần xem chính là *nội dung* phản hồi lỗi (server trả 500? timeout? reset kết nối?) — mà không phải trả giá bộ nhớ cho hàng chục nghìn mẫu thành công.

**Vì sao AI bỏ sót:** ràng buộc về bộ nhớ chỉ xuất hiện ở đúng tổ hợp "listener này + mức tải kia". Prompt yêu cầu "ba loại report view khác nhau"; mô hình đáp ứng đúng yêu cầu chữ nghĩa mà không lượng hoá cái giá vận hành ở mức tải của kịch bản Spike.

---

## Lỗi 6 — Trung bình: bẫy đọc số trong chính file `.jtl` thô

**Không phải lỗi cấu hình, mà là lỗi diễn giải** — nhưng cực dễ mắc nên ghi lại đây.

JMeter ghi **cả Transaction Controller** thành bản ghi trong file `.jtl`. Một vòng lặp của workflow này tạo ra:

- **7** request HTTP thật
- **3** sample của Transaction Controller (TC-01, TC-02, TC-03)
- **= 10 bản ghi** trong `.jtl`

Với kịch bản Stress: file `.jtl` có **155.696 bản ghi**, nhưng chỉ **108.740** trong đó là request HTTP thật; 46.956 bản ghi còn lại là Transaction Controller. Ai đếm số dòng của file thô rồi chia cho thời lượng sẽ **thổi phồng thông lượng lên 10/7 ≈ 43%**.

**Điểm cần nói cho chính xác:** bản thân JMeter **không** mắc lỗi này. Đã kiểm chứng:

| Nguồn số liệu | Số mẫu báo cáo | Có gồm Transaction Controller? |
|---|---|---|
| File `.jtl` thô (đếm dòng) | 155.696 | **Có** |
| Dòng `summary =` cuối của console | 108.740 | Không |
| Ô Total của HTML report (`statistics.json`) | 108.740 | Không |

Nghĩa là cái bẫy chỉ bung ra khi **tự phân tích file thô** — đúng tình huống của Task 2, nơi file `.jtl` được đưa thẳng cho AI đọc.

**Cách sửa:** `scripts/analyze_jtl.py` tách hẳn hai nhóm và in riêng, luôn ghi rõ bao nhiêu bản ghi là request thật, bao nhiêu là Transaction Controller.

**Vì sao đáng ghi:** đây là một trong những chỉ số mà AI phân tích log dễ đọc sai nhất ở Task 2 — xem `docs/06_ai_analysis_and_misinterpretation_hunt.md` §1.

---

## Lỗi 7 — Nhỏ: các lỗi kỹ thuật khi sinh tự động, phát hiện lúc chạy thử

Ba lỗi này đều được phát hiện bằng cách **chạy thật rồi đọc kết quả**, không phải bằng đọc code:

| Lỗi | Triệu chứng | Cách sửa |
|---|---|---|
| `reset_sut.ps1` treo vĩnh viễn | Script không bao giờ kết thúc, dù backend đã chạy | `Start-Process -PassThru` khiến tiến trình cha chờ cả cây tiến trình con — mà backend thì chạy mãi. Đổi sang `cmd /c start` để tách hẳn tiến trình. |
| `gen_variants.ps1` không tách được file | `Khong tach duoc cau truc file Load` | Mốc cắt chuỗi viết theo CRLF trong khi file nguồn dùng LF. Chuẩn hoá về LF trước khi cắt. |
| Kiểu dữ liệu `price` không nhất quán | Chưa gây hỏng, nhưng là quả bom hẹn giờ | `server.js:162` trả `price` dạng **chuỗi** khi product id chẵn, dạng **số** khi id lẻ. Thêm JSR223 PostProcessor chuẩn hoá về số trước khi nhân với `quantity`, và ép `total_amount` tối thiểu 600.000 để `apply-coupon` luôn đi vào nhánh tính giảm giá thật (`BIGBUY` yêu cầu tối thiểu 500.000) thay vì trả 400 rồi bị đếm nhầm thành lỗi server. |

---

## Tổng kết: vì sao AI bỏ sót — ba nhóm nguyên nhân

| Nhóm nguyên nhân | Lỗi thuộc nhóm | Bản chất |
|---|---|---|
| **Chất lượng prompt** | 3 | Prompt chép nguyên tiền đề sai từ đề bài ("3-fail lockout"). AI kế thừa sai lầm của prompt. Sửa bằng cách bắt AI probe thay vì tin mô tả. |
| **Giới hạn của mô hình** | 1, 2, 5 | Cần suy luận về những thứ *nằm ngoài* artefact đang sinh: vòng đời socket của OS, tương tác giữa các lần chạy, chi phí bộ nhớ của công cụ đo ở một mức tải cụ thể. Không thứ nào hiện diện trong file `.jmx`. |
| **Đặc thù của endpoint / SUT** | 4, 6, 7 | Cần đã đọc mã nguồn SUT (403 nghĩa là lockout, `price` đổi kiểu theo tính chẵn lẻ của id) hoặc đã thuộc cách JMeter ghi log (Transaction Controller cũng là sample). |

**Nguyên tắc rút ra:** AI sinh test plan tốt ở phần *cấu trúc* (cây sampler, extractor, tham số hoá, khuôn XML) — phần này gần như không phải sửa. Nó yếu ở phần *tiếp đất*: mọi chỗ mà độ đúng phụ thuộc vào hành vi thật của hệ thống này, trên máy này, ở mức tải này. Cách chia việc hiệu quả là **để AI dựng khung, còn con người thì đo**.
