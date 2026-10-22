// ignore_for_file: invalid_use_of_visible_for_testing_member
// Chụp ảnh màn hình bằng font thật để soát giao diện:
//   flutter test --update-goldens test_screens/
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_thu_chi/app.dart';
import 'package:so_thu_chi/capture/capture_channel.dart';
import 'package:so_thu_chi/data/models.dart';
import 'package:so_thu_chi/state/app_state.dart';
import 'package:so_thu_chi/ui/editor/transaction_editor.dart';
import 'package:so_thu_chi/ui/more/accounts_screen.dart';
import 'package:so_thu_chi/ui/more/auto_capture_screen.dart';
import 'package:so_thu_chi/ui/more/categories_screen.dart';
import 'package:so_thu_chi/ui/quick_add/popup_app.dart';

import '../test/helpers.dart';

Future<void> _loadFonts() async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter-sdk/flutter'}/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String f) async =>
      ByteData.sublistView(await File('$dir/$f').readAsBytes());
  final roboto = FontLoader('Roboto')
    ..addFont(bytes('Roboto-Regular.ttf'))
    ..addFont(bytes('Roboto-Medium.ttf'))
    ..addFont(bytes('Roboto-Bold.ttf'));
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<AppState> _demoState() async {
  final s = await createState();
  final now = DateTime.now();
  final cash = s.accounts.first.id!;
  final mb = s.accounts.last.id!;
  int cat(String name, CategoryKind k) =>
      s.categoriesOf(k).firstWhere((c) => c.name == name).id!;
  await s.saveAccount(s.accounts.last.copyWith(initialBalance: 12500000));
  final data = [
    (
      TxnType.income,
      18000000,
      mb,
      cat('Lương', CategoryKind.income),
      'Lương tháng ${now.month}',
      0,
      TxnSource.auto,
    ),
    (
      TxnType.expense,
      45000,
      mb,
      cat('Ăn uống', CategoryKind.expense),
      'Ăn trưa',
      0,
      TxnSource.auto,
    ),
    (
      TxnType.expense,
      35000,
      cash,
      cat('Cà phê, đồ uống', CategoryKind.expense),
      'Cà phê sáng',
      0,
      TxnSource.voice,
    ),
    (
      TxnType.expense,
      80000,
      cash,
      cat('Xăng xe', CategoryKind.expense),
      'Đổ xăng',
      1,
      TxnSource.manual,
    ),
    (
      TxnType.expense,
      1250000,
      mb,
      cat('Hoá đơn, tiện ích', CategoryKind.expense),
      'Tiền điện tháng 9',
      2,
      TxnSource.auto,
    ),
    (
      TxnType.expense,
      3500000,
      mb,
      cat('Nhà cửa', CategoryKind.expense),
      'Tiền nhà',
      3,
      TxnSource.auto,
    ),
    (
      TxnType.expense,
      420000,
      mb,
      cat('Mua sắm', CategoryKind.expense),
      'Shopee',
      4,
      TxnSource.auto,
    ),
    (
      TxnType.expense,
      150000,
      mb,
      cat('Chuyển tiền', CategoryKind.expense),
      'Góp tiền sinh nhật',
      5,
      TxnSource.auto,
    ),
  ];
  for (final (type, amount, acc, c, note, daysAgo, src) in data) {
    final d = now.subtract(Duration(days: daysAgo));
    await s.addTransaction(
      TransactionRecord(
        type: type,
        amount: amount,
        accountId: acc,
        categoryId: c,
        note: note,
        date: DateTime(d.year, d.month, d.day, 12 - daysAgo, 15),
        source: src,
      ),
    );
  }
  await s.addTransaction(
    TransactionRecord(
      type: TxnType.transfer,
      amount: 2000000,
      accountId: mb,
      toAccountId: cash,
      note: 'Rút tiền mặt',
      date: now.subtract(const Duration(days: 2)),
    ),
  );
  await s.setMonthlyBudget(8000000);
  return s;
}

void main() {
  setUpAll(() async {
    await initTestEnv();
    await _loadFonts();
  });

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp).first,
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('tổng quan + các tab', (tester) async {
    setPhoneSize(tester);
    final s = await _demoState();
    await tester.pumpWidget(SoThuChiApp(state: s));
    await shot(tester, '01_tong_quan');
    await tester.tap(find.text('Sổ giao dịch').last);
    await shot(tester, '02_so_giao_dich');
    await tester.tap(find.text('Báo cáo').last);
    await shot(tester, '03_bao_cao_chi');
    await tester.tap(find.text('Theo tháng'));
    await shot(tester, '04_bao_cao_thang');
    await tester.tap(find.text('Khác').last);
    await shot(tester, '05_khac');
  });

  testWidgets('ghi chép', (tester) async {
    setPhoneSize(tester);
    final s = await _demoState();
    await pushPage(tester, s, const TransactionEditor());
    await tester.enterText(find.byKey(const Key('editor_amount')), '45000');
    await tester.enterText(find.byKey(const Key('editor_note')), 'Ăn trưa');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    FocusManager.instance.primaryFocus?.unfocus();
    await shot(tester, '06_ghi_chep');
  });

  testWidgets('cửa sổ ghi nhanh trên app ngân hàng', (tester) async {
    setPhoneSize(tester);
    final s = await _demoState();
    final capture = CaptureData(
      id: 'x',
      amount: 150000,
      type: TxnType.expense,
      bankKey: 'mbbank',
      content: 'NGUYEN VAN A chuyen tien',
      packageName: 'com.mbmobile',
      time: DateTime.now(),
    );
    await tester.pumpWidget(
      wrap(
        s,
        Stack(
          children: [
            // Giả lập màn hình "Chuyển khoản thành công" của ngân hàng phía sau.
            Container(
              color: const Color(0xFF0B2A8A),
              alignment: const Alignment(0, -0.5),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent, size: 72),
                  SizedBox(height: 12),
                  Text(
                    'Chuyển khoản thành công',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                  Text(
                    '-150,000 VND',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            PopupHost(initial: capture, onClose: () {}),
          ],
        ),
      ),
    );
    await shot(tester, '07_popup_ghi_nhanh');
  });

  testWidgets('cài đặt tự động ghi chép', (tester) async {
    setPhoneSize(tester, height: 1400);
    CaptureChannel.debugSupported = true;
    addTearDown(() => CaptureChannel.debugSupported = null);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      CaptureChannel.channel,
      (call) async {
        switch (call.method) {
          case 'getPermissions':
            return {
              'notificationListener': true,
              'overlay': false,
              'postNotifications': true,
              'microphone': false,
            };
          case 'getSettings':
            return const CaptureSettings().toMap();
          case 'getInstalledBankPackages':
            return ['com.mbmobile', 'com.mservice.momotransfer'];
          case 'getPendingCaptures':
            return [];
        }
        return null;
      },
    );
    final s = await _demoState();
    await pushPage(tester, s, const AutoCaptureScreen());
    await shot(tester, '08_tu_dong_ghi_chep');
  });

  testWidgets('tài khoản, hạng mục', (tester) async {
    setPhoneSize(tester);
    final s = await _demoState();
    await pushPage(tester, s, const AccountsScreen());
    await shot(tester, '09_tai_khoan');
    await pushPage(tester, s, const CategoriesScreen());
    await shot(tester, '10_hang_muc');
  });
}
