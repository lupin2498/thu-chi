import 'package:flutter/foundation.dart' hide Category;

import '../capture/capture_channel.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'settings.dart';

/// Trạng thái dùng chung của ứng dụng.
class AppState extends ChangeNotifier {
  AppState(this.repo, this.settings);

  final FinanceRepository repo;
  final AppSettings settings;

  List<Account> _allAccounts = const [];
  List<Category> _allCategories = const [];
  Map<int, int> balances = const {};
  List<CaptureData> pending = const [];

  /// Tăng mỗi khi dữ liệu thay đổi để các màn hình tải lại.
  int revision = 0;
  bool loaded = false;

  List<Account> get accounts =>
      _allAccounts.where((a) => !a.archived).toList(growable: false);
  List<Account> get allAccounts => _allAccounts;

  List<Category> categoriesOf(CategoryKind kind) => _allCategories
      .where((c) => c.kind == kind && !c.archived)
      .toList(growable: false);

  List<Category> get allCategories => _allCategories;

  Account? accountById(int? id) {
    if (id == null) return null;
    for (final a in _allAccounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Category? categoryById(int? id) {
    if (id == null) return null;
    for (final c in _allCategories) {
      if (c.id == id) return c;
    }
    return null;
  }

  int balanceOf(int? accountId) => balances[accountId] ?? 0;

  int get totalBalance {
    var sum = 0;
    for (final a in accounts) {
      if (a.includeInTotal) sum += balanceOf(a.id);
    }
    return sum;
  }

  Future<void> load() async {
    await refresh(notify: false);
    loaded = true;
    notifyListeners();
  }

  Future<void> refresh({bool notify = true}) async {
    _allAccounts = await repo.accounts(includeArchived: true);
    _allCategories = await repo.categories(includeArchived: true);
    balances = await repo.accountBalances();
    revision++;
    if (notify) notifyListeners();
  }

  Future<void> refreshPending() async {
    final list = await CaptureChannel.pending();
    list.sort((a, b) => b.time.compareTo(a.time));
    pending = list;
    notifyListeners();
  }

  Future<void> dismissCapture(String id) async {
    await CaptureChannel.remove(id);
    pending = pending.where((c) => c.id != id).toList();
    notifyListeners();
  }

  /// Tài khoản phù hợp với ngân hàng phát sinh thông báo.
  Account? accountForBank(String? bankKey) {
    if (bankKey == null) return null;
    for (final a in accounts) {
      if (a.bankKey == bankKey) return a;
    }
    return null;
  }

  /// Tài khoản mặc định khi ghi mới.
  int? defaultAccountId({String? bankKey}) {
    final list = accounts;
    if (list.isEmpty) return null;
    final byBank = accountForBank(bankKey);
    if (byBank != null) return byBank.id;
    final last = settings.lastAccountId;
    if (last != null && list.any((a) => a.id == last)) return last;
    return list.first.id;
  }

  // ---------------------------------------------------------------- Giao dịch

  Future<int> addTransaction(TransactionRecord t) async {
    final id = await repo.insertTransaction(t);
    await settings.setLastAccountId(t.accountId);
    await refresh();
    return id;
  }

  Future<void> updateTransaction(TransactionRecord t) async {
    await repo.updateTransaction(t);
    await refresh();
  }

  Future<void> deleteTransaction(int id) async {
    await repo.deleteTransaction(id);
    await refresh();
  }

  /// Khôi phục giao dịch vừa xoá (Hoàn tác).
  Future<void> restoreTransaction(TransactionRecord t) async {
    await repo.insertTransaction(t.copyWith());
    await refresh();
  }

  // ---------------------------------------------------- Tài khoản / hạng mục

  Future<void> saveAccount(Account a) async {
    if (a.id == null) {
      await repo.insertAccount(a);
    } else {
      await repo.updateAccount(a);
    }
    await refresh();
  }

  Future<bool> deleteAccount(int id) async {
    final removed = await repo.deleteAccount(id);
    await refresh();
    return removed;
  }

  Future<void> saveCategory(Category c) async {
    if (c.id == null) {
      await repo.insertCategory(c);
    } else {
      await repo.updateCategory(c);
    }
    await refresh();
  }

  Future<bool> deleteCategory(int id) async {
    final removed = await repo.deleteCategory(id);
    await refresh();
    return removed;
  }

  Future<void> setMonthlyBudget(int v) async {
    await settings.setMonthlyBudget(v);
    notifyListeners();
  }

  Future<void> setAutoListen(bool v) async {
    await settings.setAutoListen(v);
    notifyListeners();
  }

  Future<void> setAutoSaveAfterVoice(bool v) async {
    await settings.setAutoSaveAfterVoice(v);
    notifyListeners();
  }

  Future<void> setHideBalance(bool v) async {
    await settings.setHideBalance(v);
    notifyListeners();
  }

  Future<void> importBackup(Map<String, Object?> data) async {
    await repo.importAll(data);
    await refresh();
  }
}
