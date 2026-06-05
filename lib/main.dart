import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/screens/home.dart';
import 'package:flutter_application_1/screens/login.dart';
import 'package:flutter_application_1/screens/register.dart';
import 'package:flutter_application_1/screens/admin/admin_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Làm trong suốt thanh Status Bar (pin, sóng, đồng hồ)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
const MainApp({super.key});

@override
Widget build(BuildContext context) {
return MaterialApp(
debugShowCheckedModeBanner: false,


  title: 'Expense Social App',

  themeMode: ThemeMode.dark,

  theme: ThemeData(
    useMaterial3: true,

    brightness: Brightness.dark,

    scaffoldBackgroundColor: const Color(0xFF080808),

    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF7B61FF),
      secondary: Color(0xFF5DE2E7),
      surface: Color(0xFF121212),
    ),
  ),

  initialRoute: '/login',

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
