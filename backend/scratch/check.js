const crypto = require('crypto');
const { pool } = require('../src/config/db');

async function test() {
  try {
    const [rows] = await pool.query('SELECT password_hash FROM users WHERE email="yanghow4604@gmail.com"');
    if (rows.length === 0) {
      console.log('User not found!');
    } else {
      console.log('Hash in DB:', rows[0].password_hash);
      const expectedHash = crypto.scryptSync('bia123', 'bia0905849427', 64).toString('hex');
      console.log('Expected:  ', expectedHash);
      if (rows[0].password_hash === expectedHash) {
        console.log('MATCH!');
      } else {
        console.log('NOT MATCH!');
      }
    }
  } catch(e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
