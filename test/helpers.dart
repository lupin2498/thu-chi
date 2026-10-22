import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:so_thu_chi/data/database.dart';
import 'package:so_thu_chi/data/repository.dart';
import 'package:so_thu_chi/state/app_state.dart';
import 'package:so_thu_chi/state/settings.dart';
import 'package:so_thu_chi/ui/theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _initDone = false;

Future<void> initTestEnv() async {
  if (_initDone) return;
  _initDone = true;
  sqfliteFfiInit();
  Intl.defaultLocale = 'vi';
  await initializeDateFormatting('vi');
}

/// CSDL trong bộ nhớ, chạy đồng bộ (dùng được trong testWidgets).
Future<FinanceRepository> createRepo({bool seed = true}) async {
  await initTestEnv();
  final db = await AppDatabase.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfiNoIsolate,
    seed: seed,
  );
  return FinanceRepository(db);
}

Future<AppState> createState({Map<String, Object> prefs = const {}}) async {
  final repo = await createRepo();
  SharedPreferences.setMockInitialValues({'auto_listen': false, ...prefs});
  final settings = await AppSettings.load();
  final state = AppState(repo, settings);
  await state.load();
  return state;
}

/// Bọc widget với Provider + MaterialApp tiếng Việt.
Widget wrap(AppState state, Widget child) {
  return ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    ),
  );
}

/// Mở [page] bằng Navigator.push từ một màn nền (giống luồng thật).
Future<void> pushPage(WidgetTester tester, AppState state, Widget page) async {
  await tester.pumpWidget(
    wrap(
      state,
      Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute<void>(builder: (_) => page),
              ),
              child: const Text('__open__'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('__open__'));
  await tester.pumpAndSettle();
}

void setPhoneSize(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
}) {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
