/*
 * seed_users.js — nạp tài khoản tải từ data/users.csv vào SUT qua POST /api/register
 *
 * BẮT BUỘC chạy lại sau MỖI lần khởi động backend:
 * backend/database.js gọi initDatabase() ở mức module, mà hàm này DROP TABLE
 * toàn bộ rồi seed lại → mọi tài khoản đăng ký ở lần chạy trước đều biến mất.
 *
 * Dùng:  node scripts/seed_users.js [baseUrl] [csvPath]
 * Mặc định: http://localhost:3000  và  ./data/users.csv
 */
const fs = require("fs");
const path = require("path");

const BASE_URL = process.argv[2] || "http://localhost:3000";
const CSV_PATH = process.argv[3] || path.join(__dirname, "..", "data", "users.csv");

function parseCsv(file) {
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/).filter((l) => l.trim());
  const header = lines.shift().split(",");
  return lines.map((line) => {
    const cells = line.split(",");
    return Object.fromEntries(header.map((h, i) => [h.trim(), (cells[i] || "").trim()]));
  });
}

async function register(user) {
  const res = await fetch(`${BASE_URL}/api/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      name: user.fullname,
      email: user.email,
      password: user.password,
    }),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}

async function verifyLogin(user) {
  const res = await fetch(`${BASE_URL}/api/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: user.email, password: user.password }),
  });
  return res.status;
}

(async () => {
  const users = parseCsv(CSV_PATH);
  console.log(`[seed] ${users.length} tài khoản từ ${CSV_PATH} → ${BASE_URL}`);

  let ok = 0;
  let failed = 0;
  for (const u of users) {
    try {
      const r = await register(u);
      if (r.status === 200) ok++;
      else {
        failed++;
        console.error(`[seed] LỖI ${u.email}: HTTP ${r.status} ${JSON.stringify(r.body)}`);
      }
    } catch (e) {
      failed++;
      console.error(`[seed] LỖI ${u.email}: ${e.message}`);
    }
  }
  console.log(`[seed] đăng ký xong: ${ok} thành công, ${failed} thất bại`);

  // Kiểm tra chéo: tài khoản đầu, giữa, cuối phải đăng nhập được.
  // Nếu bước này hỏng thì test plan sẽ hỏng dây chuyền ngay từ request đầu tiên.
  const probes = [users[0], users[Math.floor(users.length / 2)], users[users.length - 1]];
  for (const p of probes) {
    const status = await verifyLogin(p);
    console.log(`[verify] login ${p.email} → HTTP ${status}${status === 200 ? " OK" : " ✗"}`);
    if (status !== 200) process.exitCode = 1;
  }
})();
