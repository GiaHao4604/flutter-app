const { pool } = require('../config/db');

async function createPost({ image_url, caption, device_id, camera_type }) {
  const [res] = await pool.execute(
    'INSERT INTO posts (image_url, caption, device_id, camera_type) VALUES (?, ?, ?, ?)',
    [image_url, caption || null, device_id || null, camera_type || null]
  );

  return { id: res.insertId };
}

async function getPosts({ page = 1, limit = 10 }) {
  const offset = (page - 1) * limit;
  const safeLimit = Number(limit);
  const safeOffset = Number(offset);

  const [rows] = await pool.query(
    `SELECT id, image_url, caption, device_id, camera_type, created_at
     FROM posts
     ORDER BY created_at DESC
     LIMIT ${safeLimit} OFFSET ${safeOffset}`
  );
  return rows;
}

async function getPostById(id) {
  const [rows] = await pool.execute('SELECT * FROM posts WHERE id = ?', [id]);
  return rows[0];
}

async function deletePost(id) {
  await pool.execute('DELETE FROM posts WHERE id = ?', [id]);
}

module.exports = { createPost, getPosts, getPostById, deletePost };
