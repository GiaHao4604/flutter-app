const Big = require('big.js');
const { pool } = require('../config/db');

function toMoneyString(value, fallback = '0') {
  try {
    if (value === null || value === undefined || value === '') {
      return fallback;
    }
    return Big(value).round(0, Big.roundDown).toFixed(0);
  } catch (_) {
    return fallback;
  }
}

function toMoneyNumber(value, fallback = 0) {
  const normalized = toMoneyString(value, String(fallback));
  const parsed = Number.parseInt(normalized, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toInt(value, fallback = 0) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toBooleanish(value, fallback = false) {
  if (value === true || value === 'true' || value === 1 || value === '1') return true;
  if (value === false || value === 'false' || value === 0 || value === '0') return false;
  return fallback;
}

function parseMonthKey(monthKey) {
  if (typeof monthKey === 'string' && /^\d{4}-\d{2}$/.test(monthKey.trim())) {
    return monthKey.trim();
  }
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

function normalizeDateString(value, fallback = new Date().toISOString().slice(0, 10)) {
  if (value === null || value === undefined || value === '') {
    return fallback;
  }

  const raw = String(value).trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    return raw;
  }

  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    return fallback;
  }

  return parsed.toISOString().slice(0, 10);
}

function monthRange(monthKey) {
  const [yearStr, monthStr] = parseMonthKey(monthKey).split('-');
  const year = Number.parseInt(yearStr, 10);
  const month = Number.parseInt(monthStr, 10);
  const startKey = `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-01`;
  const nextMonth = month === 12 ? 1 : month + 1;
  const nextYear = month === 12 ? year + 1 : year;
  const endKey = `${String(nextYear).padStart(4, '0')}-${String(nextMonth).padStart(2, '0')}-01`;
  return { monthKey: `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}`, startKey, endKey };
}

function slugify(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'custom';
}

function normalizeCategoryRow(row) {
  return {
    id: row.id,
    userId: row.user_id || null,
    key: row.slug,
    label: row.name,
    name: row.name,
    slug: row.slug,
    iconKey: row.icon_key,
    kind: row.kind,
    color: row.color,
    sortOrder: row.sort_order,
    isGlobal: row.user_id == null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function normalizeTransactionRow(row) {
  return {
    id: row.id,
    userId: row.user_id,
    calendarEntryId: row.calendar_entry_id || null,
    categoryId: row.category_id || null,
    amount: toMoneyNumber(row.amount),
    isExpense: Boolean(row.is_expense),
    transactionDate: row.transaction_date,
    note: row.note || null,
    category: row.category_id ? {
      id: row.category_id,
      key: row.category_slug,
      label: row.category_name,
      iconKey: row.category_icon_key,
      kind: row.category_kind,
      color: row.category_color,
    } : null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function normalizeBudgetRow(row) {
  return {
    id: row.id,
    userId: row.user_id,
    categoryId: row.category_id,
    monthKey: row.month_key,
    limitAmount: toMoneyNumber(row.limit_amount),
    isRepeat: Boolean(row.is_repeat),
    spentAmount: toMoneyNumber(row.spent_amount),
    remainingAmount: toMoneyNumber(row.limit_amount) - toMoneyNumber(row.spent_amount),
    progress: toMoneyNumber(row.limit_amount) > 0 ? Math.min(1, toMoneyNumber(row.spent_amount) / toMoneyNumber(row.limit_amount)) : 0,
    category: row.category_id ? {
      id: row.category_id,
      key: row.category_slug,
      label: row.category_name,
      iconKey: row.category_icon_key,
      kind: row.category_kind,
      color: row.category_color,
    } : null,
    name: row.category_name,
    iconKey: row.category_icon_key,
    kind: row.category_kind,
    color: row.category_color,
    startDate: row.start_date,
    endDate: row.end_date,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function listCategories(userId) {
  const [rows] = await pool.execute(
    `SELECT id, user_id, slug, name, icon_key, kind, color, sort_order, created_at, updated_at
     FROM categories
     WHERE user_id IS NULL OR user_id = ?
     ORDER BY sort_order ASC, name ASC`,
    [userId],
  );

  return rows.map(normalizeCategoryRow);
}

async function createCategory(userId, payload) {
  const name = String(payload.name || '').trim();
  if (!name) {
    throw new Error('Category name is required');
  }

  const slug = slugify(payload.slug || name);
  const iconKey = String(payload.iconKey || 'other').trim() || 'other';
  const kind = ['expense', 'income', 'both'].includes(String(payload.kind || '').trim())
    ? String(payload.kind).trim()
    : 'expense';
  const color = String(payload.color || '#8E8E93').trim() || '#8E8E93';
  const sortOrder = toInt(payload.sortOrder, 0);

  const [result] = await pool.execute(
    `INSERT INTO categories (user_id, slug, name, icon_key, kind, color, sort_order)
     VALUES (?, ?, ?, ?, ?, ?, ?)` ,
    [userId, slug, name, iconKey, kind, color, sortOrder],
  );

  return result.insertId;
}

async function findCategoryIdBySlug(userId, slug) {
  const normalizedSlug = slugify(slug);
  const [rows] = await pool.execute(
    `SELECT id
     FROM categories
     WHERE slug = ? AND (user_id = ? OR user_id IS NULL)
     ORDER BY user_id IS NULL ASC, id ASC
     LIMIT 1`,
    [normalizedSlug, userId],
  );

  return rows[0] ? toInt(rows[0].id, 0) : 0;
}

async function resolveCategoryIdForBudget(userId, payload) {
  const providedCategoryId = toInt(payload.categoryId, 0);
  if (providedCategoryId > 0) {
    return providedCategoryId;
  }

  const slugSource = payload.slug || payload.key || payload.name || '';
  const existingCategoryId = await findCategoryIdBySlug(userId, slugSource);
  if (existingCategoryId > 0) {
    return existingCategoryId;
  }

  return createCategory(userId, payload);
}

async function resolveCategoryIdForTransaction(userId, payload) {
  const providedCategoryId = toInt(payload.categoryId, 0);
  if (providedCategoryId > 0) {
    return providedCategoryId;
  }

  const rawCategoryId = typeof payload.categoryId === 'string' ? payload.categoryId.trim() : '';
  const slugCandidates = [
    payload.slug,
    payload.categorySlug,
    payload.categoryKey,
    payload.key,
  ];

  if (rawCategoryId && !/^\d+$/.test(rawCategoryId)) {
    slugCandidates.push(rawCategoryId);
  }

  for (const candidate of slugCandidates) {
    if (!candidate) continue;
    const resolvedCategoryId = await findCategoryIdBySlug(userId, candidate);
    if (resolvedCategoryId > 0) {
      return resolvedCategoryId;
    }
  }

  return null;
}

async function updateCategory(userId, categoryId, payload) {
  const fields = [];
  const values = [];

  if (payload.name !== undefined) {
    const name = String(payload.name || '').trim();
    if (!name) throw new Error('Category name is required');
    fields.push('name = ?');
    values.push(name);
  }

  if (payload.slug !== undefined) {
    fields.push('slug = ?');
    values.push(slugify(payload.slug));
  }

  if (payload.iconKey !== undefined) {
    fields.push('icon_key = ?');
    values.push(String(payload.iconKey || 'other').trim() || 'other');
  }

  if (payload.kind !== undefined) {
    const kind = ['expense', 'income', 'both'].includes(String(payload.kind || '').trim())
      ? String(payload.kind).trim()
      : 'expense';
    fields.push('kind = ?');
    values.push(kind);
  }

  if (payload.color !== undefined) {
    fields.push('color = ?');
    values.push(String(payload.color || '#8E8E93').trim() || '#8E8E93');
  }

  if (payload.sortOrder !== undefined) {
    fields.push('sort_order = ?');
    values.push(toInt(payload.sortOrder, 0));
  }

  if (fields.length === 0) return false;

  fields.push('updated_at = CURRENT_TIMESTAMP');
  values.push(userId, categoryId);

  await pool.execute(
    `UPDATE categories
     SET ${fields.join(', ')}
     WHERE user_id = ? AND id = ?`,
    values,
  );

  return true;
}

async function deleteCategory(userId, categoryId) {
  await pool.execute('DELETE FROM categories WHERE user_id = ? AND id = ?', [userId, categoryId]);
}

async function upsertBudget(userId, payload) {
  const monthKey = parseMonthKey(payload.monthKey);
  const categoryId = await resolveCategoryIdForBudget(userId, payload);

  const limitAmount = toMoneyString(payload.limitAmount ?? payload.limit ?? 0);
  const isRepeat = toBooleanish(payload.isRepeat, false) ? 1 : 0;
  const startDate = payload.startDate ? normalizeDateString(payload.startDate) : null;
  const endDate = payload.endDate ? normalizeDateString(payload.endDate) : null;

  if (payload.id) {
    await pool.execute(
      `UPDATE budgets 
       SET category_id = ?, month_key = ?, limit_amount = ?, is_repeat = ?, start_date = ?, end_date = ?, updated_at = CURRENT_TIMESTAMP
       WHERE id = ? AND user_id = ?`,
      [categoryId, monthKey, limitAmount, isRepeat, startDate, endDate, payload.id, userId]
    );
  } else {
    await pool.execute(
      `INSERT INTO budgets (user_id, category_id, month_key, limit_amount, is_repeat, start_date, end_date)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         limit_amount = VALUES(limit_amount),
         is_repeat = VALUES(is_repeat),
         start_date = VALUES(start_date),
         end_date = VALUES(end_date),
         updated_at = CURRENT_TIMESTAMP`,
      [userId, categoryId, monthKey, limitAmount, isRepeat, startDate, endDate],
    );
  }

  const [rows] = await pool.execute(
    `SELECT b.id, b.user_id, b.category_id, b.month_key, b.limit_amount, b.is_repeat, b.start_date, b.end_date, b.created_at, b.updated_at,
            c.slug AS category_slug, c.name AS category_name, c.icon_key AS category_icon_key,
            c.kind AS category_kind, c.color AS category_color
     FROM budgets b
     JOIN categories c ON c.id = b.category_id
     WHERE b.user_id = ? AND b.category_id = ? AND b.month_key = ?
     LIMIT 1`,
    [userId, categoryId, monthKey],
  );

  return rows[0] ? normalizeBudgetRow(rows[0]) : null;
}

async function updateBudget(userId, budgetId, payload) {
  const fields = [];
  const values = [];

  if (payload.limitAmount !== undefined || payload.limit !== undefined) {
    fields.push('limit_amount = ?');
    values.push(toMoneyString(payload.limitAmount ?? payload.limit));
  }

  if (payload.isRepeat !== undefined) {
    fields.push('is_repeat = ?');
    values.push(toBooleanish(payload.isRepeat, false) ? 1 : 0);
  }

  if (payload.startDate !== undefined) {
    fields.push('start_date = ?');
    values.push(payload.startDate ? normalizeDateString(payload.startDate) : null);
  }

  if (payload.endDate !== undefined) {
    fields.push('end_date = ?');
    values.push(payload.endDate ? normalizeDateString(payload.endDate) : null);
  }

  if (fields.length > 0) {
    fields.push('updated_at = CURRENT_TIMESTAMP');
    values.push(userId, budgetId);

    await pool.execute(
      `UPDATE budgets
       SET ${fields.join(', ')}
       WHERE user_id = ? AND id = ?`,
      values,
    );
  }

  if (payload.categoryId || payload.name || payload.slug || payload.iconKey || payload.kind || payload.color || payload.sortOrder !== undefined) {
    const [budgetRows] = await pool.execute('SELECT category_id FROM budgets WHERE user_id = ? AND id = ? LIMIT 1', [userId, budgetId]);
    if (budgetRows.length > 0) {
      await updateCategory(userId, budgetRows[0].category_id, payload);
    }
  }
}

async function deleteBudget(userId, budgetId) {
  await pool.execute('DELETE FROM budgets WHERE user_id = ? AND id = ?', [userId, budgetId]);
}

async function listBudgets(userId, monthKey) {
  const normalizedMonthKey = parseMonthKey(monthKey);
  const { startKey, endKey } = monthRange(normalizedMonthKey);

  const [rows] = await pool.execute(
    `SELECT b.id,
            b.user_id,
            b.category_id,
            b.month_key,
            b.limit_amount,
            b.is_repeat,
            b.start_date,
            b.end_date,
            b.created_at,
            b.updated_at,
            c.slug AS category_slug,
            c.name AS category_name,
            c.icon_key AS category_icon_key,
            c.kind AS category_kind,
            c.color AS category_color,
            COALESCE(SUM(CASE
              WHEN (
                (c.kind = 'income' AND t.is_expense = 0)
                OR (c.kind = 'both')
                OR ((c.kind IS NULL OR c.kind = '' OR c.kind = 'expense') AND t.is_expense = 1)
              )
               AND (
                 t.category_id = b.category_id
                 OR (
                   t.category_id IS NULL
                   AND ce.category_key IS NOT NULL
                   AND ce.category_key <> ''
                   AND (ce.category_key = c.slug OR ce.category_key = CAST(c.id AS CHAR))
                 )
               )
              THEN t.amount ELSE 0 END), 0) AS spent_amount
     FROM budgets b
     JOIN categories c ON c.id = b.category_id
     LEFT JOIN transactions t
       ON t.user_id = b.user_id
      AND t.transaction_date >= ?
      AND t.transaction_date < ?
      LEFT JOIN calendar_entries ce
        ON ce.id = t.calendar_entry_id
     WHERE b.user_id = ? 
       AND b.month_key = ? 
       AND (b.end_date IS NULL OR b.end_date >= CURRENT_DATE())
     GROUP BY b.id, c.id
     ORDER BY c.sort_order ASC, c.name ASC`,
    [startKey, endKey, userId, normalizedMonthKey],
  );

  const items = rows.map(normalizeBudgetRow);
  const monthlyBudget = items.reduce((sum, item) => sum + item.limitAmount, 0);
  const totalSpent = items.reduce((sum, item) => sum + item.spentAmount, 0);

  return {
    monthKey: normalizedMonthKey,
    monthlyBudget,
    totalSpent,
    remaining: monthlyBudget - totalSpent,
    items,
  };
}

async function listHistoryBudgets(userId) {
  const currentMonthKey = parseMonthKey(null);

  const [rows] = await pool.execute(
    `SELECT b.id,
            b.user_id,
            b.category_id,
            b.month_key,
            b.limit_amount,
            b.is_repeat,
            b.start_date,
            b.end_date,
            b.created_at,
            b.updated_at,
            c.slug AS category_slug,
            c.name AS category_name,
            c.icon_key AS category_icon_key,
            c.kind AS category_kind,
            c.color AS category_color,
            COALESCE(SUM(CASE
              WHEN (
                (c.kind = 'income' AND t.is_expense = 0)
                OR (c.kind = 'both')
                OR ((c.kind IS NULL OR c.kind = '' OR c.kind = 'expense') AND t.is_expense = 1)
              )
               AND (
                 t.category_id = b.category_id
                 OR (
                   t.category_id IS NULL
                   AND ce.category_key IS NOT NULL
                   AND ce.category_key <> ''
                   AND (ce.category_key = c.slug OR ce.category_key = CAST(c.id AS CHAR))
                 )
               )
              THEN t.amount ELSE 0 END), 0) AS spent_amount
     FROM budgets b
     JOIN categories c ON c.id = b.category_id
     LEFT JOIN transactions t
       ON t.user_id = b.user_id
      AND (
         (b.start_date IS NOT NULL AND b.end_date IS NOT NULL AND t.transaction_date >= b.start_date AND t.transaction_date <= b.end_date)
         OR
         ((b.start_date IS NULL OR b.end_date IS NULL) AND DATE_FORMAT(t.transaction_date, '%Y-%m') = b.month_key)
      )
      LEFT JOIN calendar_entries ce
        ON ce.id = t.calendar_entry_id
     WHERE b.user_id = ? 
       AND (
         (b.end_date IS NOT NULL AND b.end_date < CURRENT_DATE()) 
         OR 
         (b.end_date IS NULL AND b.month_key < ?)
       )
       AND b.category_id NOT IN (
         SELECT b2.category_id 
         FROM budgets b2 
         WHERE b2.user_id = ? 
           AND (
             (b2.end_date IS NOT NULL AND b2.end_date >= CURRENT_DATE())
             OR
             (b2.end_date IS NULL AND b2.month_key >= ?)
           )
       )
     GROUP BY b.id, c.id
     ORDER BY COALESCE(b.end_date, LAST_DAY(STR_TO_DATE(CONCAT(b.month_key, '-01'), '%Y-%m-%d'))) DESC, c.sort_order ASC`,
    [userId, currentMonthKey, userId, currentMonthKey],
  );

  return rows.map(normalizeBudgetRow);
}

async function getBudgetByCategoryMonth(userId, categoryId, monthKey) {
  const normalizedMonthKey = parseMonthKey(monthKey);
  const [rows] = await pool.execute(
    `SELECT b.id,
            b.user_id,
            b.category_id,
            b.month_key,
            b.limit_amount,
            b.is_repeat,
            b.start_date,
            b.end_date,
            b.created_at,
            b.updated_at,
            c.slug AS category_slug,
            c.name AS category_name,
            c.icon_key AS category_icon_key,
            c.kind AS category_kind,
            c.color AS category_color,
            COALESCE(SUM(CASE
              WHEN (
                (c.kind = 'income' AND t.is_expense = 0)
                OR (c.kind = 'both')
                OR ((c.kind IS NULL OR c.kind = '' OR c.kind = 'expense') AND t.is_expense = 1)
              )
               AND (
                 t.category_id = b.category_id
                 OR (
                   t.category_id IS NULL
                   AND ce.category_key IS NOT NULL
                   AND ce.category_key <> ''
                   AND (ce.category_key = c.slug OR ce.category_key = CAST(c.id AS CHAR))
                 )
               )
              THEN t.amount ELSE 0 END), 0) AS spent_amount
     FROM budgets b
     JOIN categories c ON c.id = b.category_id
     LEFT JOIN transactions t
       ON t.user_id = b.user_id
      AND t.transaction_date >= ?
      AND t.transaction_date < ?
      LEFT JOIN calendar_entries ce
        ON ce.id = t.calendar_entry_id
     WHERE b.user_id = ?
       AND b.category_id = ?
       AND b.month_key = ?
     GROUP BY b.id, c.id
     LIMIT 1`,
    [monthRange(normalizedMonthKey).startKey, monthRange(normalizedMonthKey).endKey, userId, categoryId, normalizedMonthKey],
  );

  return rows[0] ? normalizeBudgetRow(rows[0]) : null;
}

async function listTransactions(userId, monthKey, filters = {}) {
  const normalizedMonthKey = parseMonthKey(monthKey);
  const { startKey, endKey } = monthRange(normalizedMonthKey);
  const categoryId = filters.categoryId ? toInt(filters.categoryId, 0) : 0;
  const typeFilter = filters.type ? String(filters.type).toLowerCase() : '';

  const params = [userId, startKey, endKey];
  let extraWhere = '';
  if (categoryId > 0) {
    extraWhere += ' AND t.category_id = ?';
    params.push(categoryId);
  }
  if (typeFilter === 'expense' || typeFilter === 'income') {
    extraWhere += ' AND t.is_expense = ?';
    params.push(typeFilter === 'expense' ? 1 : 0);
  }

  const [rows] = await pool.execute(
    `SELECT t.id,
            t.user_id,
            t.calendar_entry_id,
            t.category_id,
            t.amount,
            t.is_expense,
            t.transaction_date,
            t.note,
            t.created_at,
            t.updated_at,
            c.slug AS category_slug,
            c.name AS category_name,
            c.icon_key AS category_icon_key,
            c.kind AS category_kind,
            c.color AS category_color
     FROM transactions t
     LEFT JOIN categories c ON c.id = t.category_id
     WHERE t.user_id = ?
       AND t.transaction_date >= ?
       AND t.transaction_date < ?
       ${extraWhere}
     ORDER BY t.transaction_date DESC, t.id DESC`,
    params,
  );

  return rows.map(normalizeTransactionRow);
}

async function createTransaction(userId, payload) {
  const amount = toMoneyString(payload.amount);
  const isExpense = toBooleanish(payload.isExpense, true) ? 1 : 0;
  const transactionDate = normalizeDateString(payload.transactionDate || payload.date);
  const categoryId = await resolveCategoryIdForTransaction(userId, payload);
  const note = payload.note ? String(payload.note).trim() : null;
  const calendarEntryId = payload.calendarEntryId ? toInt(payload.calendarEntryId, 0) : null;

  if (calendarEntryId > 0) {
    const [existingRows] = await pool.execute(
      'SELECT id FROM transactions WHERE user_id = ? AND calendar_entry_id = ? LIMIT 1',
      [userId, calendarEntryId],
    );

    if (existingRows.length > 0) {
      await pool.execute(
        `UPDATE transactions
         SET category_id = ?, amount = ?, is_expense = ?, transaction_date = ?, note = ?, updated_at = CURRENT_TIMESTAMP
         WHERE user_id = ? AND calendar_entry_id = ?`,
        [categoryId, amount, isExpense, transactionDate, note, userId, calendarEntryId],
      );

      const [updatedRows] = await pool.execute(
        `SELECT t.id,
                t.user_id,
                t.calendar_entry_id,
                t.category_id,
                t.amount,
                t.is_expense,
                t.transaction_date,
                t.note,
                t.created_at,
                t.updated_at,
                c.slug AS category_slug,
                c.name AS category_name,
                c.icon_key AS category_icon_key,
                c.kind AS category_kind,
                c.color AS category_color
         FROM transactions t
         LEFT JOIN categories c ON c.id = t.category_id
         WHERE t.user_id = ? AND t.calendar_entry_id = ?
         LIMIT 1`,
        [userId, calendarEntryId],
      );

      return updatedRows[0] ? normalizeTransactionRow(updatedRows[0]) : null;
    }
  }

  const [result] = await pool.execute(
    `INSERT INTO transactions (user_id, calendar_entry_id, category_id, amount, is_expense, transaction_date, note)
     VALUES (?, ?, ?, ?, ?, ?, ?)` ,
    [userId, calendarEntryId, categoryId, amount, isExpense, transactionDate, note],
  );

  const [rows] = await pool.execute(
    `SELECT t.id,
            t.user_id,
            t.calendar_entry_id,
            t.category_id,
            t.amount,
            t.is_expense,
            t.transaction_date,
            t.note,
            t.created_at,
            t.updated_at,
            c.slug AS category_slug,
            c.name AS category_name,
            c.icon_key AS category_icon_key,
            c.kind AS category_kind,
            c.color AS category_color
     FROM transactions t
     LEFT JOIN categories c ON c.id = t.category_id
     WHERE t.id = ?
     LIMIT 1`,
    [result.insertId],
  );

  return rows[0] ? normalizeTransactionRow(rows[0]) : null;
}

async function upsertTransactionForCalendarEntry(userId, calendarEntryId, payload) {
  const [existingRows] = await pool.execute(
    'SELECT id, amount, is_expense, transaction_date, note FROM transactions WHERE user_id = ? AND calendar_entry_id = ? LIMIT 1',
    [userId, calendarEntryId],
  );

  let calendarDateKey = null;
  let calendarCategoryKey = null;
  try {
    const [ceRows] = await pool.execute(
      'SELECT date_key, category_key FROM calendar_entries WHERE id = ? AND user_id = ? LIMIT 1',
      [calendarEntryId, userId],
    );
    if (ceRows && ceRows.length > 0) {
      calendarDateKey = ceRows[0].date_key || null;
      calendarCategoryKey = ceRows[0].category_key || null;
    }
  } catch (e) {
    // ignore lookup errors
  }

  const existingTx = existingRows.length > 0 ? existingRows[0] : null;
  const transactionDate = normalizeDateString(
    payload.transactionDate || payload.dateKey || payload.date || calendarDateKey || existingTx?.transaction_date,
  );
  const amount = toMoneyString(payload.amount !== undefined ? payload.amount : existingTx?.amount);
  const isExpense = toBooleanish(payload.isExpense, existingTx ? Boolean(existingTx.is_expense) : true) ? 1 : 0;
  // If payload lacks category info, try to read it from calendar_entries.category_key
  const note = payload.note !== undefined
    ? (payload.note ? String(payload.note).trim() : null)
    : (existingTx?.note || null);
  let effectivePayload = Object.assign({}, payload);
  if ((!effectivePayload.categoryId || effectivePayload.categoryId === null) && !effectivePayload.categoryKey) {
    if (calendarCategoryKey) {
      effectivePayload.categoryKey = calendarCategoryKey;
    }
  }

  const categoryId = await resolveCategoryIdForTransaction(userId, effectivePayload);

  if (existingRows.length > 0) {
    await pool.execute(
      `UPDATE transactions
       SET category_id = ?, amount = ?, is_expense = ?, transaction_date = ?, note = ?, updated_at = CURRENT_TIMESTAMP
       WHERE user_id = ? AND calendar_entry_id = ?`,
      [categoryId, amount, isExpense, transactionDate, note, userId, calendarEntryId],
    );
    return true;
  }

  await pool.execute(
    `INSERT INTO transactions (user_id, calendar_entry_id, category_id, amount, is_expense, transaction_date, note)
     VALUES (?, ?, ?, ?, ?, ?, ?)` ,
    [userId, calendarEntryId, categoryId, amount, isExpense, transactionDate, note],
  );
  return true;
}

async function updateTransaction(userId, transactionId, payload) {
  const fields = [];
  const values = [];

  if (payload.amount !== undefined) {
    fields.push('amount = ?');
    values.push(toMoneyString(payload.amount));
  }

  if (payload.isExpense !== undefined) {
    fields.push('is_expense = ?');
    values.push(toBooleanish(payload.isExpense, true) ? 1 : 0);
  }

  if (payload.transactionDate !== undefined || payload.date !== undefined) {
    fields.push('transaction_date = ?');
    values.push(normalizeDateString(payload.transactionDate || payload.date));
  }

  if (payload.categoryId !== undefined) {
    fields.push('category_id = ?');
    values.push(await resolveCategoryIdForTransaction(userId, payload));
  }

  if (payload.categoryKey !== undefined || payload.slug !== undefined || payload.key !== undefined || payload.categorySlug !== undefined) {
    fields.push('category_id = ?');
    values.push(await resolveCategoryIdForTransaction(userId, payload));
  }

  if (payload.note !== undefined) {
    fields.push('note = ?');
    values.push(payload.note ? String(payload.note).trim() : null);
  }

  if (payload.calendarEntryId !== undefined) {
    fields.push('calendar_entry_id = ?');
    values.push(payload.calendarEntryId ? toInt(payload.calendarEntryId, 0) : null);
  }

  if (fields.length === 0) return false;

  fields.push('updated_at = CURRENT_TIMESTAMP');
  values.push(userId, transactionId);

  await pool.execute(
    `UPDATE transactions
     SET ${fields.join(', ')}
     WHERE user_id = ? AND id = ?`,
    values,
  );
  return true;
}

async function deleteTransaction(userId, transactionId) {
  await pool.execute('DELETE FROM transactions WHERE user_id = ? AND id = ?', [userId, transactionId]);
}

async function getMonthlySummary(userId, monthKey) {
  const normalizedMonthKey = parseMonthKey(monthKey);
  const { startKey, endKey } = monthRange(normalizedMonthKey);
  const transactions = await listTransactions(userId, normalizedMonthKey);

  let totalExpense = 0;
  let totalIncome = 0;
  const categoryMap = new Map();
  const dailyMap = new Map();

  for (const tx of transactions) {
    const amount = toMoneyNumber(tx.amount);
    const categoryKey = tx.category?.key || 'uncategorized';
    const categoryLabel = tx.category?.label || 'Chưa phân loại';

    if (tx.isExpense) {
      totalExpense += amount;
    } else {
      totalIncome += amount;
    }

    const categoryBucket = categoryMap.get(categoryKey) || {
      key: categoryKey,
      label: categoryLabel,
      amount: 0,
      expenseAmount: 0,
      incomeAmount: 0,
      iconKey: tx.category?.iconKey || 'other',
      color: tx.category?.color || '#8E8E93',
      kind: tx.category?.kind || 'expense',
    };
    categoryBucket.amount += amount;
    if (tx.isExpense) categoryBucket.expenseAmount += amount;
    else categoryBucket.incomeAmount += amount;
    categoryMap.set(categoryKey, categoryBucket);

    const dayKey = tx.transactionDate;
    const dailyBucket = dailyMap.get(dayKey) || {
      dateKey: dayKey,
      expenseAmount: 0,
      incomeAmount: 0,
      netAmount: 0,
    };
    if (tx.isExpense) dailyBucket.expenseAmount += amount;
    else dailyBucket.incomeAmount += amount;
    dailyBucket.netAmount = dailyBucket.incomeAmount - dailyBucket.expenseAmount;
    dailyMap.set(dayKey, dailyBucket);
  }

  const categories = [...categoryMap.values()].sort((a, b) => b.amount - a.amount);
  const daily = [...dailyMap.values()].sort((a, b) => String(a.dateKey).localeCompare(String(b.dateKey)));

  return {
    monthKey: normalizedMonthKey,
    range: { startKey, endKey },
    totalExpense,
    totalIncome,
    netTotal: totalIncome - totalExpense,
    transactionCount: transactions.length,
    categories,
    daily,
    transactions,
  };
}

async function listBudgetDashboard(userId, monthKey) {
  return listBudgets(userId, monthKey);
}

module.exports = {
  createBudget: upsertBudget,
  createCategory,
  createTransaction,
  deleteBudget,
  deleteCategory,
  deleteTransaction,
  getMonthlySummary,
  listBudgetDashboard,
  listBudgets,
  listHistoryBudgets,
  listCategories,
  listTransactions,
  getBudgetByCategoryMonth,
  normalizeCategoryRow,
  normalizeBudgetRow,
  normalizeTransactionRow,
  parseMonthKey,
  updateBudget,
  updateCategory,
  updateTransaction,
  upsertTransactionForCalendarEntry,
};
