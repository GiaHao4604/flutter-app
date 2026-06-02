const { validationResult } = require('express-validator');
const calendarModel = require('../models/calendarModel');
const financeModel = require('../models/financeModel');

function getUserId(req, res) {
  const userId = Number(req.user?.sub);
  if (!Number.isInteger(userId) || userId <= 0) {
    res.status(401).json({ success: false, message: 'Unauthorized' });
    return null;
  }

  return userId;
}

function handleValidation(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    res.status(400).json({ success: false, errors: errors.array() });
    return false;
  }

  return true;
}

async function getMonth(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const data = await calendarModel.listMonthEntries(userId, {
      year: req.query.year,
      month: req.query.month,
      monthKey: req.query.monthKey,
    });

    return res.json({ success: true, data });
  } catch (error) {
    console.error('[calendar] getMonth error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function getEntries(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const data = await calendarModel.listMonthEntries(userId, {
      year: req.query.year,
      month: req.query.month,
      monthKey: req.query.monthKey,
    });

    return res.json({ success: true, data: data.entries });
  } catch (error) {
    console.error('[calendar] getEntries error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function postEntry(req, res) {
  try {
    if (!handleValidation(req, res)) return;

    const userId = getUserId(req, res);
    if (!userId) return;

    const imageUrl = req.file ? `/uploads/calendar/${req.file.filename}` : req.body.imageUrl;
    const entryId = await calendarModel.createEntry(userId, {
      ...req.body,
      imageUrl,
    });

    const shouldSyncTransaction = req.body.amount != null
      || req.body.isExpense != null
      || req.body.categoryId != null
      || req.body.categoryKey != null
      || req.body.slug != null
      || req.body.categorySlug != null
      || req.body.key != null
      || req.body.transactionDate != null;
    if (shouldSyncTransaction) {
      await financeModel.upsertTransactionForCalendarEntry(userId, entryId, {
        amount: req.body.amount,
        isExpense: req.body.isExpense,
        categoryId: req.body.categoryId,
        categoryKey: req.body.categoryKey,
        slug: req.body.slug,
        categorySlug: req.body.categorySlug,
        key: req.body.key,
        transactionDate: req.body.transactionDate || req.body.dateKey || req.body.date,
        dateKey: req.body.dateKey,
        note: req.body.transactionNote || req.body.note,
      });
    }

    const entry = await calendarModel.getEntryById(userId, entryId);

    const payload = entry ? {
      ...entry,
      imageUrl: entry.imageUrl && entry.imageUrl.startsWith('/uploads/')
        ? `${req.protocol}://${req.get('host')}${entry.imageUrl}`
        : entry.imageUrl,
      clientLocalId: req.body.clientLocalId || req.body.localId || null,
    } : null;

    return res.status(201).json({ success: true, message: 'Entry created', data: payload });
  } catch (error) {
    console.error('[calendar] postEntry error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function patchEntry(req, res) {
  try {
    if (!handleValidation(req, res)) return;

    const userId = getUserId(req, res);
    if (!userId) return;

    const entryId = Number(req.params.id);
    if (!Number.isInteger(entryId) || entryId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid entry id' });
    }

    const existing = await calendarModel.getEntryById(userId, entryId);
    if (!existing) {
      return res.status(404).json({ success: false, message: 'Entry not found' });
    }

    await calendarModel.updateEntry(userId, entryId, req.body);
    const shouldSyncTransaction = req.body.amount != null
      || req.body.isExpense != null
      || req.body.categoryId != null
      || req.body.categoryKey != null
      || req.body.slug != null
      || req.body.categorySlug != null
      || req.body.key != null
      || req.body.transactionDate != null;
    if (shouldSyncTransaction) {
      await financeModel.upsertTransactionForCalendarEntry(userId, entryId, {
        amount: req.body.amount,
        isExpense: req.body.isExpense,
        categoryId: req.body.categoryId,
        categoryKey: req.body.categoryKey,
        slug: req.body.slug,
        categorySlug: req.body.categorySlug,
        key: req.body.key,
        transactionDate: req.body.transactionDate || req.body.dateKey || req.body.date,
        dateKey: req.body.dateKey,
        note: req.body.transactionNote || req.body.note,
      });
    }

    const entry = await calendarModel.getEntryById(userId, entryId);

    const payload = entry ? {
      ...entry,
      imageUrl: entry.imageUrl && entry.imageUrl.startsWith('/uploads/')
        ? `${req.protocol}://${req.get('host')}${entry.imageUrl}`
        : entry.imageUrl,
    } : null;

    return res.json({ success: true, message: 'Entry updated', data: payload });
  } catch (error) {
    console.error('[calendar] patchEntry error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function deleteEntry(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const entryId = Number(req.params.id);
    if (!Number.isInteger(entryId) || entryId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid entry id' });
    }

    await calendarModel.deleteEntry(userId, entryId);
    return res.json({ success: true, message: 'Entry deleted' });
  } catch (error) {
    console.error('[calendar] deleteEntry error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

module.exports = {
  deleteEntry,
  getEntries,
  getMonth,
  patchEntry,
  postEntry,
};