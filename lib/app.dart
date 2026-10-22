import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'capture/capture_channel.dart';
import 'core/format.dart';
import 'data/models.dart';
import 'state/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/quick_add/quick_add_panel.dart';
import 'ui/theme.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Chuyển liên kết sothuchi://app/add?... thành dữ liệu ghi nhanh.
///
/// Hỗ trợ `text` (nội dung SMS/thông báo để trích xuất số tiền) hoặc
/// `amount` + `note` + `type` (expense|income).
CaptureData? captureFromUri(Uri uri) {
  final path = uri.path.isEmpty ? '/${uri.host}' : uri.path;
  if (!path.endsWith('/add') && uri.host != 'add') return null;
  final q = uri.queryParameters;
  final text = q['text'];
  if (text != null && text.trim().isNotEmpty) {
    final c = CaptureData.fromText(text);
    if (c != null) return c;
  }
  final amount = parseMoneyInput(q['amount'] ?? '');
  return CaptureData(
    id: 'link-${DateTime.now().microsecondsSinceEpoch}',
    amount: amount,
    type: q['type'] == 'income' ? TxnType.income : TxnType.expense,
    content: q['note'] ?? text,
    rawText: text,
    time: DateTime.now(),
  );
}

class SoThuChiApp extends StatefulWidget {
  const SoThuChiApp({super.key, required this.state, this.initialLink});

  final AppState state;
  final Uri? initialLink;

  @override
  State<SoThuChiApp> createState() => _SoThuChiAppState();
}

class _SoThuChiAppState extends State<SoThuChiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.refreshPending();
    final link = widget.initialLink;
    if (link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openLink(link));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      // Cửa sổ ghi nhanh có thể đã ghi dữ liệu trong lúc app ở nền.
      widget.state.settings.reload().whenComplete(() {
        widget.state.refresh();
        widget.state.refreshPending();
      });
    }
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation info) async {
    // App chỉ có một màn gốc: nuốt mọi route từ hệ thống để không mở trùng màn hình.
    if (captureFromUri(info.uri) != null) _openLink(info.uri);
    return true;
  }

  Uri? _lastLink;
  DateTime? _lastLinkAt;

  void _openLink(Uri uri) {
    // iOS/Android có thể gửi cùng một liên kết hai lần (initialRoute + pushRoute).
    final now = DateTime.now();
    if (_lastLink == uri &&
        _lastLinkAt != null &&
        now.difference(_lastLinkAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastLink = uri;
    _lastLinkAt = now;
    final c = captureFromUri(uri);
    final ctx = rootNavigatorKey.currentContext;
    if (c == null || ctx == null) return;
    showQuickAddSheet(ctx, capture: c.amount > 0 ? c : null);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.state,
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Sổ Thu Chi',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        initialRoute: '/',
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: const RouteSettings(name: '/'),
          builder: (_) => const HomeShell(),
        ),
      ),
    );
  }
}
