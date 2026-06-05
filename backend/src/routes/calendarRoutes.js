const express = require('express');
const { body, param, query } = require('express-validator');
const { authMiddleware } = require('../middlewares/authMiddleware');
const uploadCalendar = require('../middleware/uploadCalendar');
const calendarController = require('../controllers/calendarController');

const router = express.Router();

router.use(authMiddleware);

const categoryFieldValidator = body('categoryId').optional().custom((value) => {
  if (value === null || value === undefined || value === '') return true;
  if (Number.isInteger(value) && value > 0) return true;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return true;
    return /^\d+$/.test(trimmed) || /^[a-zA-Z0-9_-]+$/.test(trimmed);
  }
  throw new Error('Invalid categoryId');
});

router.get(
  '/month',
  [query('year').optional().isInt({ min: 1970, max: 3000 }), query('month').optional().isInt({ min: 1, max: 12 }), query('monthKey').optional().isString()],
  calendarController.getMonth,
);

router.get(
  '/entries',
  [query('year').optional().isInt({ min: 1970, max: 3000 }), query('month').optional().isInt({ min: 1, max: 12 }), query('monthKey').optional().isString()],
  calendarController.getEntries,
);

router.post(
  '/entries',
  (req, res, next) => {
    uploadCalendar.single('image')(req, res, (err) => {
      if (err) {
        return res.status(400).json({ success: false, message: err.message });
      }

      return next();
    });
  },
  [
    body('amount').optional().isNumeric(),
    body('isExpense').optional().isBoolean({ loose: true }),
    body('date').optional().isISO8601(),
    body('dateKey').optional().isString(),
    body('imageUrl').optional().isString(),
    body('note').optional().isString(),
    categoryFieldValidator,
    body('slug').optional().isString(),
    body('categoryKey').optional().isString(),
    body('categorySlug').optional().isString(),
    body('key').optional().isString(),
    body('transactionDate').optional().isISO8601(),
    body('transactionNote').optional().isString(),
  ],
  calendarController.postEntry,
);

router.patch(
  '/entries/:id',
  (req, res, next) => {
    uploadCalendar.single('image')(req, res, (err) => {
      if (err) {
        return res.status(400).json({ success: false, message: err.message });
      }

      return next();
    });
  },
  [
    param('id').isInt({ min: 1 }),
    body('amount').optional().isNumeric(),
    body('isExpense').optional().isBoolean({ loose: true }),
    body('date').optional().isISO8601(),
    body('dateKey').optional().isString(),
    body('imageUrl').optional().isString(),
    body('note').optional().isString(),
    categoryFieldValidator,
    body('slug').optional().isString(),
    body('categoryKey').optional().isString(),
    body('categorySlug').optional().isString(),
    body('key').optional().isString(),
    body('transactionDate').optional().isISO8601(),
    body('transactionNote').optional().isString(),
  ],
  calendarController.patchEntry,
);

router.delete('/entries/:id', [param('id').isInt({ min: 1 })], calendarController.deleteEntry);

module.exports = router;