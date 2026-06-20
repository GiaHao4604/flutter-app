const express = require('express');
const { body, param, query } = require('express-validator');
const { authMiddleware } = require('../middlewares/authMiddleware');
const financeController = require('../controllers/financeController');

const router = express.Router();

router.use(authMiddleware);

router.get('/categories', financeController.getCategories);
router.post(
  '/categories',
  [
    body('name').optional().isString(),
    body('slug').optional().isString(),
    body('iconKey').optional().isString(),
    body('kind').optional().isIn(['expense', 'income', 'both']),
    body('color').optional().isString(),
    body('sortOrder').optional().isInt(),
  ],
  financeController.postCategory,
);
router.patch('/categories/:id', [param('id').isInt({ min: 1 })], financeController.patchCategory);
router.delete('/categories/:id', [param('id').isInt({ min: 1 })], financeController.deleteCategory);

router.get('/budgets/history', financeController.getHistoryBudgets);
router.get('/budgets', [query('monthKey').optional().isString()], financeController.getBudgets);
router.post(
  '/budgets',
  [
    body('monthKey').optional().isString(),
    body('categoryId').optional().isInt({ min: 1 }),
    body('slug').optional().isString(),
    body('name').optional().isString(),
    body('limitAmount').optional().isNumeric(),
    body('limit').optional().isNumeric(),
    body('iconKey').optional().isString(),
    body('kind').optional().isIn(['expense', 'income', 'both']),
    body('color').optional().isString(),
    body('sortOrder').optional().isInt(),
    body('isRepeat').optional().isBoolean({ loose: true }),
  ],
  financeController.postBudget,
);
router.patch('/budgets/:id', [param('id').isInt({ min: 1 })], financeController.patchBudget);
router.delete('/budgets/:id', [param('id').isInt({ min: 1 })], financeController.deleteBudget);

router.get(
  '/transactions',
  [
    query('monthKey').optional().isString(),
    query('categoryId').optional().isInt({ min: 1 }),
    query('type').optional().isIn(['expense', 'income']),
  ],
  financeController.getTransactions,
);
router.post(
  '/transactions',
  [
    body('amount').optional().isNumeric(),
    body('isExpense').optional().isBoolean({ loose: true }),
    body('transactionDate').optional().isISO8601(),
    body('date').optional().isISO8601(),
    body('categoryId').optional().custom((value) => {
      if (value === null || value === undefined || value === '') return true;
      if (Number.isInteger(value) && value > 0) return true;
      if (typeof value === 'string') {
        const trimmed = value.trim();
        if (!trimmed) return true;
        return /^\d+$/.test(trimmed) || /^[a-zA-Z0-9_-]+$/.test(trimmed);
      }
      throw new Error('Invalid categoryId');
    }),
    body('slug').optional().isString(),
    body('categoryKey').optional().isString(),
    body('categorySlug').optional().isString(),
    body('key').optional().isString(),
    body('calendarEntryId').optional().isInt({ min: 1 }),
    body('note').optional().isString(),
  ],
  financeController.postTransaction,
);
router.patch('/transactions/:id', [param('id').isInt({ min: 1 })], financeController.patchTransaction);
router.delete('/transactions/:id', [param('id').isInt({ min: 1 })], financeController.deleteTransaction);

router.get('/summary', [query('monthKey').optional().isString()], financeController.getSummary);

module.exports = router;
