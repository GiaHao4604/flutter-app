const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { pool } = require('../config/db');

function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

function verifyPassword(password, storedValue) {
  const [salt, originalHash] = String(storedValue).split(':');

  if (!salt || !originalHash) {
    return false;
  }

  const hashBuffer = crypto.scryptSync(password, salt, 64);
  const originalBuffer = Buffer.from(originalHash, 'hex');

  if (originalBuffer.length !== hashBuffer.length) {
    return false;
  }

  return crypto.timingSafeEqual(originalBuffer, hashBuffer);
}

function normalizeUserRow(row) {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    avatar_url: row.avatar_url || null,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

async function getMyProfile(req, res) {
  try {
    const userId = Number(req.user?.sub);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const [rows] = await pool.query(
      'SELECT id, name, email, avatar_url, created_at, updated_at FROM users WHERE id = ? LIMIT 1',
      [userId],
    );

    if (!rows.length) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    return res.json({ success: true, message: 'Get profile successful', data: normalizeUserRow(rows[0]) });
  } catch (error) {
    console.error('[profile] getMyProfile error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function getProfileById(req, res) {
  try {
    const userId = Number(req.params.id);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid profile id' });
    }

    const [rows] = await pool.query(
      'SELECT id, name, avatar_url, created_at, updated_at FROM users WHERE id = ? LIMIT 1',
      [userId],
    );

    if (!rows.length) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    return res.json({ success: true, message: 'Get public profile successful', data: rows[0] });
  } catch (error) {
    console.error('[profile] getProfileById error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function updateMyProfile(req, res) {
  try {
    const userId = Number(req.user?.sub);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const name = req.body.name != null ? String(req.body.name).trim() : undefined;
    const updates = [];
    const values = [];

    if (name !== undefined) {
      if (!name) {
        return res.status(400).json({ success: false, message: 'Name cannot be empty' });
      }
      if (name.length > 100) {
        return res.status(400).json({ success: false, message: 'Name is too long' });
      }
      updates.push('name = ?');
      values.push(name);
    }

    if (!updates.length) {
      return res.status(400).json({ success: false, message: 'No fields to update' });
    }

    values.push(userId);
    await pool.query(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`, values);

    const [rows] = await pool.query(
      'SELECT id, name, email, avatar_url, created_at, updated_at FROM users WHERE id = ? LIMIT 1',
      [userId],
    );

    return res.json({ success: true, message: 'Profile updated successfully', data: normalizeUserRow(rows[0]) });
  } catch (error) {
    console.error('[profile] updateMyProfile error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function updateMyAvatar(req, res) {
  try {
    const userId = Number(req.user?.sub);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Please choose an image file' });
    }

    const avatarUrl = `${req.protocol}://${req.headers.host}/uploads/avatars/${req.file.filename}`;
    const savedPath = path.join(__dirname, '..', '..', 'uploads', 'avatars', req.file.filename);

    if (!fs.existsSync(savedPath)) {
      return res.status(500).json({ success: false, message: 'Avatar file was not saved correctly' });
    }

    await pool.query('UPDATE users SET avatar_url = ? WHERE id = ?', [avatarUrl, userId]);

    const [rows] = await pool.query(
      'SELECT id, name, email, avatar_url, created_at, updated_at FROM users WHERE id = ? LIMIT 1',
      [userId],
    );

    return res.status(200).json({
      success: true,
      message: 'Avatar updated successfully',
      avatar_url: avatarUrl,
      data: normalizeUserRow(rows[0]),
    });
  } catch (error) {
    console.error('[profile] updateMyAvatar error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function updateMyPassword(req, res) {
  try {
    const userId = Number(req.user?.sub);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const currentPassword = String(req.body.currentPassword || '').trim();
    const newPassword = String(req.body.newPassword || '').trim();
    const confirmPassword = String(req.body.confirmPassword || '').trim();

    if (!currentPassword || !newPassword || !confirmPassword) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập đủ mật khẩu hiện tại, mật khẩu mới và xác nhận mật khẩu' });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({ success: false, message: 'Mật khẩu mới phải có ít nhất 6 ký tự' });
    }

    if (newPassword !== confirmPassword) {
      return res.status(400).json({ success: false, message: 'Mật khẩu xác nhận không khớp' });
    }

    const [rows] = await pool.query(
      'SELECT password_hash FROM users WHERE id = ? LIMIT 1',
      [userId],
    );

    if (!rows.length) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    const isValid = verifyPassword(currentPassword, rows[0].password_hash);
    if (!isValid) {
      return res.status(401).json({ success: false, message: 'Mật khẩu hiện tại không đúng' });
    }

    const nextPasswordHash = hashPassword(newPassword);
    await pool.query('UPDATE users SET password_hash = ? WHERE id = ?', [nextPasswordHash, userId]);

    return res.json({
      success: true,
      message: 'Đổi mật khẩu thành công',
    });
  } catch (error) {
    console.error('[profile] updateMyPassword error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

module.exports = {
  getMyProfile,
  getProfileById,
  updateMyProfile,
  updateMyAvatar,
  updateMyPassword,
};