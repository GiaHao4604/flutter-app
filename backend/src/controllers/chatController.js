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
  let sharedPost = null;
  if (row.shared_post_id) {
    sharedPost = {
      id: row.shared_post_id,
      image_url: row.post_image_url || null,
      caption: row.post_caption || null,
      author_id: row.post_author_id || null,
      author_name: row.post_author_name || null,
      author_avatar: row.post_author_avatar || null,
      created_at: row.post_created_at || null,
    };
  }
  let replyTo = null;
  if (row.reply_to_id) {
    replyTo = {
      id: row.reply_to_id,
      text: row.reply_is_deleted ? 'Tin nhắn đã thu hồi' : (row.reply_to_text || (row.reply_to_image ? '[Hình ảnh]' : (row.reply_shared_post_id ? '[Bài viết]' : ''))),
      sender_name: row.reply_sender_name || 'Người dùng',
    };
  }

  return {
    id: row.id,
    conversation_id: row.conversation_id,
    sender_id: row.sender_id,
    text: row.is_deleted ? null : (row.message || null),
    image_url: row.is_deleted ? null : (row.image_url || null),
    shared_post: row.is_deleted ? null : sharedPost,
    is_seen: !!row.is_seen,
    created_at: row.created_at,
    is_me: row.sender_id === currentUserId,
    status: row.sender_id === currentUserId ? (row.is_seen ? 'seen' : 'delivered') : null,
    is_deleted: !!row.is_deleted,
    reply_to: replyTo,
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
      `SELECT m.*,
              u.name AS sender_name, u.avatar_url AS sender_avatar,
              p.image_url AS post_image_url,
              p.caption AS post_caption,
              p.user_id AS post_author_id,
              p.created_at AS post_created_at,
              pa.name AS post_author_name,
              pa.avatar_url AS post_author_avatar,
              r.message AS reply_to_text,
              r.image_url AS reply_to_image,
              r.shared_post_id AS reply_shared_post_id,
              r.is_deleted AS reply_is_deleted,
              ru.name AS reply_sender_name
       FROM messages m
       JOIN users u ON u.id = m.sender_id
       LEFT JOIN posts p ON p.id = m.shared_post_id
       LEFT JOIN users pa ON pa.id = p.user_id
       LEFT JOIN messages r ON r.id = m.reply_to_id
       LEFT JOIN users ru ON ru.id = r.sender_id
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
    const { conversation_id, recipient_id, message, image_url, shared_post_id, reply_to_id } = req.body;
    const textMessage = String(message || '').trim();
    const imageUrl = String(image_url || '').trim() || null;
    const sharedPostId = shared_post_id ? Number(shared_post_id) : null;
    const replyToId = reply_to_id ? Number(reply_to_id) : null;

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

      // Kiểm tra nếu đã có cuộc trò chuyện 1-1 với recipient_id
      const [existingConv] = await pool.query(
        `SELECT cm1.conversation_id FROM conversation_members cm1
         JOIN conversation_members cm2 ON cm2.conversation_id = cm1.conversation_id
         WHERE cm1.user_id = ? AND cm2.user_id = ?
         LIMIT 1`,
        [currentUserId, recipientId]
      );

      if (existingConv.length > 0) {
        conversationId = existingConv[0].conversation_id;
      } else {
        const [createdConversation] = await pool.query('INSERT INTO conversations () VALUES ()');
        conversationId = createdConversation.insertId;
        await pool.query(
          'INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?), (?, ?)',
          [conversationId, currentUserId, conversationId, recipientId],
        );
      }
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

    if (!textMessage && !imageUrl && !sharedPostId) {
      return res.status(400).json({ success: false, message: 'Tin nhắn trống' });
    }

    const [result] = await pool.query(
      'INSERT INTO messages (conversation_id, sender_id, message, image_url, shared_post_id, reply_to_id) VALUES (?, ?, ?, ?, ?, ?)',
      [conversationId, currentUserId, textMessage || null, imageUrl, sharedPostId, replyToId],
    );

    const [savedRows] = await pool.query(
      `SELECT m.*,
              p.image_url AS post_image_url,
              p.caption AS post_caption,
              p.user_id AS post_author_id,
              p.created_at AS post_created_at,
              pa.name AS post_author_name,
              pa.avatar_url AS post_author_avatar,
              r.message AS reply_to_text,
              r.image_url AS reply_to_image,
              r.shared_post_id AS reply_shared_post_id,
              r.is_deleted AS reply_is_deleted,
              ru.name AS reply_sender_name
       FROM messages m
       LEFT JOIN posts p ON p.id = m.shared_post_id
       LEFT JOIN users pa ON pa.id = p.user_id
       LEFT JOIN messages r ON r.id = m.reply_to_id
       LEFT JOIN users ru ON ru.id = r.sender_id
       WHERE m.id = ? LIMIT 1`,
      [result.insertId]
    );
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

    return res.json({ success: true, message: 'Message sent', data: messagePayload });
  } catch (error) {
    console.error('sendMessage error:', error);
    return res.status(500).json({ success: false, message: 'Internal server error' });
  }
}

async function deleteMessage(req, res) {
  try {
    const currentUserId = Number(req.user?.sub);
    const messageId = Number(req.params.messageId);

    if (!Number.isInteger(messageId) || messageId <= 0) {
      return res.status(400).json({ success: false, message: 'Invalid message ID' });
    }

    const [msgs] = await pool.query('SELECT conversation_id, sender_id FROM messages WHERE id = ? LIMIT 1', [messageId]);
    if (msgs.length === 0) {
      return res.status(404).json({ success: false, message: 'Message not found' });
    }

    const msg = msgs[0];
    if (msg.sender_id !== currentUserId) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền thu hồi tin nhắn này' });
    }

    await pool.query(
      'UPDATE messages SET is_deleted = 1, message = NULL, image_url = NULL, shared_post_id = NULL WHERE id = ?',
      [messageId]
    );

    const io = require('../utils/socket').getIO();
    io.to(`conversation_${msg.conversation_id}`).emit('message_deleted', {
      conversation_id: msg.conversation_id,
      message_id: messageId,
    });

    return res.json({ success: true, message: 'Message deleted successfully' });
  } catch (error) {
    console.error('deleteMessage error:', error);
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
  deleteMessage,
};
