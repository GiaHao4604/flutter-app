import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/screens/home.dart';
import 'package:flutter_application_1/screens/login.dart';
import 'package:flutter_application_1/screens/register.dart';
import 'package:flutter_application_1/screens/admin/admin_home.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Khởi tạo timezone (hardcode Asia/Ho_Chi_Minh cho ứng dụng Việt Nam)
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));

  // Khởi tạo dịch vụ thông báo cục bộ và lên lịch tự động
  try {
    final notificationService = NotificationService();
    await notificationService.init();
    await notificationService.scheduleDailyNotifications();
  } catch (_) {
    // Bỏ qua nếu có lỗi, không crash app
  }

  // Làm trong suốt thanh Status Bar (pin, sóng, đồng hồ)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  final sessionService = AuthSessionService();
  final token = await sessionService.getToken();
  final role = await sessionService.getUserRole() ?? 'user';

  String initialRoute = '/login';
  if (token != null && token.trim().isNotEmpty) {
    if (role == 'admin' || role == 'director_admin') {
      initialRoute = '/admin_home';
    } else {
      initialRoute = '/home';
    }
  }

  runApp(MainApp(initialRoute: initialRoute));
}

class MainApp extends StatelessWidget {
  final String initialRoute;
  const MainApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'MoneyLife',
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000), // Đen nguyên bản
        colorScheme: const ColorScheme.dark(
          primary: Colors.white, // Nổi bật là Trắng
          secondary: Colors.grey, // Phụ là Xám
          surface: Color(0xFF121212),
          onPrimary: Colors.black, // Chữ trên nền Trắng là Đen
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ),
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const Login(),
        '/register': (context) => const Register(),
        '/home': (context) => const HomeScreen(),
        '/admin_home': (context) => const AdminHome(),
      },
    );
  }
}

// AppWrapper removed
