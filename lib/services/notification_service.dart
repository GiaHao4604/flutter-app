import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_notification');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
    
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
        
    _initialized = true;
  }

  Future<void> showWarningNotification(
      String categoryName, int actual, int limit) async {
    await init();

    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final prefs = await SharedPreferences.getInstance();
    
    // Check if we already notified for this category today
    final notifKey = 'notified_${categoryName}_$todayKey';
    if (prefs.getBool(notifKey) == true) {
      return; // Already notified today
    }

    final formatVnd = NumberFormat.decimalPattern('vi_VN');

    final String title = '⚠️ Cảnh báo chi tiêu: $categoryName';
    final String body = 'Hôm nay bạn đã tiêu ${formatVnd.format(actual)} đ, lố mức trung bình ${formatVnd.format(limit)} đ/ngày.';

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'budget_warnings',
      'Cảnh báo ngân sách',
      channelDescription: 'Thông báo khi chi tiêu vượt hạn mức',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
      enableVibration: false,
    );
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformChannelSpecifics,
    );

    await prefs.setBool(notifKey, true);
  }

  Future<void> showSystemNotification(String title, String body) async {
    await init();

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'system_notifications',
      'Hộp thư hệ thống',
      channelDescription: 'Thông báo từ hệ thống (vi phạm, cảnh báo,...)',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
      enableVibration: true,
    );
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  Future<void> showThresholdNotification(
      String categoryName, int percentThreshold, int spent, int limit) async {
    await init();

    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final prefs = await SharedPreferences.getInstance();
    
    // Check if we already notified for this category and threshold today
    final notifKey = 'notified_${percentThreshold}_${categoryName}_$todayKey';
    if (prefs.getBool(notifKey) == true) {
      return; // Already notified today
    }

    final formatVnd = NumberFormat.decimalPattern('vi_VN');
    
    String title = '';
    String body = '';

    if (percentThreshold >= 100) {
      title = '🚨 Ngân sách $categoryName đã VƯỢT GIỚI HẠN!';
      body = 'Bạn đã chi ${formatVnd.format(spent)} đ / ${formatVnd.format(limit)} đ. Hãy cẩn thận nhé!';
    } else {
      title = '⚠️ Ngân sách $categoryName sắp hết!';
      body = 'Bạn đã dùng hết $percentThreshold% (${formatVnd.format(spent)} đ / ${formatVnd.format(limit)} đ).';
    }

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'budget_threshold_warnings',
      'Cảnh báo ngưỡng ngân sách',
      channelDescription: 'Thông báo khi chi tiêu sắp hoặc đã vượt hạn mức tổng',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
      ),
      enableVibration: true,
      playSound: true,
    );
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      platformChannelSpecifics,
    );

    await prefs.setBool(notifKey, true);
  }

  Future<void> scheduleDailyNotifications() async {
    await init();

    // 12:00 PM Notification
    await _scheduleDailyNotification(
      id: 1001,
      hour: 12,
      minute: 0,
      title: 'An tâm chi tiêu',
      body: 'Đặt hạn mức theo tuần và giao dịch cùng MoneyLife, giúp bạn kiểm soát chi tiêu hiệu quả hơn. Khám phá ngay',
    );

    // 17:00 PM Notification
    await _scheduleDailyNotification(
      id: 1002,
      hour: 17,
      minute: 0,
      title: 'An tâm chi tiêu',
      body: 'Đặt hạn mức theo tuần và giao dịch cùng MoneyLife, giúp bạn kiểm soát chi tiêu hiệu quả hơn. Khám phá ngay',
    );

    // --- ĐOẠN CODE TEST: Bắn thông báo sau 10 giây để kiểm tra ---
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    await _flutterLocalNotificationsPlugin.zonedSchedule(
      9999,
      '[TEST] An tâm chi tiêu',
      'Đây là thông báo test tự động hiện sau 10 giây. Tính năng 12h và 17h đã hoạt động tốt!',
      now.add(const Duration(seconds: 10)),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel',
          'Kênh Test',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
    // -------------------------------------------------------------
  }

  Future<void> _scheduleDailyNotification({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    tz.TZDateTime scheduledDate = _nextInstanceOfTime(hour, minute);

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_tips',
          'Mẹo chi tiêu hàng ngày',
          channelDescription: 'Thông báo nhắc nhở quản lý chi tiêu lúc 12h và 17h',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
