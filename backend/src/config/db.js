require('dotenv').config();
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'flutter_app',
  port: Number(process.env.DB_PORT || 3306),
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

async function testConnection() {
  const connection = await pool.getConnection();
  connection.release();
  const dbName = process.env.DB_NAME || 'flutter_app';
  console.log('Connected to MySQL successfully (DB_NAME=' + dbName + ')');

  async function ensureUserColumn(columnName, definition) {
    try {
      const [cols] = await pool.query(
        'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = \'users\' AND COLUMN_NAME = ?',
        [dbName, columnName]
      );

      if (!cols || cols.length === 0) {
        console.log(`[db] ${columnName} column missing — adding it to users table...`);
        await pool.query(`ALTER TABLE users ADD COLUMN ${columnName} ${definition}`);
        console.log(`[db] ${columnName} column added`);
      } else {
        console.log(`[db] ${columnName} column exists`);
      }
    } catch (e) {
      console.error(`[db] Error ensuring ${columnName} column:`, e);
    }
  }

  async function hasColumn(tableName, columnName) {
    const [cols] = await pool.query(
      'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?',
      [dbName, tableName, columnName],
    );
    return !!cols && cols.length > 0;
  }

  await ensureUserColumn('avatar_url', 'VARCHAR(255) DEFAULT NULL');

  async function ensureColumn(tableName, columnName, definition) {
    try {
      const [cols] = await pool.query(
        'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        [dbName, tableName, columnName],
      );

      if (!cols || cols.length === 0) {
        console.log(`[db] ${tableName}.${columnName} missing — adding it...`);
        await pool.query(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${definition}`);
      }
    } catch (e) {
      console.error(`[db] Error ensuring ${tableName}.${columnName}:`, e);
    }
  }

  try {
    await pool.query(`
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
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    await pool.query(`
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
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS posts (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        user_id INT UNSIGNED DEFAULT NULL,
        image_url VARCHAR(255) NOT NULL,
        caption TEXT,
        device_id VARCHAR(100),
        camera_type ENUM('front','back') DEFAULT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_posts_user_created (user_id, created_at),
        CONSTRAINT fk_posts_user
          FOREIGN KEY (user_id) REFERENCES users(id)
          ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    await ensureColumn('posts', 'user_id', 'INT UNSIGNED DEFAULT NULL');
    await ensureColumn('posts', 'caption', 'TEXT');
    await ensureColumn('posts', 'device_id', 'VARCHAR(100) DEFAULT NULL');
    await ensureColumn('posts', 'camera_type', "ENUM('front','back') DEFAULT NULL");

    try {
      await pool.query('CREATE INDEX idx_posts_user_created ON posts (user_id, created_at)');
    } catch (e) {
      if (String(e && e.code) !== 'ER_DUP_KEYNAME') {
        console.error('[db] Error ensuring idx_posts_user_created:', e);
      }
    }

    await pool.query(`
      CREATE TABLE IF NOT EXISTS conversations (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS conversation_members (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        conversation_id BIGINT UNSIGNED NOT NULL,
        user_id INT UNSIGNED NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_conversation_members_conversation (conversation_id),
        KEY idx_conversation_members_user (user_id),
        CONSTRAINT fk_conversation_members_conversation FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        CONSTRAINT fk_conversation_members_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS messages (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        conversation_id BIGINT UNSIGNED NOT NULL,
        sender_id INT UNSIGNED NOT NULL,
        message TEXT DEFAULT NULL,
        image_url VARCHAR(255) DEFAULT NULL,
        is_seen TINYINT(1) NOT NULL DEFAULT 0,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY idx_messages_conversation (conversation_id),
        KEY idx_messages_sender (sender_id),
        CONSTRAINT fk_messages_conversation FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    await pool.query(`
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
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    await pool.query(`
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
        CONSTRAINT fk_transactions_user
          FOREIGN KEY (user_id) REFERENCES users(id)
          ON DELETE CASCADE,
        CONSTRAINT fk_transactions_category
          FOREIGN KEY (category_id) REFERENCES categories(id)
          ON DELETE SET NULL,
        CONSTRAINT fk_transactions_calendar_entry
          FOREIGN KEY (calendar_entry_id) REFERENCES calendar_entries(id)
          ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);

    await pool.query('ALTER TABLE transactions MODIFY COLUMN amount DECIMAL(15,0) NOT NULL DEFAULT 0');
    await ensureColumn('calendar_entries', 'category_key', 'VARCHAR(100) DEFAULT NULL');
    await ensureColumn('transactions', 'category_id', 'BIGINT UNSIGNED DEFAULT NULL');
    await ensureColumn('transactions', 'transaction_date', 'DATE NULL');
    await ensureColumn('transactions', 'note', 'VARCHAR(255) DEFAULT NULL');
    await ensureColumn('transactions', 'calendar_entry_id', 'BIGINT UNSIGNED DEFAULT NULL');

    try {
      await pool.query(
        'CREATE INDEX idx_transactions_user_category_month ON transactions (user_id, category_id, transaction_date, is_expense)',
      );
    } catch (e) {
      // Ignore duplicate index creation when migration already applied
      if (String(e && e.code) !== 'ER_DUP_KEYNAME') {
        console.error('[db] Error ensuring idx_transactions_user_category_month:', e);
      }
    }

    try {
      await pool.query(`
        UPDATE transactions t
        JOIN calendar_entries ce
          ON ce.id = t.calendar_entry_id
         AND ce.user_id = t.user_id
        SET t.category_id = (
          SELECT c.id
          FROM categories c
          WHERE c.slug = ce.category_key
            AND (c.user_id = t.user_id OR c.user_id IS NULL)
          ORDER BY c.user_id IS NULL ASC, c.id ASC
          LIMIT 1
        )
        WHERE t.category_id IS NULL
          AND ce.category_key IS NOT NULL
          AND ce.category_key <> ''
      `);
    } catch (e) {
      console.error('[db] Error backfilling transaction categories from calendar_entries.category_key:', e);
    }

    // Additional backfill: if calendar_entries.category_key contains a numeric
    // category id (string), map it directly to transactions.category_id.
    try {
      await pool.query(`
        UPDATE transactions t
        JOIN calendar_entries ce
          ON ce.id = t.calendar_entry_id
         AND ce.user_id = t.user_id
        JOIN categories c ON c.id = CAST(ce.category_key AS UNSIGNED)
        SET t.category_id = c.id
        WHERE t.category_id IS NULL
          AND ce.category_key REGEXP '^[0-9]+$'
      `);
    } catch (e) {
      console.error('[db] Error backfilling numeric calendar_entries.category_key to transactions.category_id:', e);
    }

    const hasLegacyAmount = await hasColumn('calendar_entries', 'amount');
    const hasLegacyExpense = await hasColumn('calendar_entries', 'is_expense');

    if (hasLegacyAmount && hasLegacyExpense) {
      await pool.query(`
        INSERT INTO transactions (user_id, calendar_entry_id, amount, is_expense, created_at, updated_at)
        SELECT ce.user_id,
               ce.id,
               COALESCE(ce.amount, 0),
               COALESCE(ce.is_expense, 1),
               ce.created_at,
               ce.updated_at
        FROM calendar_entries ce
        LEFT JOIN transactions t ON t.calendar_entry_id = ce.id
        WHERE t.id IS NULL
      `);

      await pool.query(`
        ALTER TABLE calendar_entries
          DROP COLUMN amount,
          DROP COLUMN is_expense
      `);
    }

    const [categoryCountRows] = await pool.query('SELECT COUNT(*) AS total FROM categories');
    const categoryCount = Number(categoryCountRows?.[0]?.total || 0);
    if (categoryCount === 0) {
      await pool.query(`
        INSERT INTO categories (user_id, slug, name, icon_key, kind, color, sort_order)
        VALUES
          (NULL, 'food', 'Ăn uống', 'food', 'expense', '#FFC04D', 10),
          (NULL, 'home', 'Nhà ở', 'home', 'expense', '#4E8DFF', 20),
          (NULL, 'car', 'Di chuyển', 'car', 'expense', '#5DD6FF', 30),
          (NULL, 'shop', 'Mua sắm', 'shop', 'expense', '#BF5AF2', 40),
          (NULL, 'health', 'Sức khoẻ', 'health', 'expense', '#FF5C8A', 50),
          (NULL, 'salary', 'Lương', 'income', 'income', '#37C95B', 60)
      `);
    }

    const [txHasLegacyCategory] = await pool.query(
      'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?',
      [dbName, 'transactions', 'category_id'],
    );
    if (txHasLegacyCategory && txHasLegacyCategory.length > 0) {
      await pool.query(`
        UPDATE transactions t
        LEFT JOIN calendar_entries ce ON ce.id = t.calendar_entry_id
        SET t.transaction_date = COALESCE(t.transaction_date, ce.entry_date, DATE(t.created_at)),
            t.note = COALESCE(t.note, ce.note)
        WHERE t.transaction_date IS NULL OR t.note IS NULL
      `);
      await pool.query('UPDATE transactions SET transaction_date = COALESCE(transaction_date, DATE(created_at)) WHERE transaction_date IS NULL');
      await pool.query('ALTER TABLE transactions MODIFY COLUMN transaction_date DATE NOT NULL');
    }
  } catch (e) {
    console.error('[db] Error ensuring calendar tables:', e);
  }
}

module.exports = {
  pool,
  testConnection,
};
