const { pool } = require('../src/config/db');
const fs = require('fs/promises');
const path = require('path');

async function cleanup() {
  try {
    // Tìm các post bị mồ côi (không có user_id)
    const [orphanedPosts] = await pool.query('SELECT id, image_url FROM posts WHERE user_id IS NULL');
    console.log(`Tìm thấy ${orphanedPosts.length} bài đăng rác (mồ côi)...`);

    let deletedFiles = 0;
    for (const post of orphanedPosts) {
      if (post.image_url && post.image_url.startsWith('/uploads')) {
        const filePath = path.join(__dirname, '..', 'public', post.image_url);
        try {
          await fs.unlink(filePath);
          deletedFiles++;
        } catch (err) {
          // File có thể không tồn tại
        }
      }
    }
    console.log(`Đã dọn dẹp ${deletedFiles} file vật lý bị mồ côi.`);

    // Xóa khỏi DB
    const [result] = await pool.query('DELETE FROM posts WHERE user_id IS NULL');
    console.log(`Đã xóa ${result.affectedRows} bài đăng mồ côi khỏi Database.`);

  } catch(e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
cleanup();
