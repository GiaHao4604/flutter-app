const multer = require('multer');
const path = require('path');
const fs = require('fs');

const chatDir = path.join(__dirname, '..', '..', 'uploads', 'chat');
if (!fs.existsSync(chatDir)) {
  fs.mkdirSync(chatDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, chatDir),
  filename: (_req, file, cb) => {
    const timestamp = Date.now();
    const extension = path.extname(file.originalname) || '.jpg';
    cb(null, `chat-${timestamp}${extension}`);
  },
});

const fileFilter = (_req, file, cb) => {
  const acceptedTypes = ['image/jpeg', 'image/png', 'image/webp'];
  cb(null, acceptedTypes.includes(file.mimetype));
};

module.exports = multer({ storage, fileFilter });
