const crypto = require('crypto');
const { pool } = require('../src/config/db');

function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

async function fix() {
  try {
    const pHash = hashPassword('bia123');
    await pool.query('UPDATE users SET password_hash = ? WHERE email = "yanghow4604@gmail.com"', [pHash]);
    console.log('Fixed password hash in DB!');
  } catch(e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
fix();
