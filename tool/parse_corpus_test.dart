// So sánh parser Dart với bản Kotlin trên một tập trường hợp lớn:
//   CORPUS_IN=cases.json CORPUS_OUT=dart.json flutter test tool/parse_corpus_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_thu_chi/capture/bank_parser.dart';
import 'package:so_thu_chi/data/models.dart';

void main() {
  test('parse corpus', () {
    final input = Platform.environment['CORPUS_IN'];
    final output = Platform.environment['CORPUS_OUT'];
    if (input == null || output == null) return;
    final cases = (jsonDecode(File(input).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final out = <Object?>[];
    for (final c in cases) {
      final r = BankNotificationParser.parse(
        c['text'] as String,
        title: c['title'] as String?,
        packageName: c['package'] as String?,
        strict: c['strict'] == true,
      );
      out.add(
        r == null
            ? null
            : {
                'amount': r.amount,
                'income': r.type == TxnType.income,
                'content': r.content,
                'balance': r.balance,
                'bank': r.bankKey,
              },
      );
    }
    File(output).writeAsStringSync(jsonEncode(out));
  });
}
