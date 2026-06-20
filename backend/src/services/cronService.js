const cron = require('node-cron');
const { pool } = require('../config/db');
const fs = require('fs');
const path = require('path');

/**
 * Lấy month_key của một date cụ thể theo format YYYY-MM
 */
function getMonthKey(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

/**
 * Hàm thực hiện logic nhân bản ngân sách lặp lại
 */
async function duplicateRepeatingBudgets() {
  console.log('[Cron] Bắt đầu quét và nhân bản ngân sách lặp lại...');
  try {
    const now = new Date();
    const currentMonthKey = getMonthKey(now);
    
    // Tính tháng trước
    const prevDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const prevMonthKey = getMonthKey(prevDate);

    console.log(`[Cron] Đang kiểm tra từ tháng ${prevMonthKey} sang ${currentMonthKey}`);

    // 1. Tìm tất cả ngân sách của tháng trước có is_repeat = 1
    const [prevBudgets] = await pool.query(
      'SELECT * FROM budgets WHERE month_key = ? AND is_repeat = 1',
      [prevMonthKey]
    );

    if (!prevBudgets || prevBudgets.length === 0) {
      console.log('[Cron] Không có ngân sách nào cần lặp lại từ tháng trước.');
      return;
    }

    let duplicatedCount = 0;

    for (const budget of prevBudgets) {
      const { user_id, category_id, limit_amount } = budget;

      // 2. Kiểm tra xem user này đã có ngân sách cho category này ở tháng HIỆN TẠI chưa
      const [existing] = await pool.query(
        'SELECT id FROM budgets WHERE user_id = ? AND category_id = ? AND month_key = ?',
        [user_id, category_id, currentMonthKey]
      );

      // 3. Nếu chưa có, tiến hành tạo mới
      if (!existing || existing.length === 0) {
        await pool.query(
          `INSERT INTO budgets (user_id, category_id, month_key, limit_amount, is_repeat) 
           VALUES (?, ?, ?, ?, ?)`,
          [user_id, category_id, currentMonthKey, limit_amount, 1]
        );
        duplicatedCount++;
        console.log(`[Cron] Đã nhân bản ngân sách (User: ${user_id}, Category: ${category_id}) sang ${currentMonthKey}`);
      }
    }

    console.log(`[Cron] Quá trình hoàn tất. Đã nhân bản thành công ${duplicatedCount} ngân sách.`);
  } catch (error) {
    console.error('[Cron] Lỗi khi chạy cronjob nhân bản ngân sách:', error);
  }
}

/**
 * Hàm dọn dẹp thư thông báo và file ảnh đính kèm sau 1 ngày
 */
async function cleanupOldNotifications() {
  console.log('[Cron] Bắt đầu dọn dẹp thông báo cũ hơn 1 ngày...');
  try {
    const [rows] = await pool.query(
      "SELECT id, post_snapshot FROM notifications WHERE created_at < NOW() - INTERVAL 1 DAY"
    );

    if (!rows || rows.length === 0) {
      console.log('[Cron] Không có thông báo nào cần dọn dẹp.');
      return;
    }

    let deletedCount = 0;
    for (const row of rows) {
      if (row.post_snapshot) {
        let snapshot;
        try {
          snapshot = typeof row.post_snapshot === 'string' ? JSON.parse(row.post_snapshot) : row.post_snapshot;
        } catch (e) {}

        if (snapshot && snapshot.image_url) {
          const filePath = path.join(__dirname, '..', '..', snapshot.image_url);
          fs.unlink(filePath, (err) => {
            if (err && err.code !== 'ENOENT') {
              console.error(`[Cron] Lỗi xóa file ảnh ${filePath}:`, err);
            } else if (!err) {
              console.log(`[Cron] Đã xóa vĩnh viễn file ảnh: ${filePath}`);
            }
          });
        }
      }
      await pool.query('DELETE FROM notifications WHERE id = ?', [row.id]);
      deletedCount++;
    }
    console.log(`[Cron] Dọn dẹp hoàn tất. Đã xóa ${deletedCount} thông báo cũ.`);
  } catch (error) {
    console.error('[Cron] Lỗi khi dọn dẹp thông báo cũ:', error);
  }
}

/**
 * Hàm khởi động cron scheduler
 */
function startCronJobs() {
  console.log('[Cron] Đã đăng ký cronjob nhân bản ngân sách. Lịch chạy: 00:00 mỗi ngày.');
  // Chạy lúc 00:00 mỗi ngày
  cron.schedule('0 0 * * *', async () => {
    await duplicateRepeatingBudgets();
  });

  console.log('[Cron] Đã đăng ký cronjob dọn dẹp thông báo. Lịch chạy: mỗi giờ 1 lần.');
  // Chạy mỗi giờ (phút thứ 0 của mỗi giờ)
  cron.schedule('0 * * * *', async () => {
    await cleanupOldNotifications();
  });
}

module.exports = {
  startCronJobs,
  duplicateRepeatingBudgets, 
  cleanupOldNotifications, // Export ra để có thể test thủ công
};
