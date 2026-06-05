const { pool } = require('../config/db');

async function createPost({ user_id, image_url, caption, device_id, camera_type }) {
  const [res] = await pool.execute(
    'INSERT INTO posts (user_id, image_url, caption, device_id, camera_type) VALUES (?, ?, ?, ?, ?)',
    [user_id || null, image_url, caption || null, device_id || null, camera_type || null],
  );

  return { id: res.insertId };
}

async function getPosts({ page = 1, limit = 10, userId = null }) {
  const offset = (page - 1) * limit;
  const safeLimit = Number(limit);
  const safeOffset = Number(offset);
  const queryParams = [];
  let whereClause = 'WHERE u.is_banned = 0';

  if (userId != null) {
    whereClause += ' AND p.user_id = ?';
    queryParams.push(userId);
  }

  const [rows] = await pool.query(
    `
      SELECT
        p.id,
        p.user_id,
        p.image_url,
        p.caption,
        p.created_at,
        u.name AS author_name,
        u.avatar_url AS author_avatar_url
      FROM posts p
      JOIN users u ON u.id = p.user_id
      ${whereClause}
      ORDER BY p.created_at DESC
      LIMIT ? OFFSET ?
    `,
    [...queryParams, safeLimit, safeOffset],
  );

  return rows;
}

module.exports = { createPost, getPosts };
