import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_thu_chi/app.dart';
import 'package:so_thu_chi/capture/capture_channel.dart';
import 'package:so_thu_chi/data/models.dart';
import 'package:so_thu_chi/state/app_state.dart';
import 'package:so_thu_chi/ui/editor/transaction_editor.dart';
import 'package:so_thu_chi/ui/quick_add/popup_app.dart';
import 'package:so_thu_chi/ui/quick_add/quick_add_panel.dart';

import 'helpers.dart';

CaptureData sampleCapture({
  int amount = 150000,
  TxnType type = TxnType.expense,
  String id = 'cap-1',
}) => CaptureData(
  id: id,
  amount: amount,
  type: type,
  bankKey: 'mbbank',
  content: 'NGUYEN VAN A chuyen tien',
  rawText:
      'TK 0xxx|GD: -150,000VND|SD: 1,000,000VND|ND: NGUYEN VAN A chuyen tien',
  packageName: 'com.mbmobile',
  time: DateTime(2026, 10, 22, 16, 30),
);

void main() {
  setUpAll(initTestEnv);

  group('Ứng dụng chính', () {
    for (final size in const [
      Size(320, 568),
      Size(390, 844),
      Size(800, 1280),
    ]) {
      testWidgets(
        'các tab hiển thị không lỗi (${size.width.toInt()}x${size.height.toInt()})',
        (tester) async {
          setPhoneSize(tester, width: size.width, height: size.height);
          final state = await createState();
          await state.addTransaction(
            TransactionRecord(
              type: TxnType.expense,
              amount: 45000,
              accountId: state.accounts.first.id!,
              categoryId: state.categoriesOf(CategoryKind.expense).first.id,
              note: 'Ăn trưa với đồng nghiệp ở quán rất xa có tên dài dài dài',
              date: DateTime.now(),
            ),
          );
          await state.addTransaction(
            TransactionRecord(
              type: TxnType.income,
              amount: 15000000,
              accountId: state.accounts.last.id!,
              categoryId: state.categoriesOf(CategoryKind.income).first.id,
              date: DateTime.now(),
            ),
          );
          await tester.pumpWidget(SoThuChiApp(state: state));
          await tester.pumpAndSettle();
          expect(find.text('Tổng số dư'), findsOneWidget);
          expect(find.text('Ghi chép gần đây'), findsOneWidget);

          await tester.tap(find.text('Sổ giao dịch').last);
          await tester.pumpAndSettle();
          expect(find.textContaining('Ăn trưa'), findsWidgets);

          await tester.tap(find.text('Báo cáo').last);
          await tester.pumpAndSettle();
          expect(find.text('Tổng chi'), findsOneWidget);
          await tester.tap(find.text('Thu nhập'));
          await tester.pumpAndSettle();
          expect(find.text('Tổng thu'), findsOneWidget);
          await tester.tap(find.text('Theo tháng'));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Khác').last);
          await tester.pumpAndSettle();
          expect(find.text('Tài khoản'), findsWidgets);
        },
      );
    }

    testWidgets('ghi chép mới qua nút +', (tester) async {
      setPhoneSize(tester);
      final state = await createState();
      await tester.pumpWidget(SoThuChiApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fab_add')));
      await tester.pumpAndSettle();
      expect(find.text('Ghi chép'), findsWidgets);

      // Lưu khi chưa nhập số tiền -> báo lỗi.
      await tester.tap(find.byKey(const Key('editor_save')));
      await tester.pump();
      expect(find.text('Vui lòng nhập số tiền'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('editor_amount')), '35000');
      await tester.pump();
      expect(find.text('35.000'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('editor_note')),
        'Cà phê sáng',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('editor_save')));
      await tester.pumpAndSettle();

      final txns = await state.repo.transactions();
      expect(txns.length, 1);
      expect(txns.first.amount, 35000);
      expect(txns.first.note, 'Cà phê sáng');
      expect(
        state.categoryById(txns.first.categoryId)?.name,
        'Cà phê, đồ uống',
      );
      expect(find.text('Tổng số dư'), findsOneWidget);
    });

    testWidgets('chuyển khoản nội bộ cần tài khoản nhận', (tester) async {
      setPhoneSize(tester);
      final state = await createState();
      await pushPage(
        tester,
        state,
        const TransactionEditor(initialType: TxnType.transfer),
      );
      await tester.enterText(find.byKey(const Key('editor_amount')), '500000');
      await tester.tap(find.byKey(const Key('editor_save')));
      await tester.pump();
      expect(find.text('Vui lòng chọn tài khoản nhận'), findsOneWidget);
      await tester.tap(find.text('Chọn tài khoản nhận'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MB Bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor_save')));
      await tester.pumpAndSettle();
      final t = (await state.repo.transactions()).single;
      expect(t.type, TxnType.transfer);
      expect(t.categoryId, isNull);
      expect(state.balanceOf(t.toAccountId), 500000);
      expect(state.balanceOf(t.accountId), -500000);
    });

    testWidgets('sửa và xoá giao dịch', (tester) async {
      setPhoneSize(tester);
      final state = await createState();
      final id = await state.addTransaction(
        TransactionRecord(
          type: TxnType.expense,
          amount: 20000,
          accountId: state.accounts.first.id!,
          note: 'Gửi xe',
          date: DateTime.now(),
        ),
      );
      final existing = (await state.repo.transaction(id))!;
      await pushPage(tester, state, TransactionEditor(existing: existing));
      expect(find.text('Sửa giao dịch'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('editor_amount')), '25000');
      await tester.tap(find.byKey(const Key('editor_save')));
      await tester.pumpAndSettle();
      expect((await state.repo.transaction(id))!.amount, 25000);

      await pushPage(
        tester,
        state,
        TransactionEditor(existing: (await state.repo.transaction(id))!),
      );
      await tester.tap(find.byTooltip('Xoá'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
      await tester.pumpAndSettle();
      expect(await state.repo.transaction(id), isNull);
    });
  });

  group('Cửa sổ ghi nhanh', () {
    Future<(AppState, List<QuickAddOutcome>)> pumpPanel(
      WidgetTester tester, {
      CaptureData? capture,
    }) async {
      setPhoneSize(tester);
      final state = await createState();
      final outcomes = <QuickAddOutcome>[];
      await tester.pumpWidget(
        wrap(
          state,
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: QuickAddPanel(
                capture: capture,
                autoListen: false,
                onDone: outcomes.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (state, outcomes);
    }

    testWidgets('số tiền điền sẵn từ thông báo, lưu vào tài khoản MB', (
      tester,
    ) async {
      final (state, outcomes) = await pumpPanel(
        tester,
        capture: sampleCapture(),
      );
      expect(find.text('150.000'), findsOneWidget);
      expect(find.text('Giao dịch MB Bank'), findsOneWidget);
      expect(find.textContaining('NGUYEN VAN A'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('quick_note')), 'ăn trưa');
      await tester.pump();
      await tester.tap(find.byKey(const Key('quick_save')));
      await tester.pumpAndSettle();
      expect(outcomes, [QuickAddOutcome.saved]);
      final t = (await state.repo.transactions()).single;
      expect(t.amount, 150000);
      expect(t.type, TxnType.expense);
      expect(t.note, 'ăn trưa');
      expect(t.source, TxnSource.auto);
      expect(t.bankKey, 'mbbank');
      expect(state.accountById(t.accountId)?.bankKey, 'mbbank');
      expect(state.categoryById(t.categoryId)?.name, 'Ăn uống');
      expect(t.date, DateTime(2026, 10, 22, 16, 30));
    });

    testWidgets(
      'không nói gì -> hạng mục "Chuyển tiền", nút Dùng ND ngân hàng',
      (tester) async {
        final (state, outcomes) = await pumpPanel(
          tester,
          capture: sampleCapture(),
        );
        await tester.tap(find.text('Dùng'));
        await tester.pump();
        expect(find.text('NGUYEN VAN A chuyen tien'), findsWidgets);
        await tester.tap(find.byKey(const Key('quick_save')));
        await tester.pumpAndSettle();
        final t = (await state.repo.transactions()).single;
        expect(state.categoryById(t.categoryId)?.icon, 'transfer');
        expect(outcomes.single, QuickAddOutcome.saved);
      },
    );

    testWidgets('khoản thu: đổi hạng mục theo loại', (tester) async {
      final (state, _) = await pumpPanel(
        tester,
        capture: sampleCapture(type: TxnType.income, amount: 15000000),
      );
      await tester.enterText(
        find.byKey(const Key('quick_note')),
        'lương tháng 10',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('quick_save')));
      await tester.pumpAndSettle();
      final t = (await state.repo.transactions()).single;
      expect(t.type, TxnType.income);
      expect(state.categoryById(t.categoryId)?.name, 'Lương');
      expect(state.balanceOf(t.accountId), 15000000);
    });

    testWidgets('chuyển Chi -> Thu đổi hạng mục hợp lệ', (tester) async {
      final (state, _) = await pumpPanel(tester, capture: sampleCapture());
      await tester.tap(find.text('Thu tiền'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('quick_save')));
      await tester.pumpAndSettle();
      final t = (await state.repo.transactions()).single;
      expect(t.type, TxnType.income);
      expect(state.categoryById(t.categoryId)?.kind, CategoryKind.income);
    });

    testWidgets('Để sau / Bỏ qua', (tester) async {
      final (state, outcomes) = await pumpPanel(
        tester,
        capture: sampleCapture(),
      );
      await tester.tap(find.text('Để sau'));
      await tester.pumpAndSettle();
      expect(outcomes, [QuickAddOutcome.later]);
      await tester.tap(find.text('Bỏ qua'));
      await tester.pumpAndSettle();
      expect(outcomes.last, QuickAddOutcome.discarded);
      expect(await state.repo.transactions(), isEmpty);
    });

    testWidgets('ghi thủ công: thiếu số tiền thì báo lỗi', (tester) async {
      final (state, outcomes) = await pumpPanel(tester);
      expect(find.text('Ghi chép nhanh'), findsOneWidget);
      expect(find.text('Bỏ qua'), findsNothing);
      await tester.tap(find.byKey(const Key('quick_save')));
      await tester.pump();
      expect(find.text('Nhập số tiền'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('quick_amount')), '50000');
      await tester.enterText(find.byKey(const Key('quick_note')), 'đổ xăng');
      await tester.pump();
      await tester.tap(find.byKey(const Key('quick_save')));
      await tester.pumpAndSettle();
      final t = (await state.repo.transactions()).single;
      expect(t.amount, 50000);
      expect(t.source, TxnSource.voice);
      expect(state.categoryById(t.categoryId)?.name, 'Xăng xe');
      expect(outcomes, [QuickAddOutcome.saved]);
    });

    testWidgets('bấm mic khi không có dịch vụ giọng nói không làm lỗi', (
      tester,
    ) async {
      final (_, outcomes) = await pumpPanel(tester, capture: sampleCapture());
      await tester.tap(find.byKey(const Key('quick_mic')));
      await tester.pumpAndSettle();
      expect(outcomes, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PopupHost đóng cửa sổ sau khi lưu', (tester) async {
      setPhoneSize(tester, width: 360, height: 640);
      final state = await createState();
      var closed = 0;
      await tester.pumpWidget(
        wrap(
          state,
          PopupHost(initial: sampleCapture(), onClose: () => closed++),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('150.000'), findsOneWidget);
      await tester.tap(find.byKey(const Key('quick_save')));
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect((await state.repo.transactions()).length, 1);
    });

    testWidgets('PopupHost không có giao dịch -> ghi thủ công', (tester) async {
      setPhoneSize(tester, width: 360, height: 640);
      final state = await createState();
      await tester.pumpWidget(wrap(state, PopupHost(onClose: () {})));
      await tester.pumpAndSettle();
      expect(find.text('Ghi chép nhanh'), findsOneWidget);
    });
  });

  group('Liên kết sothuchi://', () {
    test('text SMS', () {
      final c = captureFromUri(
        Uri.parse(
          'sothuchi://app/add?text=${Uri.encodeComponent('TK 0xxx|GD: -150,000VND 22/10/26 16:30 |SD: 2,345,678VND|ND: an trua')}',
        ),
      );
      expect(c, isNotNull);
      expect(c!.amount, 150000);
      expect(c.type, TxnType.expense);
      expect(c.content, 'an trua');
    });

    test('amount + note + type', () {
      final c = captureFromUri(
        Uri.parse('sothuchi://app/add?amount=200000&note=Luong&type=income'),
      )!;
      expect(c.amount, 200000);
      expect(c.type, TxnType.income);
      expect(c.content, 'Luong');
    });

    test('route Android /add', () {
      expect(captureFromUri(Uri.parse('/add?amount=1000'))!.amount, 1000);
    });

    test('đường dẫn khác thì bỏ qua', () {
      expect(captureFromUri(Uri.parse('sothuchi://app/other')), isNull);
      expect(captureFromUri(Uri.parse('/')), isNull);
    });

    test('text không phải giao dịch -> mở ghi thủ công (amount 0)', () {
      final c = captureFromUri(
        Uri.parse('sothuchi://app/add?text=xin%20chao'),
      )!;
      expect(c.amount, 0);
    });
  });
}
