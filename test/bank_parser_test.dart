import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_thu_chi/capture/bank_apps.dart';
import 'package:so_thu_chi/capture/bank_parser.dart';
import 'package:so_thu_chi/data/models.dart';

void main() {
  final fixtures = (jsonDecode(
    File('test/fixtures/bank_notifications.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  group('Mẫu thông báo ngân hàng', () {
    for (final f in fixtures) {
      test(f['name'] as String, () {
        final r = BankNotificationParser.parse(
          f['text'] as String,
          title: f['title'] as String?,
          packageName: f['package'] as String?,
          strict: f['strict'] == true,
        );
        final expect_ = f['expect'] as Map<String, dynamic>?;
        if (expect_ == null) {
          expect(r, isNull, reason: 'Không được nhận là giao dịch: $r');
          return;
        }
        expect(r, isNotNull, reason: 'Phải nhận được giao dịch');
        expect(r!.amount, expect_['amount']);
        expect(r.type.key, expect_['type']);
        if (expect_.containsKey('balance')) {
          expect(r.balance, expect_['balance']);
        }
        if (expect_.containsKey('bank')) expect(r.bankKey, expect_['bank']);
        if (expect_.containsKey('content')) {
          expect(r.content, expect_['content']);
        }
        if (expect_.containsKey('contentContains')) {
          expect(r.content, contains(expect_['contentContains']));
        }
      });
    }
  });

  test('Danh sách ngân hàng Dart và Kotlin khớp nhau', () {
    final kt = File(
      'android/app/src/main/kotlin/vn/sothuchi/so_thu_chi/capture/BankApps.kt',
    ).readAsStringSync();
    for (final b in kBankApps) {
      expect(kt, contains('Bank("${b.key}", "${b.name}"'), reason: b.key);
      for (final p in b.packages) {
        expect(kt, contains('"$p"'), reason: p);
      }
      for (final a in b.aliases) {
        expect(kt, contains('"$a"'), reason: a);
      }
    }
    for (final p in kSmsPackages) {
      expect(kt, contains('"$p"'));
    }
    final ktBanks = RegExp(r'Bank\("').allMatches(kt).length;
    expect(ktBanks, kBankApps.length);
  });

  group('Trường hợp biên', () {
    test('chuỗi rỗng', () {
      expect(BankNotificationParser.parse(''), isNull);
      expect(BankNotificationParser.parse('   ', title: ''), isNull);
    });

    test('không có số', () {
      expect(BankNotificationParser.parse('Chào mừng bạn đến MB Bank'), isNull);
    });

    test('ký tự đặc biệt / emoji không làm lỗi chỉ số', () {
      final r = BankNotificationParser.parse(
        '💰 İstanbul TK 0xxx1|GD: -10,000VND 22/10/26 10:00 |SD: 90,000VND|ND: test 🎉',
      );
      expect(r, isNotNull);
      expect(r!.amount, 10000);
      expect(r.type, TxnType.expense);
      expect(r.content, contains('test'));
    });

    test('số tiền lớn', () {
      final r = BankNotificationParser.parse(
        'TK 0xxx1|GD: +1,234,567,890VND 22/10/26 10:00 |SD: 2,000,000,000VND',
      );
      expect(r!.amount, 1234567890);
      expect(r.type, TxnType.income);
    });

    test('chuỗi rất dài không gây lỗi', () {
      final long = 'TK 0xxx1|GD: -10,000VND|ND: ${'a' * 5000}';
      final r = BankNotificationParser.parse(long);
      expect(r!.amount, 10000);
      expect(r.content!.length, lessThanOrEqualTo(141));
    });

    test('foldVietnamese giữ độ dài', () {
      const s = 'Số dư TK: Đã chuyển 150.000đ İ ẞ ﬀ';
      expect(foldVietnamese(s).length, s.length);
      expect(foldVietnamese('Đã Chuyển'), 'da chuyen');
    });
  });
}
