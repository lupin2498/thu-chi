import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import 'bank_apps.dart';
import 'bank_parser.dart';

/// Một giao dịch bắt được từ thông báo ngân hàng (chờ người dùng xác nhận).
@immutable
class CaptureData {
  const CaptureData({
    required this.id,
    required this.amount,
    required this.type,
    this.bankKey,
    this.content,
    this.rawText,
    this.packageName,
    this.balance,
    required this.time,
  });

  final String id;
  final int amount;
  final TxnType type;
  final String? bankKey;
  final String? content;
  final String? rawText;
  final String? packageName;
  final int? balance;
  final DateTime time;

  String get bankName =>
      bankByKey(bankKey)?.name ??
      bankByPackage(packageName)?.name ??
      'Ngân hàng';

  factory CaptureData.fromMap(Map<Object?, Object?> m) {
    final time = (m['time'] as num?)?.toInt();
    return CaptureData(
      id: (m['id'] ?? '').toString(),
      amount: (m['amount'] as num?)?.toInt() ?? 0,
      type: (m['income'] == true) ? TxnType.income : TxnType.expense,
      bankKey: m['bankKey'] as String?,
      content: m['content'] as String?,
      rawText: m['rawText'] as String?,
      packageName: m['packageName'] as String?,
      balance: (m['balance'] as num?)?.toInt(),
      time: time == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(time),
    );
  }

  /// Tạo từ văn bản (SMS dán vào, liên kết Phím tắt iOS...).
  static CaptureData? fromText(String text, {String? id, DateTime? time}) {
    final r = BankNotificationParser.parse(text);
    if (r == null) return null;
    return CaptureData(
      id: id ?? 'text-${DateTime.now().microsecondsSinceEpoch}',
      amount: r.amount,
      type: r.type,
      bankKey: r.bankKey,
      content: r.content,
      rawText: text,
      balance: r.balance,
      time: time ?? DateTime.now(),
    );
  }
}

@immutable
class CapturePermissions {
  const CapturePermissions({
    this.notificationListener = false,
    this.overlay = false,
    this.postNotifications = false,
    this.microphone = false,
  });

  final bool notificationListener;
  final bool overlay;
  final bool postNotifications;
  final bool microphone;

  bool get ready => notificationListener && overlay;

  factory CapturePermissions.fromMap(Map<Object?, Object?> m) =>
      CapturePermissions(
        notificationListener: m['notificationListener'] == true,
        overlay: m['overlay'] == true,
        postNotifications: m['postNotifications'] == true,
        microphone: m['microphone'] == true,
      );
}

@immutable
class CaptureSettings {
  const CaptureSettings({
    this.enabled = true,
    this.disabledBanks = const {},
    this.readSms = true,
    this.anyApp = false,
    this.extraPackages = const [],
    this.showPopup = true,
  });

  final bool enabled;

  /// Mã ngân hàng bị tắt.
  final Set<String> disabledBanks;
  final bool readSms;

  /// Đọc thông báo của mọi ứng dụng (chỉ nhận khi có dấu hiệu rõ ràng).
  final bool anyApp;
  final List<String> extraPackages;

  /// Bật cửa sổ ghi nhanh ngay (nếu tắt chỉ hiện thông báo).
  final bool showPopup;

  CaptureSettings copyWith({
    bool? enabled,
    Set<String>? disabledBanks,
    bool? readSms,
    bool? anyApp,
    List<String>? extraPackages,
    bool? showPopup,
  }) => CaptureSettings(
    enabled: enabled ?? this.enabled,
    disabledBanks: disabledBanks ?? this.disabledBanks,
    readSms: readSms ?? this.readSms,
    anyApp: anyApp ?? this.anyApp,
    extraPackages: extraPackages ?? this.extraPackages,
    showPopup: showPopup ?? this.showPopup,
  );

  Map<String, Object?> toMap() => {
    'enabled': enabled,
    'disabledBanks': disabledBanks.toList(),
    'readSms': readSms,
    'anyApp': anyApp,
    'extraPackages': extraPackages,
    'showPopup': showPopup,
  };

  factory CaptureSettings.fromMap(Map<Object?, Object?> m) => CaptureSettings(
    enabled: m['enabled'] != false,
    disabledBanks: ((m['disabledBanks'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet(),
    readSms: m['readSms'] != false,
    anyApp: m['anyApp'] == true,
    extraPackages: ((m['extraPackages'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
    showPopup: m['showPopup'] != false,
  );
}

/// Kênh nói chuyện với phần Android (NotificationListener, cửa sổ nổi...).
class CaptureChannel {
  CaptureChannel._();

  static const MethodChannel channel = MethodChannel('vn.sothuchi/capture');

  /// Cho phép test ghi đè.
  @visibleForTesting
  static bool? debugSupported;

  static bool get supported =>
      debugSupported ?? (!kIsWeb && Platform.isAndroid);

  static final StreamController<CaptureData> _incoming =
      StreamController<CaptureData>.broadcast();

  /// Giao dịch mới đến khi cửa sổ ghi nhanh đang mở.
  static Stream<CaptureData> get incoming => _incoming.stream;

  static bool _handlerSet = false;

  static void ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onNewCapture' && call.arguments is Map) {
        _incoming.add(CaptureData.fromMap(call.arguments as Map));
      }
      return null;
    });
  }

  static Future<T?> _invoke<T>(String method, [Object? args]) async {
    if (!supported) return null;
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('CaptureChannel.$method lỗi: ${e.message}');
      return null;
    }
  }

  static Future<CapturePermissions> permissions() async {
    final m = await _invoke<Map<Object?, Object?>>('getPermissions');
    return m == null
        ? const CapturePermissions()
        : CapturePermissions.fromMap(m);
  }

  static Future<void> openNotificationListenerSettings() =>
      _invoke<void>('openNotificationListenerSettings');

  static Future<void> openOverlaySettings() =>
      _invoke<void>('openOverlaySettings');

  static Future<void> openAppSettings() => _invoke<void>('openAppSettings');

  /// Trang "Hiển thị cửa sổ bật lên khi chạy nền" của Xiaomi/Oppo/Vivo (nếu có).
  static Future<bool> openBackgroundPopupSettings() async =>
      (await _invoke<bool>('openBackgroundPopupSettings')) ?? false;

  static Future<bool> requestPostNotifications() async =>
      (await _invoke<bool>('requestPostNotifications')) ?? false;

  static Future<bool> requestMicrophone() async =>
      (await _invoke<bool>('requestMicrophone')) ?? false;

  static Future<CaptureSettings> settings() async {
    final m = await _invoke<Map<Object?, Object?>>('getSettings');
    return m == null ? const CaptureSettings() : CaptureSettings.fromMap(m);
  }

  static Future<void> saveSettings(CaptureSettings s) =>
      _invoke<void>('setSettings', s.toMap());

  static Future<List<CaptureData>> pending() async {
    final list = await _invoke<List<Object?>>('getPendingCaptures');
    if (list == null) return const [];
    return list
        .whereType<Map<Object?, Object?>>()
        .map(CaptureData.fromMap)
        .where((c) => c.amount > 0)
        .toList();
  }

  static Future<void> remove(String id) =>
      _invoke<void>('removeCapture', {'id': id});

  static Future<void> clearAll() => _invoke<void>('clearCaptures');

  /// Giao dịch đã mở cửa sổ ghi nhanh (chỉ trong cửa sổ popup).
  static Future<CaptureData?> launchCapture() async {
    final m = await _invoke<Map<Object?, Object?>>('getLaunchCapture');
    return m == null ? null : CaptureData.fromMap(m);
  }

  static Future<void> closePopup() => _invoke<void>('closePopup');

  /// Giả lập một thông báo ngân hàng để thử toàn bộ luồng.
  static Future<String?> simulate({
    required String title,
    required String text,
    String package = 'com.mbmobile',
  }) => _invoke<String>('simulateNotification', {
    'title': title,
    'text': text,
    'package': package,
  });

  /// Ứng dụng ngân hàng đã cài trên máy (theo danh sách hỗ trợ).
  static Future<Set<String>> installedPackages() async {
    final list = await _invoke<List<Object?>>('getInstalledBankPackages');
    return (list ?? const []).map((e) => e.toString()).toSet();
  }
}
