const { pool } = require('../config/db');

async function getNotifications(req, res) {
  try {
    const userId = Number(req.user?.sub);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const [rows] = await pool.query(
      'SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC',
      [userId]
    );

    return res.json({ success: true, data: rows });
  } catch (error) {
    console.error('getNotifications error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function getUnreadCount(req, res) {
  try {
    const userId = Number(req.user?.sub);
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const [rows] = await pool.query(
      'SELECT COUNT(*) as unread_count FROM notifications WHERE user_id = ? AND is_read = 0',
      [userId]
    );

    const count = Number(rows?.[0]?.unread_count || 0);
    return res.json({ success: true, data: { unread_count: count } });
  } catch (error) {
    console.error('getUnreadCount error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function markAsRead(req, res) {
  try {
    const userId = Number(req.user?.sub);
    const notificationId = req.params.id;
    
    if (!Number.isInteger(userId) || userId <= 0) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    await pool.query(
      'UPDATE notifications SET is_read = 1 WHERE id = ? AND user_id = ?',
      [notificationId, userId]
    );

    return res.json({ success: true, message: 'Đã đánh dấu là đã đọc' });
  } catch (error) {
    console.error('markAsRead error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

module.exports = {
  getNotifications,
  getUnreadCount,
  markAsRead,
};
