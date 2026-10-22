import 'package:flutter/material.dart';

enum TxnType {
  expense('expense', 'Chi tiền'),
  income('income', 'Thu tiền'),
  transfer('transfer', 'Chuyển khoản');

  const TxnType(this.key, this.label);
  final String key;
  final String label;

  static TxnType fromKey(String? key) =>
      TxnType.values.firstWhere((t) => t.key == key, orElse: () => expense);
}

enum CategoryKind {
  expense('expense', 'Mục chi'),
  income('income', 'Mục thu');

  const CategoryKind(this.key, this.label);
  final String key;
  final String label;

  static CategoryKind fromKey(String? key) =>
      CategoryKind.values.firstWhere((t) => t.key == key, orElse: () => expense);

  static CategoryKind forTxn(TxnType t) =>
      t == TxnType.income ? CategoryKind.income : CategoryKind.expense;
}

enum AccountType {
  cash('cash', 'Tiền mặt', 'wallet'),
  bank('bank', 'Tài khoản ngân hàng', 'bank'),
  ewallet('ewallet', 'Ví điện tử', 'phone'),
  credit('credit', 'Thẻ tín dụng', 'card'),
  saving('saving', 'Tiết kiệm', 'savings'),
  other('other', 'Khác', 'other');

  const AccountType(this.key, this.label, this.icon);
  final String key;
  final String label;
  final String icon;

  static AccountType fromKey(String? key) =>
      AccountType.values.firstWhere((t) => t.key == key, orElse: () => other);
}

enum TxnSource {
  manual('manual'),
  voice('voice'),
  auto('auto'),
  link('link');

  const TxnSource(this.key);
  final String key;

  static TxnSource fromKey(String? key) =>
      TxnSource.values.firstWhere((t) => t.key == key, orElse: () => manual);
}

@immutable
class Account {
  const Account({
    this.id,
    required this.name,
    this.type = AccountType.cash,
    this.initialBalance = 0,
    this.bankKey,
    this.color = 0xFF1E88E5,
    this.icon,
    this.archived = false,
    this.includeInTotal = true,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final AccountType type;
  final int initialBalance;

  /// Mã ngân hàng/ví (vd "mbbank") để tự chọn tài khoản khi bắt thông báo.
  final String? bankKey;
  final int color;
  final String? icon;
  final bool archived;
  final bool includeInTotal;
  final int sortOrder;

  String get iconKey => icon ?? type.icon;

  Account copyWith({
    int? id,
    String? name,
    AccountType? type,
    int? initialBalance,
    String? bankKey,
    bool clearBankKey = false,
    int? color,
    String? icon,
    bool? archived,
    bool? includeInTotal,
    int? sortOrder,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      initialBalance: initialBalance ?? this.initialBalance,
      bankKey: clearBankKey ? null : (bankKey ?? this.bankKey),
      color: color ?? this.color,
      icon: icon ?? this.icon,
      archived: archived ?? this.archived,
      includeInTotal: includeInTotal ?? this.includeInTotal,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'type': type.key,
    'initial_balance': initialBalance,
    'bank_key': bankKey,
    'color': color,
    'icon': icon,
    'archived': archived ? 1 : 0,
    'include_in_total': includeInTotal ? 1 : 0,
    'sort_order': sortOrder,
  };

  factory Account.fromMap(Map<String, Object?> m) => Account(
    id: m['id'] as int?,
    name: (m['name'] as String?) ?? '',
    type: AccountType.fromKey(m['type'] as String?),
    initialBalance: (m['initial_balance'] as num?)?.toInt() ?? 0,
    bankKey: m['bank_key'] as String?,
    color: (m['color'] as num?)?.toInt() ?? 0xFF1E88E5,
    icon: m['icon'] as String?,
    archived: (m['archived'] as num?) == 1,
    includeInTotal: (m['include_in_total'] as num?) != 0,
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
  );
}

@immutable
class Category {
  const Category({
    this.id,
    required this.name,
    required this.kind,
    this.icon = 'other',
    this.color = 0xFF78909C,
    this.sortOrder = 0,
    this.archived = false,
  });

  final int? id;
  final String name;
  final CategoryKind kind;
  final String icon;
  final int color;
  final int sortOrder;
  final bool archived;

  Category copyWith({
    int? id,
    String? name,
    CategoryKind? kind,
    String? icon,
    int? color,
    int? sortOrder,
    bool? archived,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'kind': kind.key,
    'icon': icon,
    'color': color,
    'sort_order': sortOrder,
    'archived': archived ? 1 : 0,
  };

  factory Category.fromMap(Map<String, Object?> m) => Category(
    id: m['id'] as int?,
    name: (m['name'] as String?) ?? '',
    kind: CategoryKind.fromKey(m['kind'] as String?),
    icon: (m['icon'] as String?) ?? 'other',
    color: (m['color'] as num?)?.toInt() ?? 0xFF78909C,
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    archived: (m['archived'] as num?) == 1,
  );
}

@immutable
class TransactionRecord {
  const TransactionRecord({
    this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    this.toAccountId,
    this.categoryId,
    this.note = '',
    required this.date,
    this.createdAt,
    this.source = TxnSource.manual,
    this.rawText,
    this.bankKey,
  });

  final int? id;
  final TxnType type;

  /// Số tiền (đồng), luôn dương.
  final int amount;
  final int accountId;

  /// Tài khoản nhận (chỉ với chuyển khoản nội bộ).
  final int? toAccountId;
  final int? categoryId;
  final String note;
  final DateTime date;
  final DateTime? createdAt;
  final TxnSource source;

  /// Nội dung thông báo gốc (khi ghi tự động).
  final String? rawText;
  final String? bankKey;

  /// Ảnh hưởng tới số dư của [account].
  int effectOn(int account) {
    switch (type) {
      case TxnType.income:
        return account == accountId ? amount : 0;
      case TxnType.expense:
        return account == accountId ? -amount : 0;
      case TxnType.transfer:
        var v = 0;
        if (account == accountId) v -= amount;
        if (account == toAccountId) v += amount;
        return v;
    }
  }

  TransactionRecord copyWith({
    int? id,
    TxnType? type,
    int? amount,
    int? accountId,
    int? toAccountId,
    bool clearToAccount = false,
    int? categoryId,
    bool clearCategory = false,
    String? note,
    DateTime? date,
    DateTime? createdAt,
    TxnSource? source,
    String? rawText,
    String? bankKey,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      accountId: accountId ?? this.accountId,
      toAccountId: clearToAccount ? null : (toAccountId ?? this.toAccountId),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      note: note ?? this.note,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      source: source ?? this.source,
      rawText: rawText ?? this.rawText,
      bankKey: bankKey ?? this.bankKey,
    );
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'type': type.key,
    'amount': amount,
    'account_id': accountId,
    'to_account_id': toAccountId,
    'category_id': categoryId,
    'note': note,
    'date': date.millisecondsSinceEpoch,
    'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
    'source': source.key,
    'raw_text': rawText,
    'bank_key': bankKey,
  };

  factory TransactionRecord.fromMap(Map<String, Object?> m) =>
      TransactionRecord(
        id: m['id'] as int?,
        type: TxnType.fromKey(m['type'] as String?),
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        accountId: (m['account_id'] as num?)?.toInt() ?? 0,
        toAccountId: (m['to_account_id'] as num?)?.toInt(),
        categoryId: (m['category_id'] as num?)?.toInt(),
        note: (m['note'] as String?) ?? '',
        date: DateTime.fromMillisecondsSinceEpoch(
          (m['date'] as num?)?.toInt() ?? 0,
        ),
        createdAt: m['created_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (m['created_at'] as num).toInt(),
              ),
        source: TxnSource.fromKey(m['source'] as String?),
        rawText: m['raw_text'] as String?,
        bankKey: m['bank_key'] as String?,
      );
}

/// Tổng thu/chi trong một khoảng thời gian.
@immutable
class PeriodSummary {
  const PeriodSummary({required this.income, required this.expense});
  final int income;
  final int expense;
  int get net => income - expense;

  static const empty = PeriodSummary(income: 0, expense: 0);
}

@immutable
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.total,
    required this.count,
  });
  final int? categoryId;
  final int total;
  final int count;
}

@immutable
class MonthTotal {
  const MonthTotal({
    required this.month,
    required this.income,
    required this.expense,
  });
  final DateTime month;
  final int income;
  final int expense;
}
