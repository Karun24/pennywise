import 'dart:async';
import 'package:flutter/services.dart';

class ShortcutAction {
  const ShortcutAction({
    required this.action,
    this.text,
  });

  final String action;
  final String? text;

  bool get isAddExpense => action == 'pennywise.action.ADD_EXPENSE';
  bool get isAddIncome => action == 'pennywise.action.ADD_INCOME';
  bool get isAddNote => action == 'pennywise.action.ADD_NOTE';
  bool get isProcessText =>
      action == 'android.intent.action.PROCESS_TEXT' && text != null && text!.isNotEmpty;

  factory ShortcutAction.fromMap(Map<dynamic, dynamic> map) {
    return ShortcutAction(
      action: map['action'] as String? ?? '',
      text: map['text'] as String?,
    );
  }
}

/// Service that handles Android launcher shortcuts and Process Text intents.
class ShortcutService {
  ShortcutService._();
  static final instance = ShortcutService._();

  static const _channel = MethodChannel('com.pennywise.pennywise/shortcuts');
  final _controller = StreamController<ShortcutAction>.broadcast();

  Stream<ShortcutAction> get stream => _controller.stream;

  void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onActionReceived') {
        final args = call.arguments;
        if (args is Map) {
          _controller.add(ShortcutAction.fromMap(args));
        }
      }
    });
  }

  Future<ShortcutAction?> getInitialAction() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getInitialAction');
      if (res != null) {
        return ShortcutAction.fromMap(res);
      }
    } catch (_) {}
    return null;
  }
}
