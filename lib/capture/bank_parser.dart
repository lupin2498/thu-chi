import '../core/text_utils.dart';
import '../data/models.dart';
import 'bank_apps.dart';

/// Kết quả trích xuất từ một thông báo / SMS biến động số dư.
class ParsedBankTxn {
  const ParsedBankTxn({
    required this.amount,
    required this.type,
    this.content,
    this.balance,
    this.bankKey,
    this.score = 0,
  });

  /// Số tiền giao dịch (đồng, > 0).
  final int amount;

  /// [TxnType.expense] hoặc [TxnType.income].
  final TxnType type;

  /// Nội dung chuyển khoản do ngân hàng gửi (ND / Nội dung / Ref...).
  final String? content;

  /// Số dư sau giao dịch nếu có.
  final int? balance;
  final String? bankKey;
  final int score;

  String? get bankName => bankByKey(bankKey)?.name;

  @override
  String toString() =>
      'ParsedBankTxn(${type.key} $amount, content: $content, balance: $balance, bank: $bankKey, score: $score)';
}

class _Candidate {
  _Candidate({
    required this.start,
    required this.end,
    required this.value,
    required this.sign,
    required this.hasCurrency,
    required this.hasGrouping,
  });

  final int start;
  final int end;
  final int value;

  /// -1, 0 (không có dấu), 1
  final int sign;
  final bool hasCurrency;
  final bool hasGrouping;
  int score = 0;
  bool isBalance = false;
}

/// Bộ phân tích thông báo biến động số dư của các ngân hàng Việt Nam.
///
/// Thuật toán giữ đồng bộ với `BankParser.kt` phía Android (cùng bộ mẫu thử
/// `test/fixtures/bank_notifications.json`).
class BankNotificationParser {
  BankNotificationParser._();

  static final RegExp _money = RegExp(
    r'(?<![A-Za-z0-9_*])(?<![0-9][:/.,\-])([+\-−]\s?)?((?:VND|VNĐ|vnd|vnđ|đ|₫)\s?)?(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2}(?!\d))?|\d+(?:[.,]\d{1,2}(?!\d))?)(?![\d/:])(\s?(?:VND|VNĐ|vnđ|vnd|Vnd|đồng|dong|đ|₫|d(?![a-zA-ZÀ-ỹ])|k(?![a-zA-ZÀ-ỹ])))?',
  );

  static final RegExp _txnLabel = RegExp(
    r'(?:^|[^a-z])(gd|ps|giao dich|so tien|so tien gd|phat sinh|thay doi|bien dong|amount|tien)\s*[:=]?\s*$',
  );
  static final RegExp _verbLabel = RegExp(
    r'(chuyen|nhan|nhan duoc|thanh toan|tru|cong|giam|tang|rut|nap|chi|mua|hoan)\s*(?:thanh cong|tien)?\s*[:=]?\s*$',
  );
  static final RegExp _balanceLabel = RegExp(
    r'(?:^|[^a-z])(sd|sdc|sdkd|so du|so du kha dung|so du hien tai|so du cuoi|sd kha dung|balance|bal|du no|han muc|kha dung)\s*(?:moi|tk|cuoi|hien tai|kha dung)?\s*[:=]?\s*$',
  );
  static final RegExp _accountLabel = RegExp(
    r'(?:^|[^a-z])(tk|stk|so tk|tai khoan|account|acc|the|card|ma gd|so gd|ma giao dich|ref|ft|so ct|so the)\s*[:=]?\s*$',
  );
  static final RegExp _contentLabel = RegExp(
    r'(?:^|[\s|.;,(\n])(nd|noi dung|noi dung gd|noi dung ck|mo ta|loi nhan|dien giai|ref|gd|chi tiet|description|remark|memo)(?:\s*[:：]\s*|\s+)',
  );
  static final RegExp _contentEnd = RegExp(
    r'(\||\n|\s+(sd|so du|so du kha dung|so gd|ma gd|ma giao dich|sd kha dung)(?![a-z0-9])|\.\s*(sd|so du|ct tu|so gd|ma gd)(?![a-z0-9]))',
  );

  static const _otpWords = [
    'otp',
    'ma xac thuc',
    'ma xac nhan',
    'mat khau',
    'smart otp',
    'khong cung cap',
  ];
  static const _promoWords = [
    'uu dai',
    'khuyen mai',
    'voucher',
    'giam gia',
    'qua tang',
    'tri an',
    'mien phi',
    'co hoi',
    'nhan ngay',
    'trung thuong',
    'hoan tien den',
    'giam den',
    'tang ngay',
  ];
  static const _txnKeywords = [
    'bien dong',
    'giao dich',
    'thanh cong',
    'da chuyen',
    'nhan duoc',
    'vua nhan',
    'bi tru',
    'duoc cong',
    'tru tien',
    'cong tien',
    'chuyen tien',
    'thanh toan',
    'ghi no',
    'ghi co',
    'vua giam',
    'vua tang',
  ];
  static const _incomeWords = [
    'nhan duoc',
    'vua nhan',
    'nhan tien',
    'da nhan',
    'nhan chuyen khoan',
    'duoc cong',
    'cong tien',
    'ghi co',
    'vua tang',
    'tang ',
    'hoan tien',
    'nap tien',
    'credit',
  ];
  static const _expenseWords = [
    'da chuyen',
    'chuyen thanh cong',
    'chuyen tien thanh cong',
    'thanh toan',
    'bi tru',
    'tru tien',
    'ghi no',
    'vua giam',
    'giam ',
    'rut tien',
    'chi tieu',
    'debit',
  ];

  /// Phân tích [text] (có thể gồm cả tiêu đề). Trả null nếu không phải giao dịch.
  ///
  /// [strict] = true với nguồn không chắc chắn (SMS, ứng dụng lạ): yêu cầu
  /// dấu hiệu rõ ràng (dấu +/- hoặc nhãn GD/PS và có từ khoá số dư).
  static ParsedBankTxn? parse(
    String text, {
    String? title,
    String? packageName,
    bool strict = false,
  }) {
    final raw = [
      if (title != null && title.trim().isNotEmpty) title.trim(),
      text.trim(),
    ].join('\n');
    if (raw.trim().isEmpty) return null;

    // Bỏ dấu tổ hợp để chuỗi gốc và chuỗi đã chuẩn hoá cùng độ dài.
    final original = raw
        .replaceAll(RegExp('[\u0300-\u036f]'), '')
        .replaceAll(RegExp('[\u00a0\u2007\u2009\u202f\t\r]'), ' ');
    final folded = foldVietnamese(original);

    if (_otpWords.any(folded.contains)) return null;

    final contentStart = _findContentStart(original, folded);
    final candidates = <_Candidate>[];
    for (final m in _money.allMatches(original)) {
      final numText = m.group(3)!;
      final value = _parseNumber(numText);
      if (value == null || value <= 0) continue;
      final signText = m.group(1)?.trim();
      final sign = signText == null
          ? 0
          : (signText == '+' ? 1 : -1);
      final cur1 = m.group(2);
      final cur2 = m.group(4)?.trim();
      final hasGrouping = RegExp(r'\d[.,]\d{3}').hasMatch(numText);
      final digitsOnly = numText.replaceAll(RegExp(r'[^0-9]'), '');
      if (!hasGrouping && digitsOnly.length > 12) continue;
      var multiplier = 1;
      final hasK = cur2 != null && cur2.toLowerCase() == 'k';
      if (hasK) multiplier = 1000;
      candidates.add(
        _Candidate(
          start: m.start,
          end: m.end,
          value: value * multiplier,
          sign: sign,
          hasCurrency: cur1 != null || (cur2 != null && !hasK),
          hasGrouping: hasGrouping || hasK,
        ),
      );
    }
    if (candidates.isEmpty) return null;

    for (final c in candidates) {
      final prefix = _segmentPrefix(folded, c.start);
      var s = 0;
      if (c.sign != 0) s += 4;
      if (c.hasCurrency) s += 3;
      if (c.hasGrouping) s += 1;
      if (_txnLabel.hasMatch(prefix)) s += 5;
      if (_verbLabel.hasMatch(prefix)) s += 2;
      if (_balanceLabel.hasMatch(prefix)) {
        s -= 20;
        c.isBalance = true;
      }
      if (_accountLabel.hasMatch(prefix)) s -= 20;
      if (!c.hasGrouping && !c.hasCurrency && c.sign == 0) s -= 3;
      if (contentStart != null && c.start > contentStart) s -= 6;
      c.score = s;
    }

    _Candidate? best;
    for (final c in candidates) {
      if (best == null || c.score > best.score) best = c;
    }
    if (best == null || best.score < 3) return null;

    final bestPrefix = _segmentPrefix(folded, best.start);
    final hasStrongLabel = _txnLabel.hasMatch(bestPrefix);
    final labeled = hasStrongLabel || _verbLabel.hasMatch(bestPrefix);
    final hasBalance = candidates.any((c) => c.isBalance) ||
        folded.contains('so du');
    final hasTxnKeyword = _txnKeywords.any(folded.contains);
    if (best.sign == 0 && !labeled) {
      // Chỉ có một con số kèm "số dư" -> thông báo số dư, không phải giao dịch.
      if (!hasTxnKeyword || hasBalance) return null;
    }

    final isPromo = _promoWords.any(folded.contains);
    if (isPromo && best.sign == 0 && !hasBalance) return null;

    if (strict) {
      final clear = best.sign != 0 || hasStrongLabel;
      final bankish = hasBalance ||
          _detectBankKey(folded) != null ||
          bankByPackage(packageName) != null;
      if (!clear || !bankish) return null;
      if (!best.hasCurrency && !best.hasGrouping) return null;
    }

    final type = _direction(best, folded);
    int? balance;
    for (final c in candidates) {
      if (c.isBalance && c.start > best.start) {
        balance = c.value;
        break;
      }
    }
    balance ??= candidates.where((c) => c.isBalance).firstOrNull?.value;

    return ParsedBankTxn(
      amount: best.value,
      type: type,
      content: _extractContent(original, folded),
      balance: balance,
      bankKey: bankByPackage(packageName)?.key ?? _detectBankKey(folded),
      score: best.score,
    );
  }

  static TxnType _direction(_Candidate best, String folded) {
    if (best.sign < 0) return TxnType.expense;
    if (best.sign > 0) return TxnType.income;
    // Không có dấu: xét từ khoá gần số tiền nhất (ưu tiên phía trước).
    int nearest(List<String> words) {
      var bestDist = 1 << 30;
      for (final w in words) {
        var idx = folded.indexOf(w);
        while (idx >= 0) {
          final dist = idx <= best.start
              ? best.start - idx
              : (idx - best.end) * 2 + 40;
          if (dist < bestDist) bestDist = dist;
          idx = folded.indexOf(w, idx + 1);
        }
      }
      return bestDist;
    }

    final inc = nearest(_incomeWords);
    final exp = nearest(_expenseWords);
    if (inc < exp) return TxnType.income;
    return TxnType.expense;
  }

  /// Phần đứng trước vị trí [index] trong cùng một đoạn (ngăn bởi | hoặc xuống dòng).
  static String _segmentPrefix(String folded, int index) {
    var startIdx = index - 32;
    if (startIdx < 0) startIdx = 0;
    var prefix = folded.substring(startIdx, index);
    final cut = prefix.lastIndexOf(RegExp(r'[|\n;]'));
    if (cut >= 0) prefix = prefix.substring(cut + 1);
    // Đoạn sau dấu chấm câu (". SD" ...).
    final dot = prefix.lastIndexOf(RegExp(r'\.\s'));
    if (dot >= 0) prefix = prefix.substring(dot + 1);
    return prefix.toLowerCase();
  }

  static int? _findContentStart(String original, String folded) {
    for (final m in _contentLabel.allMatches(folded)) {
      final after = original.substring(m.end);
      // "GD: -150,000VND" là nhãn số tiền, không phải nội dung.
      if (RegExp(r'^\s*[+\-−]?\s?(VND|VNĐ|đ)?\s?\d').hasMatch(after)) continue;
      return m.end;
    }
    return null;
  }

  static String? _extractContent(String original, String folded) {
    final start = _findContentStart(original, folded);
    if (start == null) return null;
    final rest = folded.substring(start);
    final endMatch = _contentEnd.firstMatch(rest);
    final end = endMatch == null ? original.length : start + endMatch.start;
    var content = original.substring(start, end).trim();
    content = content.replaceAll(RegExp(r'\s+'), ' ');
    // Bỏ mã tham chiếu đầu nội dung: "MBVCB.1234567.", "FT2629512345 ", "IBFT "...
    content = content.replaceFirst(
      RegExp(r'^(?:[A-Z]{2,10}\.\d{3,}\.|FT\d{6,}\s|IBFT\s|TKThe\s:\S+\s*,?\s*)'),
      '',
    );
    content = content.replaceAll(RegExp(r'^[\s:.\-]+|[\s.;,\-]+$'), '');
    if (content.isEmpty) return null;
    if (content.length > 140) content = '${content.substring(0, 140)}…';
    return content;
  }

  static String? _detectBankKey(String folded) {
    for (final b in kBankApps) {
      for (final alias in b.aliases) {
        final a = alias.trim();
        if (RegExp('(^|[^a-z])${RegExp.escape(a)}(\$|[^a-z])').hasMatch(folded)) {
          return b.key;
        }
      }
    }
    return null;
  }

  /// "1,500,000" / "1.500.000" / "1,500,000.00" / "150000" -> số nguyên đồng.
  static int? _parseNumber(String s) {
    final t = s.trim();
    String intPart;
    if (RegExp(r'^\d+$').hasMatch(t)) {
      intPart = t;
    } else if (RegExp(r'^\d+[.,]\d{1,2}$').hasMatch(t)) {
      intPart = t.split(RegExp(r'[.,]')).first;
    } else {
      final m = RegExp(r'^(\d{1,3}(?:[.,]\d{3})+)(?:[.,]\d{1,2})?$').firstMatch(t);
      if (m == null) return null;
      intPart = m.group(1)!;
    }
    final digits = intPart.replaceAll(RegExp(r'[.,]'), '');
    if (digits.isEmpty || digits.length > 15) return null;
    return int.tryParse(digits);
  }
}

/// Bỏ dấu, chữ thường, giữ nguyên độ dài chuỗi (để chỉ số khớp với chuỗi gốc).
String foldVietnamese(String input) {
  final b = StringBuffer();
  for (final unit in input.codeUnits) {
    final ch = String.fromCharCode(unit);
    final mapped = diacriticMap[ch];
    if (mapped != null) {
      b.write(mapped.toLowerCase());
      continue;
    }
    final lower = ch.toLowerCase();
    b.write(lower.length == 1 ? lower : ch);
  }
  return b.toString();
}
