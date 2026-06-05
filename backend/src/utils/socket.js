const jwt = require('jsonwebtoken');

let io;
const onlineUsers = new Map();

function init(server) {
  const { Server } = require('socket.io');
  io = new Server(server, {
    cors: { origin: '*' },
  });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token || socket.handshake.headers?.authorization?.split(' ')[1];
    if (!token) {
      return next(new Error('Unauthorized: missing token'));
    }
    try {
      const payload = jwt.verify(token, process.env.JWT_SECRET);
      socket.user = payload;
      return next();
    } catch (error) {
      return next(new Error('Unauthorized: invalid token'));
    }
  });

  io.on('connection', (socket) => {
    const userId = Number(socket.user?.sub);
    if (Number.isInteger(userId) && userId > 0) {
      const current = onlineUsers.get(userId) ?? new Set();
      current.add(socket.id);
      onlineUsers.set(userId, current);
      socket.join(`user_${userId}`);
      io.emit('user_presence', { userId, online: true });
    }

    socket.on('join_conversation', (conversationId) => {
      if (conversationId != null) {
        socket.join(`conversation_${conversationId}`);
      }
    });

    socket.on('leave_conversation', (conversationId) => {
      if (conversationId != null) {
        socket.leave(`conversation_${conversationId}`);
      }
    });

    socket.on('typing', (payload) => {
      const conversationId = payload?.conversation_id;
      const isTyping = payload?.is_typing === true;
      if (conversationId != null) {
        socket.to(`conversation_${conversationId}`).emit('typing', {
          conversation_id: conversationId,
          is_typing: isTyping,
        });
      }
    });

    socket.on('disconnect', () => {
      if (Number.isInteger(userId) && userId > 0) {
        const sockets = onlineUsers.get(userId);
        if (sockets != null) {
          sockets.delete(socket.id);
          if (sockets.size === 0) {
            onlineUsers.delete(userId);
            io.emit('user_presence', { userId, online: false });
          }
        }
      }
    });
  });
}

function getIO() {
  if (!io) throw new Error('Socket.io not initialized');
  return io;
}

module.exports = { init, getIO };
