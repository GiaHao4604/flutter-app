-- 1. Khởi tạo Database với bảng mã hỗ trợ tiếng Việt có dấu và Emoji (utf8mb4)
CREATE DATABASE IF NOT EXISTS flutter_app
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE flutter_app;

-- 2. Bảng Users (Người dùng) - Đã gộp avatar_url vào cấu trúc gốc
CREATE TABLE IF NOT EXISTS users (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(150) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  avatar_url VARCHAR(255) DEFAULT NULL, -- 💡 Đã đưa vào đây một cách hợp lệ
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Bảng Posts (Bài viết/Ảnh chụp từ App)
CREATE TABLE IF NOT EXISTS posts (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT, -- 💡 Chuyển thành UNSIGNED để đồng bộ liên kết sau này
  user_id INT UNSIGNED DEFAULT NULL,       -- 💡 Thêm cột này để sau này biết Post này của User nào
  image_url VARCHAR(255) NOT NULL,
  caption TEXT,
  device_id VARCHAR(100),
  camera_type ENUM('front','back'),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Bảng Camera Settings (Cấu hình Camera)
CREATE TABLE IF NOT EXISTS camera_settings (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  flash_mode VARCHAR(20),
  zoom_level FLOAT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Bảng QR Logs (Lịch sử quét mã QR)
CREATE TABLE IF NOT EXISTS qr_logs (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED DEFAULT NULL,       -- 💡 Nên có để biết ai là người đã quét mã QR này
  qr_code TEXT,
  qr_type VARCHAR(50),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Calendar Entries (Bản ghi lịch theo ngày)
CREATE TABLE IF NOT EXISTS calendar_entries (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  entry_date DATE NOT NULL,
  entry_ts DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  date_key CHAR(10) NOT NULL,
  category_key VARCHAR(100) DEFAULT NULL,
  image_url VARCHAR(255) DEFAULT NULL,
  note VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_calendar_entries_user_date (user_id, entry_date),
  KEY idx_calendar_entries_user_date_key (user_id, date_key),
  KEY idx_calendar_entries_user_category_date (user_id, category_key, date_key),
  CONSTRAINT fk_calendar_entries_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. Categories (Danh mục chi tiêu/thu nhập)
CREATE TABLE IF NOT EXISTS categories (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED DEFAULT NULL,
  slug VARCHAR(100) NOT NULL,
  name VARCHAR(100) NOT NULL,
  icon_key VARCHAR(50) NOT NULL DEFAULT 'other',
  kind ENUM('expense','income','both') NOT NULL DEFAULT 'expense',
  color VARCHAR(20) NOT NULL DEFAULT '#8E8E93',
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_categories_user_slug (user_id, slug),
  KEY idx_categories_user_kind (user_id, kind),
  CONSTRAINT fk_categories_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 8. Budgets (Ngân sách theo category và tháng)
CREATE TABLE IF NOT EXISTS budgets (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  category_id BIGINT UNSIGNED NOT NULL,
  month_key CHAR(7) NOT NULL,
  limit_amount DECIMAL(15,0) NOT NULL DEFAULT 0,
  is_repeat TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_budgets_user_category_month (user_id, category_id, month_key),
  KEY idx_budgets_user_month (user_id, month_key),
  CONSTRAINT fk_budgets_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE CASCADE,
  CONSTRAINT fk_budgets_category
    FOREIGN KEY (category_id) REFERENCES categories(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 9. Transactions (Giao dịch tiền tách riêng khỏi calendar)
CREATE TABLE IF NOT EXISTS transactions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  calendar_entry_id BIGINT UNSIGNED DEFAULT NULL,
  category_id BIGINT UNSIGNED DEFAULT NULL,
  amount DECIMAL(15,0) NOT NULL DEFAULT 0,
  is_expense TINYINT(1) NOT NULL DEFAULT 1,
  transaction_date DATE NOT NULL,
  note VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_transactions_calendar_entry (calendar_entry_id),
  KEY idx_transactions_user_created (user_id, created_at),
  KEY idx_transactions_user_date (user_id, transaction_date),
  KEY idx_transactions_category_date (category_id, transaction_date),
  KEY idx_transactions_user_category_month (user_id, category_id, transaction_date, is_expense),
  CONSTRAINT fk_transactions_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE CASCADE,
  CONSTRAINT fk_transactions_category
    FOREIGN KEY (category_id) REFERENCES categories(id)
    ON DELETE SET NULL,
  CONSTRAINT fk_transactions_calendar_entry
    FOREIGN KEY (calendar_entry_id) REFERENCES calendar_entries(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;