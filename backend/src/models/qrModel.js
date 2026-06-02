
const { pool } = require('../config/db');

async function insertQR({ qr_code, qr_type }) {
  const [res] = await pool.execute('INSERT INTO qr_logs (qr_code, qr_type) VALUES (?, ?)', [qr_code, qr_type || null]);
  return { id: res.insertId };
}

module.exports = { insertQR };
