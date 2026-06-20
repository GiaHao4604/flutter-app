const { pool } = require('../config/db');

async function createPost({ user_id, image_url, caption, device_id, camera_type, calendar_entry_id }) {
  const [res] = await pool.execute(
    'INSERT INTO posts (user_id, image_url, caption, device_id, camera_type, calendar_entry_id) VALUES (?, ?, ?, ?, ?, ?)',
    [user_id || null, image_url, caption || null, device_id || null, camera_type || null, calendar_entry_id || null],
  );

  return { id: res.insertId };
}

async function getPosts({ page = 1, limit = 10, userId = null, currentUserId = null }) {
  const offset = (page - 1) * limit;
  const safeLimit = Number(limit);
  const safeOffset = Number(offset);
  const queryParams = [];

  let whereClause = 'WHERE u.is_banned = 0';
  if (userId != null) {
    whereClause += ' AND p.user_id = ?';
    queryParams.push(userId);
  }
  queryParams.push(safeLimit, safeOffset);

  const [rows] = await pool.query(
    `
      SELECT
        p.id,
        p.user_id,
        p.image_url,
        p.caption,
        p.created_at,
        u.name AS author_name,
        u.avatar_url AS author_avatar_url,
        c.name AS category_name,
        c.icon_key AS category_icon_key,
        c.color AS category_color,
        t.amount AS transaction_amount,
        t.is_expense AS transaction_is_expense
      FROM posts p
      JOIN users u ON u.id = p.user_id
      LEFT JOIN calendar_entries ce ON ce.id = p.calendar_entry_id
      LEFT JOIN transactions t ON t.calendar_entry_id = ce.id
      LEFT JOIN categories c ON c.id = t.category_id
      ${whereClause}
      ORDER BY p.created_at DESC
      LIMIT ? OFFSET ?
    `,
    queryParams
  );

  if (rows.length === 0) return [];

  const postIds = rows.map(r => r.id);

  const [reactions] = await pool.query(
    `
      SELECT pr.post_id, pr.user_id, pr.reaction_icon, pr.created_at, u.name AS reactor_name, u.avatar_url AS reactor_avatar_url
      FROM post_reactions pr
      JOIN users u ON u.id = pr.user_id
      WHERE pr.post_id IN (?)
      ORDER BY pr.created_at DESC, pr.id DESC
    `,
    [postIds]
  );

  const reactionsByPost = {};
  for (const row of rows) {
    reactionsByPost[row.id] = [];
  }
  for (const r of reactions) {
    reactionsByPost[r.post_id].push(r);
  }

  for (const row of rows) {
    const postReactions = reactionsByPost[row.id];
    
    row.my_reaction = null;
    if (currentUserId != null) {
      const myReact = postReactions.find(r => r.user_id == currentUserId);
      if (myReact) row.my_reaction = myReact.reaction_icon;
    }

    const r1 = postReactions[0];
    if (r1) {
      row.reactor_name_1 = r1.reactor_name;
      row.reactor_avatar_1 = r1.reactor_avatar_url;
      row.reaction_icon_1 = r1.reaction_icon;
    }

    const r2 = postReactions[1];
    if (r2) {
      row.reactor_name_2 = r2.reactor_name;
      row.reactor_avatar_2 = r2.reactor_avatar_url;
      row.reaction_icon_2 = r2.reaction_icon;
    }
  }

  return rows;
}

module.exports = { createPost, getPosts };
