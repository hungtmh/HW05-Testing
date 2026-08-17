# 10 — Danh mục đối chiếu yêu cầu nộp bài

Đối chiếu từng gạch đầu dòng của **mục 14 (Submission Regulations)** trong đề bài với tài liệu tương ứng trong repo. Mục nào cần sinh viên tự làm đều ghi rõ.

**Tên file nộp:** `23127195_HW05_AI_Performance_089.zip`
*(mẫu `<StudentID>_HW05_AI_Performance_<SelfAssessedGrade>.zip`; điểm tự chấm 89 — xem bảng tự đánh giá trong `README.md`)*

---

## Yêu cầu bắt buộc trong file .zip

| # | Yêu cầu của đề bài | Tình trạng | Vị trí |
|---|---|---|---|
| 1 | Báo cáo chính (Markdown + PDF), gồm báo cáo hiệu năng và phần phê bình phân tích của AI | ✅ Markdown xong · ⚠️ **cần xuất PDF** | `docs/00_MAIN_REPORT.md` |
| 2 | Link repo GitHub công khai (test plan + data) | ✅ | https://github.com/hungtmh/HW05-Testing |
| 3 | Ba test plan (Load / Stress / Spike) đúng quy ước đặt tên | ✅ (kèm cả Soak) | `testplans/23127195_{Load,Stress,Spike,Soak}_20260816.jmx` |
| 4 | Ba log `.jtl` thô và ba thư mục HTML report | ✅ (kèm cả Soak → 4 bộ) | `results/jtl/` · `results/html/` |
| 5 | Ảnh chụp resource monitor và cấu hình phần cứng | ⚠️ **cần tự chụp** | `evidence/` — xem `evidence/README.md` |
| 6 | Link video YouTube unlisted | ⚠️ **cần tự quay** | Kịch bản: `docs/09_demo_video_script.md` |
| 7 | AI Critique và AI Audit Report (Markdown + PDF) | ✅ Markdown xong · ⚠️ **cần xuất PDF** | `docs/AI_CRITIQUE.md` · `docs/AI_AUDIT_REPORT.md` |
| 8 | Git commit log (file text) | ✅ | `git_commit_log.txt` |
| 9 | Bug report kèm ảnh chụp trang GitHub Issues | ✅ nội dung · ⚠️ **cần chụp trang Issues** | `docs/08_bug_report.md` · [Issues](https://github.com/hungtmh/HW05-Testing/issues) |
| 10 | `README.md` có bảng tự đánh giá và test summary report | ✅ | `README.md` |
| 11 | Tài liệu hỗ trợ khác | ✅ | `docs/`, `scripts/`, `skill/` |

---

## Đối chiếu chi tiết từng task

### Task 1 — Thiết kế và thực thi có AI hỗ trợ

| Yêu cầu | Tình trạng | Bằng chứng |
|---|---|---|
| Điều khiển AI **từng bước**, không phải một prompt tổng quát | ✅ | 14 prompt trong `docs/02` và `docs/AI_AUDIT_REPORT.md` |
| Ba test plan cùng chạy **một workflow E2E** phủ đủ 3 nhóm endpoint | ✅ | Sinh từ một nguồn duy nhất bằng `scripts/gen_variants.ps1` |
| AI giúp chọn think-time / ramp-up / số VU, có giải trình | ✅ | `docs/02` §P4–P6, kèm calibration thật |
| Giải trình workflow phủ từng nhóm endpoint thế nào | ✅ | `docs/02` §3, tỉ lệ 1 : 2 : 4 |
| **Dữ liệu hoá bằng CSV** | ✅ | 3 file trong `data/` |
| **Ba loại report view khác nhau**, không lặp | ✅ | Summary Report / Aggregate Report / View Results Tree (+ Aggregate Graph cho Soak) |
| Đặt tên `{StudentID}_{ScenarioType}_{YYYYMMDD}` | ✅ | `23127195_Load_20260816` v.v. |
| **Rà soát của con người**: AI sai/thiếu gì và **vì sao** | ✅ | `docs/03` — 7 lỗi, quy về 3 nhóm nguyên nhân |
| Chạy đủ 3 kịch bản, có ảnh chụp công cụ **và** resource monitor | ✅ số liệu · ⚠️ ảnh cần tự chụp | `results/` · `evidence/README.md` |
| Báo cáo phần cứng (dxdiag + bảng spec) | ✅ bảng spec · ⚠️ ảnh dxdiag cần tự chụp | `docs/04` §1.1 |
| Reset lockout giữa các lần chạy, **có ghi lại các bước** | ✅ | `docs/04` §3 · `scripts/reset_lockout.js` |
| Log `.jtl` thô và thư mục HTML report | ✅ | `results/jtl/` · `results/html/` |
| **Ngưỡng chịu đựng** qua soak 10–15 phút, báo bằng số cụ thể | ✅ | `docs/05` — soak 15 phút, 7 ngưỡng có số |
| Video demo ≥ 6 phút, công cụ và resource monitor **cùng khung hình**, thuyết minh tiếng Việt | ⚠️ **cần tự quay** | Kịch bản 8–9 phút: `docs/09` |
| Báo lỗi lên GitHub Issues kèm ảnh | ✅ 7 issue đã mở · ⚠️ cần chụp màn hình | [Issues](https://github.com/hungtmh/HW05-Testing/issues) |

### Task 2 — Phân tích bằng AI và săn lỗi diễn giải

| Yêu cầu | Tình trạng | Bằng chứng |
|---|---|---|
| Dùng AI phân tích log `.jtl` và đề xuất ngưỡng | ✅ | `docs/06` §1 |
| Chỉ ra chỗ AI đọc sai chỉ số, **trích giá trị đúng từ log thô** | ✅ | `docs/06` §2 — 6 lỗi, mỗi lỗi kèm lệnh kiểm chứng |
| Phân loại đề xuất tối ưu là **khả thi hay ảo tưởng**, có lý lẽ | ✅ | `docs/06` §4 — có **kiểm chứng A/B thực nghiệm** |

### Task 3 — Continuous Performance Testing

| Yêu cầu | Tình trạng | Bằng chứng |
|---|---|---|
| Mô hình theo dõi commit, quyết định có chạy test hay không, cảnh báo p95 suy giảm | ✅ | `docs/07` §2–3 |
| **Sơ đồ luồng** | ✅ | `docs/07` §2 (Mermaid, hiển thị trực tiếp trên GitHub) |
| Bàn về **đánh đổi** (chi phí, báo động giả) | ✅ | `docs/07` §4, có định lượng |

### Agent Skill

| Yêu cầu | Tình trạng | Bằng chứng |
|---|---|---|
| Skill áp dụng lại được quy trình này cho endpoint khác | ✅ | `skill/performance-testing-jmeter/` |
| Video demo dùng skill trên một nhóm endpoint hoàn chỉnh | ⚠️ **cần tự quay** | Có thể quay chung với video chính |

### Phụ lục bắt buộc

| Yêu cầu | Tình trạng | Bằng chứng |
|---|---|---|
| Tuyên bố dùng AI | ✅ | "I use AI tools for the following tasks" — `docs/AI_AUDIT_REPORT.md` |
| Với mỗi lần tương tác: tên công cụ, ngày giờ, prompt, đầu ra | ✅ | `docs/AI_AUDIT_REPORT.md` — 14 mục |
| AI Critique 200–300 từ | ✅ **đúng 300 từ** | `docs/AI_CRITIQUE.md` |
| Mỗi bước một Git commit | ✅ | `git_commit_log.txt` |

---

## Việc còn lại cần sinh viên tự làm

Bốn việc dưới đây **không thể tự động hoá** và là bằng chứng TA kiểm tra trực tiếp:

1. **Quay video demo** (≥ 6 phút, thuyết minh tiếng Việt, công cụ + Task Manager cùng khung hình).
   → Kịch bản chi tiết từng phần, có sẵn lời thoại: `docs/09_demo_video_script.md`
   → Sau khi quay: dán link vào `README.md` và `docs/00_MAIN_REPORT.md`

2. **Chụp ảnh màn hình** theo danh mục trong `evidence/README.md`
   → Gồm cả ảnh DxDiag (phải thấy hostname `DESKTOP-96ARBFL`) và ảnh trang GitHub Issues

3. **Xuất PDF** cho 3 tài liệu: `00_MAIN_REPORT.md`, `AI_AUDIT_REPORT.md`, `AI_CRITIQUE.md`
   → Cách nhanh: mở bằng VS Code + extension "Markdown PDF", hoặc dán vào Google Docs rồi xuất PDF

4. **Đóng gói** `23127195_HW05_AI_Performance_089.zip` và nộp lên Moodle
   → Điều chỉnh điểm tự chấm nếu muốn, nhớ đổi cả tên file lẫn bảng trong `README.md`

---

## Lệnh sinh nhanh dxdiag

```powershell
New-Item -ItemType Directory -Force evidence\hardware | Out-Null
dxdiag /t "$PWD\evidence\hardware\dxdiag_report.txt"
```

Sau đó mở `dxdiag` bằng giao diện (`Win + R` → `dxdiag`) và chụp màn hình cửa sổ đó lưu vào `evidence/hardware/dxdiag.png`.
