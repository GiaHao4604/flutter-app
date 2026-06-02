const { validationResult } = require('express-validator');
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

async function getCategories(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const data = await financeModel.listCategories(userId);
    return res.json({ success: true, data });
  } catch (error) {
    console.error('[finance] getCategories error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function postCategory(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const id = await financeModel.createCategory(userId, req.body);
    const data = await financeModel.listCategories(userId);
    const created = data.find((item) => Number(item.id) === Number(id)) || null;
    return res.status(201).json({ success: true, message: 'Category created', data: created });
  } catch (error) {
    console.error('[finance] postCategory error:', error);
    return res.status(400).json({ success: false, message: error.message || 'Unable to create category' });
  }
}

async function patchCategory(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const categoryId = Number(req.params.id);
    if (!Number.isInteger(categoryId) || categoryId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid category id' });
    }

    await financeModel.updateCategory(userId, categoryId, req.body);
    const data = await financeModel.listCategories(userId);
    const updated = data.find((item) => Number(item.id) === Number(categoryId)) || null;
    return res.json({ success: true, message: 'Category updated', data: updated });
  } catch (error) {
    console.error('[finance] patchCategory error:', error);
    return res.status(400).json({ success: false, message: error.message || 'Unable to update category' });
  }
}

async function deleteCategory(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const categoryId = Number(req.params.id);
    if (!Number.isInteger(categoryId) || categoryId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid category id' });
    }

    await financeModel.deleteCategory(userId, categoryId);
    return res.json({ success: true, message: 'Category deleted' });
  } catch (error) {
    console.error('[finance] deleteCategory error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function getBudgets(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const monthKey = req.query.monthKey;
    const data = await financeModel.listBudgets(userId, monthKey);
    return res.json({ success: true, data });
  } catch (error) {
    console.error('[finance] getBudgets error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function postBudget(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const item = await financeModel.createBudget(userId, req.body);
    return res.status(201).json({
      success: true,
      message: 'Budget saved',
      data: item,
      budget: item,
    });
  } catch (error) {
    console.error('[finance] postBudget error:', error);
    return res.status(400).json({ success: false, message: error.message || 'Unable to save budget' });
  }
}

async function patchBudget(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const budgetId = Number(req.params.id);
    if (!Number.isInteger(budgetId) || budgetId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid budget id' });
    }

    await financeModel.updateBudget(userId, budgetId, req.body);
    const monthKey = req.body.monthKey;
    const data = await financeModel.listBudgets(userId, monthKey);
    return res.json({ success: true, message: 'Budget updated', data });
  } catch (error) {
    console.error('[finance] patchBudget error:', error);
    return res.status(400).json({ success: false, message: error.message || 'Unable to update budget' });
  }
}

async function deleteBudget(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const budgetId = Number(req.params.id);
    if (!Number.isInteger(budgetId) || budgetId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid budget id' });
    }

    await financeModel.deleteBudget(userId, budgetId);
    return res.json({ success: true, message: 'Budget deleted' });
  } catch (error) {
    console.error('[finance] deleteBudget error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function getTransactions(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const data = await financeModel.listTransactions(userId, req.query.monthKey, {
      categoryId: req.query.categoryId,
      type: req.query.type,
    });
    return res.json({ success: true, data });
  } catch (error) {
    console.error('[finance] getTransactions error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function postTransaction(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const transaction = await financeModel.createTransaction(userId, req.body);
    const transactionDate = transaction?.transactionDate || req.body.transactionDate || req.body.date;
    const monthKey = typeof transactionDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(transactionDate)
      ? transactionDate.slice(0, 7)
      : null;
    const budget = transaction && transaction.categoryId && monthKey
      ? await financeModel.getBudgetByCategoryMonth(userId, transaction.categoryId, monthKey)
      : null;

    return res.status(201).json({
      success: true,
      message: 'Transaction created',
      data: transaction,
      transaction,
      budget,
    });
  } catch (error) {
    console.error('[finance] postTransaction error:', error);
    return res.status(400).json({ success: false, message: error.message || 'Unable to create transaction' });
  }
}

async function patchTransaction(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const transactionId = Number(req.params.id);
    if (!Number.isInteger(transactionId) || transactionId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid transaction id' });
    }

    await financeModel.updateTransaction(userId, transactionId, req.body);
    return res.json({ success: true, message: 'Transaction updated' });
  } catch (error) {
    console.error('[finance] patchTransaction error:', error);
    return res.status(400).json({ success: false, message: error.message || 'Unable to update transaction' });
  }
}

async function deleteTransaction(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const transactionId = Number(req.params.id);
    if (!Number.isInteger(transactionId) || transactionId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid transaction id' });
    }

    await financeModel.deleteTransaction(userId, transactionId);
    return res.json({ success: true, message: 'Transaction deleted' });
  } catch (error) {
    console.error('[finance] deleteTransaction error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function getSummary(req, res) {
  try {
    const userId = getUserId(req, res);
    if (!userId) return;

    const monthKey = req.query.monthKey;
    const summary = await financeModel.getMonthlySummary(userId, monthKey);
    const budgets = await financeModel.listBudgetDashboard(userId, monthKey);
    return res.json({ success: true, data: { ...summary, budgets } });
  } catch (error) {
    console.error('[finance] getSummary error:', error);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

module.exports = {
  deleteBudget,
  deleteCategory,
  deleteTransaction,
  getBudgets,
  getCategories,
  getSummary,
  getTransactions,
  patchBudget,
  patchCategory,
  patchTransaction,
  postBudget,
  postCategory,
  postTransaction,
};
