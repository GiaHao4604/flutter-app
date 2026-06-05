const { validationResult } = require('express-validator');
const postModel = require('../models/postModel');
const { getIO } = require('../utils/socket');

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
    const { caption, device_id, camera_type } = req.body;
    const userId = req.user?.sub || null;

    const result = await postModel.createPost({
      user_id: userId,
      image_url: imagePath,
      caption,
      device_id,
      camera_type,
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

    const rows = await postModel.getPosts({ page, limit, userId });

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
    }));

    return res.json({ success: true, data });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

module.exports = { uploadPost, listPosts };
