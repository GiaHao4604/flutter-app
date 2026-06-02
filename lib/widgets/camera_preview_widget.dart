import 'dart:convert';
import 'dart:io';
// dart:math removed (not needed)
import '../screens/home2.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_application_1/services/auth_session_service.dart';
import 'package:flutter_application_1/services/calendar_api_service.dart';
import 'package:flutter_application_1/services/calendar_refresh_notifier.dart';
import 'package:flutter_application_1/services/calendar_storage_service.dart';

class CameraPreviewWidget extends StatefulWidget {
  const CameraPreviewWidget({
    super.key,
    required this.height,
  });

  final double height;

  @override
  State<CameraPreviewWidget> createState() =>
      CameraPreviewWidgetState();
}

class CameraPreviewWidgetState
    extends State<CameraPreviewWidget> {
  CameraController? _controller;

  bool _isReady = false;

  List<CameraDescription> _cameras = [];

  int _currentCameraIndex = 0;

  /// FLASH
  FlashMode _flashMode = FlashMode.off;

  /// ZOOM
  double _currentZoom = 1.0;

  double _baseZoom = 1.0;

  double _minZoom = 0.5;

  double _maxZoom = 5.0;

  /// PREVIEW IMAGE
  XFile? _capturedImage;

  DateTime? _capturedAt;

  bool _isPosting = false;

  // _isGalleryImage removed (not read anywhere)

  // base url kept for reference; not used directly in this widget
  final AuthSessionService _sessionService = AuthSessionService();
  final CalendarApiService _apiService = CalendarApiService();
  final CalendarStorageService _storageService = CalendarStorageService();

  @override
  void initState() {
    super.initState();

    initCamera();
  }

  Future<void> initCamera() async {
    _cameras = await availableCameras();

    if (_cameras.isEmpty) return;

    _controller = CameraController(
      _cameras[_currentCameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _controller!.initialize();

    /// FLASH
    await _controller!.setFlashMode(_flashMode);

    /// ZOOM RANGE
    _minZoom = await _controller!.getMinZoomLevel();

    _maxZoom = await _controller!.getMaxZoomLevel();

    if (_minZoom < 0.5) {
      _minZoom = 0.5;
    }

    if (_maxZoom > 5.0) {
      _maxZoom = 5.0;
    }

    await _controller!.setZoomLevel(_currentZoom);

    if (!mounted) return;

    setState(() {
      _isReady = true;
    });
  }

  /// TAKE PICTURE
  Future<void> takePicture() async {
  if (_controller == null) return;

  try {
    final image = await _controller!.takePicture();

    /// CAMERA TRƯỚC => FLIP ẢNH
    final isFront =
        _cameras.isNotEmpty &&
        _cameras[_currentCameraIndex]
                .lensDirection ==
            CameraLensDirection.front;

    if (isFront) {
      final bytes =
          await File(image.path).readAsBytes();

      final original = img.decodeImage(bytes);

      if (original != null) {
        final flipped =
            img.flipHorizontal(original);

        final flippedBytes =
            img.encodeJpg(flipped);

        await File(image.path)
            .writeAsBytes(flippedBytes);
      }
    }

    if (!mounted) return;

    // Set captured image so preview shows while in Home2
    final capturedAt = DateTime.now();
    setState(() {
      _capturedImage = image;
      _capturedAt = capturedAt;
    });

    // Navigate to preview and wait until user returns; then clear preview
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Home2(
          imageFile: File(image.path),
          capturedAt: capturedAt,
        ),
      ),
    );

    if (!mounted) return;

    // When returning from Home2 (e.g., user pressed X), clear preview and show camera
    setState(() {
      _capturedImage = null;
      _capturedAt = null;
    });
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Lỗi chụp ảnh: $e',
        ),
      ),
    );
  }
}
  Future<void> pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (image == null || !mounted) return;

      setState(() {
        _capturedImage = image;
        _capturedAt = File(image.path).statSync().modified;
      });

      // Navigate to Home2 preview and wait; when returned clear the preview
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Home2(
            imageFile: File(image.path),
            capturedAt: _capturedAt,
          ),
        ),
      );

      if (!mounted) return;

      setState(() {
        _capturedImage = null;
        _capturedAt = null;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể mở thư viện ảnh: $e'),
        ),
      );
    }
  }

  Future<void> uploadPost() async {
    if (_capturedImage == null) return;

    try {
      setState(() {
        _isPosting = true;
      });

      var uri = Uri.parse(
        'http://192.168.1.240:3000/api/posts/upload',
      );

      var request = http.MultipartRequest(
        'POST',
        uri,
      );

      /// FILE ẢNH
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          _capturedImage!.path,
           contentType: MediaType('image', 'jpeg'),
        ),
      );

      /// DATA
      request.fields['device_id'] = 'redmi_a5';

      request.fields['caption'] = 'hello';

      request.fields['camera_type'] = 'front';

      /// GỬI REQUEST
      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      debugPrint('uploadPost status: ${response.statusCode}');
      debugPrint(responseData);

      if (response.statusCode == 200) {
        await _saveCalendarPost();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đăng tin....'),
          ),
        );

        setState(() {
          _capturedImage = null;
          _capturedAt = null;
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(responseData),
          ),
        );
      }
    } catch (e) {
      debugPrint('uploadPost error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
          ),
        );
      }
    } finally {
      setState(() {
        _isPosting = false;
      });
    }
  }

  Future<void> _saveCalendarPost() async {
    final now = DateTime.now();
    final effectiveNow = _capturedAt ?? now;
    final token = await _sessionService.getToken();

    if (token != null && token.trim().isNotEmpty) {
      final clientLocalId = effectiveNow.millisecondsSinceEpoch.toString();
      final remote = await _apiService.createEntry(
        token: token,
        imageFile: File(_capturedImage!.path),
        amount: 0,
        isExpense: true,
        dateKey: _dateKey(effectiveNow),
        date: effectiveNow.toUtc().toIso8601String(),
        clientLocalId: clientLocalId,
        note: '',
      );

      if (remote.success && remote.data != null && remote.data is Map<String, dynamic>) {
        await _saveCalendarPostLocally(effectiveNow, serverData: Map<String, dynamic>.from(remote.data!));
        return;
      }
    }

    await _saveCalendarPostLocally(effectiveNow);
  }

  Future<void> _saveCalendarPostLocally(DateTime now, {Map<String, dynamic>? serverData}) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = await _storageService.currentCalendarKey();
    final raw = prefs.getString(storageKey);
    final posts = <Map<String, dynamic>>[];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              posts.add(Map<String, dynamic>.from(item));
            }
          }
        }
      } catch (_) {}
    }

    final storedImagePath = await _persistCalendarImage(File(_capturedImage!.path));
    final localId = now.millisecondsSinceEpoch.toString();
    final entry = <String, dynamic>{
      'id': serverData != null && serverData['id'] != null ? serverData['id'].toString() : localId,
      'localId': localId,
      'imagePath': storedImagePath,
      'localDateTime': now.toLocal().toIso8601String(),
      // store in UTC ISO format to avoid local timezone parsing issues
      'date': serverData != null && serverData['entryTs'] != null
          ? DateTime.tryParse(serverData['entryTs'].toString())?.toUtc().toIso8601String() ?? now.toUtc().toIso8601String()
          : now.toUtc().toIso8601String(),
      'dateKey': serverData != null && serverData['dateKey'] != null
          ? serverData['dateKey'].toString()
          : _dateKey(now),
      'amount': serverData != null && serverData['amount'] != null ? int.tryParse(serverData['amount'].toString()) ?? 0 : 0,
      'isExpense': serverData != null && serverData['isExpense'] != null ? serverData['isExpense'] == true : true,
      'note': serverData != null && serverData['note'] != null ? serverData['note'].toString() : '',
      'imageUrl': serverData != null && serverData['imageUrl'] != null ? serverData['imageUrl'].toString() : null,
      'entryTs': serverData != null && serverData['entryTs'] != null ? serverData['entryTs'].toString() : null,
    };

    // If server returned clientLocalId, try to replace existing local record
    final clientLocalFromServer = serverData != null ? (serverData['clientLocalId'] ?? serverData['localId'])?.toString() : null;
    if (clientLocalFromServer != null && clientLocalFromServer.isNotEmpty) {
      final idx = posts.indexWhere((p) => p['localId']?.toString() == clientLocalFromServer);
      if (idx != -1) {
        posts[idx] = entry;
      } else {
        posts.add(entry);
      }
    } else {
      posts.add(entry);
    }

    await prefs.setString(storageKey, jsonEncode(posts));
    calendarRefreshNotifier.value++;
  }

  Future<String> _persistCalendarImage(File sourceFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final calendarDir = Directory(p.join(directory.path, 'calendar_posts'));
    if (!calendarDir.existsSync()) {
      calendarDir.createSync(recursive: true);
    }

    final safeName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourceFile.path)}';
    final targetPath = p.join(calendarDir.path, safeName);
    final storedFile = await sourceFile.copy(targetPath);
    return storedFile.path;
  }

  /// XÓA PREVIEW
  void clearPreview() {
    setState(() {
      _capturedImage = null;
      _capturedAt = null;
    });
  }

  /// SWITCH CAMERA
  Future<void> switchCamera() async {
    if (_cameras.isEmpty) return;

    _currentCameraIndex =
        (_currentCameraIndex + 1) % _cameras.length;

    try {
      setState(() {
        _isReady = false;
      });

      await _controller?.dispose();

      _controller = CameraController(
        _cameras[_currentCameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      /// FLASH
      await _controller!.setFlashMode(_flashMode);

      /// ZOOM
      _minZoom = await _controller!.getMinZoomLevel();

      _maxZoom = await _controller!.getMaxZoomLevel();

      if (_minZoom < 0.5) {
        _minZoom = 0.5;
      }

      if (_maxZoom > 5.0) {
        _maxZoom = 5.0;
      }

      _currentZoom = 1.0;

      await _controller!.setZoomLevel(_currentZoom);

      if (!mounted) return;

      setState(() {
        _isReady = true;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể đổi camera: $e'),
        ),
      );
    }
  }

  /// FLASH
  Future<void> toggleFlash() async {
    if (_controller == null) return;

    try {
      if (_flashMode == FlashMode.off) {
        _flashMode = FlashMode.torch;
      } else {
        _flashMode = FlashMode.off;
      }

      await _controller!.setFlashMode(_flashMode);

      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flash không khả dụng'),
          ),
        );
      }
    }
  }

  /// ZOOM
  Future<void> _handleZoom(double scale) async {
    if (_controller == null) return;

    double zoom = (_baseZoom * scale)
        .clamp(_minZoom, _maxZoom);

    await _controller!.setZoomLevel(zoom);

    setState(() {
      _currentZoom = zoom;
    });
  }

  // removed unused helpers to reduce analyzer warnings

  String _dateKey(DateTime dateTime) {
    final local = dateTime.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// QR
  Future<void> openQRScanner() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const QRScannerScreen(),
      ),
    );

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('QR: $result'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,

      child: GestureDetector(
        onScaleStart: (details) {
          _baseZoom = _currentZoom;
        },

        onScaleUpdate: (details) async {
          await _handleZoom(details.scale);
        },

        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 30,
                offset: const Offset(0, 20),
              ),
            ],
          ),

          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),

            child: Stack(
              fit: StackFit.expand,
              children: [
                /// ================= CAMERA / IMAGE =================

                if (_capturedImage != null)
                  Image.file(
                    File(_capturedImage!.path),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stack) => Container(color: Colors.black),
                  )
                else if (_isReady)
                  ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width:
                            _controller!
                                    .value
                                    .previewSize
                                    ?.height ??
                                1,

                        height:
                            _controller!
                                    .value
                                    .previewSize
                                    ?.width ??
                                1,

                        child: CameraPreview(_controller!),
                      ),
                    ),
                  )
                else
                  Container(
                    color: Colors.black,

                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                  ),

                /// OVERLAY
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,

                        end: Alignment.bottomCenter,

                        colors: [
                          Colors.black.withValues(alpha: 0.15),

                          Colors.transparent,

                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                ),

                /// TOP SHADOW
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                /// BOTTOM SHADOW
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                /// FLASH
                Positioned(
                  top: 18,
                  left: 18,
                  child: GestureDetector(
                    onTap: toggleFlash,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),

                        shape: BoxShape.circle,

                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),

                      child: Icon(
                        _flashMode == FlashMode.off
                            ? Icons.flash_off_rounded
                            : Icons.flash_on_rounded,

                        color: Colors.white,

                        size: 22,
                      ),
                    ),
                  ),
                ),

                /// QR
                Positioned(
                  top: 18,
                  right: 18,
                  child: GestureDetector(
                    onTap: openQRScanner,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),

                        shape: BoxShape.circle,

                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),

                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),

                /// CLOSE PREVIEW
                if (_capturedImage != null)
                  Positioned(
                    top: 80,
                    right: 20,
                    child: GestureDetector(
                      onTap: clearPreview,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: 0.45,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                /// ZOOM TEXT
                if (_capturedImage == null)
                  Positioned(
                    bottom: 28,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),

                        decoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: 0.45,
                          ),

                          borderRadius:
                              BorderRadius.circular(20),
                        ),

                        child: Text(
                          '${_currentZoom.toStringAsFixed(1)}x',

                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),

                /// ĐANG ĐĂNG
                if (_isPosting)
                  Container(
                    color: Colors.black.withValues(alpha: 0.45),

                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                  ),

                /// BORDER
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),

                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: 0.08,
                        ),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ================= QR SCREEN =================

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() =>
      _QRScannerScreenState();
}

class _QRScannerScreenState
    extends State<QRScannerScreen> {
  bool _isScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,

      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_isScanned) return;

              final List<Barcode> barcodes =
                  capture.barcodes;

              if (barcodes.isEmpty) return;

              final String? code =
                  barcodes.first.rawValue;

              if (code == null) return;

              _isScanned = true;

              Navigator.pop(context, code);
            },
          ),

          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),

          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),

          Positioned(
            top: 60,
            left: 20,
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),

                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),

          const Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Đưa mã QR vào khung',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}