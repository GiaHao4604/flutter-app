const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { pool } = require('../config/db');

// --- CÁC HÀM TRỢ GIÚP (HELPERS) ---

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

function createAccessToken(user) {
  return jwt.sign(
    {
      sub: user.id,
      email: user.email,
      name: user.name,
    },
    process.env.JWT_SECRET,
    {
      expiresIn: process.env.JWT_EXPIRES_IN || '7d',
    },
  );
}

// --- CÁC HÀM XỬ LÝ CHÍNH (LOGIC CONTROLLERS) ---

async function register(req, res) {
  try {
    const name = String(req.body.name || '').trim();
    const email = String(req.body.email || '').trim().toLowerCase();
    const password = String(req.body.password || '');

    if (!name || !email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Name, email, and password are required',
      });
    }

    if (password.length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters',
      });
    }

    const [existingUsers] = await pool.query('SELECT id FROM users WHERE email = ? LIMIT 1', [email]);

    if (existingUsers.length > 0) {
      return res.status(409).json({
        success: false,
        message: 'Email này đã tồn tại, vui lòng sử dụng email khác',
      });
    }

    const passwordHash = hashPassword(password);

    const [result] = await pool.query(
      'INSERT INTO users (name, email, password_hash) VALUES (?, ?, ?)',
      [name, email, passwordHash],
    );

    return res.status(201).json({
      success: true,
      message: 'User registered successfully',
      data: {
        id: result.insertId,
        name,
        email,
      },
    });
  } catch (error) {
    console.error('Register error:', error);
    return res.status(500).json({
      success: false,
      message: 'Internal server error',
    });
  }
}

async function login(req, res) {
  try {
    const email = String(req.body.email || '').trim().toLowerCase();
    const password = String(req.body.password || '');

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Bắt buộc phải có email hoặc mật khẩu',
      });
    }

    const [users] = await pool.query(
      'SELECT id, name, email, password_hash, avatar_url FROM users WHERE email = ? LIMIT 1',
      [email],
    );

    if (users.length === 0) {
      return res.status(401).json({
        success: false,
        message: 'Email hoặc mật khẩu không đúng',
      });
    }

    const user = users[0];
    const isPasswordValid = verifyPassword(password, user.password_hash);

    if (!isPasswordValid) {
      return res.status(401).json({
        success: false,
        message: 'Email hoặc mật khẩu không đúng',
      });
    }

    return res.json({
      success: true,
      message: 'Login successful',
      data: {
        id: user.id,
        name: user.name,
        email: user.email,
        avatar_url: user.avatar_url || null,
        token: createAccessToken(user),
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    return res.status(500).json({
      success: false,
      message: 'Internal server error',
    });
  }
}

async function getMe(req, res) {
  try {
    const userId = Number(req.user?.sub);

    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({
        success: false,
        message: 'Unauthorized',
      });
    }

    // 💡 Đồng bộ profile fields để Flutter dùng chung dữ liệu với /api/profile/me
    const [users] = await pool.query(
      'SELECT id, name, email, avatar_url, created_at, updated_at FROM users WHERE id = ? LIMIT 1',
      [userId],
    );

    if (users.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    return res.json({
      success: true,
      message: 'Get profile successful',
      data: users[0],
    });
  } catch (error) {
    console.error('🔴 Get profile error tổng:', error);
    return res.status(500).json({
      success: false,
      message: 'Internal server error',
    });
  }
}

async function uploadAvatar(req, res) {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Vui lòng chọn một file ảnh.' });
    }

    // Debug: log incoming file and user for diagnosis
    try {
      console.log('[uploadAvatar] req.file =', JSON.stringify({
        originalname: req.file.originalname,
        filename: req.file.filename,
        mimetype: req.file.mimetype,
        size: req.file.size,
      }));
    } catch (e) {
      console.log('[uploadAvatar] could not stringify req.file', e);
    }

    const avatarUrl = `${req.protocol}://${req.headers.host}/uploads/avatars/${req.file.filename}`;
    const userId = Number(req.user?.sub);

    console.log('[uploadAvatar] userId =', userId, 'avatarUrl =', avatarUrl);

    // Check file exists on disk
    try {
      const savedPath = require('path').join(__dirname, '..', '..', 'uploads', 'avatars', req.file.filename);
      const exists = require('fs').existsSync(savedPath);
      console.log('[uploadAvatar] saved file exists?', exists, 'path=', savedPath);
    } catch (e) {
      console.log('[uploadAvatar] error checking saved file', e);
    }

    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ success: false, message: 'Unauthorized - Không tìm thấy thông tin user.' });
    }

    // 💡 ĐÃ SỬA: Đồng bộ cập nhật duy nhất vào trường avatar_url
    try {
      await pool.query(
        'UPDATE users SET avatar_url = ? WHERE id = ?',
        [avatarUrl, userId]
      );
    } catch (dbError) {
      console.error('[uploadAvatar] DB update error:', dbError);
      return res.status(500).json({ success: false, message: 'Lỗi khi cập nhật database: ' + String(dbError.message || dbError) });
    }

    return res.status(200).json({
      success: true,
      message: 'Tải ảnh đại diện lên thành công!',
      avatarUrl: avatarUrl,
      avatar_url: avatarUrl,
    });

  } catch (error) {
    console.error("🔴 Lỗi upload controller:", error);
    return res.status(500).json({ success: false, message: 'Lỗi server nội bộ.' });
  }
}

// --- XUẤT CÁC HÀM RA NGOÀI (EXPORT) ---
module.exports = {
  register,
  login,
  getMe,
  uploadAvatar,
};