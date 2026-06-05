const jwt = require('jsonwebtoken');

function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const [scheme, token] = authHeader.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({
      success: false,
      message: 'Unauthorized: missing token',
    });
  }

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.user = payload;
    return next();
  } catch (_) {
    return res.status(401).json({
      success: false,
      message: 'Unauthorized: invalid or expired token',
    });
  }
}

const { pool } = require('../config/db');

async function isAdmin(req, res, next) {
  try {
    const userId = req.user?.sub;
    if (!userId) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const [rows] = await pool.query('SELECT role, is_banned FROM users WHERE id = ? LIMIT 1', [userId]);
    if (rows.length === 0) {
      return res.status(401).json({ success: false, message: 'User not found' });
    }

    if (rows[0].is_banned === 1) {
      return res.status(403).json({ success: false, message: 'Tài khoản của bạn đã bị khóa' });
    }

    if (rows[0].role !== 'admin' && rows[0].role !== 'director_admin') {
      return res.status(403).json({ success: false, message: 'Forbidden: Bạn không có quyền Admin' });
    }

    req.user.role = rows[0].role;
    return next();
  } catch (error) {
    console.error('isAdmin error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

module.exports = { authMiddleware, isAdmin };