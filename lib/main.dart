import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'capture/capture_channel.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'state/app_state.dart';
import 'state/settings.dart';
import 'ui/quick_add/popup_app.dart';

Future<AppState> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'vi';
  await initializeDateFormatting('vi');
  final db = await AppDatabase.shared();
  final settings = await AppSettings.load();
  final state = AppState(FinanceRepository(db), settings);
  await state.load();
  return state;
}

Future<void> main() async {
  final state = await _bootstrap();
  // Mở app qua liên kết sothuchi://app/add?... (Phím tắt iOS).
  final route = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  Uri? link;
  if (route != '/' && route.isNotEmpty) {
    final uri = Uri.tryParse(route);
    if (uri != null && captureFromUri(uri) != null) link = uri;
  }
  runApp(SoThuChiApp(state: state, initialLink: link));
}

/// Điểm vào của cửa sổ ghi nhanh nổi trên ứng dụng ngân hàng (Android).
@pragma('vm:entry-point')
Future<void> quickAddMain() async {
  final state = await _bootstrap();
  CaptureChannel.ensureHandler();
  final capture = await CaptureChannel.launchCapture();
  runApp(PopupApp(state: state, initial: capture));
}
