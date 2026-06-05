const express = require('express');
const router = express.Router();
const { body } = require('express-validator');
const { authMiddleware } = require('../middlewares/authMiddleware');
const upload = require('../middleware/uploadMiddleware');
const postController = require('../controllers/postController');

const logUploadStart = (req, res, next) => {
  console.log('Incoming POST /api/posts/upload from', req.ip);
  console.log('Content-Length:', req.headers['content-length']);
  next();
};

router.use(authMiddleware);
router.post(
  '/upload',
  logUploadStart,
  (req, res, next) => {
    upload.single('image')(req, res, function (err) {
      if (err) {
        console.error('MULTER ERROR:', err);
        return res.status(500).json({ success: false, message: err.message });
      }
      next();
    });
  },
  [
    body('caption').optional().isString(),
    body('device_id').optional().isString(),
    body('camera_type').optional().isIn(['front', 'back']),
  ],
  postController.uploadPost,
);
router.get('/', postController.listPosts);

module.exports = router;
