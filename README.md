# Mạng Xã Hội Tích Hợp Thống Kê Chi Tiêu

## 📖 Giới thiệu chung
Đây là một ứng dụng di động kết hợp độc đáo giữa **Mạng xã hội** tích hợp **Thống kê chi tiêu cá nhân**. Người dùng không chỉ ghi chép lại các khoản chi tiêu, lập ngân sách để kiểm soát tài chính, mà còn có thể chia sẻ cuộc sống, nhắn tin trò chuyện với bạn bè ngay trong cùng một nền tảng.

## 🚀 Các tính năng nổi bật
* **💸 Quản lý Ngân Sách:** Theo dõi chi tiết thu/chi, tự động phân loại giao dịch và thiết lập hạn mức khống chế chi tiêu (Budget).
* **📊 Thống Kê & Báo Cáo Tài Chính:** Hiển thị biểu đồ (Pie Chart) trực quan, theo dõi sát sao tình hình thu nhập, chi tiêu và lịch sử ngân sách.
* **🌐 Mạng xã hội (News Feed):** Đăng dòng trạng thái, đính kèm hình ảnh, tương tác trên bài viết. Chế độ riêng tư cho phép ẩn số tiền giao dịch khi đăng tải.
* **💬 Nhắn tin Thời gian thực (Real-time Chat):** Chat tốc độ cao nhờ công nghệ WebSocket. Hỗ trợ gửi ảnh, nhấn giữ tin nhắn để mở menu tương tác (trả lời, thu hồi tin nhắn).
* **📅 Lịch trình cá nhân:** Quản lý giao dịch theo ngày trên giao diện lịch, dễ dàng theo dõi dòng tiền.
* **🛡️ Hệ thống Quản trị (Admin Panel):** Phân quyền người dùng, khóa tài khoản, xử lý và xóa các bài đăng vi phạm.

## 🛠 Công nghệ sử dụng
* **Frontend (Mobile App):** Flutter / Dart
* **Backend (API Server):** Node.js, Express.js
* **Giao tiếp thời gian thực:** Socket.IO
* **Cơ sở dữ liệu:** MySQL
* **Bảo mật:** JSON Web Tokens (JWT)

## ⚙️ Hướng dẫn cài đặt & Chạy thử

**1. Khởi chạy Backend Server:**
```bash
cd backend
npm install
npm run dev
```

**2. Khởi chạy Frontend (Flutter App):**
```bash
flutter run
```
