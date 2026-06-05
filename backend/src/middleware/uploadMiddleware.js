// module.exports = upload;
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const uploadDir = path.join(
  __dirname,
  '..', // /middleware → /src
  '..', // /src → /backend
  'uploads',
  'posts',
);

if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, {
    recursive: true,
  });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },

  filename: (req, file, cb) => {
    const uniqueName =
      Date.now() +
      '-' +
      Math.round(Math.random() * 1e9);

    cb(
      null,
      uniqueName +
        path.extname(file.originalname || '.jpg'),
    );
  },
});

const allowedMimeTypes = [
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/webp',

  /// Redmi/Xiaomi đôi khi gửi kiểu này
  'application/octet-stream',
];

const fileFilter = (req, file, cb) => {
  console.log('========== FILE UPLOAD ==========');
  console.log('Original Name:', file.originalname);
  console.log('MIME:', file.mimetype);
  console.log('=================================');

  if (
    allowedMimeTypes.includes(file.mimetype)
  ) {
    cb(null, true);
  } else {
    cb(
      new Error(
        `Only images allowed. Received: ${file.mimetype}`,
      ),
      false,
    );
  }
};

const upload = multer({
  storage,

  fileFilter,

  limits: {
    fileSize: 10 * 1024 * 1024,
  },
});

module.exports = upload;
