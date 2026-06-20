const { validationResult } = require('express-validator');
const postModel = require('../models/postModel');
const { getIO } = require('../utils/socket');
const { pool } = require('../config/db');

function getMediaUrl(req, rawUrl) {
  if (!rawUrl) return null;
  const value = rawUrl.toString().trim();
  if (!value) return null;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }
  const root = `${req.protocol}://${req.get('host')}`;
  if (value.startsWith('/')) {
    return `${root}${value}`;
  }
  return `${root}/${value}`;
}

async function uploadPost(req, res) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });

    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No file uploaded' });
    }

    const imagePath = `/uploads/posts/${req.file.filename}`;
    const imageUrl = getMediaUrl(req, imagePath);
    const { caption, device_id, camera_type, calendar_entry_id } = req.body;
    const userId = req.user?.sub || null;

    const result = await postModel.createPost({
      user_id: userId,
      image_url: imagePath,
      caption,
      device_id,
      camera_type,
      calendar_entry_id: calendar_entry_id ? Number(calendar_entry_id) : null,
    });

    const postData = { id: result.id, imageUrl, createdAt: new Date().toISOString() };

    try {
      getIO().emit('new_post', postData);
    } catch (_) {
      // ignore socket errors
    }

    return res.json({ success: true, message: 'Upload thành công', data: postData });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function listPosts(req, res) {
  try {
    const page = Number(req.query.page || 1);
    const limit = Number(req.query.limit || 12);
    const myPosts = req.query.my === '1' || String(req.query.my).toLowerCase() === 'true';
    const userId = myPosts ? req.user?.sub : null;
    const currentUserId = req.user?.sub || null;

    const rows = await postModel.getPosts({ page, limit, userId, currentUserId });

    const data = rows.map((row) => ({
      id: row.id,
      imageUrl: getMediaUrl(req, row.image_url),
      caption: row.caption,
      createdAt: row.created_at,
      author: {
        id: row.user_id,
        name: row.author_name || 'Người dùng',
        avatarUrl: getMediaUrl(req, row.author_avatar_url),
      },
      categoryName: currentUserId == row.user_id ? row.category_name : null,
      categoryIconKey: currentUserId == row.user_id ? row.category_icon_key : null,
      categoryColor: currentUserId == row.user_id ? row.category_color : null,
      transactionAmount: currentUserId == row.user_id ? (row.transaction_amount != null ? Number(row.transaction_amount) : null) : null,
      transactionIsExpense: currentUserId == row.user_id ? (row.transaction_is_expense != null ? row.transaction_is_expense === 1 : null) : null,
      myReaction: row.my_reaction || null,
      latestReaction: row.reaction_icon_1 ? {
        reactorName: row.reactor_name_1 || 'Người dùng',
        reactorAvatarUrl: getMediaUrl(req, row.reactor_avatar_1),
        reactionIcon: row.reaction_icon_1,
      } : null,
      secondReaction: row.reaction_icon_2 ? {
        reactorName: row.reactor_name_2 || 'Người dùng',
        reactorAvatarUrl: getMediaUrl(req, row.reactor_avatar_2),
        reactionIcon: row.reaction_icon_2,
      } : null,
    }));

    return res.json({ success: true, data });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function reportPost(req, res) {
  try {
    const postId = req.params.id;
    const userId = req.user?.sub || null;
    const { reason = 'Báo cáo bài viết vi phạm' } = req.body;

    const [posts] = await pool.query('SELECT id, user_id FROM posts WHERE id = ?', [postId]);
    if (posts.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy bài viết' });
    }

    if (posts[0].user_id == userId) {
      return res.status(400).json({ success: false, message: 'Bạn không thể báo cáo bài viết của chính mình' });
    }

    const [existing] = await pool.query('SELECT id FROM post_reports WHERE post_id = ? AND user_id = ?', [postId, userId]);
    if (existing.length > 0) {
      return res.status(400).json({ success: false, message: 'Bạn đã báo cáo bài viết này rồi' });
    }

    await pool.query(
      'INSERT INTO post_reports (post_id, user_id, reason, status) VALUES (?, ?, ?, "pending")',
      [postId, userId, reason],
    );

    return res.json({ success: true, message: 'Báo cáo bài viết thành công' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function deletePost(req, res) {
  try {
    const postId = req.params.id;
    const userId = req.user?.sub;

    const [posts] = await pool.query('SELECT user_id, calendar_entry_id FROM posts WHERE id = ?', [postId]);
    if (posts.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy bài viết' });
    }

    if (posts[0].user_id != userId) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền xóa bài viết này' });
    }

    const calEntryId = posts[0].calendar_entry_id;
    if (calEntryId) {
      await pool.query('DELETE FROM calendar_entries WHERE id = ? AND user_id = ?', [calEntryId, userId]);
      await pool.query('DELETE FROM posts WHERE id = ?', [postId]);
    } else {
      await pool.query('DELETE FROM posts WHERE id = ?', [postId]);
    }

    return res.json({ success: true, message: 'Đã xóa bài viết thành công' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function reactPost(req, res) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });

    const postId = req.params.id;
    const userId = req.user?.sub;
    const { reaction_icon } = req.body;

    if (!userId) {
      return res.status(401).json({ success: false, message: 'Bạn chưa đăng nhập' });
    }

    const [posts] = await pool.query('SELECT id FROM posts WHERE id = ?', [postId]);
    if (posts.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy bài viết' });
    }

    const [existing] = await pool.query(
      'SELECT id, reaction_icon FROM post_reactions WHERE post_id = ? AND user_id = ?',
      [postId, userId]
    );

    if (existing.length > 0) {
      if (existing[0].reaction_icon === reaction_icon) {
        await pool.query('DELETE FROM post_reactions WHERE id = ?', [existing[0].id]);
        return res.json({ success: true, message: 'Đã bỏ thả cảm xúc', data: { reacted: false } });
      } else {
        await pool.query('UPDATE post_reactions SET reaction_icon = ? WHERE id = ?', [reaction_icon, existing[0].id]);
        return res.json({ success: true, message: 'Đã cập nhật cảm xúc', data: { reacted: true, reactionIcon: reaction_icon } });
      }
    } else {
      await pool.query(
        'INSERT INTO post_reactions (post_id, user_id, reaction_icon) VALUES (?, ?, ?)',
        [postId, userId, reaction_icon]
      );
      return res.json({ success: true, message: 'Đã thả cảm xúc thành công', data: { reacted: true, reactionIcon: reaction_icon } });
    }
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function getPostReactions(req, res) {
  try {
    const postId = req.params.id;
    const [rows] = await pool.query(`
      SELECT pr.reaction_icon, u.name as reactorName, u.avatar_url as reactorAvatarUrl, pr.created_at
      FROM post_reactions pr
      JOIN users u ON pr.user_id = u.id
      WHERE pr.post_id = ?
      ORDER BY pr.created_at DESC
    `, [postId]);

    const reactions = rows.map(r => ({
      reactorName: r.reactorName,
      reactorAvatarUrl: r.reactorAvatarUrl,
      reactionIcon: r.reaction_icon,
      createdAt: r.created_at
    }));

    return res.json({ success: true, data: reactions });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

module.exports = { uploadPost, listPosts, reportPost, deletePost, reactPost, getPostReactions };
