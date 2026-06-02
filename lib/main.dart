import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/home.dart';
import 'package:flutter_application_1/screens/login.dart';
import 'package:flutter_application_1/screens/register.dart';

void main() async {
WidgetsFlutterBinding.ensureInitialized();

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
    '/login': (context) => const AppWrapper(
          child: Login(),
        ),

    '/register': (context) => const AppWrapper(
          child: Register(),
        ),

    '/home': (context) => const HomeScreen(),
  },
);


}
}

class AppWrapper extends StatelessWidget {
final Widget child;

const AppWrapper({
super.key,
required this.child,
});

@override
Widget build(BuildContext context) {
return Scaffold(
body: Container(
decoration: const BoxDecoration(
gradient: LinearGradient(
begin: Alignment.topLeft,
end: Alignment.bottomRight,
colors: [
Color(0xFF5C4DE1),
Color(0xFF7A3CF0),
],
),
),


    child: SafeArea(
      child: child,
    ),
  ),
);


}
}
