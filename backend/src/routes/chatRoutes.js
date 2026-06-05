const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../middlewares/authMiddleware');
const uploadChatImageMiddleware = require('../middleware/uploadChatImage');
const {
  getConversations,
  getMessages,
  sendMessage,
  markMessagesSeen,
  uploadMessageImage,
  searchUsers,
} = require('../controllers/chatController');

router.use(authMiddleware);

router.get('/conversations', getConversations);
router.get('/users/search', searchUsers);
router.get('/messages/:conversationId', getMessages);
router.post('/messages', sendMessage);
router.put('/messages/seen', markMessagesSeen);
router.post('/messages/image', uploadChatImageMiddleware.single('image'), uploadMessageImage);

module.exports = router;
