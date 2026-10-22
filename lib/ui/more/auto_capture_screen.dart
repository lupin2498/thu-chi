import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../capture/bank_apps.dart';
import '../../capture/bank_parser.dart';
import '../../capture/capture_channel.dart';
import '../../core/format.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

const String kSampleMbNotification =
    'TK 0xxx6789|GD: -150,000VND 22/10/26 16:30 |SD: 2,345,678VND|ND: NGUYEN VAN A chuyen tien';

/// Cài đặt tự động ghi chép giao dịch từ thông báo ngân hàng (Android).
class AutoCaptureScreen extends StatefulWidget {
  const AutoCaptureScreen({super.key});

  @override
  State<AutoCaptureScreen> createState() => _AutoCaptureScreenState();
}

class _AutoCaptureScreenState extends State<AutoCaptureScreen>
    with WidgetsBindingObserver {
  CapturePermissions _perm = const CapturePermissions();
  CaptureSettings _settings = const CaptureSettings();
  Set<String> _installed = const {};
  bool _loading = true;
  final _testCtrl = TextEditingController(text: kSampleMbNotification);
  String? _testResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _testCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quay lại từ màn cài đặt hệ thống -> cập nhật trạng thái quyền.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final p = await CaptureChannel.permissions();
    final s = await CaptureChannel.settings();
    final inst = await CaptureChannel.installedPackages();
    if (!mounted) return;
    setState(() {
      _perm = p;
      _settings = s;
      _installed = inst;
      _loading = false;
    });
  }

  Future<void> _update(CaptureSettings s) async {
    setState(() => _settings = s);
    await CaptureChannel.saveSettings(s);
  }

  void _testParse() {
    final r = BankNotificationParser.parse(_testCtrl.text);
    setState(() {
      _testResult = r == null
          ? 'Không nhận ra giao dịch trong nội dung này.'
          : '${r.type.label}: ${formatMoney(r.amount)}'
                '${r.balance != null ? '\nSố dư sau GD: ${formatMoney(r.balance!)}' : ''}'
                '${r.content != null ? '\nNội dung: ${r.content}' : ''}'
                '${r.bankName != null ? '\nNgân hàng: ${r.bankName}' : ''}';
    });
  }

  Future<void> _simulate() async {
    final res = await CaptureChannel.simulate(
      title: 'Thông báo biến động số dư',
      text: _testCtrl.text,
    );
    if (!mounted) return;
    if (res == 'ignored') {
      showSnack(context, 'Nội dung không được nhận là giao dịch');
    } else if (res == 'duplicate') {
      showSnack(
        context,
        'Giao dịch trùng vừa ghi nhận, sửa số tiền để thử lại',
      );
    } else if (res == 'disabled') {
      showSnack(context, 'Tự động ghi chép đang tắt');
    } else {
      showSnack(context, 'Đã giả lập thông báo. Cửa sổ ghi nhanh sẽ hiện ra.');
    }
    await context.read<AppState>().refreshPending();
  }

  @override
  Widget build(BuildContext context) {
    if (!CaptureChannel.supported) return const IosCaptureGuide();
    return Scaffold(
      appBar: AppBar(title: const Text('Tự động ghi chép')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Sau khi chuyển khoản thành công, ngân hàng gửi thông báo biến động số dư. '
                      'Sổ Thu Chi đọc thông báo đó, trích xuất số tiền và bật cửa sổ ghi nhanh với micro chờ sẵn – '
                      'bạn chỉ cần nói tên khoản chi (vd: "ăn trưa") rồi bấm Lưu.\n\n'
                      'Dữ liệu chỉ xử lý trên máy, không gửi đi đâu.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Cấp quyền',
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Column(
                    children: [
                      _PermTile(
                        ok: _perm.notificationListener,
                        title: '1. Đọc thông báo',
                        subtitle: 'Để nhận biết thông báo biến động số dư từ app ngân hàng',
                        onTap: CaptureChannel.openNotificationListenerSettings,
                      ),
                      if (!_perm.notificationListener)
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text(
                            'Nút bật bị mờ / "Cài đặt bị hạn chế"?',
                          ),
                          subtitle: const Text(
                            'Android 13+ chặn ứng dụng cài từ file APK. Mở Thông tin ứng dụng → '
                            'menu ⋮ góc trên → "Cho phép cài đặt bị hạn chế", rồi quay lại bật "Đọc thông báo".',
                          ),
                          trailing: const Icon(Icons.open_in_new),
                          onTap: CaptureChannel.openAppSettings,
                        ),
                      _PermTile(
                        ok: _perm.overlay,
                        title: '2. Hiển thị trên ứng dụng khác',
                        subtitle: 'Để cửa sổ ghi nhanh hiện ngay trên màn hình ngân hàng',
                        onTap: CaptureChannel.openOverlaySettings,
                      ),
                      _PermTile(
                        ok: _perm.microphone,
                        title: '3. Micro',
                        subtitle: 'Để nhập nội dung bằng giọng nói',
                        onTap: () async {
                          await CaptureChannel.requestMicrophone();
                          _load();
                        },
                      ),
                      _PermTile(
                        ok: _perm.postNotifications,
                        title: '4. Gửi thông báo',
                        subtitle: 'Nhắc ghi chép khi không mở được cửa sổ nổi',
                        onTap: () async {
                          await CaptureChannel.requestPostNotifications();
                          _load();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.phone_android),
                        title: const Text('Máy Xiaomi / Oppo / Vivo'),
                        subtitle: const Text(
                          'Bật thêm "Hiển thị cửa sổ bật lên khi chạy nền" và "Tự khởi chạy" cho Sổ Thu Chi',
                        ),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () async {
                          final ok =
                              await CaptureChannel.openBackgroundPopupSettings();
                          if (!ok) await CaptureChannel.openAppSettings();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Tuỳ chọn',
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Bật tự động ghi chép'),
                        value: _settings.enabled,
                        onChanged: (v) =>
                            _update(_settings.copyWith(enabled: v)),
                      ),
                      SwitchListTile(
                        title: const Text('Bật cửa sổ ghi nhanh ngay'),
                        subtitle: const Text(
                          'Tắt: chỉ hiện thông báo nhắc, chạm để ghi',
                        ),
                        value: _settings.showPopup,
                        onChanged: _settings.enabled
                            ? (v) => _update(_settings.copyWith(showPopup: v))
                            : null,
                      ),
                      SwitchListTile(
                        title: const Text('Đọc SMS biến động số dư'),
                        subtitle: const Text(
                          'Từ ứng dụng Tin nhắn (SMS Banking)',
                        ),
                        value: _settings.readSms,
                        onChanged: _settings.enabled
                            ? (v) => _update(_settings.copyWith(readSms: v))
                            : null,
                      ),
                      SwitchListTile(
                        title: const Text('Mọi ứng dụng (nâng cao)'),
                        subtitle: const Text(
                          'Nhận cả ngân hàng chưa có trong danh sách, chỉ khi thông báo có dấu hiệu giao dịch rõ ràng',
                        ),
                        value: _settings.anyApp,
                        onChanged: _settings.enabled
                            ? (v) => _update(_settings.copyWith(anyApp: v))
                            : null,
                      ),
                      Consumer<AppState>(
                        builder: (context, state, _) => SwitchListTile(
                          title: const Text('Tự bật micro khi mở cửa sổ'),
                          value: state.settings.autoListen,
                          onChanged: state.setAutoListen,
                        ),
                      ),
                      Consumer<AppState>(
                        builder: (context, state, _) => SwitchListTile(
                          title: const Text('Tự lưu sau khi nói xong'),
                          subtitle: const Text(
                            'Đếm ngược 3 giây, chạm bất kỳ đâu để huỷ',
                          ),
                          value: state.settings.autoSaveAfterVoice,
                          onChanged: state.setAutoSaveAfterVoice,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Ngân hàng & ví',
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Column(
                    children: [
                      for (final b in kBankApps)
                        CheckboxListTile(
                          dense: true,
                          title: Text(b.name),
                          subtitle: _installed.any(b.packages.contains)
                              ? const Text(
                                  'Đã cài trên máy',
                                  style: TextStyle(color: kIncomeColor),
                                )
                              : null,
                          value: !_settings.disabledBanks.contains(b.key),
                          onChanged: _settings.enabled
                              ? (v) {
                                  final set = {..._settings.disabledBanks};
                                  if (v == true) {
                                    set.remove(b.key);
                                  } else {
                                    set.add(b.key);
                                  }
                                  _update(
                                    _settings.copyWith(disabledBanks: set),
                                  );
                                }
                              : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Thử nghiệm',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _testCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Nội dung thông báo / SMS',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _testParse,
                              child: const Text('Phân tích'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: _simulate,
                              child: const Text('Giả lập thông báo'),
                            ),
                          ),
                        ],
                      ),
                      if (_testResult != null) ...[
                        const SizedBox(height: 8),
                        Text(_testResult!),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '"Giả lập thông báo" chạy đúng luồng thật: phát hiện → cửa sổ ghi nhanh với micro. '
                        'Hãy về màn hình chính trong 3 giây để xem cửa sổ hiện trên ứng dụng khác.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PermTile extends StatelessWidget {
  const _PermTile({
    required this.ok,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool ok;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        ok ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ok ? kIncomeColor : kExpenseColor,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: ok
          ? const Text('Đã bật', style: TextStyle(color: kIncomeColor))
          : FilledButton.tonal(onPressed: onTap, child: const Text('Bật')),
      onTap: onTap,
    );
  }
}

/// Hướng dẫn trên iPhone: iOS không cho đọc thông báo app khác,
/// dùng Phím tắt (Shortcuts) tự chạy khi có SMS ngân hàng.
class IosCaptureGuide extends StatelessWidget {
  const IosCaptureGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            child: Text(n, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Tự động ghi chép (iPhone)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'iOS không cho ứng dụng đọc thông báo của ứng dụng khác. Trên iPhone, hãy dùng ứng dụng Phím tắt để '
            'tự mở cửa sổ ghi nhanh khi nhận SMS biến động số dư:',
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Cài đặt một lần',
            child: Column(
              children: [
                step(
                  '1',
                  'Mở app Phím tắt → tab Tự động hoá → Tạo mục tự động hoá cá nhân.',
                ),
                step(
                  '2',
                  'Chọn "Tin nhắn" → Người gửi: MBBank (hoặc tên ngân hàng của bạn) → chọn "Chạy ngay lập tức".',
                ),
                step(
                  '3',
                  'Thêm tác vụ "Mã hoá URL" với đầu vào là "Nội dung tin nhắn".',
                ),
                step(
                  '4',
                  'Thêm tác vụ "Mở URL": sothuchi://app/add?text=[URL đã mã hoá].',
                ),
                step(
                  '5',
                  'Xong! Mỗi lần có SMS ngân hàng, Sổ Thu Chi mở ra với số tiền sẵn và micro chờ bạn nói nội dung.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Cách khác',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• Sao chép nội dung thông báo/SMS → mở Sổ Thu Chi → "Dán SMS/thông báo".\n'
                  '• Bấm "Nói để ghi" và nói cả số tiền: "ăn trưa 50 nghìn".\n'
                  '• Liên kết ghi trực tiếp: sothuchi://app/add?amount=150000&note=An%20trua',
                  style: style,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
