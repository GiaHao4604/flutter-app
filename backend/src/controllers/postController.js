const path = require('path');
const fs = require('fs');
const { validationResult } = require('express-validator');
const postModel = require('../models/postModel');
const { getIO } = require('../utils/socket');

async function uploadPost(req, res) {
  try {
    console.log('POST /api/posts/upload called');
    console.log('Headers:', {
      host: req.headers.host,
      'content-length': req.headers['content-length'],
      'content-type': req.headers['content-type'],
      'user-agent': req.headers['user-agent'],
    });

    console.log('Body fields before multer:', req.body);
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });

    if (!req.file) {
      console.warn('No req.file present after multer');
      return res.status(400).json({ success: false, message: 'No file uploaded' });
    }

    const imageUrl = `/uploads/posts/${req.file.filename}`;
    const { caption, device_id, camera_type } = req.body;

    console.log('Received fields:', { caption, device_id, camera_type });
    console.log('Uploaded file:', {
      originalname: req.file.originalname,
      mimetype: req.file.mimetype,
      size: req.file.size,
      path: req.file.path,
    });

    const result = await postModel.createPost({ image_url: imageUrl, caption, device_id, camera_type });

    const postData = { id: result.id, imageUrl, createdAt: new Date().toISOString() };

    // broadcast via socket.io
    try { getIO().emit('new_post', postData); } catch (e) { /* ignore if io not ready */ }

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
    const rows = await postModel.getPosts({ page, limit });

    const data = rows.map((r) => ({ id: r.id, imageUrl: r.image_url, caption: r.caption, createdAt: r.created_at }));

    return res.json({ success: true, data });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function deletePost(req, res) {
  try {
    const id = req.params.id;
    const deviceHeader = req.headers['x-device-id'];

    const post = await postModel.getPostById(id);
    if (!post) return res.status(404).json({ success: false, message: 'Post not found' });

    // permission check: device must match
    if (!deviceHeader || deviceHeader !== post.device_id) {
      return res.status(403).json({ success: false, message: 'No permission to delete' });
    }

    // delete file
    const filepath = path.join(__dirname, '..', post.image_url.replace(/^\//, ''));
    fs.unlink(filepath, (err) => { if (err) console.warn('unlink error', err); });

    await postModel.deletePost(id);

    return res.json({ success: true, message: 'Deleted' });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

module.exports = { uploadPost, listPosts, deletePost };
