import 'dart:convert';

/// Key-value persistence for settings, progress and sandbox slots (ENGINE_API.md 13.7).
abstract class SaveStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<List<String>> keys();
}

/// In-memory store (tests, web fallback).
class MemorySaveStore implements SaveStore {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
  @override
  Future<List<String>> keys() async => _m.keys.toList();
}

/// JSON helpers.
String encodeJson(Object? v) => jsonEncode(v);
Object? decodeJson(String s) => jsonDecode(s);
