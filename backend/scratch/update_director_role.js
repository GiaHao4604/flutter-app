const { pool } = require('../src/config/db');

async function updateDb() {
  try {
    console.log('Altering users table to add director_admin role...');
    await pool.query("ALTER TABLE users MODIFY COLUMN role enum('user', 'admin', 'director_admin') DEFAULT 'user'");
    
    console.log('Setting yanghow4604@gmail.com to director_admin...');
    await pool.query("UPDATE users SET role = 'director_admin' WHERE email = 'yanghow4604@gmail.com'");
    
    console.log('Database updated successfully.');
  } catch(e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
updateDb();
