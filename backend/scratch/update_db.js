const { pool } = require('../src/config/db');
async function run() {
  try {
    await pool.query("ALTER TABLE users ADD COLUMN role ENUM('user', 'admin') DEFAULT 'user'");
    console.log('Added role column');
  } catch(e) {
    if (e.code === 'ER_DUP_FIELDNAME') {
      console.log('Role column already exists');
    } else {
      console.error(e.message);
    }
  } finally {
    process.exit();
  }
}
run();
