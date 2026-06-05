const express = require('express');
const router = express.Router();

const { authMiddleware } = require('../middlewares/authMiddleware');
const uploadAvatar = require('../middleware/uploadAvatar');
const {
  getMyProfile,
  getProfileById,
  updateMyProfile,
  updateMyAvatar,
  updateMyPassword,
} = require('../controllers/profileController');

router.get('/me', authMiddleware, getMyProfile);
router.put('/me', authMiddleware, updateMyProfile);
const uploadAvatarMiddleware = typeof uploadAvatar.single === 'function'
  ? uploadAvatar.single('avatar')
  : uploadAvatar;

router.patch('/me/avatar', authMiddleware, uploadAvatarMiddleware, updateMyAvatar);
router.patch('/me/password', authMiddleware, updateMyPassword);
router.get('/:id', getProfileById);

module.exports = router;