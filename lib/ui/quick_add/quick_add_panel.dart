import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../capture/bank_apps.dart';
import '../../capture/capture_channel.dart';
import '../../capture/category_suggester.dart';
import '../../capture/voice_input.dart';
import '../../core/format.dart';
import '../../core/spoken_amount.dart';
import '../../core/text_utils.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/pickers.dart';

enum QuickAddOutcome { saved, later, discarded, cancelled }

/// Khung ghi nhanh: số tiền điền sẵn, micro tự bật để nói nội dung.
class QuickAddPanel extends StatefulWidget {
  const QuickAddPanel({
    super.key,
    this.capture,
    required this.onDone,
    this.autoListen,
    this.voice,
    this.initialType = TxnType.expense,
  });

  /// Giao dịch bắt từ thông báo ngân hàng (null = ghi nhanh thủ công).
  final CaptureData? capture;
  final ValueChanged<QuickAddOutcome> onDone;

  /// Ghi đè cài đặt tự bật micro (dùng cho test).
  final bool? autoListen;
  final VoiceInput? voice;
  final TxnType initialType;

  @override
  State<QuickAddPanel> createState() => _QuickAddPanelState();
}

class _QuickAddPanelState extends State<QuickAddPanel> {
  late final VoiceInput _voice = widget.voice ?? VoiceInput();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _noteFocus = FocusNode();

  late TxnType _type;
  int? _categoryId;
  bool _userPickedCategory = false;
  int? _accountId;
  late DateTime _date;
  bool _saving = false;
  int? _countdown;
  Timer? _countdownTimer;
  String? _error;

  bool get _fromBank => widget.capture != null;

  @override
  void initState() {
    super.initState();
    final c = widget.capture;
    _type = c?.type ?? widget.initialType;
    _date = c?.time ?? DateTime.now();
    if (c != null && c.amount > 0) _amountCtrl.text = formatNumber(c.amount);
    final state = context.read<AppState>();
    _accountId = state.defaultAccountId(bankKey: c?.bankKey);
    _suggestCategory('');
    _voice.addListener(_onVoiceChanged);
    final auto = widget.autoListen ?? state.settings.autoListen;
    if (auto) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _startListening();
        });
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _voice.removeListener(_onVoiceChanged);
    if (widget.voice == null) _voice.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _onVoiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startListening() async {
    _cancelCountdown();
    final ok = await _voice.start(_onSpeech);
    if (!ok && mounted) {
      // Không có micro -> mở bàn phím để gõ.
      _noteFocus.requestFocus();
    }
  }

  void _onSpeech(String text, bool isFinal) {
    if (!mounted) return;
    var note = text;
    if (!_fromBank && isFinal) {
      // Ghi thủ công: hiểu cả số tiền trong câu nói ("ăn trưa 50 nghìn").
      final parsed = parseSpokenAmount(text);
      if (parsed != null && parseMoneyInput(_amountCtrl.text) == 0) {
        _amountCtrl.text = formatNumber(parsed.amount);
        note = parsed.rest;
      }
    }
    if (note.isNotEmpty || isFinal) {
      final v = capitalizeFirst(note);
      _noteCtrl.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }
    _suggestCategory(note);
    if (isFinal) {
      _suggestFromHistory(note);
      final state = context.read<AppState>();
      if (state.settings.autoSaveAfterVoice &&
          note.trim().isNotEmpty &&
          parseMoneyInput(_amountCtrl.text) > 0) {
        _startCountdown();
      }
    }
    setState(() {});
  }

  void _suggestCategory(String text) {
    if (_userPickedCategory) return;
    final state = context.read<AppState>();
    final kind = CategoryKind.forTxn(_type);
    final suggested = CategorySuggester.suggest(
      text,
      state.categoriesOf(kind),
      kind,
    );
    if (suggested != null) {
      _categoryId = suggested.id;
    } else if (_categoryId == null ||
        state.categoryById(_categoryId)?.kind != kind) {
      _categoryId = _defaultCategory(state, kind)?.id;
    }
  }

  Future<void> _suggestFromHistory(String text) async {
    if (text.trim().isEmpty) return;
    final state = context.read<AppState>();
    final id = await state.repo.lastCategoryForNote(
      text,
      CategoryKind.forTxn(_type),
    );
    if (!mounted || id == null || _userPickedCategory) return;
    if (state.categoryById(id)?.archived == false) {
      setState(() => _categoryId = id);
    }
  }

  Category? _defaultCategory(AppState state, CategoryKind kind) {
    final list = state.categoriesOf(kind);
    if (list.isEmpty) return null;
    if (_fromBank) {
      // Chuyển khoản ngân hàng chưa rõ mục đích -> "Chuyển tiền"/"Nhận chuyển khoản".
      for (final c in list) {
        if (c.icon == 'transfer') return c;
      }
    }
    for (final c in list) {
      if (c.icon == 'other') return c;
    }
    return list.last;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 3);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final next = (_countdown ?? 0) - 1;
      if (next <= 0) {
        t.cancel();
        setState(() => _countdown = null);
        _save();
      } else {
        setState(() => _countdown = next);
      }
    });
  }

  void _cancelCountdown() {
    if (_countdown == null) return;
    _countdownTimer?.cancel();
    setState(() => _countdown = null);
  }

  Future<void> _save() async {
    if (_saving) return;
    _cancelCountdown();
    final amount = parseMoneyInput(_amountCtrl.text);
    final state = context.read<AppState>();
    if (amount <= 0) {
      setState(() => _error = 'Nhập số tiền');
      return;
    }
    final accountId = _accountId ?? state.defaultAccountId();
    if (accountId == null) {
      setState(() => _error = 'Chưa có tài khoản nào, hãy tạo trong mục Khác');
      return;
    }
    final kind = CategoryKind.forTxn(_type);
    var categoryId = _categoryId;
    if (state.categoryById(categoryId)?.kind != kind) {
      categoryId = _defaultCategory(state, kind)?.id;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await _voice.stop();
    final c = widget.capture;
    try {
      await state.addTransaction(
        TransactionRecord(
          type: _type,
          amount: amount,
          accountId: accountId,
          categoryId: categoryId,
          note: _noteCtrl.text.trim(),
          date: _date,
          source: c != null ? TxnSource.auto : TxnSource.voice,
          rawText: c?.rawText,
          bankKey: c?.bankKey,
        ),
      );
      if (c != null) await state.dismissCapture(c.id);
      HapticFeedback.lightImpact();
      widget.onDone(QuickAddOutcome.saved);
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Không lưu được: $e';
        });
      }
    }
  }

  Future<void> _discard() async {
    _cancelCountdown();
    await _voice.cancel();
    final c = widget.capture;
    if (c != null) {
      if (!mounted) return;
      await context.read<AppState>().dismissCapture(c.id);
    }
    widget.onDone(QuickAddOutcome.discarded);
  }

  Future<void> _later() async {
    _cancelCountdown();
    await _voice.cancel();
    widget.onDone(
      _fromBank ? QuickAddOutcome.later : QuickAddOutcome.cancelled,
    );
  }

  Future<void> _pickCategory() async {
    _cancelCountdown();
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
  }

  Future<void> _pickAccount() async {
    _cancelCountdown();
    final a = await pickAccount(context, selectedId: _accountId);
    if (a != null) setState(() => _accountId = a.id);
  }

  Future<void> _pickDate() async {
    _cancelCountdown();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final c = widget.capture;
    final kind = CategoryKind.forTxn(_type);
    final cats = state.categoriesOf(kind);
    final selectedCat = state.categoryById(_categoryId);
    final chips = <Category>[
      ?selectedCat,
      ...cats.where((x) => x.id != _categoryId).take(7),
    ];
    final account = state.accountById(_accountId);
    final color = txnColor(_type);
    final listening = _voice.isListening;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconBadge(
              icon: c != null ? 'bank' : 'wallet',
              color: c != null ? 0xFF1565C0 : 0xFF43A047,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c != null ? 'Giao dịch ${c.bankName}' : 'Ghi chép nhanh',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    c != null
                        ? 'Đã trích xuất số tiền · ${formatTime(c.time)}'
                        : 'Nói "ăn trưa 50 nghìn" hoặc gõ',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: c != null ? 'Để sau' : 'Đóng',
              onPressed: _saving ? null : _later,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<TxnType>(
          segments: const [
            ButtonSegment(
              value: TxnType.expense,
              label: Text('Chi tiền'),
              icon: Icon(Icons.arrow_upward),
            ),
            ButtonSegment(
              value: TxnType.income,
              label: Text('Thu tiền'),
              icon: Icon(Icons.arrow_downward),
            ),
          ],
          selected: {_type},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            _cancelCountdown();
            setState(() {
              _type = s.first;
              _userPickedCategory = false;
              _categoryId = null;
              _suggestCategory(_noteCtrl.text);
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('quick_amount'),
          controller: _amountCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [MoneyInputFormatter()],
          textAlign: TextAlign.center,
          onTap: _cancelCountdown,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: '0',
            suffixText: 'đ',
            suffixStyle: TextStyle(color: color, fontSize: 20),
            prefixIcon: Icon(
              _type == TxnType.expense ? Icons.remove : Icons.add,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('quick_note'),
          controller: _noteCtrl,
          focusNode: _noteFocus,
          textCapitalization: TextCapitalization.sentences,
          onTap: () {
            _cancelCountdown();
            if (listening) _voice.stop();
          },
          onChanged: (v) {
            _cancelCountdown();
            setState(() => _suggestCategory(v));
          },
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: 'Nội dung',
            hintText: listening
                ? 'Đang nghe…'
                : 'Nói hoặc gõ tên khoản (vd: Ăn trưa)',
            suffixIcon: _MicButton(
              listening: listening,
              level: _voice.level,
              onPressed: () {
                if (listening) {
                  _voice.stop();
                } else {
                  _noteFocus.unfocus();
                  _startListening();
                }
              },
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          child: _voice.message.isEmpty
              ? const SizedBox(height: 4)
              : Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    _voice.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: listening ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
        ),
        if (c?.content != null && c!.content!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.notes, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ND: ${c.content}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _cancelCountdown();
                    _voice.stop();
                    setState(() {
                      _noteCtrl.text = capitalizeFirst(c.content!);
                      _suggestCategory(c.content!);
                    });
                  },
                  child: const Text('Dùng'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final cat in chips)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: Icon(
                      appIcon(cat.icon),
                      size: 18,
                      color: Color(cat.color),
                    ),
                    label: Text(cat.name),
                    selected: cat.id == _categoryId,
                    onSelected: (_) {
                      _cancelCountdown();
                      setState(() {
                        _categoryId = cat.id;
                        _userPickedCategory = true;
                      });
                    },
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.apps, size: 18),
                label: const Text('Tất cả'),
                onPressed: _pickCategory,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ActionChip(
                avatar: Icon(appIcon(account?.iconKey ?? 'wallet'), size: 18),
                label: Text(
                  account?.name ?? 'Chọn tài khoản',
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: _pickAccount,
              ),
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.schedule, size: 18),
              label: Text(
                dateOnly(_date) == dateOnly(DateTime.now())
                    ? formatTime(_date)
                    : '${formatTime(_date)} ${formatDate(_date)}',
              ),
              onPressed: _pickDate,
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: kExpenseColor)),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (c != null)
              TextButton(
                onPressed: _saving ? null : _discard,
                child: const Text('Bỏ qua'),
              ),
            TextButton(
              onPressed: _saving ? null : _later,
              child: Text(c != null ? 'Để sau' : 'Huỷ'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                key: const Key('quick_save'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_countdown != null ? 'Lưu ($_countdown)' : 'Lưu'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.level,
    required this.onPressed,
  });

  final bool listening;
  final double level;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (listening)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 34 + 14 * level,
              height: 34 + 14 * level,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kExpenseColor.withValues(alpha: 0.18),
              ),
            ),
          IconButton(
            key: const Key('quick_mic'),
            tooltip: listening ? 'Dừng nghe' : 'Nói nội dung',
            onPressed: onPressed,
            icon: Icon(
              listening ? Icons.mic : Icons.mic_none,
              color: listening ? kExpenseColor : primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mở khung ghi nhanh dạng bottom sheet trong ứng dụng.
Future<QuickAddOutcome?> showQuickAddSheet(
  BuildContext context, {
  CaptureData? capture,
  TxnType initialType = TxnType.expense,
}) {
  return showModalBottomSheet<QuickAddOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: QuickAddPanel(
          capture: capture,
          initialType: initialType,
          onDone: (o) => Navigator.of(ctx).pop(o),
        ),
      ),
    ),
  );
}

/// Tên ngân hàng hiển thị cho mã gói (dùng ở danh sách chờ).
String bankLabel(CaptureData c) =>
    bankByKey(c.bankKey)?.name ??
    bankByPackage(c.packageName)?.name ??
    'Ngân hàng';
