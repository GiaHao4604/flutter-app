// const express = require('express');
// const router = express.Router();

// // 1. Import các hàm xử lý từ controller
// const { register, login, getMe, uploadAvatar } = require('../controllers/authController');

// // 2. Import các middleware (💡 Đã sửa đồng bộ tên thư mục 'middlewares' có chữ s)
// const authMiddleware = require('../middlewares/authMiddleware');
// const uploadAvatarMiddleware = require('../middleware/uploadAvatar'); 

// // Route Đăng ký tài khoản
// router.post('/register', register);

// // Route Đăng nhập
// router.post('/login', login);

// // Route Lấy thông tin cá nhân hiện tại (Cần check login)
// router.get('/me', authMiddleware, getMe);

// // Route Upload ảnh đại diện
// router.post(
//   '/upload-avatar', 
//   authMiddleware, 
//   // 💡 Giải pháp an toàn: Kiểm tra nếu nó có hàm .single thì gọi, nếu không thì chính nó là middleware
//   typeof uploadAvatarMiddleware.single === 'function' 
//     ? uploadAvatarMiddleware.single('avatar') 
//     : uploadAvatarMiddleware, 
//   uploadAvatar
// );

// module.exports = router;

const express = require('express');
const router = express.Router();

// Import các hàm từ controller
const { register, login, getMe, uploadAvatar } = require('../controllers/authController');
const {
  updateMyProfile,
  updateMyPassword,
} = require('../controllers/profileController');

// Import các middleware (Đảm bảo đúng chính tả thư mục 'middlewares')
const authMiddleware = require('../middlewares/authMiddleware');
const uploadAvatarMiddleware = require('../middleware/uploadAvatar'); 

const avatarUploadHandler = typeof uploadAvatarMiddleware.single === 'function'
  ? uploadAvatarMiddleware.single('avatar')
  : uploadAvatarMiddleware;

router.post('/register', register);
router.post('/login', login);
router.get('/me', authMiddleware, getMe);
router.put('/me', authMiddleware, updateMyProfile);
router.patch('/me/password', authMiddleware, updateMyPassword);

// Route Upload ảnh đại diện
router.post(
  '/upload-avatar', 
  authMiddleware, 
  avatarUploadHandler,
  uploadAvatar
);

module.exports = router;