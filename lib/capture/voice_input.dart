import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceState { idle, initializing, listening, unavailable, denied, error }

/// Bao bọc speech_to_text: nhận dạng tiếng Việt, báo kết quả từng phần.
class VoiceInput extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  VoiceInput({SpeechToText? engine}) : _engine = engine;

  SpeechToText? _engine;
  SpeechToText get _stt => _engine ??= SpeechToText();

  /// Phiên đang giữ micro (SpeechToText dùng chung toàn app).
  static VoiceInput? _owner;
  bool get _isOwner => identical(_owner, this);

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;
  bool get isListening => _state == VoiceState.listening;

  String _message = '';
  String get message => _message;

  /// Mức âm lượng 0..1 để vẽ hiệu ứng mic.
  double level = 0;

  String? _localeId;
  bool _ready = false;
  bool _disposed = false;
  void Function(String text, bool isFinal)? _onResult;
  Timer? _watchdog;

  Future<bool> _ensureReady() async {
    if (_ready) return true;
    _set(VoiceState.initializing, 'Đang khởi động micro…');
    try {
      final ok = await _stt.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
        options: [SpeechToText.androidNoBluetooth],
      );
      if (!ok) {
        final perm = await _stt.hasPermission;
        _set(
          perm ? VoiceState.unavailable : VoiceState.denied,
          perm ? 'Thiết bị chưa hỗ trợ nhận dạng giọng nói. Hãy gõ nội dung.' : 'Chưa cấp quyền micro. Hãy gõ nội dung hoặc cấp quyền trong Cài đặt.',
        );
        return false;
      }
      _localeId = await _pickVietnameseLocale();
      _ready = true;
      return true;
    } on PlatformException catch (e) {
      _set(
        VoiceState.unavailable,
        e.code == 'recognizerNotAvailable'
            ? 'Máy chưa có dịch vụ nhận dạng giọng nói (Google). Hãy gõ nội dung.'
            : 'Không mở được micro (${e.code}). Hãy gõ nội dung.',
      );
      return false;
    } catch (e) {
      _set(VoiceState.error, 'Không mở được micro. Hãy gõ nội dung.');
      return false;
    }
  }

  Future<String?> _pickVietnameseLocale() async {
    try {
      final locales = await _stt.locales();
      for (final l in locales) {
        final id = l.localeId.toLowerCase();
        if (id == 'vi_vn' || id == 'vi-vn') return l.localeId;
      }
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('vi')) return l.localeId;
      }
    } catch (_) {}
    // Không liệt kê được ngôn ngữ (một số máy) -> vẫn yêu cầu tiếng Việt.
    return 'vi_VN';
  }

  /// Bắt đầu nghe. [onResult] nhận văn bản (từng phần và cuối cùng).
  Future<bool> start(void Function(String text, bool isFinal) onResult) async {
    _onResult = onResult;
    if (isListening) return true;
    if (!await _ensureReady()) return false;
    if (_disposed) return false;
    // SpeechToText là singleton: gắn lại listener cho phiên hiện tại.
    _owner = this;
    _stt.errorListener = _handleError;
    _stt.statusListener = _handleStatus;
    try {
      await _stt.listen(
        onResult: _handleResult,
        onSoundLevelChange: (l) {
          // Android trả khoảng -2..10 dB.
          level = ((l + 2) / 12).clamp(0.0, 1.0);
          notifyListeners();
        },
        listenOptions: SpeechListenOptions(
          localeId: _localeId,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 3),
        ),
      );
      _set(VoiceState.listening, 'Đang nghe… hãy nói nội dung');
      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 25), () {
        if (isListening) stop();
      });
      return true;
    } catch (e) {
      _set(VoiceState.error, 'Không bắt đầu nghe được. Hãy thử lại hoặc gõ.');
      return false;
    }
  }

  Future<void> stop() async {
    _watchdog?.cancel();
    if (_ready && _isOwner) {
      try {
        await _stt.stop();
      } catch (_) {}
    }
    if (_state == VoiceState.listening || _state == VoiceState.initializing) {
      _set(VoiceState.idle, '');
    }
  }

  Future<void> cancel() async {
    _watchdog?.cancel();
    _onResult = null;
    if (_ready && _isOwner) {
      try {
        await _stt.cancel();
      } catch (_) {}
    }
    if (!_disposed) _set(VoiceState.idle, '');
  }

  void _handleResult(SpeechRecognitionResult r) {
    final text = r.recognizedWords.trim();
    _onResult?.call(text, r.finalResult);
    if (r.finalResult) {
      _watchdog?.cancel();
      _set(
        VoiceState.idle,
        text.isEmpty ? 'Không nghe rõ, chạm mic để nói lại' : '',
      );
    }
  }

  void _handleStatus(String status) {
    if ((status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) &&
        _state == VoiceState.listening) {
      _set(VoiceState.idle, _message.startsWith('Đang nghe') ? '' : _message);
    }
  }

  void _handleError(SpeechRecognitionError e) {
    _watchdog?.cancel();
    final msg = switch (e.errorMsg) {
      'error_no_match' ||
      'error_speech_timeout' => 'Không nghe rõ, chạm mic để nói lại',
      'error_permission' ||
      'error_insufficient_permissions' => 'Chưa cấp quyền micro',
      'error_network' ||
      'error_network_timeout' ||
      'error_server' => 'Lỗi mạng khi nhận dạng giọng nói, hãy gõ nội dung',
      'error_busy' => 'Micro đang bận, thử lại sau giây lát',
      'error_language_not_supported' || 'error_language_unavailable' =>
        'Máy chưa có gói tiếng Việt cho nhận dạng giọng nói',
      _ => 'Không nhận dạng được (${e.errorMsg})',
    };
    _set(VoiceState.idle, msg);
  }

  void _set(VoiceState s, String msg) {
    if (_disposed) return;
    _state = s;
    _message = msg;
    if (s != VoiceState.listening) level = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    _onResult = null;
    if (_ready && _isOwner) {
      _owner = null;
      _stt.errorListener = null;
      _stt.statusListener = null;
      _stt.cancel().catchError((_) {});
    }
    super.dispose();
  }
}
