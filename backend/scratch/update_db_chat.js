const { pool } = require('../src/config/db');

async function migrate() {
  try {
    console.log('Bắt đầu cập nhật database cho tính năng Trả lời và Thu hồi...');

    // Kiểm tra cột reply_to_id
    const [cols1] = await pool.query(`SHOW COLUMNS FROM messages LIKE 'reply_to_id'`);
    if (cols1.length === 0) {
      console.log('Thêm cột reply_to_id...');
      await pool.query(`ALTER TABLE messages ADD COLUMN reply_to_id BIGINT UNSIGNED DEFAULT NULL`);
      await pool.query(`ALTER TABLE messages ADD CONSTRAINT fk_messages_reply FOREIGN KEY (reply_to_id) REFERENCES messages(id) ON DELETE SET NULL`);
    } else {
      console.log('Cột reply_to_id đã tồn tại.');
    }

    // Kiểm tra cột is_deleted
    const [cols2] = await pool.query(`SHOW COLUMNS FROM messages LIKE 'is_deleted'`);
    if (cols2.length === 0) {
      console.log('Thêm cột is_deleted...');
      await pool.query(`ALTER TABLE messages ADD COLUMN is_deleted TINYINT(1) NOT NULL DEFAULT 0`);
    } else {
      console.log('Cột is_deleted đã tồn tại.');
    }

    console.log('Cập nhật thành công!');
  } catch (error) {
    console.error('Lỗi khi cập nhật DB:', error);
  } finally {
    process.exit(0);
  }
}

migrate();
