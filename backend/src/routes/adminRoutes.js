const express = require('express');
const router = express.Router();

const { authMiddleware, isAdmin } = require('../middlewares/authMiddleware');
const {
  getUsersChart,
  getRevenueChart,
  getAllUsers,
  toggleUserRole,
  toggleUserBan,
  deleteUser,
  getReportedPosts,
  resolveReport,
  deletePost,
  transferDirectorAdmin
} = require('../controllers/adminController');

// Mọi route ở đây đều yêu cầu đăng nhập và có quyền Admin
router.use(authMiddleware);
router.use(isAdmin);

// Dashboard
router.get('/dashboard/users-chart', getUsersChart);
router.get('/dashboard/revenue-chart', getRevenueChart);

// User Management
router.get('/users', getAllUsers);
router.put('/users/:id/role', toggleUserRole);
router.put('/users/:id/ban', toggleUserBan);
router.delete('/users/:id', deleteUser);
router.post('/users/:id/transfer', transferDirectorAdmin);

// Content Moderation (Reports)
router.get('/reports', getReportedPosts);
router.put('/reports/:id/resolve', resolveReport);
router.delete('/posts/:id', deletePost);

module.exports = router;
