
const { pool } = require('../config/db');

async function insertFlash(mode) {
  const [res] = await pool.execute('INSERT INTO camera_settings (flash_mode) VALUES (?)', [mode]);
  return { id: res.insertId };
}

async function insertZoom(zoom) {
  const [res] = await pool.execute('INSERT INTO camera_settings (zoom_level) VALUES (?)', [Number(zoom)]);
  return { id: res.insertId };
}

module.exports = { insertFlash, insertZoom };
