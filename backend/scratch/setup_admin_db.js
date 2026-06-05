const { pool } = require('../src/config/db');
const { hashPassword } = require('../src/utils/hash');

async function run() {
  try {
    console.log('Altering users table...');
    // Thêm cột role
    try {
      await pool.query("ALTER TABLE users ADD COLUMN role ENUM('user', 'admin') DEFAULT 'user'");
      console.log('Added role column');
    } catch(e) {
      if (e.code === 'ER_DUP_FIELDNAME') console.log('Role column already exists');
      else throw e;
    }

    // Thêm cột is_banned
    try {
      await pool.query("ALTER TABLE users ADD COLUMN is_banned TINYINT(1) DEFAULT 0");
      console.log('Added is_banned column');
    } catch(e) {
      if (e.code === 'ER_DUP_FIELDNAME') console.log('is_banned column already exists');
      else throw e;
    }

    console.log('Creating post_reports table...');
    await pool.query(`
      CREATE TABLE IF NOT EXISTS post_reports (
        id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        post_id INT UNSIGNED NOT NULL,
        user_id INT UNSIGNED NOT NULL,
        reason VARCHAR(255) NOT NULL,
        status ENUM('pending', 'resolved') DEFAULT 'pending',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('Created post_reports table');

    console.log('Creating admin user...');
    const email = 'yanghow4604@gmail.com';
    const password = 'bia123';
    const name = 'Admin YangHow';
    const pHash = hashPassword(password);
    
    // Check if exists
    const [existing] = await pool.query('SELECT id FROM users WHERE email = ?', [email]);
    if (existing.length > 0) {
       await pool.query('UPDATE users SET role = "admin", password_hash = ? WHERE email = ?', [pHash, email]);
       console.log('Updated existing user to Admin');
    } else {
       await pool.query('INSERT INTO users (name, email, password_hash, role) VALUES (?, ?, ?, "admin")', [name, email, pHash]);
       console.log('Created new Admin user');
    }

    console.log('Database migration completed successfully!');
  } catch(e) {
    console.error('Error:', e.message);
  } finally {
    process.exit();
  }
}
run();
