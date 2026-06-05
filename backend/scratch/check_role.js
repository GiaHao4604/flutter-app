const { pool } = require('../src/config/db');

async function test() {
  try {
    const [rows] = await pool.query("SELECT role FROM users WHERE email='yanghow4604@gmail.com'");
    console.log(rows);
  } catch(e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
