let io;

function init(server) {
  const { Server } = require('socket.io');
  io = new Server(server, {
    cors: { origin: '*' },
  });

  io.on('connection', (socket) => {
    console.log('Socket connected', socket.id);
    socket.on('join-room', (room) => {
      socket.join(room);
    });
    socket.on('leave-room', (room) => {
      socket.leave(room);
    });
  });
}

function getIO() {
  if (!io) throw new Error('Socket.io not initialized');
  return io;
}

module.exports = { init, getIO };
