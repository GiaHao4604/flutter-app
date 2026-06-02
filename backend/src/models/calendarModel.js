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

function toDateKey(value) {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
      return trimmed;
    }
  }
  // Always derive dateKey based on UTC components to avoid server timezone shifts.
  const parsed = value ? new Date(value) : new Date();
  if (Number.isNaN(parsed.getTime())) {
    const now = new Date();
    const year = now.getUTCFullYear();
    const month = String(now.getUTCMonth() + 1).padStart(2, '0');
    const day = String(now.getUTCDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  const year = parsed.getUTCFullYear();
  const month = String(parsed.getUTCMonth() + 1).padStart(2, '0');
  const day = String(parsed.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function parseMonthInput({ year, month, monthKey }) {
  if (monthKey && /^\d{4}-\d{2}$/.test(String(monthKey).trim())) {
    const [y, m] = String(monthKey).split('-').map((part) => Number.parseInt(part, 10));
    return { year: y, month: m };
  }

  const parsedYear = Number.parseInt(year, 10);
  const parsedMonth = Number.parseInt(month, 10);

  if (Number.isInteger(parsedYear) && Number.isInteger(parsedMonth) && parsedMonth >= 1 && parsedMonth <= 12) {
    return { year: parsedYear, month: parsedMonth };
  }

  const now = new Date();
  return { year: now.getFullYear(), month: now.getMonth() + 1 };
}

function monthRange({ year, month }) {
  const y = Number.parseInt(year, 10);
  const m = Number.parseInt(month, 10);
  const startKey = `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-01`;
  // endKey is first day of next month
  const nextMonth = m === 12 ? 1 : m + 1;
  const nextYear = m === 12 ? y + 1 : y;
  const endKey = `${String(nextYear).padStart(4, '0')}-${String(nextMonth).padStart(2, '0')}-01`;
  return { startKey, endKey };
}

function mapEntryRow(row) {
  return {
    id: row.id,
    date: row.date_key,
    dateKey: row.date_key,
    transactionId: row.transaction_id || null,
    // Ensure entryTs is an ISO UTC string. MySQL DATETIME has no timezone
    // so if the stored value looks like 'YYYY-MM-DD HH:MM:SS' we convert
    // to 'YYYY-MM-DDTHH:MM:SSZ' to force UTC interpretation.
    entryTs: (function () {
      if (!row.entry_ts) return null;
      // If it's already a Date object
      if (row.entry_ts instanceof Date) return row.entry_ts.toISOString();
      const s = String(row.entry_ts).trim();
      // Match 'YYYY-MM-DD HH:MM:SS' (MySQL DATETIME default text)
      const m = s.match(/^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:\.\d+)?$/);
      if (m) {
        const iso = `${m[1]}T${m[2]}Z`;
        try {
          const d = new Date(iso);
          if (!Number.isNaN(d.getTime())) return d.toISOString();
        } catch (_) {}
      }
      // Fallback: try parsing directly and convert to ISO
      try {
        const d = new Date(s);
        if (!Number.isNaN(d.getTime())) return d.toISOString();
      } catch (_) {}
      return s;
    })(),
    amount: toMoneyNumber(row.amount),
    isExpense: Boolean(row.is_expense),
    categoryKey: row.category_key || null,
    imageUrl: row.image_url,
    note: row.note,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function listMonthEntries(userId, { year, month, monthKey } = {}) {
  const parsed = parseMonthInput({ year, month, monthKey });
  const range = monthRange(parsed);

  const [rows] = await pool.execute(
    `SELECT c.id,
            c.entry_date,
            c.entry_ts,
            c.date_key,
            c.category_key,
            COALESCE(t.amount, 0) AS amount,
            COALESCE(t.is_expense, 1) AS is_expense,
            t.id AS transaction_id,
            c.image_url,
            c.note,
            c.created_at,
            c.updated_at
     FROM calendar_entries c
     LEFT JOIN transactions t ON t.calendar_entry_id = c.id AND t.user_id = c.user_id
    WHERE c.user_id = ? AND c.date_key >= ? AND c.date_key < ?
     ORDER BY c.date_key DESC, c.id DESC`,
    [userId, range.startKey, range.endKey],
  );

  const entries = rows.map(mapEntryRow);
  const postsByDay = {};
  let monthIncome = 0;
  let monthExpense = 0;

  for (const entry of entries) {
    const day = Number(String(entry.dateKey).slice(8, 10));
    if (!Number.isFinite(day)) {
      continue;
    }

    if (!postsByDay[day]) {
      postsByDay[day] = [];
    }

    postsByDay[day].push(entry);

    if (entry.isExpense) {
      monthExpense += entry.amount;
    } else {
      monthIncome += entry.amount;
    }
  }

  return {
    monthKey: `${parsed.year}-${String(parsed.month).padStart(2, '0')}`,
    year: parsed.year,
    month: parsed.month,
    entries,
    postsByDay,
    monthIncome,
    monthExpense,
  };
}

async function getEntryById(userId, entryId) {
  const [rows] = await pool.execute(
    `SELECT c.id,
            c.entry_date,
            c.entry_ts,
            c.date_key,
            c.category_key,
            COALESCE(t.amount, 0) AS amount,
            COALESCE(t.is_expense, 1) AS is_expense,
            t.id AS transaction_id,
            c.image_url,
            c.note,
            c.created_at,
            c.updated_at
     FROM calendar_entries c
     LEFT JOIN transactions t ON t.calendar_entry_id = c.id AND t.user_id = c.user_id
     WHERE c.user_id = ? AND c.id = ?
     LIMIT 1`,
    [userId, entryId],
  );

  return rows[0] ? mapEntryRow(rows[0]) : null;
}

async function createEntry(userId, payload) {
  // determine entry timestamp (prefer payload.date ISO string), store as UTC DATETIME
  const parsedTs = payload && payload.date ? new Date(payload.date) : new Date();
  const entryDateObj = Number.isNaN(parsedTs.getTime()) ? new Date() : parsedTs;
  // MySQL DATETIME format: 'YYYY-MM-DD HH:MM:SS'
  const entryTs = entryDateObj.toISOString().slice(0, 19).replace('T', ' ');
  // derive dateKey from provided date or computed timestamp
  const dateKey = toDateKey(payload.dateKey || entryDateObj);
  const imageUrl = payload.imageUrl ? String(payload.imageUrl).trim() : null;
  const note = payload.note ? String(payload.note).trim() : null;
  const categoryKey = payload.categoryKey
    ? String(payload.categoryKey).trim()
    : (payload.slug ? String(payload.slug).trim() : (payload.categoryId ? String(payload.categoryId).trim() : null));
  // If caller provided a numeric categoryId but not a slug/key, prefer storing
  // the category's slug so downstream backfill and lookups can resolve it.
  let finalCategoryKey = categoryKey;
  if ((!finalCategoryKey || finalCategoryKey === '') && payload && payload.categoryId) {
    try {
      const catId = Number.parseInt(payload.categoryId, 10);
      if (Number.isFinite(catId) && catId > 0) {
        const [rows] = await pool.execute(
          'SELECT slug FROM categories WHERE id = ? AND (user_id = ? OR user_id IS NULL) LIMIT 1',
          [catId, userId],
        );
        if (rows && rows.length > 0 && rows[0].slug) {
          finalCategoryKey = String(rows[0].slug);
        } else {
          finalCategoryKey = String(payload.categoryId).trim();
        }
      }
    } catch (e) {
      finalCategoryKey = String(payload.categoryId).trim();
    }
  }

  const [result] = await pool.execute(
    `INSERT INTO calendar_entries (user_id, entry_date, entry_ts, date_key, category_key, image_url, note)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [userId, dateKey, entryTs, dateKey, finalCategoryKey, imageUrl, note],
  );

  return result.insertId;
}

async function updateEntry(userId, entryId, payload) {
  const fields = [];
  const values = [];

  if (payload.dateKey || payload.date) {
    const parsed = payload.date ? new Date(payload.date) : null;
    const entryDateObj = parsed && !Number.isNaN(parsed.getTime()) ? parsed : new Date(payload.dateKey || Date.now());
    const dateKey = toDateKey(payload.dateKey || entryDateObj);
    const entryTs = entryDateObj.toISOString().slice(0, 19).replace('T', ' ');
    fields.push('entry_date = ?', 'date_key = ?', 'entry_ts = ?');
    values.push(dateKey, dateKey, entryTs);
  }

  if (payload.imageUrl !== undefined) {
    fields.push('image_url = ?');
    values.push(payload.imageUrl ? String(payload.imageUrl).trim() : null);
  }

  if (payload.note !== undefined) {
    fields.push('note = ?');
    values.push(payload.note ? String(payload.note).trim() : null);
  }

  if (payload.categoryKey !== undefined || payload.slug !== undefined || payload.categoryId !== undefined) {
    let categoryKey = payload.categoryKey
      ? String(payload.categoryKey).trim()
      : (payload.slug ? String(payload.slug).trim() : (payload.categoryId ? String(payload.categoryId).trim() : null));

    if ((!categoryKey || categoryKey === '') && payload.categoryId) {
      try {
        const catId = Number.parseInt(payload.categoryId, 10);
        if (Number.isFinite(catId) && catId > 0) {
          const [rows] = await pool.execute(
            'SELECT slug FROM categories WHERE id = ? AND (user_id = ? OR user_id IS NULL) LIMIT 1',
            [catId, userId],
          );
          if (rows && rows.length > 0 && rows[0].slug) {
            categoryKey = String(rows[0].slug);
          } else {
            categoryKey = String(payload.categoryId).trim();
          }
        }
      } catch (e) {
        categoryKey = String(payload.categoryId).trim();
      }
    }

    fields.push('category_key = ?');
    values.push(categoryKey);
  }

  if (fields.length === 0) {
    return;
  }

  fields.push('updated_at = CURRENT_TIMESTAMP');
  values.push(userId, entryId);

  await pool.execute(
    `UPDATE calendar_entries
     SET ${fields.join(', ')}
     WHERE user_id = ? AND id = ?`,
    values,
  );
}

async function deleteEntry(userId, entryId) {
  await pool.execute('DELETE FROM calendar_entries WHERE user_id = ? AND id = ?', [userId, entryId]);
}

module.exports = {
  createEntry,
  deleteEntry,
  getEntryById,
  listMonthEntries,
  parseMonthInput,
  toDateKey,
  updateEntry,
};