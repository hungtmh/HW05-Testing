# AI Critique

**MSSV:** 23127195 · **Ngày:** 2026-08-16 · **Công cụ AI:** Claude Opus 5 (Claude Code CLI)

---

Trong bài này, AI sai ở ba chỗ, và ba chỗ đó lộ ra ba giới hạn khác nhau.

Lỗi nặng nhất là đọc chỉ số CPU. Thấy tiến trình backend đạt đỉnh 5,3%, AI kết luận CPU còn dư nhiều và nút thắt phải nằm ở I/O. Thực tế backend là Node đơn luồng chạy trên máy hai mươi luồng logic, nên trần của nó chỉ là 5%; con số 5,3% nghĩa là đã bão hoà trọn một core. AI có đủ dữ liệu để tự suy ra — chuỗi giám sát ghi rõ "trên tổng 20 luồng logic" — nhưng vẫn so 5,3% với thang trực giác "100% là hết CPU". Đây là lỗi suy luận, không phải thiếu thông tin.

Lỗi thứ hai mang tính thiên lệch: thấy tỉ lệ lỗi bằng không ở 500 VU, AI kết luận hệ thống chịu tải tốt. Nhưng p95 lúc đó đã gấp bốn mươi chín lần đường cơ sở. AI bám vào chỉ số nổi bật nhất trong bảng tóm tắt và bỏ qua thứ quyết định trải nghiệm người dùng.

Lỗi thứ ba là không đặt câu hỏi: khi calibration báo 15,82% lỗi, AI mặc nhiên coi đó là lỗi của hệ thống được kiểm thử. Mở log thô ra thì đó là BindException — chính máy chạy JMeter cạn cổng.

Nguyên tắc rút ra: AI suy luận tốt trên dữ liệu được đưa cho nó, nhưng gần như không tự hỏi dữ liệu đó có đáng tin không, hay được đo trong điều kiện nào. Nó nhận mọi con số như sự thật. Việc nghi ngờ phép đo — hỏi con số này tính trên cửa sổ nào, thang đo nào, công cụ đo có tự làm nhiễu không — vẫn phải là việc của con người.
