import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'default_data.dart';

/// Mở / khởi tạo CSDL SQLite của ứng dụng.
class AppDatabase {
  AppDatabase._();

  static const int schemaVersion = 1;
  static const String fileName = 'so_thu_chi.db';

  static Future<Database>? _shared;

  /// CSDL dùng chung trong một Flutter engine.
  static Future<Database> shared() => _shared ??= open();

  static Future<Database> open({
    String? path,
    DatabaseFactory? factory,
    bool seed = true,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), fileName);
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          // WAL cho phép popup và app chính cùng đọc/ghi an toàn.
          if (dbPath != inMemoryDatabasePath) {
            await db.rawQuery('PRAGMA journal_mode = WAL');
          }
          await db.rawQuery('PRAGMA busy_timeout = 3000');
        },
        onCreate: (db, version) async {
          await createSchema(db);
          if (seed) await seedDefaults(db);
        },
      ),
    );
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE accounts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        initial_balance INTEGER NOT NULL DEFAULT 0,
        bank_key TEXT,
        color INTEGER NOT NULL,
        icon TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        include_in_total INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        account_id INTEGER NOT NULL REFERENCES accounts(id),
        to_account_id INTEGER REFERENCES accounts(id),
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        note TEXT NOT NULL DEFAULT '',
        date INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        raw_text TEXT,
        bank_key TEXT
      )''');
    await db.execute('CREATE INDEX idx_txn_date ON transactions(date)');
    await db.execute('CREATE INDEX idx_txn_account ON transactions(account_id)');
    await db.execute(
      'CREATE INDEX idx_txn_category ON transactions(category_id)',
    );
  }

  static Future<void> seedDefaults(DatabaseExecutor db) async {
    var order = 0;
    for (final a in kDefaultAccounts) {
      await db.insert('accounts', a.copyWith(sortOrder: order++).toMap());
    }
    order = 0;
    for (final c in [...kDefaultExpenseCategories, ...kDefaultIncomeCategories]) {
      await db.insert('categories', c.copyWith(sortOrder: order++).toMap());
    }
  }
}
