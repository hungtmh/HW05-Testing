# 09 — Kịch bản quay video demo (tối thiểu 6 phút, thuyết minh tiếng Việt)

**Yêu cầu bắt buộc của đề bài (mục 11):** video phải cho thấy **công cụ và trình giám sát tài nguyên trong CÙNG một khung hình**, và phải có **giọng thuyết minh của chính sinh viên**. Đây là artefact TA kiểm tra trực tiếp, không được thay bằng bất cứ thứ gì khác.

Video đăng ở chế độ **unlisted** trên YouTube, dán link vào `README.md` và vào báo cáo chính.

---

## Chuẩn bị trước khi bấm ghi

1. Chia đôi màn hình: **JMeter bên trái**, **Task Manager (tab Details)** bên phải.
2. Trong Task Manager bật các cột: `CPU`, `Memory (private working set)`, `Threads`. Lọc để thấy rõ `node.exe`.
3. Mở sẵn một cửa sổ PowerShell ở `D:\Kiem_thu\HW5`.
4. Kiểm tra đồng hồ hệ thống hiện rõ ở góc màn hình.
5. Chạy trước một lần cho "nóng máy" rồi mới ghi thật — tránh lúng túng.

**Tổng thời lượng đề xuất: 8–9 phút** (đề bài yêu cầu tối thiểu 6). Có thể tách thành nhiều clip, mỗi kịch bản một clip.

---

## Phần 1 — Giới thiệu và môi trường (khoảng 1 phút)

> "Chào thầy cô, em là **[họ tên]**, MSSV **23127195**. Đây là video demo bài HW05 — Performance Testing. Hệ thống em kiểm thử là backend API của EShop, chạy cục bộ ở cổng 3000. Công cụ em dùng là Apache JMeter 5.6.3, và em giám sát tài nguyên bằng Task Manager của Windows.
>
> Máy em đang chạy là **DESKTOP-96ARBFL** — trùng với hostname em đã dùng ở các bài tập trước — CPU Intel i7-13700H 14 nhân 20 luồng, RAM 13,75 GB. Em để cửa sổ Task Manager bên phải trong suốt video để thầy cô thấy được tài nguyên của tiến trình `node.exe`, tức là backend đang được kiểm thử."

**Thao tác trên màn hình:** mở DxDiag cho thấy hostname và cấu hình, rồi đóng lại.

---

## Phần 2 — Giải thích thiết kế test plan (khoảng 1 phút 30)

Mở file `23127195_Load_20260816.jmx` trong JMeter GUI, vừa nói vừa bấm vào từng phần tử trong cây.

> "Cả bốn kịch bản của em dùng **chung một workflow end-to-end**, gồm 7 request phủ đủ ba nhóm endpoint mà đề bài yêu cầu.
>
> Nhóm **auth-heavy** là request đăng nhập — em chọn nó vì đọc mã nguồn `server.js` thì thấy mỗi lần đăng nhập thành công server đều `UPDATE` bảng `users`, nên đây là endpoint auth duy nhất vừa đọc vừa ghi.
>
> Nhóm **read-heavy** gồm hai request: tìm kiếm sản phẩm dùng `LIKE` không có index — là truy vấn đắt, và xem chi tiết sản phẩm theo khoá chính — là truy vấn rẻ. Đặt hai cái cạnh nhau để so sánh trực tiếp trong cùng một lần chạy.
>
> Nhóm **transactional** gồm bốn request: thêm giỏ hàng, áp mã giảm giá, thanh toán, và xem lịch sử đơn hàng. Request thanh toán là nơi ghi xuống đĩa, và em dự đoán từ đầu đây sẽ là điểm nghẽn.
>
> Toàn bộ dữ liệu đều lấy từ **ba file CSV** — [bấm vào từng CSV Data Set Config] — tài khoản đăng nhập, từ khoá tìm kiếm, và dữ liệu đơn hàng."

Bấm vào JSR223 Assertion ở bước login:

> "Chỗ này em muốn nói kỹ. Bản test plan mà AI sinh ra lúc đầu chỉ kiểm tra 'response code bằng 200'. Em đã sửa lại thành đoạn script phân biệt rõ **401 và 403**, vì khi em đọc mã nguồn thì thấy SUT trả **403 khi tài khoản bị khoá**. Hai mã này có nghĩa hoàn toàn khác nhau: 401 là dữ liệu test của em sai, còn 403 là trạng thái bị nhiễm từ lần chạy trước. Nếu không tách ra thì lúc đọc log sẽ không biết đường nào mà lần."

---

## Phần 3 — Chạy kịch bản Load (khoảng 1 phút 30)

Trong PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Load
```

> "Em chạy kịch bản Load. Script này tự động **reset lại SUT về trạng thái sạch trước** — đây là bước em phát hiện ra là bắt buộc, và em sẽ giải thích tại sao ở phần sau.
>
> [chỉ vào Task Manager] Thầy cô nhìn cột CPU của `node.exe` — hiện khoảng **1%**. Nhưng con số này phải đọc cho đúng: máy em có 20 luồng logic, mà Node là **đơn luồng**, nên trần lý thuyết của tiến trình này chỉ là **5%**. Vậy 1% ở đây tương đương khoảng **20% của một core**. Đây là chỉ số rất dễ đọc nhầm thành 'server đang rảnh'.
>
> Kết quả: **18.749 request, không một lỗi nào, p95 chỉ 9 mili-giây**. Đây là đường cơ sở khoẻ mạnh để so sánh với các kịch bản sau."

---

## Phần 4 — Chạy kịch bản Stress (khoảng 2 phút)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Stress
```

> "Kịch bản Stress tăng tuyến tính từ 0 lên **500 virtual user** trong 300 giây. Em chọn con số 500 không phải bốc đại — em đã chạy calibration trước và đo được trần của hệ thống là khoảng **65 vòng lặp mỗi giây**. Với think-time 1 đến 3 giây thì 500 VU tạo ra tải chào khoảng 80 vòng lặp mỗi giây, tức **vượt trần khoảng 23%** — chắc chắn chạm được điểm gãy.
>
> [chỉ Task Manager khi VU tăng] Thầy cô để ý CPU của `node.exe` đang leo dần lên. Lát nữa khi tới khoảng 500 VU nó sẽ chạm khoảng **5,3%** — tức là **106% của một core** — bão hoà hoàn toàn đúng như dự đoán về mô hình đơn luồng.
>
> [khi thấy độ trễ tăng] Đây là **điểm gối**. Ở 300 VU độ trễ trung bình mới 18 mili-giây, nhưng lên 350 VU đã thành 48, lên 400 VU thành 104. Throughput thì đứng yên ở khoảng **458 request mỗi giây**. Đó là dấu hiệu kinh điển của hàng đợi bão hoà: thêm người dùng không làm hệ thống phục vụ nhanh hơn, chỉ làm ai cũng phải chờ lâu hơn.
>
> Một điểm em muốn nhấn mạnh: **không có một lỗi nào trong suốt 108.740 request**, kể cả ở 500 VU. Hệ thống suy giảm một cách có kiểm soát chứ không sập."

---

## Phần 5 — Chạy kịch bản Spike (khoảng 1 phút 30)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Spike
```

> "Kịch bản Spike dùng **hai Thread Group chồng nhau**: một nhóm nền 40 VU chạy suốt 240 giây, và một nhóm sốc 300 VU khởi động trễ 90 giây, dựng lên chỉ trong 5 giây rồi giữ 60 giây.
>
> Em cố ý cho nhóm nền **chạy tiếp sau khi cú sốc kết thúc** — vì như vậy mới đo được **thời gian hồi phục**, thứ mà một Thread Group đơn lẻ không đo được.
>
> [đúng lúc sốc, chỉ Task Manager] Đây rồi — CPU nhảy vọt, độ trễ trung bình từ 3 mili-giây lên hơn 290 mili-giây chỉ trong vài giây.
>
> [sau khi sốc kết thúc] Và bây giờ tải nền vẫn chạy, thầy cô nhìn độ trễ tụt về lại mức bình thường. Em đo được thời gian hồi phục cụ thể trong báo cáo."

---

## Phần 6 — Soak test và ngưỡng chịu đựng (khoảng 1 phút)

> "Kịch bản Soak chạy 150 VU liên tục trong **15 phút**. Mục tiêu là tìm ngưỡng chịu đựng của phần cứng của em.
>
> Em nhắm vào hai cơ chế tích luỹ mà em phát hiện được khi **đọc mã nguồn**: thứ nhất, biến `userCarts` trong `server.js` giữ giỏ hàng trong RAM và **không bao giờ được giải phóng sau khi thanh toán** — đây là rò rỉ bộ nhớ. Thứ hai, bảng `orders` **không có index trên `user_id`**, nên càng nhiều đơn thì request xem lịch sử càng chậm.
>
> [chỉ vào cột Memory trong Task Manager] Thầy cô thấy bộ nhớ của `node.exe` tăng dần đều trong suốt 15 phút — nó không quay về mức ban đầu."

*(Nếu không đủ thời lượng, có thể tua nhanh phần giữa và giữ nguyên đoạn đầu + đoạn cuối để thấy chênh lệch bộ nhớ.)*

---

## Phần 7 — Điều AI đọc sai và cách phát hiện (khoảng 1 phút 30) ⭐

**Đây là phần ghi điểm cao nhất — đừng bỏ.**

> "Cuối cùng em muốn kể một chuyện đã xảy ra trong lúc làm bài.
>
> Khi em chạy calibration ở mức 100 VU, kết quả báo **15,82% lỗi**. Nếu em đưa thẳng file log này cho AI phân tích, nó kết luận ngay là 'SUT quá tải, gãy ở khoảng 100 VU'. Nghe rất hợp lý.
>
> Nhưng em mở **file `.jtl` thô** ra xem cột `responseCode` [mở file lên, chỉ vào dòng lỗi]. Nó không phải mã HTTP nào cả. Nó là `java.net.BindException — Address already in use`.
>
> Em kiểm tra tiếp ở mức hệ điều hành [gõ lệnh]:
>
> ```
> netsh int ipv4 show dynamicport tcp   →  chỉ có 16.384 cổng
> (Get-NetTCPConnection -State TimeWait).Count  →  12.570 socket
> ```
>
> Tức là **chính máy chạy JMeter của em bị cạn cổng**, chứ server hoàn toàn khoẻ mạnh. Lỗi nằm ở công cụ đo, không phải ở thứ đang được đo.
>
> Em sửa bằng cách bật `same_user_on_next_iteration` để giữ kết nối keep-alive, và sau đó **tỉ lệ lỗi về đúng 0%** ở cả 50, 100 và 200 VU.
>
> Bài học em rút ra: **AI phân tích rất tốt những con số được đưa cho nó, nhưng nó không tự hỏi con số đó có đáng tin không.** Việc đặt câu hỏi đó là của mình. Em cảm ơn thầy cô đã xem."

---

## Danh mục kiểm tra trước khi đăng

- [ ] Tổng thời lượng ≥ 6 phút
- [ ] Có giọng thuyết minh tiếng Việt của chính mình xuyên suốt
- [ ] JMeter và Task Manager **cùng khung hình** ở mọi đoạn đang chạy test
- [ ] Thấy rõ tiến trình `node.exe` với cột CPU và Memory
- [ ] Có đoạn thấy rõ hostname `DESKTOP-96ARBFL`
- [ ] Có đủ cả bốn kịch bản (hoặc tách thành nhiều clip, tổng vẫn ≥ 6 phút)
- [ ] Đăng chế độ **Unlisted**
- [ ] Dán link vào `README.md` và vào `docs/00_MAIN_REPORT.md`
