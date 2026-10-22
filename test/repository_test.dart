import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_thu_chi/data/models.dart';
import 'package:so_thu_chi/data/repository.dart';

import 'helpers.dart';

void main() {
  late FinanceRepository repo;
  late int cash;
  late int bank;
  late Category food;
  late Category salary;

  setUp(() async {
    repo = await createRepo();
    final accounts = await repo.accounts();
    cash = accounts.firstWhere((a) => a.type == AccountType.cash).id!;
    bank = accounts.firstWhere((a) => a.bankKey == 'mbbank').id!;
    food = (await repo.categories(kind: CategoryKind.expense))
        .firstWhere((c) => c.name == 'Ăn uống');
    salary = (await repo.categories(kind: CategoryKind.income))
        .firstWhere((c) => c.name == 'Lương');
  });

  TransactionRecord txn(
    TxnType type,
    int amount, {
    int? account,
    int? to,
    int? category,
    String note = '',
    DateTime? date,
  }) => TransactionRecord(
    type: type,
    amount: amount,
    accountId: account ?? cash,
    toAccountId: to,
    categoryId: category,
    note: note,
    date: date ?? DateTime(2026, 10, 15, 12),
  );

  test('dữ liệu mặc định', () async {
    expect((await repo.accounts()).length, 2);
    expect(
      (await repo.categories(kind: CategoryKind.expense)).length,
      greaterThan(10),
    );
    expect(
      (await repo.categories(kind: CategoryKind.income)).length,
      greaterThan(5),
    );
  });

  test('số dư và tổng thu chi, chuyển khoản không tính vào thu chi', () async {
    await repo.updateAccount(
      (await repo.account(bank))!.copyWith(initialBalance: 1000000),
    );
    await repo.insertTransaction(
      txn(TxnType.income, 5000000, account: bank, category: salary.id),
    );
    await repo.insertTransaction(
      txn(TxnType.expense, 150000, account: bank, category: food.id),
    );
    await repo.insertTransaction(
      txn(TxnType.transfer, 500000, account: bank, to: cash),
    );
    await repo.insertTransaction(
      txn(TxnType.expense, 50000, account: cash, category: food.id),
    );

    final bal = await repo.accountBalances();
    expect(bal[bank], 1000000 + 5000000 - 150000 - 500000);
    expect(bal[cash], 500000 - 50000);

    final s = await repo.summary(DateTime(2026, 10), DateTime(2026, 11));
    expect(s.income, 5000000);
    expect(s.expense, 200000);
    expect(s.net, 4800000);

    final sBank = await repo.summary(
      DateTime(2026, 10),
      DateTime(2026, 11),
      accountId: bank,
    );
    expect(sBank.expense, 150000);
  });

  test('ranh giới tháng', () async {
    await repo.insertTransaction(
      txn(TxnType.expense, 1, date: DateTime(2026, 10, 31, 23, 59, 59)),
    );
    await repo.insertTransaction(
      txn(TxnType.expense, 2, date: DateTime(2026, 11, 1)),
    );
    final oct = await repo.summary(DateTime(2026, 10), DateTime(2026, 11));
    final nov = await repo.summary(DateTime(2026, 11), DateTime(2026, 12));
    expect(oct.expense, 1);
    expect(nov.expense, 2);
    final daily = await repo.dailyExpense(DateTime(2026, 10));
    expect(daily.length, 31);
    expect(daily[30], 1);
  });

  test('kiểm tra hợp lệ', () async {
    expect(
      () => repo.insertTransaction(txn(TxnType.expense, 0)),
      throwsArgumentError,
    );
    expect(
      () => repo.insertTransaction(txn(TxnType.expense, -5)),
      throwsArgumentError,
    );
    expect(
      () => repo.insertTransaction(txn(TxnType.transfer, 10)),
      throwsArgumentError,
    );
    expect(
      () => repo.insertTransaction(
        txn(TxnType.transfer, 10, account: cash, to: cash),
      ),
      throwsArgumentError,
    );
  });

  test('sửa, xoá giao dịch', () async {
    final id = await repo.insertTransaction(
      txn(TxnType.expense, 100, note: 'a'),
    );
    final t = (await repo.transaction(id))!;
    await repo.updateTransaction(t.copyWith(amount: 200, note: 'b'));
    final u = (await repo.transaction(id))!;
    expect(u.amount, 200);
    expect(u.note, 'b');
    await repo.deleteTransaction(id);
    expect(await repo.transaction(id), isNull);
  });

  test('tìm kiếm không dấu và theo số tiền', () async {
    await repo.insertTransaction(
      txn(TxnType.expense, 45000, note: 'Ăn trưa quán Bún Chả'),
    );
    await repo.insertTransaction(txn(TxnType.expense, 30000, note: 'Cà phê'));
    expect((await repo.transactions(search: 'an trua')).length, 1);
    expect((await repo.transactions(search: 'BUN CHA')).length, 1);
    expect((await repo.transactions(search: 'cà phê')).length, 1);
    expect((await repo.transactions(search: '45.000')).length, 1);
    expect((await repo.transactions(search: 'xyz')).length, 0);
    expect((await repo.transactions(search: '  ')).length, 2);
  });

  test('báo cáo theo hạng mục và theo tháng', () async {
    await repo.insertTransaction(txn(TxnType.expense, 100, category: food.id));
    await repo.insertTransaction(txn(TxnType.expense, 300, category: food.id));
    await repo.insertTransaction(txn(TxnType.expense, 50));
    await repo.insertTransaction(
      txn(
        TxnType.income,
        1000,
        category: salary.id,
        date: DateTime(2026, 3, 5),
      ),
    );
    final totals = await repo.categoryTotals(
      TxnType.expense,
      DateTime(2026, 10),
      DateTime(2026, 11),
    );
    expect(totals.first.categoryId, food.id);
    expect(totals.first.total, 400);
    expect(totals.first.count, 2);
    expect(totals.last.categoryId, isNull);
    final months = await repo.monthTotals(2026);
    expect(months.length, 12);
    expect(months[2].income, 1000);
    expect(months[9].expense, 450);
  });

  test('học hạng mục theo diễn giải', () async {
    final market = (await repo.categories(kind: CategoryKind.expense))
        .firstWhere((c) => c.icon == 'market');
    await repo.insertTransaction(
      txn(TxnType.expense, 100, category: market.id, note: 'Ăn trưa'),
    );
    expect(
      await repo.lastCategoryForNote('ăn TRƯA ', CategoryKind.expense),
      market.id,
    );
    expect(
      await repo.lastCategoryForNote('ăn tối', CategoryKind.expense),
      isNull,
    );
    expect(
      await repo.lastCategoryForNote('ăn trưa', CategoryKind.income),
      isNull,
    );
    expect(await repo.lastCategoryForNote('', CategoryKind.expense), isNull);
  });

  test('xoá tài khoản/hạng mục đã dùng thì ẩn', () async {
    await repo.insertTransaction(
      txn(TxnType.expense, 100, account: bank, category: food.id),
    );
    expect(await repo.deleteAccount(bank), isFalse);
    expect((await repo.accounts()).any((a) => a.id == bank), isFalse);
    expect(
      (await repo.accounts(includeArchived: true)).any((a) => a.id == bank),
      isTrue,
    );
    expect(await repo.deleteCategory(food.id!), isFalse);
    expect((await repo.categories()).any((c) => c.id == food.id), isFalse);

    final newId = await repo.insertAccount(const Account(name: 'Ví phụ'));
    expect(await repo.deleteAccount(newId), isTrue);
    expect(
      (await repo.accounts(includeArchived: true)).any((a) => a.id == newId),
      isFalse,
    );
  });

  test('sao lưu và khôi phục', () async {
    await repo.insertTransaction(
      txn(TxnType.expense, 100, category: food.id, note: 'x'),
    );
    await repo.insertTransaction(
      txn(TxnType.transfer, 50, account: cash, to: bank),
    );
    final data = await repo.exportAll();
    final json = jsonDecode(jsonEncode(data)) as Map<String, Object?>;
    final balances = await repo.accountBalances();

    final other = await createRepo();
    await other.importAll(json);
    expect((await other.transactions()).length, 2);
    expect(await other.accountBalances(), balances);
    expect((await other.categories()).length, (await repo.categories()).length);

    expect(() => other.importAll({'app': 'khac'}), throwsFormatException);
    expect(() => other.importAll({'app': 'so_thu_chi'}), throwsFormatException);
    // Khôi phục lỗi không được làm mất dữ liệu cũ.
    expect((await other.transactions()).length, 2);
  });

  test('xuất CSV', () async {
    await repo.insertTransaction(
      txn(TxnType.expense, 100, category: food.id, note: 'Ăn "ngon", rẻ'),
    );
    final csv = await repo.exportCsv();
    expect(csv.startsWith('﻿'), isTrue);
    final lines = csv.trim().split('\n');
    expect(lines.length, 2);
    expect(lines[1], contains('"Ăn ""ngon"", rẻ"'));
    expect(lines[1], contains('Ăn uống'));
  });

  test('effectOn', () {
    final t = txn(TxnType.transfer, 10, account: 1, to: 2);
    expect(t.effectOn(1), -10);
    expect(t.effectOn(2), 10);
    expect(t.effectOn(3), 0);
    expect(txn(TxnType.income, 5, account: 1).effectOn(1), 5);
    expect(txn(TxnType.expense, 5, account: 1).effectOn(1), -5);
  });
}
