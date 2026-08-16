/*
 * reset_lockout.js — gỡ khoá tài khoản bị lockout giữa các lần chạy test.
 *
 * Vì sao cần: server.js:54 cộng login_attempts += 2 cho mỗi lần sai, ngưỡng khoá
 * là >= 3 → tài khoản bị khoá NGAY Ở LẦN SAI THỨ HAI, khoá 180.000 ms (3 phút).
 * Không có endpoint HTTP nào gỡ khoá được (login thành công mới reset, mà đang
 * khoá thì không login được), nên phải ghi thẳng vào SQLite.
 *
 * Dùng:  node scripts/reset_lockout.js [duongDanDatabase.sqlite]
 * Mặc định: D:\Kiem_thu\eshop-sut\backend\database.sqlite
 * Có thể đặt biến môi trường SUT_BACKEND để trỏ tới thư mục backend của SUT.
 */
const path = require("path");

const SUT_BACKEND = process.env.SUT_BACKEND || "D:\\Kiem_thu\\eshop-sut\\backend";
const DB_PATH = process.argv[2] || path.join(SUT_BACKEND, "database.sqlite");

// sqlite3 không được cài trong repo bài tập — mượn module đã có sẵn của SUT.
const sqlite3 = require(path.join(SUT_BACKEND, "node_modules", "sqlite3"));

const db = new sqlite3.Database(DB_PATH, (err) => {
  if (err) {
    console.error(`[reset] Không mở được DB tại ${DB_PATH}: ${err.message}`);
    process.exit(1);
  }
});

db.serialize(() => {
  db.all(
    "SELECT id, email, login_attempts, locked_until FROM users WHERE locked_until IS NOT NULL OR login_attempts > 0",
    [],
    (err, rows) => {
      if (err) {
        console.error(`[reset] Lỗi truy vấn: ${err.message}`);
        process.exit(1);
      }
      console.log(`[reset] Trước khi reset: ${rows.length} tài khoản có login_attempts > 0 hoặc đang bị khoá`);
      rows.forEach((r) =>
        console.log(`        id=${r.id} ${r.email} attempts=${r.login_attempts} locked_until=${r.locked_until}`),
      );

      db.run("UPDATE users SET login_attempts = 0, locked_until = NULL", function (err2) {
        if (err2) {
          console.error(`[reset] Lỗi UPDATE: ${err2.message}`);
          process.exit(1);
        }
        console.log(`[reset] Đã gỡ khoá / đặt lại bộ đếm cho ${this.changes} bản ghi users.`);

        db.get(
          "SELECT COUNT(*) AS still_locked FROM users WHERE locked_until IS NOT NULL",
          [],
          (err3, row) => {
            console.log(`[reset] Kiểm tra lại: còn ${row.still_locked} tài khoản bị khoá (kỳ vọng 0).`);
            db.close();
          },
        );
      });
    },
  );
});
