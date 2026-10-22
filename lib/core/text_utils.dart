/// Tiện ích xử lý chuỗi tiếng Việt.
library;

const Map<String, String> _groups = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'A': 'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ',
  'e': 'èéẹẻẽêềếệểễ',
  'E': 'ÈÉẸẺẼÊỀẾỆỂỄ',
  'i': 'ìíịỉĩ',
  'I': 'ÌÍỊỈĨ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'O': 'ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ',
  'u': 'ùúụủũưừứựửữ',
  'U': 'ÙÚỤỦŨƯỪỨỰỬỮ',
  'y': 'ỳýỵỷỹ',
  'Y': 'ỲÝỴỶỸ',
  'd': 'đ',
  'D': 'Đ',
};

/// Bảng ký tự có dấu -> không dấu (giữ hoa/thường).
final Map<String, String> diacriticMap = () {
  final map = <String, String>{};
  _groups.forEach((base, chars) {
    for (final c in chars.split('')) {
      map[c] = base;
    }
  });
  return map;
}();

final RegExp _combining = RegExp('[̀-ͯ]');

/// Bỏ dấu tiếng Việt (giữ nguyên chữ hoa/thường).
String removeDiacritics(String input) {
  // Bỏ các dấu tổ hợp (NFD) đôi khi gặp trong SMS / bàn phím.
  final cleaned = input.replaceAll(_combining, '');
  final buffer = StringBuffer();
  for (final unit in cleaned.codeUnits) {
    final ch = String.fromCharCode(unit);
    buffer.write(diacriticMap[ch] ?? ch);
  }
  return buffer.toString();
}

/// Chuẩn hoá để so khớp: bỏ dấu, chữ thường, gộp khoảng trắng.
String normalizeForSearch(String input) {
  return removeDiacritics(input)
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Viết hoa chữ cái đầu câu.
String capitalizeFirst(String input) {
  final s = input.trim();
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}
