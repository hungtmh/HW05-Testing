# Thư mục bằng chứng — hướng dẫn chụp

Đây là những artefact **không thể sinh tự động** và theo mục 11 của đề bài thì TA sẽ kiểm tra trực tiếp. Cần tự chụp/quay.

## Cấu trúc cần có

```
evidence/
├── hardware/
│   ├── dxdiag.png              ← ảnh chụp cửa sổ DxDiag
│   └── dxdiag_report.txt       ← đã sinh sẵn bằng: dxdiag /t evidence\hardware\dxdiag_report.txt
├── load/
│   ├── jmeter_load.png         ← JMeter + Task Manager trong CÙNG một khung hình
│   └── taskmanager_load.png    ← tab Details, thấy rõ dòng node.exe
├── stress/
├── spike/
└── soak/
```

## Cách chụp cho đúng yêu cầu

Yêu cầu quan trọng nhất: **công cụ và trình giám sát tài nguyên phải nằm trong CÙNG một khung hình**. Ảnh chụp riêng từng cửa sổ sẽ không được tính.

### Bố trí màn hình

1. Chia đôi màn hình: **JMeter bên trái**, **Task Manager bên phải**.
2. Task Manager → tab **Details** → chuột phải vào tiêu đề cột → **Select columns** → bật `CPU`, `Memory (private working set)`, `Threads`.
3. Sắp xếp theo CPU giảm dần để `node.exe` nổi lên đầu, hoặc gõ vào ô lọc.
4. Đảm bảo **đồng hồ hệ thống ở góc phải màn hình hiện rõ** — nó chứng minh các ảnh được chụp đúng lúc đang chạy.

### Mốc thời gian nên chụp cho từng kịch bản

| Kịch bản | Chụp vào lúc | Lý do |
|---|---|---|
| **Load** | phút thứ 2–4 (đã qua ramp-up, đang ổn định) | Cho thấy trạng thái ổn định, CPU thấp |
| **Stress** | phút thứ 5–6 (đang ở 450–500 VU) | Lúc CPU của `node.exe` chạm trần một core |
| **Spike** | **giây thứ 90–150** — đúng lúc cú sốc | Đây là khoảnh khắc quan trọng nhất của cả bài |
| **Soak** | phút thứ 12–15 | Lúc RSS đã leo lên cao nhất |

> Mốc của Spike rất hẹp (đúng 60 giây). Nên **quay màn hình** kịch bản này thay vì chụp ảnh, rồi cắt hình từ video ra.

## Chạy lại từng kịch bản để quay

```powershell
cd D:\Kiem_thu\HW5
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Load
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Stress
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Spike
powershell -ExecutionPolicy Bypass -File scripts\run_scenario.ps1 -Scenario Soak
```

Chạy lại sẽ **ghi đè** kết quả trong `results/`. Nếu muốn giữ kết quả đã commit thì sao lưu thư mục `results/` trước, hoặc chỉ quay lại phần hình ảnh mà không quan tâm số liệu mới (nhưng khi đó số trong video sẽ khác số trong báo cáo — nên nói rõ trong lời thuyết minh, hoặc cập nhật lại báo cáo theo lần chạy mới).

## Nếu muốn quay bằng JMeter GUI (dễ nhìn hơn khi lên video)

```powershell
D:\Kiem_thu\tools\apache-jmeter-5.6.3\bin\jmeter.bat -t D:\Kiem_thu\HW5\testplans\23127195_Load_20260816.jmx
```

Test plan mở lên là chạy được ngay — mọi đường dẫn CSV dùng giá trị mặc định tuyệt đối (`D:/Kiem_thu/HW5/data`), không cần truyền tham số dòng lệnh.

**Nhưng trước khi bấm Start, luôn phải chạy trước:**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\reset_sut.ps1
```

Nếu bỏ bước này, backend có thể chưa chạy, hoặc DB còn dữ liệu tồn từ lần trước làm số liệu lệch hẳn (đã đo được: chênh 2,17 lần).

> Lưu ý khi quay bằng GUI kịch bản **Spike**: GUI nặng hơn chế độ CLI đáng kể ở 340 VU. Số liệu quay bằng GUI chỉ nên dùng để **minh hoạ trực quan**; số liệu chính thức trong báo cáo lấy từ các lần chạy CLI đã commit trong `results/`.
