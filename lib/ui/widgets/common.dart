import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../theme.dart';

/// Số tiền có màu theo loại giao dịch.
class AmountText extends StatelessWidget {
  const AmountText(
    this.amount, {
    super.key,
    this.type,
    this.style,
    this.hidden = false,
    this.showSign = true,
  });

  final int amount;
  final TxnType? type;
  final TextStyle? style;
  final bool hidden;
  final bool showSign;

  @override
  Widget build(BuildContext context) {
    final color = type == null ? null : txnColor(type!);
    String text;
    if (hidden) {
      text = '••••••';
    } else if (type == TxnType.expense && showSign) {
      text = '-${formatMoney(amount)}';
    } else if (type == TxnType.income && showSign) {
      text = '+${formatMoney(amount)}';
    } else {
      text = formatMoney(amount);
    }
    return Text(
      text,
      style: (style ?? const TextStyle(fontWeight: FontWeight.w600)).copyWith(
        color: color ?? style?.color,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Thanh chuyển tháng ‹ Tháng 10/2026 ›.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    super.key,
    required this.month,
    required this.onChanged,
    this.yearMode = false,
    this.color,
  });

  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final bool yearMode;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final label = yearMode ? 'Năm ${month.year}' : monthLabel(month);
    DateTime shift(int d) => yearMode
        ? DateTime(month.year + d)
        : DateTime(month.year, month.month + d);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: yearMode ? 'Năm trước' : 'Tháng trước',
          icon: Icon(Icons.chevron_left, color: color),
          onPressed: () => onChanged(shift(-1)),
        ),
        Flexible(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: month,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                helpText: yearMode ? 'Chọn năm' : 'Chọn tháng',
                initialDatePickerMode: yearMode
                    ? DatePickerMode.year
                    : DatePickerMode.day,
              );
              if (picked != null) {
                onChanged(
                  yearMode ? DateTime(picked.year) : monthStart(picked),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: yearMode ? 'Năm sau' : 'Tháng sau',
          icon: Icon(Icons.chevron_right, color: color),
          onPressed: () => onChanged(shift(1)),
        ),
      ],
    );
  }
}

/// Thẻ có tiêu đề.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: color),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// Hiện thông báo ngắn.
void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Đồng ý',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: kExpenseColor)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Hộp thoại nhập chữ/số tiền (tự quản lý controller để không bị dùng sau khi huỷ).
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String? suffix,
  bool money = false,
  int maxLines = 1,
  String confirm = 'Lưu',
  bool pasteButton = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      initial: initial,
      hint: hint,
      suffix: suffix,
      money: money,
      maxLines: maxLines,
      confirm: confirm,
      pasteButton: pasteButton,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.suffix,
    required this.money,
    required this.maxLines,
    required this.confirm,
    required this.pasteButton,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? suffix;
  final bool money;
  final int maxLines;
  final String confirm;
  final bool pasteButton;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty && mounted) {
      setState(() => _ctrl.text = text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: widget.maxLines,
        keyboardType: widget.money ? TextInputType.number : null,
        inputFormatters: widget.money ? [MoneyInputFormatter()] : null,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixText: widget.suffix,
        ),
      ),
      actions: [
        if (widget.pasteButton)
          TextButton.icon(
            onPressed: _paste,
            icon: const Icon(Icons.content_paste),
            label: const Text('Dán'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
