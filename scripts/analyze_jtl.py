#!/usr/bin/env python3
"""
analyze_jtl.py — Đọc file .jtl thô của JMeter và tính lại toàn bộ số liệu.

Vì sao cần script này thay vì chỉ nhìn HTML report:
  Task 2 của HW05 yêu cầu, với mỗi chỗ AI đọc sai chỉ số, phải trích ĐÚNG giá trị
  từ log .jtl thô. Muốn trích được thì phải có một cách tính độc lập, tái lập được,
  và nói rõ công thức. Script này làm đúng việc đó.

Những điểm cần lưu ý về cách tính (đã kiểm chứng lại với HTML report của JMeter):
  * JMeter ghi cả TRANSACTION CONTROLLER thành sample trong .jtl. Nếu cộng gộp thì
    throughput bị thổi lên ~43% (10 sample/vòng lặp thay vì 7 request thật).
    Script mặc định TÁCH RIÊNG hai nhóm này.
  * Percentile ở đây dùng phương pháp nearest-rank: p95 = phần tử thứ ceil(0.95*n)
    của dãy đã sắp xếp. JMeter HTML report dùng nội suy (Apache Commons Math), nên
    lệch 1-2 ms ở các mẫu nhỏ là bình thường, không phải sai số dữ liệu.
  * elapsed = tổng thời gian phản hồi; Latency = tới byte đầu tiên; Connect = thời
    gian bắt tay TCP. Ba cột này KHÁC nhau, đọc nhầm là nguồn sai sót phổ biến.

Dùng:
    python scripts/analyze_jtl.py results/jtl/23127195_Load_20260816.jtl
    python scripts/analyze_jtl.py <file.jtl> --time-buckets 30
    python scripts/analyze_jtl.py <file.jtl> --concurrency-buckets 50
    python scripts/analyze_jtl.py <file.jtl> --json results/jtl/load_stats.json
"""
import argparse
import csv
import json
import math
import os
import sys
from collections import defaultdict


def pct(sorted_vals, p):
    """Percentile theo nearest-rank. sorted_vals phải được sắp xếp tăng dần."""
    if not sorted_vals:
        return 0
    k = max(1, math.ceil(p / 100.0 * len(sorted_vals)))
    return sorted_vals[min(k, len(sorted_vals)) - 1]


def load(path):
    rows = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for r in csv.DictReader(f):
            try:
                r["_ts"] = int(r["timeStamp"])
                r["_el"] = int(r["elapsed"])
                r["_lat"] = int(r.get("Latency") or 0)
                r["_con"] = int(r.get("Connect") or 0)
                r["_all"] = int(r.get("allThreads") or 0)
                r["_ok"] = (r.get("success", "").lower() == "true")
            except (ValueError, KeyError, TypeError):
                continue
            rows.append(r)
    return rows


def stats_for(rows):
    if not rows:
        return None
    el = sorted(r["_el"] for r in rows)
    lat = sorted(r["_lat"] for r in rows)
    t0 = min(r["_ts"] for r in rows)
    t1 = max(r["_ts"] + r["_el"] for r in rows)
    span = max((t1 - t0) / 1000.0, 0.001)
    errs = [r for r in rows if not r["_ok"]]
    return {
        "count": len(rows),
        "errors": len(errs),
        "error_pct": round(100.0 * len(errs) / len(rows), 2),
        "avg_ms": round(sum(el) / len(el), 1),
        "min_ms": el[0],
        "p50_ms": pct(el, 50),
        "p90_ms": pct(el, 90),
        "p95_ms": pct(el, 95),
        "p99_ms": pct(el, 99),
        "max_ms": el[-1],
        "avg_latency_ms": round(sum(lat) / len(lat), 1),
        "span_s": round(span, 1),
        "throughput_per_s": round(len(rows) / span, 2),
    }


def fmt_table(title, per_label):
    out = [title, "-" * len(title)]
    hdr = f"{'Label':<38}{'N':>7}{'Err':>6}{'Err%':>7}{'Avg':>7}{'p50':>6}{'p90':>7}{'p95':>7}{'p99':>7}{'Max':>7}{'req/s':>8}"
    out.append(hdr)
    out.append("-" * len(hdr))
    for label, s in sorted(per_label.items(), key=lambda kv: -kv[1]["p95_ms"]):
        out.append(
            f"{label[:37]:<38}{s['count']:>7}{s['errors']:>6}{s['error_pct']:>7}"
            f"{s['avg_ms']:>7}{s['p50_ms']:>6}{s['p90_ms']:>7}{s['p95_ms']:>7}"
            f"{s['p99_ms']:>7}{s['max_ms']:>7}{s['throughput_per_s']:>8}"
        )
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("jtl")
    ap.add_argument("--time-buckets", type=int, default=0,
                    help="Gom theo cua so thoi gian N giay de xem xu huong")
    ap.add_argument("--concurrency-buckets", type=int, default=0,
                    help="Gom theo so VU dong thoi (cot allThreads), buoc N")
    ap.add_argument("--json", default=None, help="Ghi ket qua ra file JSON")
    args = ap.parse_args()

    rows = load(args.jtl)
    if not rows:
        print(f"Khong doc duoc mau nao tu {args.jtl}", file=sys.stderr)
        return 1

    tc = [r for r in rows if r["label"].startswith("TC-")]
    http = [r for r in rows if not r["label"].startswith("TC-")]

    result = {"file": os.path.basename(args.jtl)}
    print("=" * 100)
    print(f"FILE: {args.jtl}")
    print(f"Tong so ban ghi trong .jtl : {len(rows)}")
    print(f"  - request HTTP that su   : {len(http)}")
    print(f"  - sample cua Transaction Controller (KHONG phai request) : {len(tc)}")
    print("=" * 100)

    overall = stats_for(http)
    result["overall_http"] = overall
    print("\nTONG HOP TOAN BO REQUEST HTTP")
    print("-" * 34)
    for k, v in overall.items():
        print(f"  {k:<20}: {v}")

    per_label = {}
    by_label = defaultdict(list)
    for r in http:
        by_label[r["label"]].append(r)
    for label, rs in by_label.items():
        per_label[label] = stats_for(rs)
    result["per_label"] = per_label
    print()
    print(fmt_table("CHI TIET THEO TUNG REQUEST (sap xep theo p95 giam dan)", per_label))

    per_tc = {}
    by_tc = defaultdict(list)
    for r in tc:
        by_tc[r["label"]].append(r)
    for label, rs in by_tc.items():
        per_tc[label] = stats_for(rs)
    if per_tc:
        result["per_transaction"] = per_tc
        print()
        print(fmt_table("THEO TRANSACTION CONTROLLER (tong cua nhieu request, khong cong vao throughput)", per_tc))

    # --- Thong ke loi ---
    errs = [r for r in http if not r["_ok"]]
    if errs:
        by_code = defaultdict(int)
        by_msg = defaultdict(int)
        for r in errs:
            by_code[f"{r['label']} | {r['responseCode']}"] += 1
            msg = (r.get("failureMessage") or "").strip()[:90]
            if msg:
                by_msg[msg] += 1
        result["errors_by_code"] = dict(by_code)
        result["errors_by_message"] = dict(by_msg)
        print("\nPHAN LOAI LOI THEO responseCode")
        print("-" * 34)
        for k, v in sorted(by_code.items(), key=lambda kv: -kv[1]):
            print(f"  {v:>7}  {k}")
        print("\nPHAN LOAI LOI THEO failureMessage")
        print("-" * 36)
        for k, v in sorted(by_msg.items(), key=lambda kv: -kv[1])[:15]:
            print(f"  {v:>7}  {k}")
    else:
        print("\nKhong co request HTTP nao that bai.")

    # --- Xu huong theo thoi gian ---
    if args.time_buckets:
        t0 = min(r["_ts"] for r in http)
        buckets = defaultdict(list)
        for r in http:
            b = int((r["_ts"] - t0) / 1000 // args.time_buckets) * args.time_buckets
            buckets[b].append(r)
        print(f"\nXU HUONG THEO THOI GIAN (cua so {args.time_buckets}s)")
        print("-" * 78)
        print(f"{'t (s)':>8}{'N':>8}{'req/s':>9}{'avg':>8}{'p95':>8}{'max':>8}{'err%':>8}{'VU tb':>8}")
        series = []
        for b in sorted(buckets):
            rs = buckets[b]
            el = sorted(r["_el"] for r in rs)
            e = sum(1 for r in rs if not r["_ok"])
            vu = round(sum(r["_all"] for r in rs) / len(rs), 1)
            row = {"t_s": b, "count": len(rs), "rps": round(len(rs) / args.time_buckets, 2),
                   "avg_ms": round(sum(el) / len(el), 1), "p95_ms": pct(el, 95),
                   "max_ms": el[-1], "error_pct": round(100.0 * e / len(rs), 2), "avg_vu": vu}
            series.append(row)
            print(f"{b:>8}{len(rs):>8}{row['rps']:>9}{row['avg_ms']:>8}{row['p95_ms']:>8}{row['max_ms']:>8}{row['error_pct']:>8}{vu:>8}")
        result["time_series"] = series

    # --- Duong cong theo do dong thoi ---
    if args.concurrency_buckets:
        step = args.concurrency_buckets
        buckets = defaultdict(list)
        for r in http:
            buckets[(r["_all"] // step) * step].append(r)
        print(f"\nDUONG CONG THEO DO DONG THOI (buoc {step} VU) - dung de tim diem goi (knee)")
        print("-" * 72)
        print(f"{'VU':>8}{'N':>9}{'req/s':>9}{'avg':>8}{'p95':>8}{'max':>8}{'err%':>8}")
        series = []
        for b in sorted(buckets):
            rs = buckets[b]
            el = sorted(r["_el"] for r in rs)
            e = sum(1 for r in rs if not r["_ok"])
            t0b = min(r["_ts"] for r in rs)
            t1b = max(r["_ts"] + r["_el"] for r in rs)
            span = max((t1b - t0b) / 1000.0, 0.001)
            row = {"vu_from": b, "vu_to": b + step - 1, "count": len(rs),
                   "rps": round(len(rs) / span, 2), "avg_ms": round(sum(el) / len(el), 1),
                   "p95_ms": pct(el, 95), "max_ms": el[-1],
                   "error_pct": round(100.0 * e / len(rs), 2)}
            series.append(row)
            print(f"{str(b) + '-' + str(b + step - 1):>8}{len(rs):>9}{row['rps']:>9}{row['avg_ms']:>8}{row['p95_ms']:>8}{row['max_ms']:>8}{row['error_pct']:>8}")
        result["concurrency_series"] = series

    if args.json:
        os.makedirs(os.path.dirname(args.json) or ".", exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        print(f"\nDa ghi JSON: {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
