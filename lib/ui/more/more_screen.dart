import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../capture/capture_channel.dart';
import '../../core/format.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'accounts_screen.dart';
import 'auto_capture_screen.dart';
import 'categories_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final budget = state.settings.monthlyBudget;
    void push(Widget w) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Khác'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bolt),
                  title: const Text('Tự động ghi chép'),
                  subtitle: Text(
                    CaptureChannel.supported
                        ? 'Đọc thông báo ngân hàng, bật cửa sổ ghi nhanh + giọng nói'
                        : 'Dùng Phím tắt iOS để ghi từ SMS ngân hàng',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const AutoCaptureScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet),
                  title: const Text('Tài khoản'),
                  subtitle: Text(
                    '${state.accounts.length} tài khoản · ${formatMoney(state.totalBalance)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const AccountsScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.category),
                  title: const Text('Hạng mục thu chi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(const CategoriesScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: const Text('Hạn mức chi tháng'),
                  subtitle: Text(budget > 0 ? formatMoney(budget) : 'Chưa đặt'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editBudget(context, state),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.mic),
                  title: const Text('Tự bật micro khi ghi nhanh'),
                  value: state.settings.autoListen,
                  onChanged: state.setAutoListen,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.visibility_off),
                  title: const Text('Ẩn số dư ở Tổng quan'),
                  value: state.settings.hideBalance,
                  onChanged: state.setHideBalance,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.table_view),
                  title: const Text('Xuất Excel (CSV)'),
                  subtitle: const Text('Toàn bộ giao dịch'),
                  onTap: () => _exportCsv(context, state),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.backup),
                  title: const Text('Sao lưu dữ liệu'),
                  subtitle: const Text(
                    'Tạo tệp .json để lưu Drive, Zalo, email…',
                  ),
                  onTap: () => _backup(context, state),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Khôi phục dữ liệu'),
                  subtitle: const Text(
                    'Từ tệp sao lưu (ghi đè dữ liệu hiện tại)',
                  ),
                  onTap: () => _restore(context, state),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Sổ Thu Chi 1.0.0'),
              subtitle: Text(
                'Dữ liệu lưu trên máy của bạn. Không quảng cáo, không gửi dữ liệu ra ngoài.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editBudget(BuildContext context, AppState state) async {
    final ctrl = TextEditingController(
      text: state.settings.monthlyBudget > 0
          ? formatNumber(state.settings.monthlyBudget)
          : '',
    );
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hạn mức chi mỗi tháng'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [MoneyInputFormatter()],
          decoration: const InputDecoration(
            suffixText: 'đ',
            hintText: '0 = không đặt',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parseMoneyInput(ctrl.text)),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (v != null) await state.setMonthlyBudget(v);
  }

  Future<File> _writeTemp(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsString(content);
    return f;
  }

  String _stamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}';
  }

  Future<void> _exportCsv(BuildContext context, AppState state) async {
    try {
      final csv = await state.repo.exportCsv();
      final f = await _writeTemp('so_thu_chi_${_stamp()}.csv', csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(f.path, mimeType: 'text/csv')],
          subject: 'Sổ thu chi',
        ),
      );
    } catch (e) {
      if (context.mounted) showSnack(context, 'Không xuất được: $e');
    }
  }

  Future<void> _backup(BuildContext context, AppState state) async {
    try {
      final data = await state.repo.exportAll();
      final f = await _writeTemp(
        'so_thu_chi_backup_${_stamp()}.json',
        const JsonEncoder.withIndent(' ').convert(data),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(f.path, mimeType: 'application/json')],
          subject: 'Sao lưu Sổ thu chi',
        ),
      );
    } catch (e) {
      if (context.mounted) showSnack(context, 'Không sao lưu được: $e');
    }
  }

  Future<void> _restore(BuildContext context, AppState state) async {
    try {
      final res = await FilePicker.pickFiles(type: FileType.any);
      if (res.isEmpty) return;
      final bytes = await res.first.readAsBytes();
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map) throw const FormatException('Tệp không hợp lệ');
      if (!context.mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Khôi phục dữ liệu?',
        message: 'Toàn bộ dữ liệu hiện tại sẽ được thay bằng bản sao lưu.',
        confirm: 'Khôi phục',
        destructive: true,
      );
      if (!ok) return;
      await state.importBackup(Map<String, Object?>.from(data));
      if (context.mounted) showSnack(context, 'Đã khôi phục dữ liệu');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Không khôi phục được: $e');
    }
  }
}
