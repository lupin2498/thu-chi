import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final NumberFormat _grouping = NumberFormat.decimalPattern('vi_VN');

/// 150000 -> "150.000"
String formatNumber(int value) => _grouping.format(value);

/// 150000 -> "150.000 đ"
String formatMoney(int value, {bool withSign = false}) {
  final abs = formatNumber(value.abs());
  if (value < 0) return '-$abs đ';
  if (withSign && value > 0) return '+$abs đ';
  return '$abs đ';
}

/// Dạng rút gọn cho biểu đồ: 1.500.000 -> "1,5tr", 150.000 -> "150k".
String formatCompact(int value) {
  final v = value.abs();
  final sign = value < 0 ? '-' : '';
  if (v >= 1000000000) {
    return '$sign${_trim(v / 1000000000)} tỷ';
  }
  if (v >= 1000000) return '$sign${_trim(v / 1000000)}tr';
  if (v >= 1000) return '$sign${_trim(v / 1000)}k';
  return '$sign$v';
}

String _trim(double v) {
  final s = v.toStringAsFixed(v >= 100 ? 0 : 1);
  final t = s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  return t.replaceAll('.', ',');
}

/// Đọc số tiền người dùng gõ ("150.000", "150000") -> 150000. Trả 0 nếu rỗng.
int parseMoneyInput(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 0;
  // Giới hạn 15 chữ số để tránh tràn số.
  final safe = digits.length > 15 ? digits.substring(0, 15) : digits;
  return int.parse(safe);
}

/// Định dạng ô nhập số tiền theo nhóm nghìn khi gõ.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final limited = trimmed.length > 13 ? trimmed.substring(0, 13) : trimmed;
    final formatted = formatNumber(int.parse(limited));

    // Giữ vị trí con trỏ theo số chữ số đứng sau nó.
    final cursor = newValue.selection.baseOffset < 0
        ? newValue.text.length
        : newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsAfterCursor = newValue.text
        .substring(cursor)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length
        .clamp(0, limited.length);
    var offset = formatted.length;
    var seen = 0;
    while (offset > 0 && seen < digitsAfterCursor) {
      offset--;
      if (RegExp(r'[0-9]').hasMatch(formatted[offset])) seen++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

final DateFormat _dayFmt = DateFormat('dd/MM/yyyy');
final DateFormat _timeFmt = DateFormat('HH:mm');

String formatDate(DateTime d) => _dayFmt.format(d);
String formatTime(DateTime d) => _timeFmt.format(d);
String formatDateTime(DateTime d) => '${formatTime(d)} ${formatDate(d)}';

const _weekdays = [
  'Thứ hai',
  'Thứ ba',
  'Thứ tư',
  'Thứ năm',
  'Thứ sáu',
  'Thứ bảy',
  'Chủ nhật',
];

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

/// "Hôm nay", "Hôm qua" hoặc "Thứ hai, 20/10/2026".
String friendlyDay(DateTime d, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final day = dateOnly(d);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  return '${weekdayName(d)}, ${formatDate(d)}';
}

String monthLabel(DateTime m) => 'Tháng ${m.month}/${m.year}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

/// Đầu tháng kế tiếp (mốc kết thúc, không bao gồm).
DateTime nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1);

int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;
