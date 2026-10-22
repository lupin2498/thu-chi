import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../capture/category_suggester.dart';
import '../../capture/voice_input.dart';
import '../../core/format.dart';
import '../../core/spoken_amount.dart';
import '../../core/text_utils.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/pickers.dart';

Future<bool?> openEditor(
  BuildContext context, {
  TransactionRecord? existing,
  TxnType initialType = TxnType.expense,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) =>
          TransactionEditor(existing: existing, initialType: initialType),
    ),
  );
}

/// Màn hình ghi chép / sửa giao dịch đầy đủ.
class TransactionEditor extends StatefulWidget {
  const TransactionEditor({
    super.key,
    this.existing,
    this.initialType = TxnType.expense,
  });

  final TransactionRecord? existing;
  final TxnType initialType;

  @override
  State<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<TransactionEditor> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final VoiceInput _voice = VoiceInput();
  late TxnType _type;
  int? _categoryId;
  int? _accountId;
  int? _toAccountId;
  late DateTime _date;
  bool _userPickedCategory = false;
  bool _saving = false;
  List<String> _recentNotes = const [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final state = context.read<AppState>();
    _type = e?.type ?? widget.initialType;
    _date = e?.date ?? DateTime.now();
    _accountId = e?.accountId ?? state.defaultAccountId();
    _toAccountId = e?.toAccountId;
    _categoryId = e?.categoryId;
    _userPickedCategory = e != null;
    if (e != null) {
      _amountCtrl.text = formatNumber(e.amount);
      _noteCtrl.text = e.note;
    }
    _voice.addListener(_onVoice);
    state.repo.recentNotes(limit: 12).then((v) {
      if (mounted) setState(() => _recentNotes = v);
    });
  }

  @override
  void dispose() {
    _voice.removeListener(_onVoice);
    _voice.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _onVoice() {
    if (mounted) setState(() {});
  }

  void _autoCategory(String text) {
    if (_userPickedCategory || _type == TxnType.transfer) return;
    final state = context.read<AppState>();
    final kind = CategoryKind.forTxn(_type);
    final c = CategorySuggester.suggest(text, state.categoriesOf(kind), kind);
    if (c != null) setState(() => _categoryId = c.id);
  }

  Future<void> _historyCategory(String text) async {
    if (_userPickedCategory || _type == TxnType.transfer) return;
    final state = context.read<AppState>();
    final id = await state.repo.lastCategoryForNote(
      text,
      CategoryKind.forTxn(_type),
    );
    if (id != null && mounted && !_userPickedCategory) {
      setState(() => _categoryId = id);
    }
  }

  Future<void> _listen() async {
    if (_voice.isListening) {
      await _voice.stop();
      return;
    }
    await _voice.start((text, isFinal) {
      var note = text;
      if (isFinal) {
        final parsed = parseSpokenAmount(text);
        if (parsed != null && parseMoneyInput(_amountCtrl.text) == 0) {
          _amountCtrl.text = formatNumber(parsed.amount);
          note = parsed.rest;
        }
      }
      _noteCtrl.text = capitalizeFirst(note);
      _autoCategory(note);
      if (isFinal) _historyCategory(note);
    });
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final amount = parseMoneyInput(_amountCtrl.text);
    if (amount <= 0) {
      showSnack(context, 'Vui lòng nhập số tiền');
      return;
    }
    if (_accountId == null) {
      showSnack(context, 'Vui lòng chọn tài khoản');
      return;
    }
    if (_type == TxnType.transfer) {
      if (_toAccountId == null) {
        showSnack(context, 'Vui lòng chọn tài khoản nhận');
        return;
      }
      if (_toAccountId == _accountId) {
        showSnack(context, 'Tài khoản nguồn và nhận phải khác nhau');
        return;
      }
    }
    var categoryId = _categoryId;
    if (_type != TxnType.transfer) {
      final kind = CategoryKind.forTxn(_type);
      if (state.categoryById(categoryId)?.kind != kind) {
        final list = state.categoriesOf(kind);
        categoryId = list.isEmpty
            ? null
            : list.firstWhere((c) => c.icon == 'other', orElse: () => list.last).id;
      }
    } else {
      categoryId = null;
    }
    setState(() => _saving = true);
    final e = widget.existing;
    final record = TransactionRecord(
      id: e?.id,
      type: _type,
      amount: amount,
      accountId: _accountId!,
      toAccountId: _type == TxnType.transfer ? _toAccountId : null,
      categoryId: categoryId,
      note: _noteCtrl.text.trim(),
      date: _date,
      createdAt: e?.createdAt,
      source: e?.source ?? TxnSource.manual,
      rawText: e?.rawText,
      bankKey: e?.bankKey,
    );
    try {
      if (_isEdit) {
        await state.updateTransaction(record);
      } else {
        await state.addTransaction(record);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Không lưu được: $err');
      }
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e?.id == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Xoá giao dịch?',
      message: 'Giao dịch ${formatMoney(e!.amount)} sẽ bị xoá.',
      confirm: 'Xoá',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<AppState>().deleteTransaction(e.id!);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final color = txnColor(_type);
    final cat = state.categoryById(_categoryId);
    final acc = state.accountById(_accountId);
    final toAcc = state.accountById(_toAccountId);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Sửa giao dịch' : 'Ghi chép'),
        actions: [
          if (_isEdit)
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
          SegmentedButton<TxnType>(
            segments: const [
              ButtonSegment(value: TxnType.expense, label: Text('Chi tiền')),
              ButtonSegment(value: TxnType.income, label: Text('Thu tiền')),
              ButtonSegment(value: TxnType.transfer, label: Text('Chuyển khoản')),
            ],
            selected: {_type},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              if (state.categoryById(_categoryId)?.kind !=
                  CategoryKind.forTxn(_type)) {
                _categoryId = null;
                _userPickedCategory = false;
              }
              _autoCategory(_noteCtrl.text);
            }),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Số tiền'),
                  TextField(
                    key: const Key('editor_amount'),
                    controller: _amountCtrl,
                    autofocus: !_isEdit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [MoneyInputFormatter()],
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      filled: false,
                      suffixText: 'đ',
                      suffixStyle: TextStyle(fontSize: 22, color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                if (_type != TxnType.transfer)
                  ListTile(
                    leading: cat == null
                        ? const CircleAvatar(child: Icon(Icons.help_outline))
                        : IconBadge(icon: cat.icon, color: cat.color),
                    title: Text(cat?.name ?? 'Chọn hạng mục'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final c = await pickCategory(
                        context,
                        kind: CategoryKind.forTxn(_type),
                        selectedId: _categoryId,
                      );
                      if (c != null) {
                        setState(() {
                          _categoryId = c.id;
                          _userPickedCategory = true;
                        });
                      }
                    },
                  ),
                ListTile(
                  leading: IconBadge(
                    icon: acc?.iconKey ?? 'wallet',
                    color: acc?.color ?? 0xFF43A047,
                  ),
                  title: Text(acc?.name ?? 'Chọn tài khoản'),
                  subtitle: Text(
                    _type == TxnType.transfer
                        ? 'Từ tài khoản'
                        : 'Số dư: ${formatMoney(state.balanceOf(_accountId))}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final a = await pickAccount(context, selectedId: _accountId);
                    if (a != null) setState(() => _accountId = a.id);
                  },
                ),
                if (_type == TxnType.transfer)
                  ListTile(
                    leading: IconBadge(
                      icon: toAcc?.iconKey ?? 'bank',
                      color: toAcc?.color ?? 0xFF1E88E5,
                    ),
                    title: Text(toAcc?.name ?? 'Chọn tài khoản nhận'),
                    subtitle: const Text('Đến tài khoản'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final a = await pickAccount(
                        context,
                        selectedId: _toAccountId,
                        excludeId: _accountId,
                        title: 'Chọn tài khoản nhận',
                      );
                      if (a != null) setState(() => _toAccountId = a.id);
                    },
                  ),
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.event)),
                  title: Text('${weekdayName(_date)}, ${formatDate(_date)}'),
                  subtitle: Text(formatTime(_date)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d == null || !context.mounted) return;
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_date),
                    );
                    setState(() {
                      _date = DateTime(
                        d.year,
                        d.month,
                        d.day,
                        t?.hour ?? _date.hour,
                        t?.minute ?? _date.minute,
                      );
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('editor_note'),
            controller: _noteCtrl,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            minLines: 1,
            onChanged: _autoCategory,
            decoration: InputDecoration(
              labelText: 'Diễn giải',
              hintText: 'VD: Ăn trưa với đồng nghiệp',
              suffixIcon: IconButton(
                tooltip: 'Nhập bằng giọng nói',
                icon: Icon(
                  _voice.isListening ? Icons.mic : Icons.mic_none,
                  color: _voice.isListening ? kExpenseColor : null,
                ),
                onPressed: _listen,
              ),
            ),
          ),
          if (_voice.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                _voice.message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_recentNotes.isNotEmpty && !_isEdit) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in _recentNotes)
                  ActionChip(
                    label: Text(n, overflow: TextOverflow.ellipsis),
                    onPressed: () {
                      _noteCtrl.text = n;
                      _autoCategory(n);
                      _historyCategory(n);
                    },
                  ),
              ],
            ),
          ],
          if (widget.existing?.rawText != null) ...[
            const SizedBox(height: 16),
            Text(
              'Thông báo gốc từ ngân hàng',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            SelectableText(
              widget.existing!.rawText!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('editor_save'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: Text(_isEdit ? 'Cập nhật' : 'Lưu'),
          ),
        ],
      ),
    );
  }
}
