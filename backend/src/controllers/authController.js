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

async function sendRegisterOtp(req, res) {
  try {
    const email = String(req.body.email || '').trim().toLowerCase();
    if (!email) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập email' });
    }

    const [existingUsers] = await pool.query('SELECT id FROM users WHERE email = ? LIMIT 1', [email]);
    if (existingUsers.length > 0) {
      return res.status(409).json({ success: false, message: 'Email này đã tồn tại' });
    }

    const otp = generateOtp();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 phút

    await pool.query('DELETE FROM register_otps WHERE email = ? AND used = 0', [email]);
    await pool.query(
      'INSERT INTO register_otps (email, otp_code, expires_at) VALUES (?, ?, ?)',
      [email, otp, expiresAt]
    );

    const { sendOtpEmail } = require('../utils/emailService');
    const isEmailSent = await sendOtpEmail(email, otp);

    if (isEmailSent) {
      return res.json({ success: true, message: 'Mã OTP đã được gửi đến email của bạn.' });
    } else {
      console.log(`[RegisterOTP Fallback] OTP for ${email}: ${otp}`);
      return res.json({ success: true, message: 'Không thể gửi email. (Debug) Mã OTP: ' + otp });
    }
  } catch (error) {
    console.error('sendRegisterOtp error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function register(req, res) {
  try {
    const name = String(req.body.name || '').trim();
    const email = String(req.body.email || '').trim().toLowerCase();
    const password = String(req.body.password || '');
    const otpCode = String(req.body.otp_code || '').trim();

    if (!name || !email || !password || !otpCode) {
      return res.status(400).json({
        success: false,
        message: 'Thiếu thông tin hoặc mã OTP',
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

    // Kiểm tra OTP hợp lệ
    const [otpRows] = await pool.query(
      'SELECT id FROM register_otps WHERE email = ? AND otp_code = ? AND used = 0 AND expires_at > NOW() LIMIT 1',
      [email, otpCode],
    );

    if (otpRows.length === 0) {
      return res.status(400).json({ success: false, message: 'Mã OTP không đúng hoặc đã hết hạn' });
    }

    const otpId = otpRows[0].id;
    const passwordHash = hashPassword(password);

    const [result] = await pool.query(
      'INSERT INTO users (name, email, password_hash) VALUES (?, ?, ?)',
      [name, email, passwordHash],
    );

    // Đánh dấu OTP đã dùng
    await pool.query('UPDATE register_otps SET used = 1 WHERE id = ?', [otpId]);

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
      'SELECT id, name, email, password_hash, avatar_url, role, is_banned FROM users WHERE email = ? LIMIT 1',
      [email],
    );

    if (users.length === 0) {
      return res.status(401).json({
        success: false,
        message: 'Email hoặc mật khẩu không đúng',
      });
    }

    const user = users[0];

    if (user.is_banned === 1) {
      return res.status(403).json({
        success: false,
        message: 'Tài khoản của bạn đã bị khóa vi phạm',
      });
    }

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
        role: user.role,
        is_banned: user.is_banned,
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
      'SELECT id, name, email, avatar_url, role, is_banned, created_at, updated_at FROM users WHERE id = ? LIMIT 1',
      [userId],
    );

    if (users.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    const user = users[0];
    if (user.is_banned === 1) {
      return res.status(403).json({
        success: false,
        message: 'Tài khoản của bạn đã bị khóa vi phạm',
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

// Tạo OTP 6 số ngẫu nhiên
function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

// POST /api/auth/forgot-password
// Body: { email }
// Trả về OTP (trong production sẽ gửi email — hiện tại trả thẳng để test)
async function forgotPassword(req, res) {
  try {
    const email = String(req.body.email || '').trim().toLowerCase();
    if (!email) {
      return res.status(400).json({ success: false, message: 'Vui lòng nhập email' });
    }

    const [users] = await pool.query('SELECT id FROM users WHERE email = ? LIMIT 1', [email]);
    // Luôn trả 200 để không lộ thông tin email tồn tại hay không
    if (users.length === 0) {
      return res.json({
        success: true,
        message: 'Nếu email tồn tại, mã OTP sẽ được gửi đến.',
      });
    }

    const userId = users[0].id;
    const otp = generateOtp();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000); // 10 phút

    // Xóa OTP cũ chưa dùng của user này
    await pool.query('DELETE FROM password_reset_otps WHERE user_id = ? AND used = 0', [userId]);

    // Lưu OTP mới
    await pool.query(
      'INSERT INTO password_reset_otps (user_id, otp_code, expires_at) VALUES (?, ?, ?)',
      [userId, otp, expiresAt],
    );

    // Gửi email chứa OTP
    const { sendOtpEmail } = require('../utils/emailService');
    const isEmailSent = await sendOtpEmail(email, otp);

    if (isEmailSent) {
      return res.json({
        success: true,
        message: 'Mã OTP đã được gửi đến email của bạn. Vui lòng kiểm tra hộp thư (hoặc thư mục Spam).',
      });
    } else {
      // Nếu gửi email thất bại (thường do chưa cấu hình SMTP), vẫn fallback về debug
      console.log(`[ForgotPassword Fallback] OTP for ${email}: ${otp}`);
      return res.json({
        success: true,
        message: 'Không thể gửi email. (Debug) Mã OTP của bạn là: ' + otp,
      });
    }
  } catch (error) {

    console.error('forgotPassword error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

// POST /api/auth/reset-password
// Body: { email, otp_code, new_password }
async function resetPassword(req, res) {
  try {
    const email = String(req.body.email || '').trim().toLowerCase();
    const otpCode = String(req.body.otp_code || '').trim();
    const newPassword = String(req.body.new_password || '');

    if (!email || !otpCode || !newPassword) {
      return res.status(400).json({ success: false, message: 'Email, mã OTP và mật khẩu mới là bắt buộc' });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({ success: false, message: 'Mật khẩu mới phải ít nhất 6 ký tự' });
    }

    const [users] = await pool.query('SELECT id FROM users WHERE email = ? LIMIT 1', [email]);
    if (users.length === 0) {
      return res.status(400).json({ success: false, message: 'Email không tồn tại' });
    }

    const userId = users[0].id;

    // Tìm OTP hợp lệ: chưa dùng, chưa hết hạn
    const [otpRows] = await pool.query(
      'SELECT id FROM password_reset_otps WHERE user_id = ? AND otp_code = ? AND used = 0 AND expires_at > NOW() LIMIT 1',
      [userId, otpCode],
    );

    if (otpRows.length === 0) {
      return res.status(400).json({ success: false, message: 'Mã OTP không đúng hoặc đã hết hạn' });
    }

    const otpId = otpRows[0].id;

    // Đổi mật khẩu
    const newHash = hashPassword(newPassword);
    await pool.query('UPDATE users SET password_hash = ? WHERE id = ?', [newHash, userId]);

    // Đánh dấu OTP đã dùng
    await pool.query('UPDATE password_reset_otps SET used = 1 WHERE id = ?', [otpId]);

    return res.json({ success: true, message: 'Đặt lại mật khẩu thành công. Bạn có thể đăng nhập với mật khẩu mới.' });
  } catch (error) {
    console.error('resetPassword error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

// --- XUẤT CÁC HÀM RA NGOÀI (EXPORT) ---
module.exports = {
  sendRegisterOtp,
  register,
  login,
  getMe,
  uploadAvatar,
  forgotPassword,
  resetPassword,
};