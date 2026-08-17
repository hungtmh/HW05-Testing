# 08 — Báo cáo lỗi phát hiện được

**MSSV:** 23127195 · **Ngày:** 2026-08-16
**SUT:** EShop backend, commit `85af3ba875c88283615e22cb108f13e2fccaf0e9`
**Cách kiểm chứng:** toàn bộ 8 lỗi dưới đây đều được xác nhận **qua API thật**, không phải suy đoán từ đọc mã nguồn. Script kiểm chứng: `scripts/probe_bugs.ps1`. Kết quả chạy đầy đủ: `results/monitor/bug_probe_output.txt` (chạy lúc 2026-08-16 21:48:59).

Các lỗi này được phát hiện **trong quá trình thiết kế test hiệu năng** — đọc mã nguồn để hiểu chi phí từng endpoint thì gặp luôn. Đề bài chỉ yêu cầu báo lỗi hiệu năng, nhưng những lỗi chức năng/bảo mật dưới đây nghiêm trọng hơn nhiều nên vẫn báo cáo đầy đủ.

---

## Bảng tổng hợp

| ID | Tiêu đề | Loại | Mức | Vị trí |
|---|---|---|---|---|
| BUG-01 | Tài khoản bị khoá sau 2 lần sai thay vì 3 | Chức năng | Trung bình | `server.js:54` |
| BUG-02 | Mã giảm giá phần trăm làm **tăng** số tiền phải trả | Chức năng | **Nghiêm trọng** | `server.js:399` |
| BUG-03 | `GET /api/orders/:id` không xác thực — đọc được đơn của người khác | Bảo mật (IDOR) | **Nghiêm trọng** | `server.js:344` |
| BUG-04 | Người dùng thường tự nâng quyền lên admin | Bảo mật (leo thang đặc quyền) | **Nghiêm trọng** | `server.js:119-129` |
| BUG-05 | Sản phẩm không tồn tại trả 200 kèm body rỗng | Chức năng | Thấp | `server.js:161` |
| BUG-06 | Kiểu dữ liệu `price` đổi theo tính chẵn lẻ của id | Chức năng | Trung bình | `server.js:162` |
| BUG-07 | Đơn đã huỷ vẫn chuyển sang "đã giao" được | Chức năng | Trung bình | `server.js:550` |
| BUG-08 | SQL injection ở `GET /api/products?search` | Bảo mật | **Nghiêm trọng** | `server.js:144` |

---

## BUG-01 — Khoá tài khoản sau 2 lần sai, không phải 3

**Mức:** Trung bình · **Loại:** Chức năng

`server.js:54` cộng `login_attempts + 2` mỗi lần đăng nhập sai, trong khi ngưỡng khoá là `>= 3`. Dãy giá trị là 0 → 2 → 4, nên ngưỡng bị vượt ngay ở lần sai **thứ hai**.

**Bằng chứng:**
```
lan sai thu 1: HTTP 401
lan sai thu 2: HTTP 401
lan sai thu 3: HTTP 403
dang nhap bang MAT KHAU DUNG: HTTP 403  -> DA BI KHOA (chi sau 2 lan sai)
```

**Ảnh hưởng:** người dùng gõ sai mật khẩu hai lần đã bị khoá 180 giây, trong khi tài liệu và giao diện đều nói ba lần. Cũng ảnh hưởng trực tiếp tới kiểm thử hiệu năng: lockout nhiễm sang lần chạy sau (xem `docs/04` §3).

**Cách sửa đề xuất:** `const newAttempts = user.login_attempts + 1;`

---

## BUG-02 — Mã giảm giá phần trăm làm TĂNG tiền phải trả

**Mức:** Nghiêm trọng · **Loại:** Chức năng / tính tiền

`server.js:399` viết `discount_amount = Math.floor(total_amount * (1 - coupon.discount_value))`. Với `discount_value = 10` (nghĩa là giảm 10%), biểu thức thành `total * (1 - 10) = total * (-9)` → giảm giá **âm**.

**Bằng chứng:**
```
POST /api/apply-coupon {code: SAVE10, total_amount: 1000000}
HTTP 200
{"success":true,"coupon_id":1,"discount_amount":-9000000,"final_amount":10000000,
 "message":"Áp dụng thành công! Giảm 10%"}
```

Khách nhập mã giảm giá 10% cho đơn 1.000.000 ₫ thì phải trả **10.000.000 ₫** — gấp **10 lần** giá gốc, trong khi hệ thống báo "Áp dụng thành công! Giảm 10%".

**Ảnh hưởng:** lỗi tính tiền trực tiếp cho khách hàng, kèm thông báo sai lệch. Đây là lỗi nghiêm trọng nhất về mặt nghiệp vụ.

**Cách sửa đề xuất:** `discount_amount = Math.floor(total_amount * coupon.discount_value / 100);`

> **Lưu ý về thiết kế test:** vì lỗi này, workflow hiệu năng chỉ dùng mã **fixed** (`BIGBUY`, `VIP100`). Nếu dùng mã percent, `final_amount` âm/khổng lồ sẽ truyền tiếp sang bước checkout và làm nhiễu số liệu.

---

## BUG-03 — `GET /api/orders/:id` không có xác thực (IDOR)

**Mức:** Nghiêm trọng · **Loại:** Bảo mật

`server.js:344` khai báo route **không kèm middleware `authenticateToken`**, khác hẳn mọi route đơn hàng còn lại. Bất kỳ ai biết (hoặc đoán) id đơn hàng đều đọc được toàn bộ thông tin đơn đó.

**Bằng chứng:**
```
Tao don hang id=21866 bang tai khoan perf01
GET /api/orders/21866  (KHONG gui token)  ->  HTTP 200
{"id":21866,"user_id":3,"total_amount":999999,"status":"pending",
 "shipping_address":"probe","created_at":"2026-08-16 14:49:00"}
```

**Ảnh hưởng:** id đơn hàng là số nguyên tăng dần, nên chỉ cần lặp từ 1 là quét sạch toàn bộ đơn hàng của hệ thống, gồm cả **địa chỉ giao hàng** và số tiền. Rò rỉ dữ liệu cá nhân quy mô lớn.

**Cách sửa đề xuất:** thêm `authenticateToken` và kiểm tra `order.user_id === req.user.id` (hoặc người gọi là admin).

---

## BUG-04 — Người dùng thường tự nâng quyền lên admin

**Mức:** Nghiêm trọng · **Loại:** Bảo mật / leo thang đặc quyền

`server.js:119-129`: handler `PUT /api/users/me` đọc `role` **từ body do client gửi lên** và ghi thẳng vào cơ sở dữ liệu nếu trường này có mặt.

**Bằng chứng:**
```
role truoc: user
PUT /api/users/me  {"name":"...","shipping_address":"x","phone":"...","role":"admin"}
role sau : admin
```

**Ảnh hưởng:** bất kỳ tài khoản nào đăng nhập được đều tự cấp quyền admin cho mình bằng đúng một request, rồi truy cập được toàn bộ API quản trị (danh sách người dùng, xoá người dùng, quản lý đơn hàng). Phá vỡ hoàn toàn mô hình phân quyền.

**Cách sửa đề xuất:** bỏ `role` khỏi danh sách trường được phép cập nhật ở endpoint tự cập nhật hồ sơ; chỉ cho đổi role qua API admin có kiểm tra quyền.

*(Script probe đã tự trả `role` về `user` sau khi kiểm chứng.)*

---

## BUG-05 — Sản phẩm không tồn tại trả HTTP 200 kèm body rỗng

**Mức:** Thấp · **Loại:** Chức năng / hợp đồng API

`server.js:161`: `if (!row) return res.status(200).json({});`

**Bằng chứng:**
```
GET /api/products/999999  ->  HTTP 200 | body: '{}'   (ky vong 404)
```

**Ảnh hưởng:** client không phân biệt được "sản phẩm không tồn tại" với "sản phẩm rỗng". Với kiểm thử tự động, mọi assertion dựa trên mã trạng thái đều mù trước lỗi này.

**Cách sửa đề xuất:** `return res.status(404).json({ error: "Product not found" });`

---

## BUG-06 — Kiểu dữ liệu `price` đổi theo tính chẵn lẻ của id

**Mức:** Trung bình · **Loại:** Chức năng / hợp đồng API

`server.js:162`: `if (row.id % 2 === 0) row.price = row.price.toString();`

**Bằng chứng:**
```
id=1 (id le )  -> price tra ve kieu SO
id=2 (id chan) -> price tra ve kieu CHUOI
id=3 (id le )  -> price tra ve kieu SO
id=4 (id chan) -> price tra ve kieu CHUOI
```

**Ảnh hưởng:** client nào tính toán trực tiếp trên `price` sẽ gặp nối chuỗi thay vì cộng số ở đúng một nửa số sản phẩm (`"30000000" + 1` ra `"300000001"`). Lỗi phụ thuộc dữ liệu nên rất khó tái hiện nếu không biết quy luật.

**Ghi nhận trong test plan:** đã xử lý bằng JSR223 PostProcessor chuẩn hoá `price` về số trước khi nhân với `quantity` (xem `docs/03` Lỗi 7).

---

## BUG-07 — Đơn đã huỷ vẫn chuyển sang "đã giao" được

**Mức:** Trung bình · **Loại:** Chức năng / máy trạng thái

`server.js:550-551` có nhánh `if (currentStatus === "canceled" && status === "delivered") isValidTransition = true;` — cho phép một chuyển trạng thái đáng lẽ phải bị cấm.

**Bằng chứng:**
```
Don 21867 sau khi huy: status = canceled
PUT /api/admin/orders/21867/status {"status":"delivered"}  ->  HTTP 200
status hien tai: delivered
```

**Ảnh hưởng:** đơn hàng đã huỷ vẫn bị đánh dấu đã giao, dẫn tới sai lệch doanh thu và tồn kho.

**Cách sửa đề xuất:** xoá nhánh đó; `canceled` phải là trạng thái kết thúc.

---

## BUG-08 — SQL injection ở `GET /api/products?search`

**Mức:** Nghiêm trọng · **Loại:** Bảo mật

`server.js:144` nối tham số của người dùng thẳng vào câu SQL:

```js
const query = `SELECT * FROM products WHERE name LIKE '%${searchQuery}%'`;
```

**Bằng chứng:**
```
?search=iPhone         ->  1 san pham
?search=%' OR '1'='1   ->  5 san pham   (toan bo bang)
```

Mệnh đề `WHERE` bị vô hiệu hoá hoàn toàn — chứng minh dữ liệu người dùng được thực thi như mã SQL.

**Ảnh hưởng:** kiểm chứng ở trên chỉ dùng payload vô hại (đọc thêm dữ liệu của chính bảng `products`). Nhưng cùng lối vào đó, kẻ tấn công có thể trích dữ liệu bảng khác qua `UNION SELECT`, hoặc gây ra truy vấn cực đắt để làm cạn CPU — **đây vừa là lỗ hổng bảo mật vừa là lỗ hổng khả dụng (DoS)**.

**Cách sửa đề xuất:** dùng tham số ràng buộc:
```js
db.all("SELECT * FROM products WHERE name LIKE ?", [`%${searchQuery}%`], cb);
```

---

## Vấn đề hiệu năng (không phải lỗi chức năng)

Đề bài ghi rõ phần này "khuyến khích, không bắt buộc". Bốn vấn đề sau đều đo được bằng số:

| ID | Vấn đề | Bằng chứng đo được |
|---|---|---|
| PERF-01 | Bảng `orders` không có index trên `user_id` | Throughput tụt **2,17 lần** khi bảng có 21.404 dòng; `my-orders` trôi ×1,89 trong soak 15 phút |
| PERF-02 | `userCarts` không giải phóng sau checkout → rò rỉ bộ nhớ | **1,76 MB/phút** ở 150 VU; ngoại suy chạm trần heap sau ~19–20 giờ |
| PERF-03 | SQLite không bật WAL | `PRAGMA journal_mode` trả `delete`; mỗi `INSERT orders` khoá toàn file |
| PERF-04 | Node đơn luồng, không cluster | CPU chạm **106% của một core** trong khi 19 luồng logic còn lại hoàn toàn rảnh |

Xem `docs/06` §4 để biết kết quả **thực nghiệm A/B** của các hướng khắc phục.

---

## GitHub Issues

Toàn bộ 8 lỗi đã được mở thành issue trên repo bài tập: https://github.com/hungtmh/HW05-Testing/issues

Ảnh chụp màn hình trang Issues cần lưu tại `evidence/issues/github_issues.png`.
