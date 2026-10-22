import '../core/text_utils.dart';
import '../data/models.dart';

/// Gợi ý hạng mục từ nội dung người dùng nói/gõ (không dấu, theo từ khoá).
class CategorySuggester {
  CategorySuggester._();

  /// Thứ tự quan trọng: mục cụ thể đứng trước mục chung.
  static const List<(String, List<String>)> _expense = [
    (
      'coffee',
      [
        'ca phe',
        'cafe',
        'cf',
        'coffee',
        'tra sua',
        'nuoc ngot',
        'sinh to',
        'tra da',
        'nuoc mia',
        'highlands',
        'starbucks',
        'phuc long',
        'cong ca phe',
        'tra chanh',
        'do uong',
        'nuoc ep',
      ],
    ),
    ('fuel', ['xang', 'do xang', 'dau xe', 'nhot']),
    (
      'transport',
      [
        'grab',
        'be',
        'xanh sm',
        'taxi',
        'xe om',
        'gui xe',
        've xe',
        've tau',
        'xe buyt',
        'xe bus',
        'bus',
        'phi cau duong',
        'vetc',
        'do xe',
        'gojek',
        'di chuyen',
        'sua xe',
        'rua xe',
      ],
    ),
    (
      'market',
      [
        'di cho',
        'cho',
        'sieu thi',
        'thit',
        'rau',
        'trai cay',
        'hoa qua',
        'winmart',
        'bach hoa xanh',
        'coopmart',
        'gao',
        'trung',
        'ca thu',
        'mua do an',
        'thuc pham',
      ],
    ),
    (
      'food',
      [
        'an',
        'com',
        'pho',
        'bun',
        'mien',
        'banh',
        'an sang',
        'an trua',
        'an toi',
        'an vat',
        'nhau',
        'lau',
        'nuong',
        'bia',
        'quan an',
        'nha hang',
        'do an',
        'grabfood',
        'shopeefood',
        'baemin',
        'kfc',
        'lotteria',
        'pizza',
        'ga ran',
        'chao',
        'xoi',
        'hu tieu',
        'mi',
        'banh mi',
        'oc',
        'buffet',
        'an uong',
      ],
    ),
    ('electric', ['tien dien', 'dien']),
    ('water', ['tien nuoc', 'nuoc sinh hoat']),
    (
      'internet',
      [
        'internet',
        'wifi',
        'mang',
        'cuoc dien thoai',
        'nap dien thoai',
        'nap the',
        '4g',
        '5g',
        'data',
        'viettel',
        'vinaphone',
        'mobifone',
        'fpt',
        'tien mang',
      ],
    ),
    (
      'bill',
      ['hoa don', 'gas', 'tien rac', 'phi quan ly', 'truyen hinh', 'tien ich'],
    ),
    (
      'home',
      [
        'tien nha',
        'thue nha',
        'tien phong',
        'sua nha',
        'do gia dung',
        'noi that',
      ],
    ),
    (
      'health',
      [
        'thuoc',
        'kham',
        'benh vien',
        'nha thuoc',
        'bac si',
        'nha khoa',
        'rang',
        'vitamin',
        'xet nghiem',
        'suc khoe',
      ],
    ),
    (
      'education',
      [
        'hoc phi',
        'hoc',
        'sach',
        'khoa hoc',
        'truong',
        'lop',
        'van phong pham',
        'hoc them',
      ],
    ),
    (
      'entertainment',
      [
        'phim',
        'xem phim',
        'cgv',
        'lotte cinema',
        'game',
        'karaoke',
        'netflix',
        'spotify',
        'youtube',
        'giai tri',
        'concert',
        'bida',
      ],
    ),
    (
      'travel',
      ['du lich', 'khach san', 'homestay', 've may bay', 'resort', 'tour'],
    ),
    (
      'gift',
      [
        'qua',
        'tang qua',
        'sinh nhat',
        'dam cuoi',
        'mung cuoi',
        'dam hieu',
        'hieu hi',
        'phong bi',
        'bieu',
        'li xi',
        'mung tuoi',
        'tu thien',
      ],
    ),
    (
      'family',
      ['bim', 'sua cho con', 'ta', 'do choi', 'bo me', 'gia dinh', 'con'],
    ),
    (
      'beauty',
      [
        'cat toc',
        'goi dau',
        'lam mong',
        'spa',
        'my pham',
        'son',
        'nuoc hoa',
        'lam dep',
        'toc',
      ],
    ),
    (
      'sport',
      [
        'gym',
        'the thao',
        'bong da',
        'cau long',
        'boi',
        'yoga',
        'tennis',
        'pickleball',
      ],
    ),
    ('insurance', ['bao hiem']),
    ('loan', ['tra no', 'cho vay', 'tra gop', 'no']),
    (
      'shopping',
      [
        'mua',
        'shopee',
        'lazada',
        'tiki',
        'tiktok',
        'quan ao',
        'ao',
        'quan',
        'giay',
        'dep',
        'tui',
        'dong ho',
        'mua sam',
        'dien thoai moi',
        'laptop',
      ],
    ),
    ('transfer', ['chuyen tien', 'chuyen khoan', 'ck']),
  ];

  static const List<(String, List<String>)> _income = [
    ('salary', ['luong', 'tien luong']),
    ('bonus', ['thuong', 'tien thuong']),
    ('refund', ['hoan tien', 'hoan', 'refund']),
    ('interest', ['lai', 'lai suat', 'tiet kiem', 'co tuc']),
    ('loan', ['thu no', 'tra no', 'di vay', 'vay']),
    ('sell', ['ban', 'ban hang', 'doanh thu', 'thanh ly']),
    ('gift', ['duoc cho', 'duoc tang', 'li xi', 'mung tuoi', 'bieu', 'qua']),
    ('transfer', ['nhan chuyen khoan', 'chuyen khoan', 'chuyen tien', 'ck']),
  ];

  /// Khoá biểu tượng gợi ý cho [text], hoặc null nếu không khớp.
  static String? suggestIcon(String text, CategoryKind kind) {
    final n =
        ' ${normalizeForSearch(text).replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')} '
            .replaceAll(RegExp(r'\s+'), ' ');
    if (n.trim().isEmpty) return null;
    final table = kind == CategoryKind.income ? _income : _expense;
    // Ưu tiên cụm từ dài khớp trước (vd "an trua" hơn "an").
    String? bestIcon;
    var bestLen = 0;
    for (final (icon, words) in table) {
      for (final w in words) {
        if (w.length > bestLen && n.contains(' $w ')) {
          bestIcon = icon;
          bestLen = w.length;
        }
      }
    }
    return bestIcon;
  }

  /// Chọn hạng mục trong [categories] khớp với [text].
  static Category? suggest(
    String text,
    List<Category> categories,
    CategoryKind kind,
  ) {
    final list = categories
        .where((c) => c.kind == kind && !c.archived)
        .toList();
    if (list.isEmpty) return null;
    final n = normalizeForSearch(text);
    if (n.isEmpty) return null;
    // Khớp trực tiếp tên hạng mục.
    for (final c in list) {
      final cn = normalizeForSearch(c.name);
      if (cn.isNotEmpty && n.contains(cn)) return c;
    }
    var icon = suggestIcon(text, kind);
    while (icon != null) {
      for (final c in list) {
        if (c.icon == icon) return c;
      }
      // Không có hạng mục riêng -> dùng hạng mục cha gần nhất.
      icon = _fallback[icon];
    }
    return null;
  }

  static const Map<String, String> _fallback = {
    'electric': 'bill',
    'water': 'bill',
    'internet': 'bill',
    'insurance': 'bill',
    'fuel': 'transport',
    'coffee': 'food',
    'market': 'food',
    'beauty': 'shopping',
    'sport': 'entertainment',
    'travel': 'entertainment',
  };
}
