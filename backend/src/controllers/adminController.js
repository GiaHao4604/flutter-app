const { pool } = require('../config/db');
const { getIO } = require('../utils/socket');
const fs = require('fs/promises');
const path = require('path');

// ==========================================
// 1. DASHBOARD & THỐNG KÊ
// ==========================================

async function getUsersChart(req, res) {
  try {
    // Thống kê số lượng user đăng ký theo từng ngày trong 30 ngày qua
    const [rows] = await pool.query(`
      SELECT DATE(created_at) as date, COUNT(*) as count 
      FROM users 
      WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
      GROUP BY DATE(created_at)
      ORDER BY date ASC
    `);
    
    // Thống kê tổng quan
    const [totalUsersRows] = await pool.query('SELECT COUNT(*) as total FROM users WHERE role = "user"');
    const [totalAdminsRows] = await pool.query('SELECT COUNT(*) as total FROM users WHERE role IN ("admin", "director_admin")');
    const [totalPosts] = await pool.query('SELECT COUNT(*) as total FROM posts');

    return res.json({
      success: true,
      data: {
        chartData: rows,
        totalUsers: totalUsersRows[0].total,
        totalAdmins: totalAdminsRows[0].total,
        totalPosts: totalPosts[0].total
      }
    });
  } catch (error) {
    console.error('getUsersChart error:', error);
    return res.status(500).json({ success: false, message: 'Lỗi server' });
  }
}

async function getRevenueChart(req, res) {
  // Placeholder cho chức năng nâng cấp VIP/Premium sau này
  return res.json({
    success: true,
    data: {
      message: "Tính năng biểu đồ doanh thu VIP/Premium đang được phát triển.",
      placeholderData: [
        { month: 'Jan', revenue: 0 },
        { month: 'Feb', revenue: 0 },
        { month: 'Mar', revenue: 0 }
      ]
    }
  });
}

// ==========================================
// 2. QUẢN LÝ NGƯỜI DÙNG (USER MANAGEMENT)
// ==========================================

async function getAllUsers(req, res) {
  try {
    const [users] = await pool.query(
      'SELECT id, name, email, avatar_url, role, is_banned, created_at FROM users ORDER BY created_at DESC'
    );
    return res.json({ success: true, data: users });
  } catch (error) {
    console.error('getAllUsers error:', error);
    return res.status(500).json({ success: false, message: 'Lỗi server' });
  }
}

async function toggleUserRole(req, res) {
  try {
    const userId = req.params.id;
    if (userId == req.user.sub) {
      return res.status(400).json({ success: false, message: 'Không thể tự đổi quyền của chính mình' });
    }

    const [users] = await pool.query('SELECT role FROM users WHERE id = ?', [userId]);
    if (users.length === 0) return res.status(404).json({ success: false, message: 'Không tìm thấy user' });
    
    if (users[0].role === 'director_admin') {
      return res.status(403).json({ success: false, message: 'Không thể thao tác lên Giám đốc Quản trị' });
    }

    const newRole = users[0].role === 'admin' ? 'user' : 'admin';
    await pool.query('UPDATE users SET role = ? WHERE id = ?', [newRole, userId]);

    return res.json({ success: true, message: `Đã chuyển quyền thành ${newRole}` });
  } catch (error) {
    console.error('toggleUserRole error:', error);
    return res.status(500).json({ success: false, message: 'Lỗi server' });
  }
}

async function toggleUserBan(req, res) {
  try {
    const userId = req.params.id;
    if (userId == req.user.sub) {
      return res.status(400).json({ success: false, message: 'Không thể tự khóa tài khoản của chính mình' });
    }

    const [users] = await pool.query('SELECT role, is_banned FROM users WHERE id = ?', [userId]);
    if (users.length === 0) return res.status(404).json({ success: false, message: 'Không tìm thấy user' });

    if (users[0].role === 'director_admin') {
      return res.status(403).json({ success: false, message: 'Không thể khóa Giám đốc Quản trị' });
    }

    const newBanStatus = users[0].is_banned === 1 ? 0 : 1;
    await pool.query('UPDATE users SET is_banned = ? WHERE id = ?', [newBanStatus, userId]);

    return res.json({ success: true, message: newBanStatus === 1 ? 'Đã khóa tài khoản' : 'Đã mở khóa tài khoản' });
  } catch (error) {
    console.error('toggleUserBan error:', error);
    return res.status(500).json({ success: false, message: 'Lỗi server' });
  }
}

async function deleteUser(req, res) {
  try {
    const userId = req.params.id;
    if (userId == req.user.sub) {
      return res.status(400).json({ success: false, message: 'Không thể tự xóa tài khoản của chính mình' });
    }

    // 1. Lấy thông tin avatar, bài viết và role
    const [users] = await pool.query('SELECT role, avatar_url FROM users WHERE id = ?', [userId]);
    if (users.length === 0) return res.status(404).json({ success: false, message: 'Không tìm thấy user' });

    if (users[0].role === 'director_admin') {
      return res.status(403).json({ success: false, message: 'Không thể xóa Giám đốc Quản trị' });
    }

    const [posts] = await pool.query('SELECT image_url FROM posts WHERE user_id = ?', [userId]);
    const [calendars] = await pool.query('SELECT image_url FROM calendar_entries WHERE user_id = ?', [userId]);
    const [messages] = await pool.query('SELECT image_url FROM messages WHERE sender_id = ?', [userId]);

    const filesToDelete = [];
    if (users.length > 0 && users[0].avatar_url) {
      if (users[0].avatar_url.startsWith('/uploads')) {
        filesToDelete.push(path.join(__dirname, '..', '..', users[0].avatar_url));
      }
    }

    for (const post of posts) {
      if (post.image_url && post.image_url.startsWith('/uploads')) {
        filesToDelete.push(path.join(__dirname, '..', '..', post.image_url));
      }
    }

    for (const cal of calendars) {
      if (cal.image_url && cal.image_url.startsWith('/uploads')) {
        filesToDelete.push(path.join(__dirname, '..', '..', cal.image_url));
      }
    }

    for (const msg of messages) {
      if (msg.image_url && msg.image_url.startsWith('/uploads')) {
        filesToDelete.push(path.join(__dirname, '..', '..', msg.image_url));
      }
    }

    // 2. Xóa file khỏi ổ cứng
    for (const filePath of filesToDelete) {
      try {
        await fs.unlink(filePath);
      } catch (err) {
        console.error(`Không thể xóa file vật lý: ${filePath}`, err);
      }
    }

    // 3. Xóa dữ liệu trong Database (Chủ động xóa để tránh lỗi mồ côi nếu DB set null thay vì cascade)
    await pool.query('DELETE FROM transactions WHERE user_id = ?', [userId]);
    await pool.query('DELETE FROM budgets WHERE user_id = ?', [userId]);
    await pool.query('DELETE FROM calendar_entries WHERE user_id = ?', [userId]);
    await pool.query('DELETE FROM categories WHERE user_id = ?', [userId]);
    await pool.query('DELETE FROM messages WHERE sender_id = ?', [userId]);
    await pool.query('DELETE FROM conversation_members WHERE user_id = ?', [userId]);
    await pool.query('DELETE FROM posts WHERE user_id = ?', [userId]);

    // 4. Cuối cùng, Xóa người dùng
    await pool.query('DELETE FROM users WHERE id = ?', [userId]);
    return res.json({ success: true, message: 'Đã xóa người dùng và dữ liệu liên quan vĩnh viễn' });
  } catch (error) {
    console.error('deleteUser error:', error);
    return res.status(500).json({ success: false, message: 'Lỗi server' });
  }
}

// ==========================================
// 3. QUẢN LÝ NỘI DUNG (CONTENT MODERATION)
// ==========================================

async function getReportedPosts(req, res) {
  try {
    const [reports] = await pool.query(`
      SELECT 
        pr.id as report_id, pr.reason, pr.status, pr.created_at as report_date,
        p.id as post_id, p.caption, p.image_url,
        reporter.name as reporter_name, reporter.email as reporter_email,
        author.name as author_name, author.email as author_email
      FROM post_reports pr
      JOIN posts p ON pr.post_id = p.id
      JOIN users reporter ON pr.user_id = reporter.id
      LEFT JOIN users author ON p.user_id = author.id
      ORDER BY pr.status ASC, pr.created_at DESC
    `);
    return res.json({ success: true, data: reports });
  } catch (error) {
    console.error('getReportedPosts error:', error);
    return res.status(500).json({ success: false, message: 'Lỗi server' });
  }
}

async function resolveReport(req, res) {
  try {
    const reportId = req.params.id;
    await pool.query('UPDATE post_reports SET status = "resolved" WHERE id = ?', [reportId]);
    return res.json({ success: true, message: 'Đã đánh dấu báo cáo là đã xử lý' });
  } catch (error) {
    console.error('resolveReport error:', error);
    return res.status(500).json({ success: false, message: 'Lỗi server' });
  }
}

async function deletePost(req, res) {
  try {
    const postId = req.params.id;
    const [posts] = await pool.query(`
      SELECT p.user_id, p.calendar_entry_id, p.caption, p.image_url, 
             t.amount, c.name as category_name
      FROM posts p
      LEFT JOIN transactions t ON p.calendar_entry_id = t.calendar_entry_id
      LEFT JOIN calendar_entries ce ON p.calendar_entry_id = ce.id
      LEFT JOIN categories c ON ce.category_key = c.slug
      WHERE p.id = ?
    `, [postId]);
    
    if (posts.length > 0) {
      const post = posts[0];
      const userId = post.user_id;
      const calEntryId = post.calendar_entry_id;
      
      const snapshot = {
        caption: post.caption,
        image_url: post.image_url,
        amount: post.amount,
        category_name: post.category_name
      };

      if (calEntryId) {
        await pool.query('DELETE FROM calendar_entries WHERE id = ?', [calEntryId]);
      }
      await pool.query('DELETE FROM posts WHERE id = ?', [postId]);

      // Gửi thông báo cho người dùng qua DB
      if (userId) {
        const title = 'Cảnh báo vi phạm cộng đồng';
        const body = 'Chúng tôi phát hiện bài đăng của bạn không đúng chuẩn mực nên đã bị ẩn và xóa. Mọi thắc mắc xin liên hệ về: yanghow4604@gmail.com';
        await pool.query(
          'INSERT INTO notifications (user_id, title, body, post_snapshot) VALUES (?, ?, ?, ?)',
          [userId, title, body, JSON.stringify(snapshot)]
        );

        // Phát sự kiện realtime tới người dùng
        try {
          const io = getIO();
          io.to(`user_${userId}`).emit('system_notification', { title, body });
        } catch (e) {
          console.error('Lỗi emit system_notification:', e);
        }
      }
    }
    return res.json({ success: true, message: 'Đã xóa bài viết vi phạm' });
  } catch (error) {
    console.error('deletePost error:', error);
    return res.status(500).json({ success: false, message: 'Lỗi server' });
  }
}

async function transferDirectorAdmin(req, res) {
  try {
    if (req.user.role !== 'director_admin') {
      return res.status(403).json({ success: false, message: 'Chỉ Director Admin mới có quyền chuyển giao' });
    }

    const targetUserId = req.params.id;
    const currentUserId = req.user.sub;

    if (targetUserId == currentUserId) {
      return res.status(400).json({ success: false, message: 'Không thể chuyển giao cho chính mình' });
    }

    const [targetUsers] = await pool.query('SELECT role FROM users WHERE id = ?', [targetUserId]);
    if (targetUsers.length === 0) {
      return res.status(404).json({ success: false, message: 'Người dùng không tồn tại' });
    }

    if (targetUsers[0].role !== 'admin') {
      return res.status(400).json({ success: false, message: 'Chỉ có thể chuyển giao cho Admin (màu xanh)' });
    }

    // Đổi target user thành director_admin, và user hiện tại thành admin
    await pool.query('UPDATE users SET role = "director_admin" WHERE id = ?', [targetUserId]);
    await pool.query('UPDATE users SET role = "admin" WHERE id = ?', [currentUserId]);

    return res.json({ success: true, message: 'Đã chuyển giao quyền Giám đốc Quản trị thành công!' });
  } catch (error) {
    console.error('transferDirectorAdmin error:', error);
    return res.status(500).json({ success: false, message: 'Lỗi server' });
  }
}

module.exports = {
  getUsersChart,
  getRevenueChart,
  getAllUsers,
  toggleUserRole,
  toggleUserBan,
  deleteUser,
  getReportedPosts,
  resolveReport,
  deletePost,
  transferDirectorAdmin
};
