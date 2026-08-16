# HW05 – Performance Testing (EShop SUT)

Repo bài tập HW05 – Performance Testing, môn Kiểm thử phần mềm.

- **SUT:** EShop — https://github.com/ttbhanh/eshop-sut
- **Công cụ:** Apache JMeter + Task Manager (resource monitor) + AI (Claude) cho phân tích log.

## Cấu trúc dự kiến

| Thư mục | Nội dung |
|---|---|
| `testplans/` | 3 test plan `.jmx`: Load / Stress / Spike, đặt tên `{StudentID}_{ScenarioType}_{YYYYMMDD}` |
| `data/` | File CSV dữ liệu đầu vào (credentials, product IDs, order payloads) |
| `results/jtl/` | Log thô `.jtl` của từng lần chạy |
| `results/html/` | Thư mục HTML report của từng scenario |
| `evidence/` | Screenshot JMeter + resource monitor, dxdiag, bảng spec phần cứng |
| `docs/` | Báo cáo chính (Markdown), AI Audit Report, AI Critique, đề xuất Continuous Performance Testing |
| `skill/` | Agent Skill tái sử dụng quy trình performance testing + phân tích log |

## Test summary report

| Mục | Giá trị |
|---|---|
| Scenarios đã chạy | _(Load / Stress / Spike / Soak — cập nhật sau khi chạy)_ |
| Endpoint groups | auth-heavy, read-heavy, transactional |
| Endurance threshold | _(max stable RPS, memory ceiling — cập nhật sau soak test)_ |
| Số bug / performance issue | _(cập nhật)_ |
| Demo video (YouTube, unlisted) | _(cập nhật)_ |

## Self-assessment

| No. | Criteria | Grade | Self-Assessed |
|---|---|---|---|
| 1 | Task 1 — Load testing | 20 | |
| 2 | Task 1 — Stress testing | 20 | |
| 3 | Task 1 — Spike testing | 20 | |
| 4 | Task 2 — AI analysis + misinterpretation hunt | 10 | |
| 5 | Task 3 — Continuous Performance Testing proposal | 10 | |
| 6 | Agent Skills | 10 | |
| | **Total** | **100** | |
