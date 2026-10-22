import 'package:shared_preferences/shared_preferences.dart';

/// Cài đặt người dùng (lưu bằng SharedPreferences).
class AppSettings {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  Future<void> reload() => _prefs.reload();

  static const _kBudget = 'monthly_budget';
  static const _kHideBalance = 'hide_balance';
  static const _kAutoListen = 'auto_listen';
  static const _kAutoSave = 'auto_save_after_voice';
  static const _kLastAccount = 'last_account_id';
  static const _kOnboarded = 'onboarded_capture';

  /// Hạn mức chi tiêu mỗi tháng (0 = không đặt).
  int get monthlyBudget => _prefs.getInt(_kBudget) ?? 0;
  Future<void> setMonthlyBudget(int v) => _prefs.setInt(_kBudget, v < 0 ? 0 : v);

  bool get hideBalance => _prefs.getBool(_kHideBalance) ?? false;
  Future<void> setHideBalance(bool v) => _prefs.setBool(_kHideBalance, v);

  /// Tự bật micro khi mở cửa sổ ghi nhanh.
  bool get autoListen => _prefs.getBool(_kAutoListen) ?? true;
  Future<void> setAutoListen(bool v) => _prefs.setBool(_kAutoListen, v);

  /// Tự lưu sau khi nói xong (đếm ngược 3 giây).
  bool get autoSaveAfterVoice => _prefs.getBool(_kAutoSave) ?? false;
  Future<void> setAutoSaveAfterVoice(bool v) => _prefs.setBool(_kAutoSave, v);

  int? get lastAccountId => _prefs.getInt(_kLastAccount);
  Future<void> setLastAccountId(int id) => _prefs.setInt(_kLastAccount, id);

  bool get onboardedCapture => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboardedCapture(bool v) => _prefs.setBool(_kOnboarded, v);
}
