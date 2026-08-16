# 05 — Ngưỡng chịu đựng của phần cứng (Endurance / Soak)

**MSSV:** 23127195 · **Máy:** `DESKTOP-96ARBFL` (i7-13700H, 14 nhân / 20 luồng, 13,75 GB RAM)
**Kịch bản:** `23127195_Soak_20260816.jmx` — 150 VU, ramp-up 30 s, giữ tải 870 s (**tổng 15 phút**), think-time 1–3 s

---

## 1. Kết quả tổng thể

| Chỉ số | Giá trị |
|---|---|
| Request HTTP | **153.366** |
| Bản ghi trong `.jtl` thô | 219.217 *(gồm 65.851 sample Transaction Controller)* |
| Lỗi | **0 (0,00%)** |
| Throughput ở trạng thái ổn định | **173,4 req/s** (24,4 vòng lặp/s) |
| p95 toàn bộ | 16 ms |
| p99 toàn bộ | 27 ms |
| Đơn hàng phát sinh | 0 → **21.865** |
| RSS backend | 69,7 → **130,0 MB** |
| CPU backend trung bình | 2,1% toàn hệ thống = **42% của một core** |
| CPU JMeter trung bình | 0,4% |

Trong suốt 15 phút, hệ thống **không hỏng lần nào**. Nhưng "không hỏng" không có nghĩa là "đứng yên": hai chỉ số trôi đều theo thời gian trong khi tải giữ **hoàn toàn cố định**.

---

## 2. Trôi số một — bộ nhớ tăng đơn điệu (rò rỉ có thật)

| Thời điểm | RSS (MB) | Private bytes (MB) | Handle |
|---|---|---|---|
| Bắt đầu | 69,7 | — | 359 |
| +120 s | 106,4 | 104,6 | 359 |
| +361 s | 108,1 | 106,0 | 359 |
| +720 s | 115,4 | 113,3 | 359 |
| Kết thúc (+900 s) | **129,3** | — | **359** |
| Đỉnh | **130,0** | | |

**Đọc số cho đúng:**

- Bước nhảy 69,7 → 106,4 MB trong 2 phút đầu **không phải rò rỉ** — đó là V8 cấp phát heap cho 150 request đồng thời, chuyện bình thường khi tải tăng từ 0 lên mức làm việc.
- Phần đáng chú ý là đoạn **sau khi tải đã ổn định**: từ +120 s tới +900 s, RSS vẫn tăng đều **106,4 → 129,3 MB**, tức **+22,9 MB trong 13 phút ≈ 1,76 MB/phút**, trong khi tải không hề đổi.
- **Số handle đứng yên tuyệt đối ở 359** trong suốt 15 phút → không rò rỉ file descriptor / socket. Chỉ rò rỉ bộ nhớ heap.

**Nguyên nhân đã xác định trong mã nguồn:** `server.js:14` khai báo `const userCarts = {}`, và `server.js:290-295` chỉ `push` thêm vào mảng giỏ hàng của người dùng. **Không có chỗ nào xoá giỏ hàng sau khi checkout thành công.** Mỗi vòng lặp của workflow thêm vĩnh viễn một phần tử vào bộ nhớ tiến trình.

**Kiểm chứng bằng phép chia:** 22,9 MB tích luỹ / 21.865 vòng lặp ≈ **1,05 KB mỗi vòng lặp**. Đây là kích thước hợp lý cho một object `{id, name, price, quantity}` trong V8 cộng chi phí phần tử mảng — con số khớp với giả thuyết rò rỉ ở `userCarts`.

---

## 3. Trôi số hai — độ trễ xấu dần dù tải không đổi

| Cửa sổ 120 s | req/s | avg (ms) | p95 (ms) |
|---|---|---|---|
| 0–120 (còn ramp-up) | 150,6 | 4,5 | 12 |
| 120–240 | 173,3 | 5,3 | 15 |
| 240–360 | 173,0 | 5,9 | 17 |
| 360–480 | 173,4 | 5,8 | 16 |
| 480–600 | 173,1 | 5,7 | 15 |
| 600–720 | 173,6 | 5,7 | 15 |
| 720–840 | 174,6 | 6,2 | 17 |
| 840–900 | 86,5\* | **7,4** | **22** |

\* cửa sổ cuối chỉ dài 60 s nên số mẫu bằng một nửa; giá trị req/s không so sánh trực tiếp được.

Throughput **giữ nguyên** ở 173 req/s suốt lần chạy, nhưng độ trễ trung bình tăng **4,5 → 7,4 ms (+64%)**. Hệ thống vẫn theo kịp tải, chỉ là mỗi request tốn nhiều thời gian hơn.

### Tách nguyên nhân: dữ liệu tích luỹ hay bão hoà chung?

So p95 của 2 phút đầu (t = 60–180 s) với 2 phút cuối (t = 720–840 s), theo từng endpoint:

| Endpoint | p95 đầu | p95 cuối | Hệ số | Chạm DB? |
|---|---|---|---|---|
| `GET /api/orders/my-orders` | 9 ms | 17 ms | **×1,89** | Đọc `orders` — **không index** |
| `POST /api/apply-coupon` | 14 ms | 20 ms | ×1,43 | Đọc `coupons` (2 query lồng nhau) |
| `POST /api/login` | 10 ms | 14 ms | ×1,40 | Đọc + ghi `users` |
| `GET /api/products/{id}` | 10 ms | 14 ms | ×1,40 | Đọc `products` theo khoá chính |
| `GET /api/products?search` | 11 ms | 14 ms | ×1,27 | Đọc `products` (`LIKE`) |
| `POST /api/cart` | 4 ms | 5 ms | **×1,25** | **Không chạm DB** |
| `POST /api/checkout` | 18 ms | 20 ms | ×1,11 | Ghi `orders` |

**Cách đọc bảng này:** `POST /api/cart` không chạm cơ sở dữ liệu lần nào, nên hệ số **×1,25** của nó chính là **mức trôi nền** — phần do event loop bận hơn và GC phải làm việc nhiều hơn khi heap phình ra. Mọi endpoint đều chịu mức nền này.

Endpoint duy nhất vượt hẳn lên là `my-orders` với **×1,89**, tức **gần gấp rưỡi mức nền**. Đó đúng là endpoint chạy `SELECT * FROM orders WHERE user_id = ?` trên bảng **không có index**, và bảng đó phình từ 0 lên 21.865 dòng ngay trong lần chạy. Hai sự việc khớp nhau về cả cơ chế lẫn thứ tự lớn.

Đáng chú ý ngược lại: `POST /api/checkout` — thao tác **ghi đĩa** — lại trôi ít nhất (×1,11). `INSERT` vào bảng không index không hề đắt lên khi bảng to ra; chỉ có **đọc** mới đắt lên. Điều này bác bỏ giả thuyết "nút thắt là I/O ghi đĩa".

---

## 4. Ngưỡng chịu đựng — kết luận bằng số

Tổng hợp cả bốn lần chạy chính thức và các lần calibration:

| Ngưỡng | Giá trị đo được | Căn cứ |
|---|---|---|
| **Mức tải ổn định tối đa** | **150 VU ≈ 173 req/s ≈ 24,4 vòng lặp/s**, giữ được 15 phút với 0 lỗi và p95 ≤ 22 ms | Kịch bản Soak |
| **Điểm gối (knee)** | **≈ 350 VU** — p95 nhảy từ 55 ms (300–349 VU) lên 147 ms (350–399 VU) trong khi throughput gần như không tăng | Kịch bản Stress, gom theo `allThreads` |
| **Throughput trần** | **458 req/s** với bảng `orders` ~13.000 dòng; **621 req/s** với bảng ~600 dòng | Stress và Spike |
| **Trần CPU** | **5,3% toàn hệ thống = 106% của một core** — bão hoà đúng giới hạn đơn luồng của Node | Stress |
| **Trần bộ nhớ (đo được)** | **130 MB** sau 15 phút ở 150 VU | Soak |
| **Tốc độ rò rỉ** | **1,76 MB/phút** ở 150 VU, tương đương **1,05 KB mỗi vòng lặp** | Soak, đoạn tải ổn định |
| **Thời gian hồi phục sau sốc** | **10–15 giây** để p95 về lại đường cơ sở sau khi bỏ tải 340 VU | Spike |

### Ngoại suy về trần bộ nhớ

Ở tốc độ **1,76 MB/phút** đo được tại mức 150 VU:

- 1 giờ → thêm ~106 MB
- 8 giờ → thêm ~845 MB
- 24 giờ → thêm ~2,5 GB

Node 22 trên máy 13,75 GB RAM có giới hạn heap cũ (old space) mặc định vào khoảng **2 GB** nếu không truyền `--max-old-space-size`. Với tốc độ trên, tiến trình sẽ chạm trần heap sau **khoảng 19–20 giờ** chạy liên tục ở mức tải này, rồi bị `FATAL ERROR: JavaScript heap out of memory`.

> **Nói rõ đây là phép ngoại suy tuyến tính**, dựa trên 13 phút quan sát ở tải cố định. Nó giả định tốc độ rò rỉ không đổi và giới hạn heap mặc định của Node. Muốn khẳng định chắc chắn thì phải chạy soak thật nhiều giờ — nằm ngoài phạm vi 10 giờ của bài tập này. Con số đáng tin duy nhất **đo được trực tiếp** là 1,76 MB/phút và trần 130 MB sau 15 phút.

### Vì sao trần thực tế không phải là RAM

Máy có 13,75 GB RAM nhưng tiến trình backend chỉ dùng 130 MB ở tải cao nhất. **RAM không bao giờ là nút thắt ở đây.** Nút thắt là **một core CPU duy nhất** — hệ quả của mô hình đơn luồng Node không dùng cluster. Máy còn dư 19 luồng logic hoàn toàn rảnh trong lúc backend nghẹt.

Đây chính là lý do phần tối ưu ở `docs/06` §4 xếp **Node cluster** là hướng có tiềm năng lớn nhất — nhưng kèm điều kiện phải sửa `userCarts` trước, vì trạng thái đang nằm trong RAM của một tiến trình và sẽ vỡ ngay khi tách nhiều worker.
