// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_thu_chi/app.dart';
import 'package:so_thu_chi/capture/bank_apps.dart';
import 'package:so_thu_chi/capture/capture_channel.dart';
import 'package:so_thu_chi/data/models.dart';
import 'package:so_thu_chi/ui/more/accounts_screen.dart';
import 'package:so_thu_chi/ui/more/auto_capture_screen.dart';
import 'package:so_thu_chi/ui/more/categories_screen.dart';
import 'package:so_thu_chi/ui/quick_add/popup_app.dart';

import 'helpers.dart';

/// Giả lập phía Android của kênh vn.sothuchi/capture.
class FakeNative {
  final calls = <MethodCall>[];
  var permissions = <String, bool>{
    'notificationCapture': true,
    'notificationListener': false,
    'overlay': false,
    'postNotifications': true,
    'microphone': true,
  };
  var settings = const CaptureSettings().toMap();
  final pending = <Map<String, Object?>>[];
  final filtered = <Map<String, Object?>>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'getPermissions':
        return permissions;
      case 'getSettings':
        return settings;
      case 'setSettings':
        settings = Map<String, Object?>.from(call.arguments as Map);
        return null;
      case 'getPendingCaptures':
        return pending;
      case 'removeCapture':
        pending.removeWhere((p) => p['id'] == (call.arguments as Map)['id']);
        return null;
      case 'clearCaptures':
        pending.clear();
        return null;
      case 'getFilteredCaptures':
        return filtered;
      case 'restoreFiltered':
        final id = (call.arguments as Map)['id'];
        final i = filtered.indexWhere((f) => f['id'] == id);
        if (i < 0) return null;
        final m = filtered.removeAt(i);
        pending.add(m);
        return m;
      case 'clearFiltered':
        filtered.clear();
        return null;
      case 'getInstalledBankPackages':
        return ['com.mbmobile'];
      case 'simulateNotification':
        return 'scheduled';
      case 'openBackgroundPopupSettings':
        return false;
    }
    return null;
  }

  List<String> get methods => calls.map((c) => c.method).toList();
}

Map<String, Object?> captureMap(String id, int amount, {bool income = false}) =>
    {
      'id': id,
      'amount': amount,
      'income': income,
      'bankKey': 'mbbank',
      'content': 'ND $id',
      'rawText': 'raw',
      'packageName': 'com.mbmobile',
      'balance': null,
      'time': DateTime(2026, 10, 22, 9).millisecondsSinceEpoch,
    };

void main() {
  setUpAll(initTestEnv);

  late FakeNative native;

  setUp(() {
    native = FakeNative();
    CaptureChannel.debugSupported = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CaptureChannel.channel, native.handle);
  });

  tearDown(() {
    CaptureChannel.debugSupported = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(CaptureChannel.channel, null);
  });

  testWidgets('màn tự động ghi chép: cấp quyền, tuỳ chọn, giả lập', (
    tester,
  ) async {
    setPhoneSize(tester, height: 2600);
    final state = await createState();
    await pushPage(tester, state, const AutoCaptureScreen());
    expect(find.text('1. Đọc thông báo'), findsOneWidget);
    expect(find.text('Đã cài trên máy'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Bật').first);
    await tester.pump();
    expect(native.methods, contains('openNotificationListenerSettings'));
    await tester.tap(find.widgetWithText(FilledButton, 'Bật').last);
    await tester.pump();
    expect(native.methods, contains('openOverlaySettings'));

    // Quay lại app -> tải lại quyền.
    native.permissions = {
      ...native.permissions,
      'notificationListener': true,
      'overlay': true,
    };
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Đã bật'), findsNWidgets(4));

    // Tắt đọc SMS.
    await tester.tap(find.text('Đọc SMS biến động số dư'));
    await tester.pumpAndSettle();
    expect(native.settings['readSms'], false);

    // Bỏ chọn MB Bank.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'MB Bank'));
    await tester.pumpAndSettle();
    expect((native.settings['disabledBanks'] as List), contains('mbbank'));

    // Phân tích mẫu.
    await tester.scrollUntilVisible(
      find.text('Phân tích'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Phân tích'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phân tích'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Chi tiền: 150.000 đ'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Chi tiền: 150.000 đ'), findsOneWidget);
    expect(find.textContaining('Nội dung: NGUYEN VAN A'), findsOneWidget);

    await tester.tap(find.text('Giả lập thông báo'));
    await tester.pumpAndSettle();
    final sim = native.calls.lastWhere(
      (c) => c.method == 'simulateNotification',
    );
    expect((sim.arguments as Map)['text'], kSampleMbNotification);
  });

  group('Lọc thông báo trùng', () {
    Map<String, Object?> filteredMap(String id, int amount, String reason) => {
      ...captureMap(id, amount),
      'packageName': 'com.google.android.gm',
      'content': 'NGUYEN VAN A chuyen tien an trua',
      'time': DateTime(2026, 11, 12, 10, 2).millisecondsSinceEpoch,
      'reason': reason,
      'originalId': 'orig-$id',
      'originalTime': DateTime(2026, 11, 12, 10, 1).millisecondsSinceEpoch,
      'originalPackage': 'com.mbmobile',
    };

    testWidgets('bật/tắt trong Tuỳ chọn', (tester) async {
      setPhoneSize(tester, height: 2600);
      final state = await createState();
      await pushPage(tester, state, const AutoCaptureScreen());
      expect(find.text('Lọc thông báo trùng'), findsOneWidget);
      // Chưa lọc gì thì không hiện danh sách.
      expect(find.textContaining('Thông báo trùng đã lọc'), findsNothing);
      await tester.tap(find.text('Lọc thông báo trùng'));
      await tester.pumpAndSettle();
      expect(native.settings['dedupe'], false);
      await tester.tap(find.text('Lọc thông báo trùng'));
      await tester.pumpAndSettle();
      expect(native.settings['dedupe'], true);
      // Tắt tự động ghi chép -> công tắc bị khoá.
      await tester.tap(find.text('Bật tự động ghi chép'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lọc thông báo trùng'));
      await tester.pumpAndSettle();
      expect(native.settings['dedupe'], true);
    });

    testWidgets('danh sách đã lọc: xem lý do, "Vẫn ghi", xoá danh sách', (
      tester,
    ) async {
      setPhoneSize(tester, height: 2800);
      native.filtered.addAll([
        filteredMap('f1', 150000, 'content'),
        filteredMap('f2', 89000, 'balance'),
      ]);
      final state = await createState();
      await pushPage(tester, state, const AutoCaptureScreen());
      expect(find.text('Thông báo trùng đã lọc (2)'), findsOneWidget);
      // Mới nhất (cuối danh sách native) hiện trước.
      final amounts = tester
          .widgetList<Text>(find.textContaining(' đ'))
          .map((t) => t.data)
          .where((t) => t == '-150.000 đ' || t == '-89.000 đ')
          .toList();
      expect(amounts, ['-89.000 đ', '-150.000 đ']);
      expect(
        find.textContaining(
          'Trùng với MB Bank lúc 10:01: cùng số tiền và nội dung',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('cùng số tiền và số dư sau giao dịch'),
        findsOneWidget,
      );
      expect(find.textContaining('Gmail · 10:02 12/11/2026'), findsNWidgets(2));

      // Lọc nhầm -> "Vẫn ghi" mở cửa sổ ghi nhanh với số tiền sẵn.
      await tester.tap(find.widgetWithText(TextButton, 'Vẫn ghi').last);
      await tester.pumpAndSettle();
      expect(native.methods, contains('restoreFiltered'));
      expect(find.byKey(const Key('quick_amount')), findsOneWidget);
      expect(find.text('150.000'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('quick_note')), 'Ăn trưa');
      await tester.tap(find.byKey(const Key('quick_save')));
      await tester.pumpAndSettle();
      final t = (await state.repo.transactions()).single;
      expect(t.amount, 150000);
      expect(t.source, TxnSource.auto);
      expect(native.pending, isEmpty);
      expect(find.text('Thông báo trùng đã lọc (1)'), findsOneWidget);

      await tester.tap(find.text('Xoá danh sách'));
      await tester.pumpAndSettle();
      expect(native.filtered, isEmpty);
      expect(find.textContaining('Thông báo trùng đã lọc'), findsNothing);
    });

    testWidgets('"Vẫn ghi" rồi để sau -> nằm ở mục chờ ghi', (tester) async {
      setPhoneSize(tester, height: 2800);
      native.filtered.add(filteredMap('f1', 150000, 'time'));
      final state = await createState();
      await pushPage(tester, state, const AutoCaptureScreen());
      expect(
        find.textContaining('cùng số tiền, báo sát nhau'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Vẫn ghi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Để sau'));
      await tester.pumpAndSettle();
      expect(await state.repo.transactions(), isEmpty);
      expect(state.pending.map((c) => c.id), ['f1']);
      expect(find.textContaining('Thông báo trùng đã lọc'), findsNothing);
    });

    testWidgets('thông báo đã bị xoá khỏi danh sách ở nơi khác', (tester) async {
      setPhoneSize(tester, height: 2800);
      native.filtered.add(filteredMap('f1', 150000, 'content'));
      final state = await createState();
      await pushPage(tester, state, const AutoCaptureScreen());
      native.filtered.clear();
      await tester.tap(find.widgetWithText(TextButton, 'Vẫn ghi'));
      await tester.pumpAndSettle();
      expect(
        find.text('Thông báo này không còn trong danh sách'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('quick_amount')), findsNothing);
      expect(find.textContaining('Thông báo trùng đã lọc'), findsNothing);
    });

    test('đọc dữ liệu từ native', () async {
      native.filtered.addAll([
        filteredMap('a', 1000, 'clock'),
        {...filteredMap('hỏng', 0, 'content')},
        {'id': 'thiếu', 'amount': 5000},
      ]);
      final list = await CaptureChannel.filtered();
      expect(list.map((f) => f.capture.id), ['thiếu', 'a']);
      expect(list.last.reasonLabel, 'cùng số tiền và giờ giao dịch');
      expect(list.last.originalPackage, 'com.mbmobile');
      expect(list.first.originalTime, isNull);
      expect(list.first.reasonLabel, 'cùng số tiền, báo sát nhau');
      expect(await CaptureChannel.restoreFiltered('không có'), isNull);
      final c = await CaptureChannel.restoreFiltered('a');
      expect(c!.amount, 1000);
      await CaptureChannel.clearFiltered();
      expect(native.filtered, isEmpty);
    });

    test('cài đặt lọc trùng mặc định bật, giữ được qua toMap/fromMap', () {
      expect(const CaptureSettings().dedupe, isTrue);
      expect(CaptureSettings.fromMap(const {}).dedupe, isTrue);
      final off = const CaptureSettings().copyWith(dedupe: false);
      expect(off.toMap()['dedupe'], false);
      expect(CaptureSettings.fromMap(off.toMap()).dedupe, isFalse);
      expect(off.copyWith(readSms: false).dedupe, isFalse);
    });

    test('tên kênh báo', () {
      expect(sourceLabel('com.mbmobile'), 'MB Bank');
      expect(sourceLabel('com.google.android.gm'), 'Gmail');
      expect(sourceLabel('com.google.android.apps.messaging'), 'Tin nhắn SMS');
      expect(sourceLabel('com.example.app'), 'com.example.app');
      expect(sourceLabel(null), 'Ứng dụng khác');
      expect(sourceLabel(''), 'Ứng dụng khác');
    });
  });

  testWidgets('giao dịch chờ ở Tổng quan -> ghi', (tester) async {
    setPhoneSize(tester);
    native.permissions = {
      ...native.permissions,
      'notificationListener': true,
      'overlay': true,
    };
    native.pending.addAll([
      captureMap('a', 150000),
      captureMap('b', 2000000, income: true),
    ]);
    final state = await createState();
    await tester.pumpWidget(SoThuChiApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Giao dịch ngân hàng chờ ghi (2)'), findsOneWidget);
    expect(find.text('Bật tự động ghi chép'), findsNothing);

    await tester.tap(find.text('-150.000 đ'));
    await tester.pumpAndSettle();
    expect(find.text('150.000'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('quick_note')), 'Ăn trưa');
    await tester.tap(find.byKey(const Key('quick_save')));
    await tester.pumpAndSettle();
    expect(native.methods, contains('removeCapture'));
    expect(find.text('Giao dịch ngân hàng chờ ghi (1)'), findsOneWidget);
    final t = (await state.repo.transactions()).single;
    expect(t.amount, 150000);
    expect(t.note, 'Ăn trưa');

    // Chỉ còn 1 giao dịch: không hiện "Bỏ qua hết".
    expect(find.text('Bỏ qua hết'), findsNothing);
  });

  testWidgets('thẻ "Bật tự động ghi chép" khi thiếu quyền', (tester) async {
    setPhoneSize(tester);
    final state = await createState();
    await tester.pumpWidget(SoThuChiApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Bật tự động ghi chép'), findsOneWidget);
    await tester.tap(find.text('Bật tự động ghi chép'));
    await tester.pumpAndSettle();
    expect(find.text('Tự động ghi chép'), findsOneWidget);
  });

  testWidgets('popup: giao dịch mới đến khi đang mở -> xếp hàng', (
    tester,
  ) async {
    setPhoneSize(tester, width: 360, height: 700);
    final state = await createState();
    var closed = 0;
    CaptureChannel.ensureHandler();
    await tester.pumpWidget(
      wrap(
        state,
        PopupHost(
          initial: CaptureData.fromMap(captureMap('a', 150000)),
          onClose: () => closed++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Phía Android gửi onNewCapture.
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      CaptureChannel.channel.name,
      CaptureChannel.channel.codec.encodeMethodCall(
        MethodCall('onNewCapture', captureMap('b', 75000)),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Còn 1 giao dịch nữa'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick_save')));
    await tester.pumpAndSettle();
    expect(closed, 0);
    expect(find.text('75.000'), findsOneWidget);
    expect(find.textContaining('Đã lưu giao dịch'), findsOneWidget);
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect((await state.repo.transactions()).length, 1);
  });

  testWidgets('liên kết sothuchi:// mở cửa sổ ghi nhanh', (tester) async {
    setPhoneSize(tester);
    final state = await createState();
    await tester.pumpWidget(SoThuChiApp(state: state));
    await tester.pumpAndSettle();
    final text = Uri.encodeComponent(
      'TK 0xxx|GD: -89,000VND 22/10/26 10:00 |SD: 1,000,000VND|ND: grab',
    );
    final msg = const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {
        'location': 'sothuchi://app/add?text=$text',
      }),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      msg,
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('89.000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quick_save')));
    await tester.pumpAndSettle();
    final t = (await state.repo.transactions()).single;
    expect(t.amount, 89000);
    expect(state.categoryById(t.categoryId)?.kind, CategoryKind.expense);
    // Route lạ không mở thêm màn hình.
    final msg2 = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('pushRouteInformation', {'location': '/'}),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      msg2,
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Tổng số dư'), findsOneWidget);
  });

  testWidgets('tài khoản: thêm, điều chỉnh số dư, xoá', (tester) async {
    setPhoneSize(tester);
    final state = await createState();
    await pushPage(tester, state, const AccountsScreen());
    await tester.tap(find.text('Thêm tài khoản'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Tên tài khoản'),
      'Techcombank',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Số dư ban đầu'),
      '2000000',
    );
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    final tcb = state.accounts.firstWhere((a) => a.name == 'Techcombank');
    expect(state.balanceOf(tcb.id), 2000000);

    await state.addTransaction(
      TransactionRecord(
        type: TxnType.expense,
        amount: 500000,
        accountId: tcb.id!,
        date: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.balanceOf(tcb.id), 1500000);

    // Điều chỉnh số dư thực tế = 1.000.000.
    await tester.longPress(find.text('Techcombank'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Số dư hiện tại'),
      '1000000',
    );
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(state.balanceOf(tcb.id), 1000000);
    expect((await state.repo.transactions()).length, 1);

    // Xoá -> ẩn vì đã có giao dịch.
    await tester.longPress(find.text('Techcombank'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Xoá'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();
    expect(state.accounts.any((a) => a.name == 'Techcombank'), isFalse);
    expect(find.text('Tài khoản'), findsOneWidget);
  });

  testWidgets('hạng mục: thêm và xoá', (tester) async {
    setPhoneSize(tester);
    final state = await createState();
    await pushPage(tester, state, const CategoriesScreen());
    await tester.tap(find.byTooltip('Thêm hạng mục'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Tên mục chi'),
      'Nuôi mèo',
    );
    await tester.tap(find.byIcon(Icons.pets));
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    final cat = state
        .categoriesOf(CategoryKind.expense)
        .firstWhere((c) => c.name == 'Nuôi mèo');
    expect(cat.icon, 'pet');
    await tester.scrollUntilVisible(
      find.text('Nuôi mèo'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Nuôi mèo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Xoá'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();
    expect(
      state.categoriesOf(CategoryKind.expense).any((c) => c.name == 'Nuôi mèo'),
      isFalse,
    );
  });

  testWidgets('hạn mức, ẩn số dư', (tester) async {
    setPhoneSize(tester);
    final state = await createState();
    await tester.pumpWidget(SoThuChiApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Khác').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hạn mức chi tháng'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '5000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(state.settings.monthlyBudget, 5000000);
    await tester.tap(find.text('Tổng quan').last);
    await tester.pumpAndSettle();
    expect(find.text('Hạn mức chi tháng này'), findsOneWidget);
    await tester.tap(find.byTooltip('Ẩn số dư'));
    await tester.pumpAndSettle();
    expect(find.text('••••••••'), findsOneWidget);
  });

  testWidgets('sổ giao dịch: tìm kiếm, vuốt xoá, hoàn tác', (tester) async {
    setPhoneSize(tester);
    final state = await createState();
    final acc = state.accounts.first.id!;
    for (final (note, amount) in [
      ('Ăn trưa', 45000),
      ('Cà phê', 30000),
      ('Grab đi làm', 52000),
    ]) {
      await state.addTransaction(
        TransactionRecord(
          type: TxnType.expense,
          amount: amount,
          accountId: acc,
          note: note,
          date: DateTime.now(),
        ),
      );
    }
    await tester.pumpWidget(SoThuChiApp(state: state));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sổ giao dịch').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tìm kiếm'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ca phe');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cà phê ·'), findsOneWidget);
    expect(find.textContaining('Ăn trưa ·'), findsNothing);
    await tester.tap(find.byTooltip('Đóng tìm kiếm'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.textContaining('Grab đi làm ·'),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();
    expect((await state.repo.transactions()).length, 2);
    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();
    expect((await state.repo.transactions()).length, 3);
  });

  group('Bản tiêu chuẩn (không quyền đọc thông báo)', () {
    setUp(() {
      native.permissions = {'notificationCapture': false, 'microphone': true};
    });

    testWidgets('màn hướng dẫn ghi qua Chia sẻ', (tester) async {
      setPhoneSize(tester, height: 1600);
      final state = await createState();
      await pushPage(tester, state, const AutoCaptureScreen());
      expect(find.text('Ghi từ biên lai ngân hàng'), findsOneWidget);
      expect(find.textContaining('Ghi vào Sổ Thu Chi'), findsWidgets);
      expect(find.text('Cấp quyền'), findsNothing);
      expect(find.text('1. Đọc thông báo'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Phân tích'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phân tích'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chi tiền: 150.000 đ'), findsOneWidget);
    });

    testWidgets('thẻ hướng dẫn ở Tổng quan chỉ hiện đến khi xem', (
      tester,
    ) async {
      setPhoneSize(tester);
      final state = await createState();
      await tester.pumpWidget(SoThuChiApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('Ghi nhanh sau chuyển khoản'), findsOneWidget);
      expect(find.text('Bật tự động ghi chép'), findsNothing);
      await tester.tap(find.text('Ghi nhanh sau chuyển khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Ghi từ biên lai ngân hàng'), findsOneWidget);
      expect(state.settings.onboardedCapture, isTrue);
      Navigator.of(tester.element(find.text('Ghi từ biên lai ngân hàng')))
          .pop();
      await tester.pumpAndSettle();
      expect(find.text('Ghi nhanh sau chuyển khoản'), findsNothing);
    });

    testWidgets('biên lai chưa đọc được số tiền -> nhập tay', (tester) async {
      setPhoneSize(tester, width: 360, height: 700);
      final state = await createState();
      await tester.pumpWidget(
        wrap(
          state,
          PopupHost(
            initial: CaptureData.fromMap({
              ...captureMap('s', 0),
              'content': 'Chuyển tới NGUYEN VAN A',
            }),
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa đọc được số tiền – nói hoặc nhập'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('quick_save')));
      await tester.pump();
      expect(find.text('Nhập số tiền'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('quick_amount')), '120000');
      await tester.tap(find.byKey(const Key('quick_save')));
      await tester.pumpAndSettle();
      expect((await state.repo.transactions()).single.amount, 120000);
    });
  });

  test('CaptureData.fromMap chịu được dữ liệu thiếu', () {
    final c = CaptureData.fromMap(const {'id': 'x'});
    expect(c.amount, 0);
    expect(c.type, TxnType.expense);
    expect(c.bankName, 'Ngân hàng');
    final s = CaptureSettings.fromMap(const {});
    expect(s.enabled, isTrue);
    expect(s.readSms, isTrue);
    expect(s.anyApp, isFalse);
  });

  test('pending bỏ qua bản ghi hỏng', () async {
    native.pending.addAll([captureMap('a', 0), captureMap('b', 1000)]);
    final list = await CaptureChannel.pending();
    expect(list.map((c) => c.id), ['b']);
    // Kênh lỗi không làm sập app.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          CaptureChannel.channel,
          (c) async => throw PlatformException(code: 'x'),
        );
    expect(await CaptureChannel.pending(), isEmpty);
    expect((await CaptureChannel.permissions()).ready, isFalse);
  });

  test('AppState.refreshPending sắp xếp mới nhất trước', () async {
    final state = await createState();
    native.pending.addAll([
      {...captureMap('old', 1000), 'time': 1000},
      {...captureMap('new', 2000), 'time': 5000},
    ]);
    await state.refreshPending();
    expect(state.pending.map((c) => c.id), ['new', 'old']);
    await state.dismissCapture('new');
    expect(state.pending.map((c) => c.id), ['old']);
    expect(native.pending.length, 1);
  });

  // Đảm bảo không còn Timer treo giữa các test.
  tearDown(() async => Future<void>.delayed(Duration.zero));
}
