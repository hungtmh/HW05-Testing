# 01 — Khảo sát SUT & Lựa chọn phạm vi endpoint

**MSSV:** 23127195
**Ngày:** 2026-08-16
**SUT:** EShop — https://github.com/ttbhanh/eshop-sut (commit đang dùng: xem `docs/04_execution_evidence.md`)
**Base URL backend:** `http://localhost:3000`

---

## 1. Cách khảo sát

Không tin vào `api_specification.md` một cách mù quáng. Quy trình khảo sát gồm 3 bước:

1. Đọc `backend/api_specification.md` để lấy danh sách endpoint danh nghĩa.
2. **Đọc mã nguồn** `backend/server.js` (573 dòng) và `backend/database.js` (119 dòng) để xác định hành vi thật, đặc biệt là chi phí I/O của từng endpoint.
3. **Probe thực nghiệm** bằng PowerShell/`Invoke-RestMethod` trước khi viết test plan, để xác nhận status code và hành vi khoá tài khoản thật sự.

Bước 3 là bước quyết định: nó đã lật ngược một giả định mà cả đề bài lẫn AI đều mặc định đúng (xem §4).

---

## 2. Bản đồ endpoint và chi phí thực thi

| Endpoint | Method | Auth | Thao tác DB thật (đọc từ `server.js`) | Nhóm |
|---|---|---|---|---|
| `/api/register` | POST | ✗ | `INSERT users` | ghi |
| `/api/login` | POST | ✗ | `SELECT users WHERE email` + **`UPDATE users`** mỗi lần gọi (kể cả khi đăng nhập thành công, dòng 47-50) | **auth-heavy** |
| `/api/products` | GET | ✗ | `SELECT * FROM products` — nếu có `?search=` thì `LIKE '%kw%'` **nối chuỗi trực tiếp** (dòng 144) | **read-heavy** |
| `/api/products/:id` | GET | ✗ | `SELECT * FROM products WHERE id = ?` | **read-heavy** |
| `/api/cart` | POST | ✓ | **Không chạm DB** — `userCarts[userId].push()` vào RAM (dòng 290-295) | **transactional** |
| `/api/cart` | GET | ✓ | Đọc RAM | transactional |
| `/api/apply-coupon` | POST | ✗ | `SELECT coupons` + `SELECT COUNT(*) coupon_usage` (2 query lồng nhau) | transactional |
| `/api/checkout` | POST | ✓ | **`INSERT orders`** — ghi đĩa, điểm nghẽn chính | **transactional** |
| `/api/orders/my-orders` | GET | ✓ | `SELECT orders WHERE user_id ORDER BY id DESC` — **không có index trên `user_id`** | transactional |
| `/api/admin/*` | mixed | ✓ | CRUD | ngoài phạm vi |

### Đặc điểm hạ tầng đáng chú ý (ảnh hưởng trực tiếp tới kết quả performance)

Trích từ `backend/database.js`:

- **SQLite chế độ journal mặc định (`delete`), không bật WAL.** Mỗi `INSERT orders` khoá toàn bộ file DB → checkout là điểm serialize hoá của toàn hệ thống.
- **Không có index nào ngoài PRIMARY KEY.** `users.email` (dùng trong mọi lần login) và `orders.user_id` đều full-scan.
- `initDatabase()` được gọi **mỗi lần `require('./database')`**, tức là **mỗi lần khởi động server sẽ `DROP TABLE` và seed lại toàn bộ dữ liệu** (dòng 15-20, 117). Hệ quả vận hành: tài khoản tải phải được seed lại sau mỗi lần restart backend — đã tự động hoá trong `scripts/seed_users.js`.
- Backend là **Node.js single-threaded**, không cluster. Trần thông lượng bị chặn bởi 1 core, không phải bởi 14 core của máy test.
- Giỏ hàng nằm trong biến toàn cục `userCarts` và **không bao giờ được xoá sau checkout** → rò rỉ bộ nhớ tuyến tính theo số request. Đây là giả thuyết chính cho bài soak test (xem `docs/05_endurance_threshold.md`).

---

## 3. Phạm vi đã chọn — 3 nhóm endpoint

Đề bài yêu cầu chọn 3 nhóm endpoint và cả 3 test plan (Load/Stress/Spike) phải chạy **cùng một workflow end-to-end**.

| Nhóm | Endpoint được chọn | Lý do chọn |
|---|---|---|
| **Auth-heavy** | `POST /api/login` | Là endpoint duy nhất vừa đọc vừa **ghi** DB trên mọi request thành công, lại có logic khoá tài khoản → vừa đo được chi phí auth, vừa buộc test plan phải xử lý trạng thái. |
| **Read-heavy** | `GET /api/products?search=` → `GET /api/products/{id}` | `search` chạy `LIKE '%...%'` không index (chi phí CPU tăng theo số sản phẩm); product detail là truy vấn theo khoá chính (baseline nhanh nhất). Hai endpoint này tạo cặp đối chứng "query đắt vs query rẻ" trong cùng một biểu đồ. |
| **Transactional** | `POST /api/cart` → `POST /api/apply-coupon` → `POST /api/checkout` | Chuỗi ghi thật: RAM (cart) → đọc coupon → **ghi đĩa (orders)**. `checkout` là nơi SQLite serialize hoá, dự kiến là bottleneck số 1. |

### Workflow end-to-end (dùng chung cho cả 4 kịch bản)

```
[VU bắt đầu]
   │
   ├─ (1) POST /api/login                     ← AUTH-HEAVY   (dữ liệu: users.csv)
   │        └─ JSON Extractor: $.token, $.user.id
   │        └─ think-time
   ├─ (2) GET  /api/products?search={keyword} ← READ-HEAVY   (dữ liệu: search_terms.csv)
   │        └─ JSON Extractor: $[0].id  (product_id)
   │        └─ think-time
   ├─ (3) GET  /api/products/{product_id}     ← READ-HEAVY
   │        └─ think-time
   ├─ (4) POST /api/cart      (Bearer token)  ← TRANSACTIONAL (dữ liệu: checkout_data.csv)
   ├─ (5) POST /api/apply-coupon              ← TRANSACTIONAL
   ├─ (6) POST /api/checkout  (Bearer token)  ← TRANSACTIONAL
   │        └─ JSON Extractor: $.orderId
   └─ (7) GET  /api/orders/my-orders          ← TRANSACTIONAL (đọc bảng không index)
[VU kết thúc]
```

**Giải trình độ phủ:** một vòng lặp của virtual user đi qua đủ 3 nhóm: 1 request auth-heavy (bước 1), 2 request read-heavy (bước 2-3), 4 request transactional (bước 4-7). Tỉ lệ 1 : 2 : 4 phản ánh hành vi thật của người mua hàng — đăng nhập một lần, xem vài sản phẩm, rồi thực hiện chuỗi giao dịch. Quan trọng hơn về mặt đo lường: mỗi vòng lặp tạo đúng **1 lần ghi `users`** (login) và **1 lần ghi `orders`** (checkout), nên tỉ lệ ghi/đọc là hằng số, giúp so sánh RPS giữa Load/Stress/Spike có ý nghĩa.

**Không trùng lặp trong nhóm:** workflow này là chuỗi *login → search → detail → cart → coupon → checkout → order history*. Nếu thành viên khác chọn luồng admin (Pool C) hoặc luồng đăng ký/quên mật khẩu (FR-01/FR-03) thì không giao nhau.

---

## 4. Phát hiện khi probe: ngưỡng khoá tài khoản KHÔNG phải 3 lần

Đề bài HW05 mô tả "3-fail login lockout". Đọc mã nguồn `server.js:54`:

```js
const newAttempts = user.login_attempts + 2;   // ← cộng 2, không phải cộng 1
let lockedUntil = null;
if (newAttempts >= 3) {
  lockedUntil = new Date(Date.now() + 180000).toISOString();  // khoá 180 giây
}
```

Vì mỗi lần sai cộng **2**, ngưỡng `>= 3` bị vượt ngay ở lần sai **thứ hai** (0 → 2 → 4).

### Bằng chứng thực nghiệm (chạy 2026-08-16, trước khi viết test plan)

```
POST /api/register  probe_lockout@eshop.test        → 200 OK
Fail attempt 1 (sai mật khẩu):  HTTP 401
Fail attempt 2 (sai mật khẩu):  HTTP 401   ← tài khoản đã bị khoá tại đây
Fail attempt 3 (sai mật khẩu):  HTTP 403   ← "Tài khoản đã bị khóa"
Đăng nhập lại bằng MẬT KHẨU ĐÚNG: HTTP 403 ← vẫn bị khoá
```

**Hệ quả lên thiết kế test plan:**

1. Không được để bất kỳ dòng nào trong `users.csv` sai mật khẩu — chỉ **2** lần sai là tài khoản đó chết trong 180 giây, và mọi vòng lặp sau của thread đó sẽ hỏng dây chuyền (không có token → cart/checkout đều 401).
2. Thời gian khoá 180 s **dài hơn** thời lượng của kịch bản Spike (150 s). Nếu lockout kích hoạt giữa chừng, nó sẽ không tự hết trong lần chạy đó → bắt buộc phải có bước reset giữa các lần chạy (`scripts/reset_lockout.js`).
3. Assertion cho bước login phải bắt **cả 403 lẫn 401**, và phải phân biệt được hai loại: 401 = sai credential (lỗi dữ liệu test), 403 = đã bị khoá (nhiễm trạng thái từ lần chạy trước). Nếu chỉ assert "response code = 200" thì khi đọc log sẽ không biết vì sao hỏng.

Điểm 3 chính là thứ mà bản test plan do AI sinh ra lần đầu đã bỏ sót — chi tiết trong `docs/03_human_review_and_fixes.md`.

---

## 5. Tài liệu tham chiếu

- `backend/api_specification.md` trong repo SUT.
- `backend/server.js`, `backend/database.js` — nguồn sự thật về hành vi.
- Apache JMeter 5.6.3 User Manual — https://jmeter.apache.org/usermanual/index.html
