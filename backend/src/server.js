require('dotenv').config();

const http = require('http');
const app = require('./app');
const { init } = require('./utils/socket');
const { testConnection } = require('./config/db');
const { startCronJobs, duplicateRepeatingBudgets } = require('./services/cronService');

const PORT = process.env.PORT || 3000;

async function startServer() {
  try {
    await testConnection();

    const server = http.createServer(app);
    init(server);

    // Bắt đầu lập lịch Cronjob
    startCronJobs();
    
    // Khởi chạy quét ngay 1 lần lúc bật server phòng hờ server bị tắt qua mùng 1
    duplicateRepeatingBudgets();

    server.listen(PORT, '0.0.0.0', () => {
      console.log(`Server running on port ${PORT}`);
    });
  } catch (error) {
    console.error('Failed to start server:', error.message);
    process.exit(1);
  }
}

startServer();

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception thrown:', err);
});
