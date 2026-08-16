/*
 * db_tool.js — Thao tác trực tiếp trên file SQLite của SUT.
 *
 * Tách riêng ra file này thay vì nhúng JS vào chuỗi `node -e "..."` trong PowerShell:
 * cách nhúng đó liên tục vỡ vì PowerShell tự phân tích các ký tự (), [], => trong chuỗi.
 *
 * Dùng:
 *   node scripts/db_tool.js count-orders
 *   node scripts/db_tool.js journal-mode
 *   node scripts/db_tool.js set-wal
 *   node scripts/db_tool.js create-index
 *   node scripts/db_tool.js drop-index
 *   node scripts/db_tool.js seed-orders <so_luong>
 *
 * Biến môi trường SUT_BACKEND trỏ tới thư mục backend của SUT
 * (mặc định D:\Kiem_thu\eshop-sut\backend).
 */
const path = require("path");

const SUT_BACKEND = process.env.SUT_BACKEND || "D:\\Kiem_thu\\eshop-sut\\backend";
const DB_PATH = path.join(SUT_BACKEND, "database.sqlite");
const sqlite3 = require(path.join(SUT_BACKEND, "node_modules", "sqlite3"));

const cmd = process.argv[2];
const arg = process.argv[3];

const db = new sqlite3.Database(DB_PATH, (err) => {
  if (err) {
    console.error(`ERR khong mo duoc DB ${DB_PATH}: ${err.message}`);
    process.exit(1);
  }
});

function done(err) {
  if (err) {
    console.error(`ERR ${err.message}`);
    db.close();
    process.exit(1);
  }
  db.close();
}

switch (cmd) {
  case "count-orders":
    db.get("SELECT COUNT(*) AS c FROM orders", [], (e, r) => {
      if (e) return done(e);
      console.log(r.c);
      done();
    });
    break;

  case "journal-mode":
    db.get("PRAGMA journal_mode", [], (e, r) => {
      if (e) return done(e);
      console.log(r.journal_mode);
      done();
    });
    break;

  case "set-wal":
    // journal_mode la thuoc tinh BEN VUNG cua file DB: dat mot lan la con mai,
    // ke ca sau khi DROP TABLE. Vi vay phai dat lai sau moi lan reset SUT.
    db.get("PRAGMA journal_mode=WAL", [], (e, r) => {
      if (e) return done(e);
      console.log(r.journal_mode);
      done();
    });
    break;

  case "create-index":
    db.run("CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id)", [], (e) => {
      if (e) return done(e);
      console.log("created idx_orders_user_id");
      done();
    });
    break;

  case "drop-index":
    db.run("DROP INDEX IF EXISTS idx_orders_user_id", [], (e) => {
      if (e) return done(e);
      console.log("dropped idx_orders_user_id");
      done();
    });
    break;

  case "seed-orders": {
    const n = parseInt(arg, 10);
    if (!n || n < 1) {
      console.error("ERR can truyen so luong don hang, vi du: seed-orders 40000");
      process.exit(1);
    }
    db.serialize(() => {
      db.all("SELECT id FROM users WHERE email LIKE 'perf%'", [], (e, rows) => {
        if (e) return done(e);
        if (!rows.length) return done(new Error("khong tim thay tai khoan perf, chay seed_users.js truoc"));
        const ids = rows.map((r) => r.id);
        db.run("BEGIN TRANSACTION");
        const st = db.prepare(
          "INSERT INTO orders (user_id, total_amount, status, shipping_address) VALUES (?,?,?,?)",
        );
        for (let i = 0; i < n; i++) {
          st.run(ids[i % ids.length], 1000000 + i, "pending", "seed-" + i);
        }
        st.finalize(() => {
          db.run("COMMIT", () => {
            db.get("SELECT COUNT(*) AS c FROM orders", [], (e2, r) => {
              if (e2) return done(e2);
              console.log(r.c);
              done();
            });
          });
        });
      });
    });
    break;
  }

  default:
    console.error(`ERR lenh khong hop le: ${cmd}`);
    console.error("Cac lenh: count-orders | journal-mode | set-wal | create-index | drop-index | seed-orders <n>");
    process.exit(1);
}
