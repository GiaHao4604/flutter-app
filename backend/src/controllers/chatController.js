const { pool } = require('../config/db');

function normalizeUser(row) {
  return {
    id: row.id,
    name: row.name,
    avatar_url: row.avatar_url || null,
    email: row.email || null,
  };
}

function normalizeMessage(row, currentUserId) {
  return {
    id: row.id,
    conversation_id: row.conversation_id,
    sender_id: row.sender_id,
    text: row.message || null,
    image_url: row.image_url || null,
    is_seen: !!row.is_seen,
    created_at: row.created_at,
    is_me: row.sender_id === currentUserId,
    status: row.sender_id === currentUserId ? (row.is_seen ? 'seen' : 'delivered') : null,
  };
}

async function getConversations(req, res) {
  try {
    const currentUserId = Number(req.user?.sub);
    if (!Number.isInteger(currentUserId) || currentUserId <= 0) {
      return res.status(401).json({ success: false, message: 'Unauthorized' });
    }

    const [conversations] = await pool.query(
      `SELECT
         c.id AS conversation_id,
         c.created_at AS created_at,
         partner.id AS partner_id,
         partner.name AS partner_name,
         partner.avatar_url AS partner_avatar,
         m.message AS last_message,
         m.image_url AS last_image_url,
         m.sender_id AS last_sender_id,
         m.created_at AS last_message_at,
         COALESCE(unread_unseen.unread_count, 0) AS unread_count
       FROM conversations c
       JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = ?
       JOIN conversation_members other_member ON other_member.conversation_id = c.id AND other_member.user_id <> ?
       JOIN users partner ON partner.id = other_member.user_id
       LEFT JOIN messages m ON m.id = (
         SELECT id FROM messages WHERE conversation_id = c.id ORDER BY created_at DESC LIMIT 1
       )
       LEFT JOIN (
         SELECT conversation_id, COUNT(*) AS unread_count
         FROM messages
         WHERE is_seen = 0 AND sender_id <> ?
         GROUP BY conversation_id
       ) unread_unseen ON unread_unseen.conversation_id = c.id
       ORDER BY m.created_at DESC, c.created_at DESC;
      `,
      [currentUserId, currentUserId, currentUserId],
    );

    return res.json({ success: true, message: 'Conversations loaded', data: conversations });
  } catch (error) {
    console.error('getConversations error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function getMessages(req, res) {
  try {
    const currentUserId = Number(req.user?.sub);
    const conversationId = Number(req.params.conversationId);

    if (!Number.isInteger(conversationId) || conversationId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid conversation id' });
    }

    const [members] = await pool.query(
      'SELECT id FROM conversation_members WHERE conversation_id = ? AND user_id = ? LIMIT 1',
      [conversationId, currentUserId],
    );

    if (members.length === 0) {
      return res.status(403).json({ success: false, message: 'Không có quyền truy cập cuộc trò chuyện này' });
    }

    const [messages] = await pool.query(
      `SELECT m.*, u.name AS sender_name, u.avatar_url AS sender_avatar
       FROM messages m
       JOIN users u ON u.id = m.sender_id
       WHERE m.conversation_id = ?
       ORDER BY m.created_at ASC`,
      [conversationId],
    );

    return res.json({
      success: true,
      message: 'Messages loaded',
      data: messages.map((row) => normalizeMessage(row, currentUserId)),
    });
  } catch (error) {
    console.error('getMessages error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function sendMessage(req, res) {
  try {
    const currentUserId = Number(req.user?.sub);
    const { conversation_id, recipient_id, message, image_url } = req.body;
    const textMessage = String(message || '').trim();
    const imageUrl = String(image_url || '').trim() || null;

    if (!conversation_id && !recipient_id) {
      return res.status(400).json({ success: false, message: 'conversation_id hoặc recipient_id bắt buộc' });
    }

    let conversationId = Number(conversation_id || 0);
    let recipientId = Number(recipient_id || 0);

    if (recipientId === currentUserId) {
      return res.status(400).json({ success: false, message: 'Không thể gửi tin nhắn cho chính bạn' });
    }

    if (!conversationId) {
      if (!Number.isInteger(recipientId) || recipientId <= 0) {
        return res.status(400).json({ success: false, message: 'recipient_id không hợp lệ' });
      }

      const [users] = await pool.query('SELECT id FROM users WHERE id = ? LIMIT 1', [recipientId]);
      if (users.length === 0) {
        return res.status(404).json({ success: false, message: 'Người nhận không tồn tại' });
      }

      const [createdConversation] = await pool.query('INSERT INTO conversations () VALUES ()');
      conversationId = createdConversation.insertId;
      await pool.query(
        'INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?), (?, ?)',
        [conversationId, currentUserId, conversationId, recipientId],
      );
    } else {
      const [members] = await pool.query(
        'SELECT id FROM conversation_members WHERE conversation_id = ? AND user_id = ? LIMIT 1',
        [conversationId, currentUserId],
      );
      if (members.length === 0) {
        return res.status(403).json({ success: false, message: 'Không thể gửi tin nhắn vào cuộc trò chuyện này' });
      }

      if (!recipientId) {
        const [partner] = await pool.query(
          'SELECT user_id FROM conversation_members WHERE conversation_id = ? AND user_id <> ? LIMIT 1',
          [conversationId, currentUserId],
        );
        recipientId = partner.length > 0 ? partner[0].user_id : 0;
      }
    }

    if (!textMessage && !imageUrl) {
      return res.status(400).json({ success: false, message: 'Tin nhắn trống' });
    }

    const [result] = await pool.query(
      'INSERT INTO messages (conversation_id, sender_id, message, image_url) VALUES (?, ?, ?, ?)',
      [conversationId, currentUserId, textMessage || null, imageUrl],
    );

    const [savedRows] = await pool.query('SELECT * FROM messages WHERE id = ? LIMIT 1', [result.insertId]);
    const savedMessage = savedRows[0];

    const messagePayload = normalizeMessage(savedMessage, currentUserId);
    const io = require('../utils/socket').getIO();
    io.to(`conversation_${conversationId}`).emit('new_message', {
      conversation_id: conversationId,
      message: messagePayload,
    });

    if (recipientId && recipientId !== currentUserId) {
      io.to(`user_${recipientId}`).emit('new_conversation', {
        conversation_id: conversationId,
        sender_id: currentUserId,
      });
    }

    return res.status(201).json({
      success: true,
      message: 'Tin nhắn đã gửi',
      data: {
        conversation_id: conversationId,
        message: messagePayload,
      },
    });
  } catch (error) {
    console.error('sendMessage error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function markMessagesSeen(req, res) {
  try {
    const currentUserId = Number(req.user?.sub);
    const conversationId = Number(req.body.conversation_id);

    if (!Number.isInteger(conversationId) || conversationId <= 0) {
      return res.status(400).json({ success: false, message: 'conversation_id không hợp lệ' });
    }

    const [members] = await pool.query(
      'SELECT id FROM conversation_members WHERE conversation_id = ? AND user_id = ? LIMIT 1',
      [conversationId, currentUserId],
    );
    if (members.length === 0) {
      return res.status(403).json({ success: false, message: 'Không có quyền truy cập cuộc trò chuyện này' });
    }

    await pool.query(
      'UPDATE messages SET is_seen = 1 WHERE conversation_id = ? AND sender_id <> ? AND is_seen = 0',
      [conversationId, currentUserId],
    );

    const io = require('../utils/socket').getIO();
    io.to(`conversation_${conversationId}`).emit('messages_seen', { conversation_id: conversationId, user_id: currentUserId });

    return res.json({ success: true, message: 'Đã đánh dấu đã xem' });
  } catch (error) {
    console.error('markMessagesSeen error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function uploadMessageImage(req, res) {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'Chưa có ảnh để tải lên' });
    }

    const imageUrl = `${req.protocol}://${req.headers.host}/uploads/chat/${req.file.filename}`;
    return res.json({ success: true, message: 'Ảnh đã tải lên', data: { image_url: imageUrl } });
  } catch (error) {
    console.error('uploadMessageImage error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function searchUsers(req, res) {
  try {
    const currentUserId = Number(req.user?.sub);
    const query = String(req.query.q || '').trim();

    if (query.length < 2) {
      return res.json({ success: true, message: 'OK', data: [] });
    }

    const searchPattern = `%${query}%`;
    const [rows] = await pool.query(
      `SELECT id, name, avatar_url
       FROM users
       WHERE id <> ? AND (name LIKE ? OR email LIKE ?)
       ORDER BY name ASC
       LIMIT 20`,
      [currentUserId, searchPattern, searchPattern],
    );

    return res.json({ success: true, message: 'Tìm thấy người dùng', data: rows });
  } catch (error) {
    console.error('searchUsers error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

module.exports = {
  getConversations,
  getMessages,
  sendMessage,
  markMessagesSeen,
  uploadMessageImage,
  searchUsers,
};
