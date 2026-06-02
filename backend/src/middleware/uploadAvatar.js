const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Đường dẫn trỏ thẳng tới thư mục uploads/avatars nằm ở gốc dự án
const uploadAvatarDir = path.join(__dirname, '..', '..', 'uploads', 'avatars');

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    // Nếu thư mục 'uploads/avatars' chưa tồn tại thì tự động tạo mới
    if (!fs.existsSync(uploadAvatarDir)) {
      fs.mkdirSync(uploadAvatarDir, { recursive: true });
    }
    cb(null, uploadAvatarDir);
  },
  filename: (req, file, cb) => {
    // Tạo tên file độc nhất để không bị trùng: avatar-171892312.jpg
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, 'avatar-' + uniqueSuffix + path.extname(file.originalname || '.jpg'));
  }
});

const allowedMimeTypes = new Set([
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/heif',
  'application/octet-stream',
]);

const allowedExtensions = new Set([
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.heic',
  '.heif',
]);

// Bộ lọc chỉ cho phép tải lên file định dạng hình ảnh
const fileFilter = (req, file, cb) => {
  const mimeType = String(file.mimetype || '').toLowerCase();
  const originalName = String(file.originalname || '').toLowerCase();
  const extension = path.extname(originalName);

  // Debug log để chẩn đoán khi client upload
  try {
    console.log('[uploadAvatar] attempt upload:', {
      originalName: file.originalname,
      mimeType: file.mimetype,
      fieldname: file.fieldname,
      encoding: file.encoding,
      extension,
      remoteIp: req.ip || req.connection?.remoteAddress,
      user: req.user ? req.user.sub || req.user.id || null : null,
    });
  } catch (e) {
    console.log('[uploadAvatar] logging error', e);
  }

  if (allowedMimeTypes.has(mimeType) || allowedExtensions.has(extension)) {
    cb(null, true);
  } else {
    console.warn('[uploadAvatar] rejected file:', {
      originalName: file.originalname,
      mimeType: file.mimetype,
      extension,
    });
    cb(new Error('Chỉ chấp nhận file định dạng hình ảnh!'), false);
  }
};

const uploadAvatar = multer({ 
  storage: storage,
  fileFilter: fileFilter,
  limits: { fileSize: 5 * 1024 * 1024 } // Giới hạn file tối đa 5MB
});

// Xuất thẳng middleware này ra ngoài
module.exports = uploadAvatar;