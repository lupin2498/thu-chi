import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../capture/bank_apps.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accounts = state.accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Thêm tài khoản'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Card(
            child: ListTile(
              title: const Text('Tổng số dư'),
              trailing: Text(
                formatMoney(state.totalBalance),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final a in accounts)
                  ListTile(
                    leading: IconBadge(icon: a.iconKey, color: a.color),
                    title: Text(a.name),
                    subtitle: Text(
                      [
                        a.type.label,
                        if (a.bankKey != null)
                          'Tự ghi từ ${bankByKey(a.bankKey)?.name ?? a.bankKey}',
                        if (!a.includeInTotal) 'Không tính vào tổng',
                      ].join(' · '),
                    ),
                    trailing: Text(
                      formatMoney(state.balanceOf(a.id)),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: state.balanceOf(a.id) < 0 ? kExpenseColor : null,
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _AccountDetail(account: a),
                      ),
                    ),
                    onLongPress: () => _edit(context, a),
                  ),
                if (accounts.isEmpty)
                  const EmptyState(
                    icon: Icons.account_balance_wallet,
                    text: 'Chưa có tài khoản',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<String?> _edit(BuildContext context, Account? a) {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => AccountEditor(account: a)),
    );
  }
}

class _AccountDetail extends StatelessWidget {
  const _AccountDetail({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final a = state.accountById(account.id) ?? account;
    return Scaffold(
      appBar: AppBar(
        title: Text(a.name),
        actions: [
          IconButton(
            tooltip: 'Sửa',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final r = await AccountsScreen._edit(context, a);
              if (r == 'deleted' && context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('Số dư hiện tại'),
                Text(
                  formatMoney(state.balanceOf(a.id)),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _AccountTxnList(accountId: a.id!)),
        ],
      ),
    );
  }
}

class _AccountTxnList extends StatefulWidget {
  const _AccountTxnList({required this.accountId});

  final int accountId;

  @override
  State<_AccountTxnList> createState() => _AccountTxnListState();
}

class _AccountTxnListState extends State<_AccountTxnList> {
  Future<List<TransactionRecord>>? _future;
  int _rev = -1;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_rev != state.revision) {
      _rev = state.revision;
      _future = state.repo.transactions(
        accountId: widget.accountId,
        limit: 300,
      );
    }
    return Scaffold(
      body: FutureBuilder<List<TransactionRecord>>(
        future: _future,
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long,
              text: 'Chưa có giao dịch',
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = list[i];
              final effect = t.effectOn(widget.accountId);
              final cat = state.categoryById(t.categoryId);
              return ListTile(
                leading: IconBadge(
                  icon: t.type == TxnType.transfer
                      ? 'transfer'
                      : (cat?.icon ?? 'other'),
                  color: t.type == TxnType.transfer
                      ? 0xFF1E88E5
                      : (cat?.color ?? 0xFF78909C),
                ),
                title: Text(
                  t.type == TxnType.transfer
                      ? 'Chuyển khoản'
                      : (cat?.name ?? t.type.label),
                ),
                subtitle: Text(
                  '${t.note.isEmpty ? '' : '${t.note} · '}${formatDateTime(t.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  formatMoney(effect, withSign: true),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: effect < 0 ? kExpenseColor : kIncomeColor,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Thêm / sửa tài khoản.
class AccountEditor extends StatefulWidget {
  const AccountEditor({super.key, this.account});

  final Account? account;

  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  late AccountType _type;
  String? _bankKey;
  late int _color;
  late bool _includeInTotal;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    final state = context.read<AppState>();
    _nameCtrl.text = a?.name ?? '';
    _type = a?.type ?? AccountType.cash;
    _bankKey = a?.bankKey;
    _color = a?.color ?? kPalette[5];
    _includeInTotal = a?.includeInTotal ?? true;
    final bal = a == null ? 0 : state.balanceOf(a.id);
    _balanceCtrl.text = bal == 0 ? '' : formatNumber(bal.abs());
    _negative = bal < 0;
  }

  bool _negative = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Nhập tên tài khoản');
      return;
    }
    var desired = parseMoneyInput(_balanceCtrl.text);
    if (_negative) desired = -desired;
    final a = widget.account;
    int initial;
    if (a == null) {
      initial = desired;
    } else {
      // Điều chỉnh số dư: giữ nguyên lịch sử, đổi số dư ban đầu.
      final current = state.balanceOf(a.id);
      initial = a.initialBalance + (desired - current);
    }
    await state.saveAccount(
      Account(
        id: a?.id,
        name: name,
        type: _type,
        initialBalance: initial,
        bankKey: _bankKey,
        color: _color,
        icon: a?.icon,
        includeInTotal: _includeInTotal,
        sortOrder: a?.sortOrder ?? 0,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final a = widget.account;
    if (a?.id == null) return;
    final state = context.read<AppState>();
    if (state.accounts.length <= 1) {
      showSnack(context, 'Cần giữ lại ít nhất một tài khoản');
      return;
    }
    final ok = await confirmDialog(
      context,
      title: 'Xoá tài khoản "${a!.name}"?',
      message:
          'Nếu tài khoản đã có giao dịch, tài khoản sẽ được ẩn để giữ lịch sử.',
      confirm: 'Xoá',
      destructive: true,
    );
    if (!ok) return;
    final removed = await state.deleteAccount(a.id!);
    if (!mounted) return;
    showSnack(
      context,
      removed ? 'Đã xoá tài khoản' : 'Đã ẩn tài khoản (còn giao dịch)',
    );
    Navigator.pop(context, 'deleted');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.account == null ? 'Thêm tài khoản' : 'Sửa tài khoản',
        ),
        actions: [
          if (widget.account != null)
            IconButton(
              tooltip: 'Xoá',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Tên tài khoản'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _balanceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyInputFormatter()],
                  decoration: InputDecoration(
                    labelText: widget.account == null
                        ? 'Số dư ban đầu'
                        : 'Số dư hiện tại',
                    suffixText: 'đ',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Âm (nợ)'),
                selected: _negative,
                onSelected: (v) => setState(() => _negative = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AccountType>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Loại tài khoản'),
            items: [
              for (final t in AccountType.values)
                DropdownMenuItem(value: t, child: Text(t.label)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _bankKey,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Liên kết ứng dụng ngân hàng',
              helperText:
                  'Giao dịch tự động từ ngân hàng này sẽ ghi vào tài khoản này',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Không liên kết'),
              ),
              for (final b in kBankApps)
                DropdownMenuItem<String?>(value: b.key, child: Text(b.name)),
            ],
            onChanged: (v) => setState(() => _bankKey = v),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tính vào tổng số dư'),
            value: _includeInTotal,
            onChanged: (v) => setState(() => _includeInTotal = v),
          ),
          const SizedBox(height: 8),
          const Text('Màu'),
          const SizedBox(height: 8),
          _ColorPicker(
            value: _color,
            onChanged: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _save,
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in kPalette)
          InkWell(
            onTap: () => onChanged(c),
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Color(c),
              child: c == value
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Bảng màu dùng chung (cho màn hạng mục).
class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) =>
      _ColorPicker(value: value, onChanged: onChanged);
}
