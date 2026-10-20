import 'dart:async';
import 'package:flutter/foundation.dart';
import 'local_store.dart';
import '../domain/models.dart';

class AppLog extends ChangeNotifier {
  AppLog(this.store)
    : entries = List<Json>.from(
        (store.readMap('logs')['items'] as List? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
  final LocalStore store;
  final List<Json> entries;
  Future<void> _writes = Future.value();
  String? persistenceError;
  // Callers supply category and fixed codes only; never accept server messages or payloads.
  void record(String category, String code, {int? status, int? milliseconds}) {
    entries.add({
      'time': DateTime.now().toIso8601String(),
      'category': category,
      'code': code,
      'status': ?status,
      'ms': ?milliseconds,
    });
    if (entries.length > 300) entries.removeRange(0, entries.length - 300);
    _save();
    notifyListeners();
  }

  void _save() {
    final snapshot = entries.map((e) => Map<String, dynamic>.of(e)).toList();
    _writes = _writes
        .then((_) => store.writeMap('logs', {'items': snapshot}))
        .catchError((Object e) {
          persistenceError = '日志保存失败';
        });
  }

  Future<void> get saved => _writes;
  Future<void> clear() async {
    entries.clear();
    _save();
    await saved;
    notifyListeners();
  }

  String export(Iterable<Json> items) => items
      .map(
        (e) =>
            '${e['time']} [${e['category']}] ${e['code']}${e.containsKey('status') ? ' status=${e['status']}' : ''}${e.containsKey('ms') ? ' ms=${e['ms']}' : ''}',
      )
      .join('\n');
}
