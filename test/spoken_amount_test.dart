import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_thu_chi/capture/category_suggester.dart';
import 'package:so_thu_chi/core/format.dart';
import 'package:so_thu_chi/core/spoken_amount.dart';
import 'package:so_thu_chi/core/text_utils.dart';
import 'package:so_thu_chi/data/default_data.dart';
import 'package:so_thu_chi/data/models.dart';

void main() {
  group('parseSpokenAmount', () {
    final cases = <String, (int, String)>{
      'ăn trưa 50 nghìn': (50000, 'Ăn trưa'),
      'Ăn trưa 50k': (50000, 'Ăn trưa'),
      'đổ xăng 100 ngàn': (100000, 'Đổ xăng'),
      'tiền nhà 3 triệu': (3000000, 'Tiền nhà'),
      'mua giày 1 triệu 2': (1200000, 'Mua giày'),
      'mua giày 1tr5': (1500000, 'Mua giày'),
      'học phí 1,5 triệu': (1500000, 'Học phí'),
      'tiền điện 1 triệu 250 nghìn': (1250000, 'Tiền điện'),
      'cà phê 35.000 đồng': (35000, 'Cà phê'),
      'cà phê 35.000đ': (35000, 'Cà phê'),
      'hai trăm nghìn tiền điện': (200000, 'Tiền điện'),
      'năm mươi nghìn ăn sáng': (50000, 'Ăn sáng'),
      'mua sách hết 120 nghìn': (120000, 'Mua sách'),
      'đám cưới bạn 1 triệu rưỡi': (1500000, 'Đám cưới bạn'),
      'grab 45': (45000, 'Grab'),
      'lương tháng 10 15 triệu': (15000000, 'Lương tháng 10'),
      'trà sữa 2 ly 60k': (60000, 'Trà sữa 2 ly'),
      'tiền nước 250000': (250000, 'Tiền nước'),
    };
    cases.forEach((input, expected) {
      test(input, () {
        final r = parseSpokenAmount(input);
        expect(r, isNotNull);
        expect(r!.amount, expected.$1);
        expect(r.rest, expected.$2);
      });
    });

    test('số không phải tiền ở cuối câu', () {
      expect(parseSpokenAmount('tiền điện tháng 10'), isNull);
      expect(parseSpokenAmount('học phí lớp 5'), isNull);
      expect(parseSpokenAmount('trà sữa 2 ly'), isNull);
      expect(parseSpokenAmount('tiền điện tháng 10 500 nghìn')!.amount, 500000);
      expect(
        parseSpokenAmount('tiền điện tháng 10 500 nghìn')!.rest,
        'Tiền điện tháng 10',
      );
      expect(parseSpokenAmount('bánh mì 25')!.amount, 25000);
      expect(parseSpokenAmount('học phí năm 2026'), isNull);
      expect(parseSpokenAmount('học phí năm 2026 5 triệu')!.amount, 5000000);
      expect(parseSpokenAmount('phòng 301'), isNull);
    });

    test('không có số tiền', () {
      expect(parseSpokenAmount('ăn trưa với bạn'), isNull);
      expect(parseSpokenAmount(''), isNull);
      expect(parseSpokenAmount('làm tóc'), isNull);
    });
  });

  group('CategorySuggester', () {
    final cats = [
      for (final (i, c) in [
        ...kDefaultExpenseCategories,
        ...kDefaultIncomeCategories,
      ].indexed)
        c.copyWith(id: i + 1),
    ];
    String? name(String text, [CategoryKind kind = CategoryKind.expense]) =>
        CategorySuggester.suggest(text, cats, kind)?.name;

    test('gợi ý chi', () {
      expect(name('Ăn trưa'), 'Ăn uống');
      expect(name('cà phê với khách'), 'Cà phê, đồ uống');
      expect(name('đổ xăng'), 'Xăng xe');
      expect(name('grab đi làm'), 'Di chuyển');
      expect(name('tiền điện tháng 10'), 'Hoá đơn, tiện ích');
      expect(name('mua áo'), 'Mua sắm');
      expect(name('đi siêu thị'), 'Đi chợ, siêu thị');
      expect(name('thuốc cảm'), 'Sức khoẻ');
      expect(name('học phí'), 'Học tập');
      expect(name('đám cưới bạn'), 'Hiếu hỉ, quà tặng');
      expect(name('xyz abc'), isNull);
    });

    test('gợi ý thu', () {
      expect(name('lương tháng 10', CategoryKind.income), 'Lương');
      expect(name('thưởng dự án', CategoryKind.income), 'Thưởng');
      expect(name('hoàn tiền shopee', CategoryKind.income), 'Hoàn tiền');
    });
  });

  group('Định dạng', () {
    test('formatMoney', () {
      expect(formatMoney(150000), '150.000 đ');
      expect(formatMoney(-2500000), '-2.500.000 đ');
      expect(formatMoney(5000, withSign: true), '+5.000 đ');
      expect(formatMoney(0), '0 đ');
    });

    test('formatCompact', () {
      expect(formatCompact(1500000), '1,5tr');
      expect(formatCompact(150000), '150k');
      expect(formatCompact(2000000000), '2 tỷ');
      expect(formatCompact(999), '999');
    });

    test('parseMoneyInput', () {
      expect(parseMoneyInput('150.000'), 150000);
      expect(parseMoneyInput(''), 0);
      expect(parseMoneyInput('abc'), 0);
      expect(parseMoneyInput('9' * 30), 999999999999999);
    });

    test('MoneyInputFormatter', () {
      final f = MoneyInputFormatter();
      TextEditingValueLike v(String t) => (t, t.length);
      String apply(String oldText, String newText) => f
          .formatEditUpdate(
            TextEditingValue(text: oldText),
            TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: newText.length),
            ),
          )
          .text;
      expect(v('a').$1, 'a');
      expect(apply('', '1'), '1');
      expect(apply('1.500', '1.5000'), '15.000');
      expect(apply('15.000', '15.00'), '1.500');
      expect(apply('', '0005'), '5');
      expect(apply('5', ''), '');
      expect(apply('', 'abc'), '');
    });

    test('friendlyDay', () {
      final now = DateTime(2026, 10, 22, 10);
      expect(friendlyDay(DateTime(2026, 10, 22, 1), now: now), 'Hôm nay');
      expect(friendlyDay(DateTime(2026, 10, 21, 23), now: now), 'Hôm qua');
      expect(
        friendlyDay(DateTime(2026, 10, 19), now: now),
        'Thứ hai, 19/10/2026',
      );
    });

    test('removeDiacritics', () {
      expect(removeDiacritics('Đường Nguyễn Huệ'), 'Duong Nguyen Hue');
      expect(normalizeForSearch('  Cà   PHÊ '), 'ca phe');
    });
  });
}

typedef TextEditingValueLike = (String, int);
