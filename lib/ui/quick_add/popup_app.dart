import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../../capture/capture_channel.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'quick_add_panel.dart';

/// Ứng dụng tối giản chạy trong cửa sổ nổi (QuickAddActivity) trên màn hình ngân hàng.
class PopupApp extends StatelessWidget {
  const PopupApp({super.key, required this.state, this.initial});

  final AppState state;
  final CaptureData? initial;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Ghi nhanh',
        color: Colors.transparent,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: PopupHost(initial: initial),
      ),
    );
  }
}

class PopupHost extends StatefulWidget {
  const PopupHost({super.key, this.initial, this.onClose});

  final CaptureData? initial;

  /// Ghi đè hành động đóng cửa sổ (test).
  final VoidCallback? onClose;

  @override
  State<PopupHost> createState() => _PopupHostState();
}

class _PopupHostState extends State<PopupHost> {
  final List<CaptureData> _queue = [];
  CaptureData? _current;
  bool _manual = false;
  bool _ready = false;
  StreamSubscription<CaptureData>? _sub;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _sub = CaptureChannel.incoming.listen(_onIncoming);
    _init();
  }

  Future<void> _init() async {
    var first = widget.initial;
    if (first == null) {
      // Mở từ thông báo nhắc: lấy giao dịch chờ mới nhất.
      final pending = [...await CaptureChannel.pending()];
      if (pending.isNotEmpty) {
        pending.sort((a, b) => b.time.compareTo(a.time));
        first = pending.first;
      }
    }
    if (!mounted) return;
    setState(() {
      _current = first;
      _manual = first == null;
      _ready = true;
    });
  }

  void _onIncoming(CaptureData c) {
    if (!mounted) return;
    if (_current?.id == c.id || _queue.any((q) => q.id == c.id)) return;
    setState(() {
      if (_current == null && !_manual) {
        _current = c;
      } else {
        _queue.add(c);
      }
    });
  }

  void _close({String? message}) {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      CaptureChannel.closePopup(message: message);
    }
  }

  void _onDone(QuickAddOutcome outcome) {
    final msg = switch (outcome) {
      QuickAddOutcome.saved => 'Đã lưu giao dịch',
      QuickAddOutcome.later => 'Đã để vào mục chờ ghi',
      _ => null,
    };
    if (_queue.isNotEmpty) {
      setState(() {
        _current = _queue.removeAt(0);
        _manual = false;
        _toast = msg;
      });
      return;
    }
    _close(
      message: outcome == QuickAddOutcome.saved
          ? 'Sổ Thu Chi: đã lưu giao dịch'
          : null,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _onDone(
            current != null ? QuickAddOutcome.later : QuickAddOutcome.cancelled,
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  margin: const EdgeInsets.all(12),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: !_ready
                        ? const SizedBox(
                            height: 160,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_toast != null || _queue.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      [
                                        ?_toast,
                                        if (_queue.isNotEmpty)
                                          'Còn ${_queue.length} giao dịch nữa',
                                      ].join(' · '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                QuickAddPanel(
                                  key: ValueKey(current?.id ?? 'manual'),
                                  capture: current,
                                  onDone: _onDone,
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
