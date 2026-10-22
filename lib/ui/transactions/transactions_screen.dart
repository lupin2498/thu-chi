import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../editor/transaction_editor.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/txn_tile.dart';

/// Sổ giao dịch: danh sách theo tháng, nhóm theo ngày.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    this.categoryId,
    this.title,
    this.start,
    this.end,
    this.type,
  });

  /// Lọc theo hạng mục (mở từ báo cáo).
  final int? categoryId;
  final String? title;
  final DateTime? start;
  final DateTime? end;
  final TxnType? type;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  DateTime _month = monthStart(DateTime.now());
  TxnType? _type;
  int? _accountId;
  String _search = '';
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  Future<List<TransactionRecord>>? _future;
  String _key = '';

  bool get _fixedRange => widget.start != null && widget.end != null;

  @override
  void initState() {
    super.initState();
    _type = widget.type;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<TransactionRecord>> _load(AppState s) {
    final searchAll = _search.trim().isNotEmpty;
    return s.repo.transactions(
      start: _fixedRange ? widget.start : (searchAll ? null : _month),
      end: _fixedRange
          ? widget.end
          : (searchAll ? null : nextMonthStart(_month)),
      type: _type,
      accountId: _accountId,
      categoryId: widget.categoryId,
      search: _search,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final key = '${state.revision}|$_month|$_type|$_accountId|$_search';
    if (key != _key || _future == null) {
      _key = key;
      _future = _load(state);
    }
    final embedded = widget.categoryId == null && !_fixedRange;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !embedded,
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Tìm diễn giải, số tiền…',
                  hintStyle: TextStyle(color: Colors.white70),
                  filled: false,
                  border: InputBorder.none,
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) setState(() => _search = v);
                  });
                },
              )
            : Text(widget.title ?? 'Sổ giao dịch'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Đóng tìm kiếm' : 'Tìm kiếm',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchCtrl.clear();
                _search = '';
              }
            }),
          ),
          if (embedded)
            PopupMenuButton<String>(
              tooltip: 'Lọc',
              icon: Icon(
                _type != null || _accountId != null
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
              ),
              onSelected: (v) => setState(() {
                if (v == 'all') _type = null;
                if (v == 'expense') _type = TxnType.expense;
                if (v == 'income') _type = TxnType.income;
                if (v == 'transfer') _type = TxnType.transfer;
                if (v.startsWith('acc:')) {
                  final id = int.tryParse(v.substring(4));
                  _accountId = id;
                }
                if (v == 'acc_all') _accountId = null;
              }),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  enabled: false,
                  child: Text('Loại giao dịch'),
                ),
                CheckedPopupMenuItem(
                  value: 'all',
                  checked: _type == null,
                  child: const Text('Tất cả'),
                ),
                CheckedPopupMenuItem(
                  value: 'expense',
                  checked: _type == TxnType.expense,
                  child: const Text('Chi tiền'),
                ),
                CheckedPopupMenuItem(
                  value: 'income',
                  checked: _type == TxnType.income,
                  child: const Text('Thu tiền'),
                ),
                CheckedPopupMenuItem(
                  value: 'transfer',
                  checked: _type == TxnType.transfer,
                  child: const Text('Chuyển khoản'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(enabled: false, child: Text('Tài khoản')),
                CheckedPopupMenuItem(
                  value: 'acc_all',
                  checked: _accountId == null,
                  child: const Text('Tất cả tài khoản'),
                ),
                for (final a in state.accounts)
                  CheckedPopupMenuItem(
                    value: 'acc:${a.id}',
                    checked: _accountId == a.id,
                    child: Text(a.name),
                  ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_fixedRange && _search.trim().isEmpty)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: Center(
                child: MonthSwitcher(
                  month: _month,
                  onChanged: (m) => setState(() => _month = m),
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<List<TransactionRecord>>(
              future: _future,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snap.data!;
                return _GroupedList(
                  list: list,
                  showSummary: true,
                  emptyText: _search.isNotEmpty
                      ? 'Không tìm thấy giao dịch phù hợp'
                      : 'Chưa có giao dịch trong ${monthLabel(_month).toLowerCase()}',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.list,
    required this.showSummary,
    required this.emptyText,
  });

  final List<TransactionRecord> list;
  final bool showSummary;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return ListView(
        children: [EmptyState(icon: Icons.receipt_long, text: emptyText)],
      );
    }
    var income = 0;
    var expense = 0;
    for (final t in list) {
      if (t.type == TxnType.income) income += t.amount;
      if (t.type == TxnType.expense) expense += t.amount;
    }
    // Nhóm theo ngày (danh sách đã sắp xếp mới nhất trước).
    final groups = <DateTime, List<TransactionRecord>>{};
    for (final t in list) {
      groups.putIfAbsent(dateOnly(t.date), () => []).add(t);
    }
    final days = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: days.length + (showSummary ? 1 : 0),
      itemBuilder: (context, index) {
        if (showSummary && index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 8,
                ),
                child: Row(
                  children: [
                    _SummaryCell(
                      label: 'Thu',
                      value: income,
                      color: kIncomeColor,
                    ),
                    _SummaryCell(
                      label: 'Chi',
                      value: expense,
                      color: kExpenseColor,
                    ),
                    _SummaryCell(
                      label: 'Chênh lệch',
                      value: income - expense,
                      color: null,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final day = days[index - (showSummary ? 1 : 0)];
        final items = groups[day]!;
        var dayIncome = 0;
        var dayExpense = 0;
        for (final t in items) {
          if (t.type == TxnType.income) dayIncome += t.amount;
          if (t.type == TxnType.expense) dayExpense += t.amount;
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        day.day.toString().padLeft(2, '0'),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              friendlyDay(day),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Tháng ${day.month}/${day.year}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (dayIncome > 0)
                            AmountText(
                              dayIncome,
                              type: TxnType.income,
                              style: const TextStyle(fontSize: 13),
                            ),
                          if (dayExpense > 0)
                            AmountText(
                              dayExpense,
                              type: TxnType.expense,
                              style: const TextStyle(fontSize: 13),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 8),
                for (final t in items) _DismissibleTxn(txn: t),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(value),
              style: TextStyle(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _DismissibleTxn extends StatelessWidget {
  const _DismissibleTxn({required this.txn});

  final TransactionRecord txn;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('txn-${txn.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: kExpenseColor,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => confirmDialog(
        context,
        title: 'Xoá giao dịch?',
        message:
            '${txn.type.label} ${formatMoney(txn.amount)}${txn.note.isNotEmpty ? ' – ${txn.note}' : ''}',
        confirm: 'Xoá',
        destructive: true,
      ),
      onDismissed: (_) async {
        final state = context.read<AppState>();
        final messenger = ScaffoldMessenger.maybeOf(context);
        await state.deleteTransaction(txn.id!);
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('Đã xoá giao dịch'),
              action: SnackBarAction(
                label: 'Hoàn tác',
                onPressed: () => state.restoreTransaction(txn),
              ),
            ),
          );
      },
      child: TxnTile(
        txn: txn,
        onTap: () => openEditor(context, existing: txn),
      ),
    );
  }
}
