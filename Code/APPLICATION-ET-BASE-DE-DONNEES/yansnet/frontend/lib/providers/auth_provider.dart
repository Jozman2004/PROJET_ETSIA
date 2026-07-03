// lib/providers/auth_provider.dart — VERSION COMPLÈTE ET CORRIGÉE
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _loading = true;

  User? get user => _user;
  bool get loading => _loading;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.role == 'admin';
  bool get isModerator => ['admin', 'moderator'].contains(_user?.role);

  final _storage = const FlutterSecureStorage();
  final _api = ApiService();
  final _socket = SocketService();

  Future<void> init() async {
    try {
      final token = await _storage.read(key: 'token');
      final userJson = await _storage.read(key: 'user');
      if (token != null && userJson != null) {
        _user = User.fromJson(jsonDecode(userJson));
        _socket.connect(_user!.id);
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await _api.login(email, password);
    await _save(data);
  }

  Future<void> register(Map<String, dynamic> data) async {
    final res = await _api.register(data);
    await _save(res);
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    _socket.disconnect();
    _user = null;
    notifyListeners();
  }

  void updateUser(User updatedUser) {
    _user = updatedUser;
    _storage.write(key: 'user', value: jsonEncode(updatedUser.toJson()));
    notifyListeners();
  }

  Future<void> _save(Map<String, dynamic> data) async {
    final token = data['token'];
    _user = User.fromJson(data['user']);
    await _storage.write(key: 'token', value: token);
    await _storage.write(key: 'user', value: jsonEncode(_user!.toJson()));
    _socket.connect(_user!.id);
    notifyListeners();
  }
}