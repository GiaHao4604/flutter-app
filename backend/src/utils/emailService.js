const nodemailer = require('nodemailer');

/**
 * Cấu hình transporter với thông tin từ biến môi trường
 */
const transporter = nodemailer.createTransport({
  service: 'gmail', // Hoặc có thể cấu hình host: 'smtp.gmail.com', port: 465, secure: true
  auth: {
    user: process.env.SMTP_EMAIL,     // Email Gmail của bạn (vd: your_email@gmail.com)
    pass: process.env.SMTP_PASSWORD,  // Mật khẩu ứng dụng (App Password) sinh từ tài khoản Google
  },
});

/**
 * Hàm gửi email chứa mã OTP
 * @param {string} toEmail - Email người nhận
 * @param {string} otpCode - Mã OTP gồm 6 chữ số
 */
async function sendOtpEmail(toEmail, otpCode) {
  // Nếu chưa cấu hình email trong .env, ném ra lỗi để thông báo
  if (!process.env.SMTP_EMAIL || !process.env.SMTP_PASSWORD) {
    console.warn('⚠️ Cảnh báo: Chưa cấu hình SMTP_EMAIL và SMTP_PASSWORD trong file .env');
    return false;
  }

  const mailOptions = {
    from: `"MoneyLife" <${process.env.SMTP_EMAIL}>`,
    to: toEmail,
    subject: 'Mã xác nhận khôi phục mật khẩu (OTP)',
    html: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #ddd; border-radius: 10px;">
        <h2 style="color: #4A46DE; text-align: center;">Khôi phục mật khẩu</h2>
        <p>Xin chào,</p>
        <p>Bạn đã yêu cầu đặt lại mật khẩu cho tài khoản tại ứng dụng <b>MoneyLife</b>.</p>
        <p>Mã xác nhận (OTP) của bạn là:</p>
        <div style="text-align: center; margin: 24px 0;">
          <span style="font-size: 28px; font-weight: bold; letter-spacing: 4px; color: #333; background: #F5F5F8; padding: 12px 24px; border-radius: 8px;">
            ${otpCode}
          </span>
        </div>
        <p style="color: #61636F; font-size: 14px;">Mã này sẽ hết hạn trong vòng 10 phút. Nếu bạn không yêu cầu thay đổi mật khẩu, vui lòng bỏ qua email này.</p>
        <hr style="border: none; border-top: 1px solid #eee; margin: 24px 0;" />
        <p style="color: #999; font-size: 12px; text-align: center;">MoneyLife - Đồng hành cùng con</p>
      </div>
    `,
  };

  try {
    const info = await transporter.sendMail(mailOptions);
    console.log(`[EmailService] Đã gửi OTP đến ${toEmail}: ${info.messageId}`);
    return true;
  } catch (error) {
    console.error('[EmailService] Lỗi khi gửi email:', error);
    return false;
  }
}

module.exports = {
  sendOtpEmail,
};
