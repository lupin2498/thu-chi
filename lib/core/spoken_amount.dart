import 'text_utils.dart';

/// Kết quả tách số tiền khỏi câu nói.
class SpokenAmount {
  const SpokenAmount(this.amount, this.rest);

  /// Số tiền (đồng).
  final int amount;

  /// Phần còn lại của câu (dùng làm diễn giải).
  final String rest;

  @override
  String toString() => 'SpokenAmount($amount, "$rest")';
}

const Map<String, int> _units = {
  'ty': 1000000000,
  'ti': 1000000000,
  'trieu': 1000000,
  'tr': 1000000,
  'cu': 1000000,
  'nghin': 1000,
  'ngan': 1000,
  'k': 1000,
  'lit': 100000,
  'xi': 10000,
  'dong': 1,
  'd': 1,
  'vnd': 1,
};

const Map<String, int> _digitWords = {
  'khong': 0,
  'mot': 1,
  'hai': 2,
  'ba': 3,
  'bon': 4,
  'tu': 4,
  'nam': 5,
  'lam': 5,
  'sau': 6,
  'bay': 7,
  'tam': 8,
  'chin': 9,
};

bool _isNumberWord(String t) =>
    _digitWords.containsKey(t) ||
    t == 'muoi' ||
    t == 'tram' ||
    t == 'linh' ||
    t == 'le';

/// Đổi cụm số đọc bằng chữ ("hai tram nam muoi") thành chữ số ("250").
String _wordsToDigits(String folded) {
  final tokens = folded.split(' ');
  final out = <String>[];
  var i = 0;
  while (i < tokens.length) {
    if (!_isNumberWord(tokens[i]) || tokens[i] == 'linh' || tokens[i] == 'le') {
      out.add(tokens[i]);
      i++;
      continue;
    }
    final start = i;
    var total = 0;
    var cur = 0;
    while (i < tokens.length && _isNumberWord(tokens[i])) {
      final t = tokens[i];
      final d = _digitWords[t];
      if (d != null) {
        cur += d;
      } else if (t == 'muoi') {
        cur = cur == 0 ? 10 : cur * 10;
      } else if (t == 'tram') {
        total += (cur == 0 ? 1 : cur) * 100;
        cur = 0;
      }
      i++;
    }
    final next = i < tokens.length ? tokens[i] : '';
    // Chỉ đổi khi có từ 2 từ số trở lên hoặc đứng ngay trước đơn vị tiền,
    // tránh đổi nhầm "nam", "ba", "sau"... đơn lẻ trong câu.
    if (i - start >= 2 || _units.containsKey(next)) {
      out.add((total + cur).toString());
    } else {
      out.addAll(tokens.sublist(start, i));
    }
  }
  return out.join(' ');
}

const Set<String> _fillers = {'het', 'mat', 'la', 'tien', 'gia', 'khoang'};

/// Tách số tiền trong câu nói tiếng Việt.
///
/// Ví dụ: "ăn trưa 50 nghìn" -> 50000 / "ăn trưa"; "1 triệu 2" -> 1200000;
/// "1tr5" -> 1500000; "200k" -> 200000; "hai trăm nghìn tiền điện" -> 200000.
SpokenAmount? parseSpokenAmount(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  // Chuẩn hoá: bỏ dấu, chữ thường, tách số dính chữ ("50k" -> "50 k").
  var folded = normalizeForSearch(text)
      .replaceAllMapped(RegExp(r'(\d)\s*([a-z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([a-z])(\d)'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'[^a-z0-9.,\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  folded = _wordsToDigits(folded);

  final tokens = folded.split(' ');
  int? bestStart;
  int? bestEnd;
  var bestValue = 0;
  var bestHasUnit = false;

  for (var i = 0; i < tokens.length; i++) {
    if (!RegExp(r'^\d').hasMatch(tokens[i])) continue;
    var j = i;
    var total = 0;
    var matchedUnit = false;
    var lastUnit = 0;
    while (j < tokens.length) {
      final numTok = tokens[j];
      final num = _parseNumberToken(numTok);
      if (num == null) break;
      final unitTok = j + 1 < tokens.length ? tokens[j + 1] : '';
      final unit = _units[unitTok];
      if (unit != null) {
        total += (num * unit).round();
        matchedUnit = true;
        lastUnit = unit;
        j += 2;
        if (j < tokens.length && tokens[j] == 'ruoi' && unit >= 1000) {
          total += unit ~/ 2;
          j++;
        }
        continue;
      }
      // Số lẻ sau đơn vị lớn: "1 triệu 2" = 1.200.000, "1tr5" = 1.500.000.
      if (matchedUnit && lastUnit >= 1000 && RegExp(r'^\d{1,3}$').hasMatch(numTok)) {
        final digits = numTok.length;
        var frac = 1;
        for (var k = 0; k < digits; k++) {
          frac *= 10;
        }
        total += num.toInt() * lastUnit ~/ frac;
        j++;
        lastUnit = 0;
      }
      break;
    }
    if (matchedUnit && total > 0) {
      if (!bestHasUnit || total > bestValue) {
        bestStart = i;
        bestEnd = j;
        bestValue = total;
        bestHasUnit = true;
      }
      i = j - 1;
      continue;
    }
    // Không có đơn vị: số có nhóm nghìn (50.000) hoặc >= 1000, hoặc số nhỏ ở cuối câu.
    final num = _parseNumberToken(tokens[i]);
    if (num == null) continue;
    final grouped = RegExp(r'\d[.,]\d{3}').hasMatch(tokens[i]);
    int? value;
    if (grouped || num >= 1000) {
      value = num.round();
    } else if (i == tokens.length - 1 && num >= 1 && num < 1000) {
      value = (num * 1000).round();
    }
    if (value != null && value > 0 && bestStart == null) {
      bestStart = i;
      bestEnd = i + 1;
      bestValue = value;
    }
  }

  if (bestStart == null || bestValue <= 0) return null;
  final restTokens = [
    ...tokens.sublist(0, bestStart),
    ...tokens.sublist(bestEnd!),
  ];
  while (restTokens.isNotEmpty && _fillers.contains(restTokens.last)) {
    restTokens.removeLast();
  }
  final rest = _restFromOriginal(text, restTokens);
  return SpokenAmount(bestValue, rest);
}

double? _parseNumberToken(String t) {
  if (RegExp(r'^\d{1,3}([.,]\d{3})+$').hasMatch(t)) {
    return double.parse(t.replaceAll(RegExp(r'[.,]'), ''));
  }
  if (RegExp(r'^\d+[.,]\d+$').hasMatch(t)) {
    return double.parse(t.replaceAll(',', '.'));
  }
  if (RegExp(r'^\d+$').hasMatch(t)) return double.parse(t);
  return null;
}

/// Lấy lại các từ còn lại theo chữ gốc (giữ dấu) nếu có thể.
String _restFromOriginal(String original, List<String> restTokens) {
  final words = original
      .replaceAll(RegExp(r'[,;]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final kept = <String>[];
  var ri = 0;
  for (final w in words) {
    if (ri >= restTokens.length) break;
    final f = normalizeForSearch(w).replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (f.isNotEmpty && f == restTokens[ri]) {
      kept.add(w);
      ri++;
    }
  }
  final joined = kept.length == restTokens.length
      ? kept.join(' ')
      : restTokens.join(' ');
  return capitalizeFirst(joined.trim());
}
