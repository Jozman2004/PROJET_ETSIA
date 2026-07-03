import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cross_file/cross_file.dart';
import 'package:http_parser/http_parser.dart';
import '../utils/constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  late final Dio _dio;

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401) {
          await _storage.deleteAll();
        }
        return handler.next(e);
      },
    ));
  }

  // ============================================================
  // AUTH
  // ============================================================
  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _dio.post('/api/auth/login', data: {
      'email': email,
      'password': password,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/auth/register', data: data);
    return res.data;
  }

  // ============================================================
  // POSTS
  // ============================================================
  Future<List<dynamic>> getFeed({int page = 0}) async {
    final res = await _dio.get(
      '/api/posts/feed',
      queryParameters: {'limit': 20, 'offset': page * 20},
    );
    return res.data;
  }

  Future<Map<String, dynamic>> getPost(String postId) async {
    final res = await _dio.get('/api/posts/$postId');
    return res.data;
  }

  Future<List<dynamic>> getComments(String postId) async {
    final res = await _dio.get('/api/posts/$postId/comments');
    return res.data;
  }

  Future<Map<String, dynamic>> createPost({
    String? content,
    String? tags,
    List<String>? filePaths,
    bool isInstitutional = false,
  }) async {
    final form = FormData();
    if (content?.isNotEmpty == true) form.fields.add(MapEntry('content', content!));
    if (tags?.isNotEmpty == true) form.fields.add(MapEntry('tags', tags!));
    if (isInstitutional) form.fields.add(const MapEntry('is_institutional', 'true'));

    if (filePaths != null && filePaths.isNotEmpty) {
      for (int i = 0; i < filePaths.length; i++) {
        final path = filePaths[i];
        if (path.isEmpty) continue;
        final ext = path.split('.').last.toLowerCase();
        final isVideo = ['mp4', 'mov', 'avi', 'mkv'].contains(ext);
        final mimeType = isVideo ? 'video/mp4' : 'image/jpeg';
        final filename = 'media_${DateTime.now().millisecondsSinceEpoch}_$i.${isVideo ? 'mp4' : 'jpg'}';

        final xFile = XFile(path);
        final bytes = await xFile.readAsBytes();
        final multipartFile = MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: MediaType.parse(mimeType),
        );
        form.files.add(MapEntry('media[]', multipartFile));
      }
    }

    final res = await _dio.post(
      '/api/posts',
      data: form,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
    return res.data;
  }

  Future<void> likePost(String postId) => _dio.post('/api/posts/$postId/like');
  Future<void> unlikePost(String postId) => _dio.delete('/api/posts/$postId/like');

  Future<Map<String, dynamic>> commentPost(String postId, String content) async {
    final res = await _dio.post('/api/posts/$postId/comment', data: {'content': content});
    return res.data;
  }

  Future<void> deletePost(String postId) => _dio.delete('/api/posts/$postId');
  Future<void> deleteComment(String commentId) => _dio.delete('/api/comments/$commentId');

  // ============================================================
  // USERS
  // ============================================================
  Future<Map<String, dynamic>> getProfile(String userId) async {
    final res = await _dio.get('/api/users/$userId');
    return res.data;
  }

  Future<void> deleteAvatar() async {
    await _dio.delete('/api/users/me/avatar');
  }

  Future<List<dynamic>> getAllMembers() async {
    final res = await _dio.get('/api/users/all');
    return res.data;
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/api/users/me');
    return res.data;
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final res = await _dio.put('/api/users/me', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>> updateAvatar(String filePath) async {
    final xFile = XFile(filePath);
    final bytes = await xFile.readAsBytes();

    String mimeType = 'image/jpeg';
    if (filePath.toLowerCase().endsWith('.png')) mimeType = 'image/png';
    else if (filePath.toLowerCase().endsWith('.gif')) mimeType = 'image/gif';
    else if (filePath.toLowerCase().endsWith('.webp')) mimeType = 'image/webp';

    final form = FormData.fromMap({
      'media': MultipartFile.fromBytes(
        bytes,
        filename: 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
        contentType: MediaType.parse(mimeType),
      ),
    });

    final res = await _dio.put(
      '/api/users/me/avatar',
      data: form,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
    return res.data;
  }

  Future<List<dynamic>> getUserPosts(String userId, {int page = 0}) async {
    final res = await _dio.get(
      '/api/users/$userId/posts',
      queryParameters: {'limit': 20, 'offset': page * 20},
    );
    return res.data;
  }

  Future<List<dynamic>> getFollowers(String userId) async {
    final res = await _dio.get('/api/users/$userId/followers');
    return res.data;
  }

  Future<List<dynamic>> getFollowing(String userId) async {
    final res = await _dio.get('/api/users/$userId/following');
    return res.data;
  }

  Future<Map<String, dynamic>> getFollowStatus(String userId) async {
    final res = await _dio.get('/api/users/$userId/follow-status');
    return res.data;
  }

  Future<void> followUser(String userId) => _dio.post('/api/users/$userId/follow');
  Future<void> unfollowUser(String userId) => _dio.delete('/api/users/$userId/follow');

  Future<List<dynamic>> getSuggestions() async {
    final res = await _dio.get('/api/users/suggestions');
    return res.data;
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final res = await _dio.get('/api/users/search', queryParameters: {'q': query});
    return res.data;
  }

  // ============================================================
  // COMMENTAIRES & RÉPONSES
  // ============================================================
  Future<void> likeComment(String commentId) async => await _dio.post('/api/comments/$commentId/like');
  Future<void> unlikeComment(String commentId) async => await _dio.delete('/api/comments/$commentId/like');

  Future<List<dynamic>> getReplies(String commentId) async {
    final res = await _dio.get('/api/replies/$commentId');
    return res.data;
  }

  Future<Map<String, dynamic>> addReply(String commentId, String content) async {
    final res = await _dio.post('/api/replies/$commentId', data: {'content': content});
    return res.data;
  }

  Future<Map<String, dynamic>> addComment(String postId, String content, {String? parentId}) async {
    if (parentId != null && parentId.isNotEmpty) {
      return addReply(parentId, content);
    } else {
      final res = await _dio.post('/api/posts/$postId/comment', data: {'content': content});
      return res.data;
    }
  }

  // ============================================================
  // MESSAGES DIRECTS (DM)
  // ============================================================
  Future<Map<String, dynamic>> sendMessage(String receiverId, String content) async {
    final res = await _dio.post('/api/messages', data: {
      'receiverId': receiverId,
      'content': content,
    });
    return res.data;
  }

  Future<Map<String, dynamic>> sendMessageWithFile(
    String receiverId,
    String filePath, {
    String? content,
    required String originalName,
  }) async {
    try {
      final form = FormData();
      form.fields.add(MapEntry('receiverId', receiverId));
      if (content?.isNotEmpty == true) form.fields.add(MapEntry('content', content!));

      final xFile = XFile(filePath);
      final bytes = await xFile.readAsBytes();
      final fileName = originalName.isNotEmpty ? originalName : 'file_${DateTime.now().millisecondsSinceEpoch}';

      form.files.add(MapEntry(
        'file',
        MultipartFile.fromBytes(bytes, filename: fileName),
      ));

      final res = await _dio.post(
        '/api/messages',
        data: form,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );
      return res.data;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<dynamic>> getConversation(String userId) async {
    final res = await _dio.get('/api/messages/$userId');
    return res.data;
  }

  Future<void> markAsRead(String messageId) async => await _dio.put('/api/messages/$messageId/read');

  Future<List<dynamic>> getConversations() async {
    final res = await _dio.get('/api/messages/conversations/list');
    return res.data;
  }

  // ============================================================
  // GROUPES
  // ============================================================

  Future<List<dynamic>> getMyGroups() async {
    final res = await _dio.get('/api/groups');
    return res.data;
  }

  Future<Map<String, dynamic>> getGroupDetail(String groupId) async {
    final res = await _dio.get('/api/groups/$groupId');
    return res.data;
  }

  // Créer un groupe (avec description optionnelle)
  Future<Map<String, dynamic>> createGroup(String name, List<String> memberIds, {String? description}) async {
    try {
      final res = await _dio.post('/api/groups', data: {
        'name': name,
        'memberIds': memberIds,
        if (description != null && description.isNotEmpty) 'description': description,
      });
      return res.data;
    } catch (e) {
      if (e is DioException) {
        throw Exception('Erreur création groupe: ${e.response?.data ?? e.message}');
      }
      rethrow;
    }
  }

  // Créer un groupe avec avatar (optionnel, backend non prêt)
  Future<Map<String, dynamic>> createGroupWithAvatar({
    required String name,
    required List<String> participantIds,
    File? avatarFile,
  }) async {
    if (avatarFile != null) {
      // Ignoré jusqu'à ce que le backend supporte le multipart
    }
    return createGroup(name, participantIds);
  }

  // Modifier le nom ou la description d'un groupe
  Future<void> updateGroup(String groupId, String name, {String? description}) async {
    final data = <String, dynamic>{};
    if (name.trim().isNotEmpty) data['name'] = name.trim();
    if (description != null) data['description'] = description.trim().isEmpty ? null : description.trim();
    await _dio.patch('/api/groups/$groupId', data: data);
  }

  Future<void> deleteGroup(String groupId) async {
    await _dio.delete('/api/groups/$groupId');
  }

  Future<void> addGroupMembers(String groupId, List<String> memberIds) async {
    await _dio.post('/api/groups/$groupId/members', data: {'memberIds': memberIds});
  }

  Future<void> removeGroupMember(String groupId, String memberId) async {
    await _dio.delete('/api/groups/$groupId/members/$memberId');
  }

  Future<void> promoteGroupMember(String groupId, String memberId) async {
    await _dio.patch('/api/groups/$groupId/members/$memberId/promote');
  }

  Future<List<dynamic>> getGroupMessages(String groupId, {int limit = 50}) async {
    final res = await _dio.get(
      '/api/groups/$groupId/messages',
      queryParameters: {'limit': limit},
    );
    return res.data;
  }

  Future<Map<String, dynamic>> sendGroupMessage(String groupId, String content) async {
    final res = await _dio.post('/api/groups/$groupId/messages', data: {'content': content});
    return res.data;
  }

  Future<Map<String, dynamic>> sendGroupMessageWithFile(
    String groupId,
    String filePath, {
    String? content,
    String? originalName,
  }) async {
    final fileName = originalName ?? filePath.split('/').last;
    final xFile = XFile(filePath);
    final bytes = await xFile.readAsBytes();

    final formData = FormData.fromMap({
      if (content != null && content.isNotEmpty) 'content': content,
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });

    final res = await _dio.post('/api/groups/$groupId/messages', data: formData);
    return res.data;
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================
  Future<List<dynamic>> getNotifications() async {
    final res = await _dio.get('/api/notifications');
    return res.data;
  }

  Future<Map<String, dynamic>> getUnreadCount() async {
    final res = await _dio.get('/api/notifications/unread-count');
    return res.data;
  }

  Future<void> markNotifRead(String notificationId) async => await _dio.put('/api/notifications/$notificationId/read');
  Future<void> markAllNotifsRead() async => await _dio.put('/api/notifications/read-all');

  // ============================================================
  // SIGNALEMENTS & ADMIN
  // ============================================================
  Future<Map<String, dynamic>> reportPost(String postId, String reason) async {
    final res = await _dio.post('/api/reports', data: {'postId': postId, 'reason': reason});
    return res.data;
  }

  Future<List<dynamic>> getReports({String status = 'pending'}) async {
    final res = await _dio.get('/api/reports', queryParameters: {'status': status});
    return res.data;
  }

  Future<void> resolveReport(String reportId, String action, String status) async {
    await _dio.put('/api/reports/$reportId/resolve', data: {'action': action, 'status': status});
  }

  Future<Map<String, dynamic>> getAdminStats() async {
    final res = await _dio.get('/api/admin/stats');
    return res.data;
  }

  Future<List<dynamic>> getAdminUsers({String search = ''}) async {
    final res = await _dio.get('/api/admin/users', queryParameters: {'search': search});
    return res.data;
  }

  Future<void> changeUserRole(String userId, String role) async {
    await _dio.put('/api/admin/users/$userId/role', data: {'role': role});
  }

  Future<Map<String, dynamic>> toggleUserActive(String userId) async {
    final res = await _dio.put('/api/admin/users/$userId/toggle');
    return res.data;
  }

  // ============================================================
  // ÉPINGLAGE DE MESSAGE (groupes)
  // ============================================================
  Future<void> pinGroupMessage(String groupId, String messageId) async {
    await _dio.patch('/api/groups/$groupId/messages/$messageId/pin');
  }

  Future<void> unpinGroupMessage(String groupId, String messageId) async {
    await _dio.delete('/api/groups/$groupId/messages/$messageId/pin');
  }

  Future<Map<String, dynamic>?> getPinnedMessage(String groupId) async {
    try {
      final res = await _dio.get('/api/groups/$groupId/pinned-message');
      return res.data;
    } catch (e) {
      return null;
    }
  }
}