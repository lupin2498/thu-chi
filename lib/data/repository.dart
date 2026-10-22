import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../core/text_utils.dart';
import 'database.dart';
import 'models.dart';

/// Truy vấn & ghi dữ liệu thu chi.
class FinanceRepository {
  FinanceRepository(this.db);

  final Database db;

  // ---------------------------------------------------------------- Tài khoản

  Future<List<Account>> accounts({bool includeArchived = false}) async {
    final rows = await db.query(
      'accounts',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'sort_order, id',
    );
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> account(int id) async {
    final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Account.fromMap(rows.first);
  }

  Future<int> insertAccount(Account a) async {
    final maxOrder =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT MAX(sort_order) FROM accounts'),
        ) ??
        0;
    final map = a.copyWith(sortOrder: maxOrder + 1).toMap()..remove('id');
    return db.insert('accounts', map);
  }

  Future<void> updateAccount(Account a) async {
    await db.update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
  }

  /// Xoá tài khoản; nếu đã có giao dịch thì chỉ ẩn đi. Trả về true nếu đã xoá hẳn.
  Future<bool> deleteAccount(int id) async {
    final used =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM transactions WHERE account_id = ? OR to_account_id = ?',
            [id, id],
          ),
        ) ??
        0;
    if (used > 0) {
      await db.update(
        'accounts',
        {'archived': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      return false;
    }
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  /// Số dư hiện tại của từng tài khoản.
  Future<Map<int, int>> accountBalances() async {
    final rows = await db.rawQuery('''
      SELECT a.id AS id,
        a.initial_balance
        + COALESCE((SELECT SUM(amount) FROM transactions t WHERE t.account_id = a.id AND t.type = 'income'), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions t WHERE t.account_id = a.id AND t.type = 'expense'), 0)
        - COALESCE((SELECT SUM(amount) FROM transactions t WHERE t.account_id = a.id AND t.type = 'transfer'), 0)
        + COALESCE((SELECT SUM(amount) FROM transactions t WHERE t.to_account_id = a.id AND t.type = 'transfer'), 0)
        AS balance
      FROM accounts a
    ''');
    return {
      for (final r in rows)
        (r['id'] as num).toInt(): (r['balance'] as num?)?.toInt() ?? 0,
    };
  }

  // ----------------------------------------------------------------- Hạng mục

  Future<List<Category>> categories({
    CategoryKind? kind,
    bool includeArchived = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.key);
    }
    if (!includeArchived) where.add('archived = 0');
    final rows = await db.query(
      'categories',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'sort_order, id',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<int> insertCategory(Category c) async {
    final maxOrder =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT MAX(sort_order) FROM categories'),
        ) ??
        0;
    final map = c.copyWith(sortOrder: maxOrder + 1).toMap()..remove('id');
    return db.insert('categories', map);
  }

  Future<void> updateCategory(Category c) async {
    await db.update(
      'categories',
      c.toMap(),
      where: 'id = ?',
      whereArgs: [c.id],
    );
  }

  /// Xoá hạng mục; nếu đã dùng thì ẩn đi để giữ lịch sử. Trả true nếu xoá hẳn.
  Future<bool> deleteCategory(int id) async {
    final used =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM transactions WHERE category_id = ?',
            [id],
          ),
        ) ??
        0;
    if (used > 0) {
      await db.update(
        'categories',
        {'archived': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      return false;
    }
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  // ---------------------------------------------------------------- Giao dịch

  Future<int> insertTransaction(TransactionRecord t) async {
    _validate(t);
    final map = t.toMap()..remove('id');
    return db.insert('transactions', map);
  }

  Future<void> updateTransaction(TransactionRecord t) async {
    _validate(t);
    if (t.id == null) throw ArgumentError('Giao dịch chưa có id');
    await db.update(
      'transactions',
      t.toMap(),
      where: 'id = ?',
      whereArgs: [t.id],
    );
  }

  Future<void> deleteTransaction(int id) async {
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  void _validate(TransactionRecord t) {
    if (t.amount <= 0) throw ArgumentError('Số tiền phải lớn hơn 0');
    if (t.type == TxnType.transfer) {
      if (t.toAccountId == null) {
        throw ArgumentError('Chưa chọn tài khoản nhận');
      }
      if (t.toAccountId == t.accountId) {
        throw ArgumentError('Tài khoản nguồn và đích phải khác nhau');
      }
    }
  }

  Future<TransactionRecord?> transaction(int id) async {
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : TransactionRecord.fromMap(rows.first);
  }

  /// Giao dịch trong khoảng [start, end), mới nhất trước.
  Future<List<TransactionRecord>> transactions({
    DateTime? start,
    DateTime? end,
    int? accountId,
    int? categoryId,
    TxnType? type,
    String? search,
    int? limit,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (start != null) {
      where.add('date >= ?');
      args.add(start.millisecondsSinceEpoch);
    }
    if (end != null) {
      where.add('date < ?');
      args.add(end.millisecondsSinceEpoch);
    }
    if (accountId != null) {
      where.add('(account_id = ? OR to_account_id = ?)');
      args
        ..add(accountId)
        ..add(accountId);
    }
    if (categoryId != null) {
      where.add('category_id = ?');
      args.add(categoryId);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type.key);
    }
    final rows = await db.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC, id DESC',
      limit: (search == null || search.trim().isEmpty) ? limit : null,
    );
    var list = rows.map(TransactionRecord.fromMap).toList();
    final q = search == null ? '' : normalizeForSearch(search);
    if (q.isNotEmpty) {
      // Tìm không dấu theo diễn giải hoặc số tiền.
      final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
      list = list.where((t) {
        if (normalizeForSearch(t.note).contains(q)) return true;
        if (t.rawText != null && normalizeForSearch(t.rawText!).contains(q)) {
          return true;
        }
        return digits.isNotEmpty && t.amount.toString().contains(digits);
      }).toList();
      if (limit != null && list.length > limit) list = list.sublist(0, limit);
    }
    return list;
  }

  Future<PeriodSummary> summary(
    DateTime start,
    DateTime end, {
    int? accountId,
  }) async {
    final args = <Object?>[
      start.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
    ];
    var accountFilter = '';
    if (accountId != null) {
      accountFilter = ' AND account_id = ?';
      args.add(accountId);
    }
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN type = 'income' THEN amount END), 0) AS income,
        COALESCE(SUM(CASE WHEN type = 'expense' THEN amount END), 0) AS expense
      FROM transactions
      WHERE date >= ? AND date < ?$accountFilter
    ''', args);
    final r = rows.first;
    return PeriodSummary(
      income: (r['income'] as num?)?.toInt() ?? 0,
      expense: (r['expense'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<CategoryTotal>> categoryTotals(
    TxnType type,
    DateTime start,
    DateTime end,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT category_id, SUM(amount) AS total, COUNT(*) AS cnt
      FROM transactions
      WHERE type = ? AND date >= ? AND date < ?
      GROUP BY category_id
      ORDER BY total DESC
    ''',
      [type.key, start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return rows
        .map(
          (r) => CategoryTotal(
            categoryId: (r['category_id'] as num?)?.toInt(),
            total: (r['total'] as num?)?.toInt() ?? 0,
            count: (r['cnt'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  /// Tổng thu/chi từng tháng của một năm (luôn đủ 12 phần tử).
  Future<List<MonthTotal>> monthTotals(int year) async {
    final result = <MonthTotal>[];
    final txns = await transactions(
      start: DateTime(year),
      end: DateTime(year + 1),
    );
    final income = List<int>.filled(12, 0);
    final expense = List<int>.filled(12, 0);
    for (final t in txns) {
      final m = t.date.month - 1;
      if (t.type == TxnType.income) income[m] += t.amount;
      if (t.type == TxnType.expense) expense[m] += t.amount;
    }
    for (var i = 0; i < 12; i++) {
      result.add(
        MonthTotal(
          month: DateTime(year, i + 1),
          income: income[i],
          expense: expense[i],
        ),
      );
    }
    return result;
  }

  /// Tổng chi theo ngày trong tháng (index 0 = ngày 1).
  Future<List<int>> dailyExpense(DateTime month) async {
    final start = monthStart(month);
    final txns = await transactions(
      start: start,
      end: nextMonthStart(month),
      type: TxnType.expense,
    );
    final days = List<int>.filled(daysInMonth(month), 0);
    for (final t in txns) {
      days[t.date.day - 1] += t.amount;
    }
    return days;
  }

  /// Hạng mục đã dùng gần nhất cho cùng diễn giải (học thói quen người dùng).
  Future<int?> lastCategoryForNote(String note, CategoryKind kind) async {
    final n = normalizeForSearch(note);
    if (n.isEmpty) return null;
    final type = kind == CategoryKind.income ? TxnType.income : TxnType.expense;
    final rows = await db.query(
      'transactions',
      columns: ['note', 'category_id'],
      where: 'type = ? AND category_id IS NOT NULL',
      whereArgs: [type.key],
      orderBy: 'date DESC',
      limit: 500,
    );
    for (final r in rows) {
      if (normalizeForSearch((r['note'] as String?) ?? '') == n) {
        return (r['category_id'] as num?)?.toInt();
      }
    }
    return null;
  }

  /// Gợi ý diễn giải đã dùng (mới nhất trước, không trùng).
  Future<List<String>> recentNotes({int limit = 20}) async {
    final rows = await db.rawQuery(
      '''
      SELECT note, MAX(date) AS d FROM transactions
      WHERE note <> '' GROUP BY note ORDER BY d DESC LIMIT ?
    ''',
      [limit],
    );
    return rows.map((r) => r['note'] as String).toList();
  }

  // ----------------------------------------------------------- Sao lưu dữ liệu

  Future<Map<String, Object?>> exportAll() async {
    return {
      'app': 'so_thu_chi',
      'version': AppDatabase.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'accounts': await db.query('accounts'),
      'categories': await db.query('categories'),
      'transactions': await db.query('transactions'),
    };
  }

  /// Thay toàn bộ dữ liệu bằng bản sao lưu.
  Future<void> importAll(Map<String, Object?> data) async {
    if (data['app'] != 'so_thu_chi') {
      throw const FormatException('Tệp không phải bản sao lưu Sổ Thu Chi');
    }
    List<Map<String, Object?>> rowsOf(String key) {
      final list = data[key];
      if (list is! List) throw FormatException('Thiếu dữ liệu "$key"');
      return list.map((e) => Map<String, Object?>.from(e as Map)).toList();
    }

    final accounts = rowsOf('accounts');
    final categories = rowsOf('categories');
    final txns = rowsOf('transactions');
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('accounts');
      await txn.delete('categories');
      for (final r in accounts) {
        await txn.insert('accounts', Account.fromMap(r).toMap());
      }
      for (final r in categories) {
        await txn.insert('categories', Category.fromMap(r).toMap());
      }
      for (final r in txns) {
        await txn.insert('transactions', TransactionRecord.fromMap(r).toMap());
      }
    });
  }

  /// Xuất CSV (mở được bằng Excel nhờ BOM UTF-8).
  Future<String> exportCsv({DateTime? start, DateTime? end}) async {
    final accounts = {
      for (final a in await this.accounts(includeArchived: true)) a.id: a,
    };
    final cats = {
      for (final c in await categories(includeArchived: true)) c.id: c,
    };
    final txns = await transactions(start: start, end: end);
    String esc(String s) {
      if (s.contains(RegExp(r'[",\n\r;]'))) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final b = StringBuffer('﻿')
      ..writeln(
        'Ngày,Giờ,Loại,Số tiền,Hạng mục,Tài khoản,Tài khoản nhận,Diễn giải,Nguồn',
      );
    for (final t in txns.reversed) {
      b.writeln(
        [
          formatDate(t.date),
          formatTime(t.date),
          t.type.label,
          t.amount.toString(),
          esc(cats[t.categoryId]?.name ?? ''),
          esc(accounts[t.accountId]?.name ?? ''),
          esc(accounts[t.toAccountId]?.name ?? ''),
          esc(t.note),
          t.source == TxnSource.auto ? 'Tự động' : 'Thủ công',
        ].join(','),
      );
    }
    return b.toString();
  }
}
