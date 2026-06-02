import 'dart:async';

class DeviceService {
  // Removed dependency on connectivity_plus and battery_plus.
  // Provide lightweight placeholder streams so other code compiles.

  // Stream wifi — yields empty list (no connectivity info).
  Stream<List<dynamic>> get connectivityStream async* {
    while (true) {
      yield <dynamic>[];
      await Future.delayed(const Duration(seconds: 60));
    }
  }

  // Stream pin — always returns 100.
  Stream<int> batteryStream() async* {
    while (true) {
      yield 100;
      await Future.delayed(const Duration(seconds: 60));
    }
  }

  // Stream thời gian — yields minute-granularity timestamps.
  Stream<String> timeStream() async* {
    while (true) {
      final now = DateTime.now();
      yield '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      await Future.delayed(const Duration(seconds: 60));
    }
  }
}
