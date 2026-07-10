import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cross_file/cross_file.dart';
import 'package:http_parser/http_parser.dart';
import '../utils/constants.dart';
import '../utils/config.dart';
import '../models/post.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  late final Dio _dio;
  late final Dio _moderationDio;
  late final Dio _dataDio;

  // Gestion du refresh token
  bool _isRefreshing = false;
  final List<(RequestOptions, ErrorInterceptorHandler)> _pendingRequests = [];

  // Stream pour notifier les événements de déconnexion (401 non récupéré)
  static final _unauthorizedController = StreamController<void>.broadcast();
  static Stream get onUnauthorized => _unauthorizedController.stream;

  void init() {
    // ------------------------------
    // 1. Dio principal (API YANSNET) avec intercepteur JWT + refresh
    // ------------------------------
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'access_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          if (error.response?.statusCode == 401 &&
              request.path != '/api/auth/refresh-token') {
            final refreshToken = await _storage.read(key: 'refresh_token');
            if (refreshToken != null && !_isRefreshing) {
              _isRefreshing = true;
              try {
                final response = await _dio.post(
                  '/api/auth/refresh-token',
                  data: {'refreshToken': refreshToken},
                );
                final newAccessToken = response.data['accessToken'] as String? ?? response.data['token'] as String?;
                if (newAccessToken != null) {
                  await _storage.write(key: 'access_token', value: newAccessToken);
                  request.headers['Authorization'] = 'Bearer $newAccessToken';
                  final retryResponse = await _dio.fetch(request);
                  return handler.resolve(retryResponse);
                } else {
                  await clearTokens();
                  _unauthorizedController.add(null);
                  return handler.reject(error);
                }
              } catch (e) {
                await clearTokens();
                _unauthorizedController.add(null);
                return handler.reject(error);
              } finally {
                _isRefreshing = false;
              }
            } else {
              await clearTokens();
              _unauthorizedController.add(null);
              return handler.reject(error);
            }
          }
          return handler.next(error);
        },
      ),
    );

    // ------------------------------
    // 2. Dio pour la modération (port 5001)
    // ------------------------------
    _moderationDio = Dio(BaseOptions(
      baseUrl: AppConfig.moderationBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));

    // ------------------------------
    // 3. Dio pour le serveur Data (port 5002)
    // ------------------------------
    _dataDio = Dio(BaseOptions(
      baseUrl: AppConfig.dataBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }

  // ============================================================
  // STOCKAGE DES TOKENS (sécurisé)
  // ============================================================
  Future<void> _storeTokens(String accessToken, [String? refreshToken]) async {
    await _storage.write(key: 'access_token', value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: 'refresh_token', value: refreshToken);
    }
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  // ============================================================
  // AUTH (avec gestion des tokens)
  // ============================================================
  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _dio.post('/api/auth/login', data: {
      'email': email,
      'password': password,
    });
    final data = res.data as Map<String, dynamic>;
    final accessToken = data['accessToken'] ?? data['token'];
    final refreshToken = data['refreshToken'];
    if (accessToken != null) {
      await _storeTokens(accessToken, refreshToken);
    }
    return data;
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    final res = await _dio.post('/api/auth/register', data: data);
    final result = res.data as Map<String, dynamic>;
    final accessToken = result['accessToken'] ?? result['token'];
    final refreshToken = result['refreshToken'];
    if (accessToken != null) {
      await _storeTokens(accessToken, refreshToken);
    }
    return result;
  }

  Future<void> logout() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken != null) {
      try {
        await _dio.post('/api/auth/logout', data: {'refreshToken': refreshToken});
      } catch (_) {}
    }
    await clearTokens();
  }

  // ============================================================
  // FCM TOKEN (pour les notifications push)
  // ============================================================
  Future<void> saveFcmToken(String token) async {
    try {
      await _dio.post('/api/users/me/fcm-token', data: {'token': token});
      print('✅ Token FCM enregistré sur le serveur');
    } catch (e) {
      print('❌ Erreur enregistrement FCM token: $e');
    }
  }

  // ============================================================
  // MODÉRATION IA (texte + images + vidéos)
  // ============================================================

  /// Modère un contenu via le service Python (port 5001).
  /// Retourne `true` si le contenu est autorisé, `false` sinon.
  Future<bool> moderateContent({
    required String text,
    List<XFile>? images,
    List<XFile>? videos,
  }) async {
    try {
      final formData = FormData();
      if (text.isNotEmpty) {
        formData.fields.add(MapEntry('text', text));
      }

      // Ajouter les images
      if (images != null && images.isNotEmpty) {
        for (int i = 0; i < images.length; i++) {
          final xFile = images[i];
          final bytes = await xFile.readAsBytes();
          final ext = xFile.name.split('.').last.toLowerCase();
          String mimeType = 'image/jpeg';
          if (ext == 'png') mimeType = 'image/png';
          else if (ext == 'gif') mimeType = 'image/gif';
          else if (['jpg', 'jpeg'].contains(ext)) mimeType = 'image/jpeg';

          formData.files.add(MapEntry(
            'images',
            MultipartFile.fromBytes(
              bytes,
              filename: 'img_$i.$ext',
              contentType: MediaType.parse(mimeType),
            ),
          ));
        }
      }

      // Ajouter les vidéos (champ distinct)
      if (videos != null && videos.isNotEmpty) {
        print('📹 [ApiService] Ajout de ${videos.length} vidéos au FormData');
        for (int i = 0; i < videos.length; i++) {
          final xFile = videos[i];
          final bytes = await xFile.readAsBytes();
          final ext = xFile.name.split('.').last.toLowerCase();

          formData.files.add(MapEntry(
            'videos',
            MultipartFile.fromBytes(
              bytes,
              filename: 'vid_$i.$ext',
              contentType: MediaType.parse('video/mp4'),
            ),
          ));
          print('📎 [ApiService] Vidéo ajoutée : ${xFile.name} (${bytes.length} octets)');
        }
      }

      print('📤 [ApiService] Envoi modération : images=${images?.length ?? 0}, videos=${videos?.length ?? 0}');
      print('📎 [ApiService] Champs du FormData : ${formData.files.map((e) => e.key).toList()}');

      final response = await _moderationDio.post(
        '/moderate',
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        print('✅ [ApiService] Modération acceptée');
        return data['allowed'] == true;
      } else {
        // Statut 400, 500, etc. → contenu refusé
        final data = response.data as Map<String, dynamic>;
        print('🔴 [ApiService] Modération refusée: ${data['reason'] ?? 'raison inconnue'}');
        return false;
      }
    } on DioException catch (e) {
      // Si le service est indisponible (timeout, connexion refusée), on autorise
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        print('⚠️ [ApiService] Service de modération indisponible, publication autorisée.');
        return true;
      }
      // Autres erreurs (ex: 400, 500) → on refuse
      print('❌ [ApiService] Erreur de modération: $e');
      if (e.response != null) {
        print('   → Réponse du serveur: ${e.response?.data}');
      }
      return false;
    } catch (e) {
      print('❌ [ApiService] Erreur inattendue: $e');
      return false;
    }
  }

  // ============================================================
  // SERVEUR DATA (port 5002)
  // ============================================================
  Future<Map<String, dynamic>> analyzeSentiment(String text) async {
    try {
      final response = await _dataDio.post('/sentiment', data: {'texte': text});
      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('❌ Erreur analyse sentiment: $e');
      return {'label': 'NEUTRAL', 'en_detresse': false, 'error': true};
    }
  }

  Future<Map<String, dynamic>> analyzeUserSentiment(String userId, List<String> posts) async {
    try {
      final response = await _dataDio.post(
        '/sentiment/user',
        data: {'user_id': userId, 'posts': posts},
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('❌ Erreur analyse sentiment user: $e');
      return {'alerte': false, 'error': true};
    }
  }

  Future<Map<String, dynamic>> detectHarcelement(String text) async {
    try {
      final response = await _dataDio.post('/harcelement', data: {'texte': text});
      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('❌ Erreur détection harcèlement: $e');
      return {'est_harcelant': false, 'error': true};
    }
  }

  Future<Map<String, dynamic>> detectUserHarcelement(
    String userId,
    List<Map<String, dynamic>> commentaires,
  ) async {
    try {
      final response = await _dataDio.post(
        '/harcelement/user',
        data: {'harceleur_id': userId, 'commentaires': commentaires},
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('❌ Erreur détection harcèlement user: $e');
      return {'alerte': false, 'error': true};
    }
  }

  Future<Map<String, dynamic>> checkSpam(Map<String, dynamic> stats) async {
    try {
      final response = await _dataDio.post('/spam', data: stats);
      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('❌ Erreur détection spam: $e');
      return {'est_spam': false, 'error': true};
    }
  }

  Future<Map<String, dynamic>> getRecommendations(String userId) async {
    try {
      final response = await _dataDio.get('/recommandation/$userId');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('❌ Erreur recommandations: $e');
      return {'posts_recommandes': [], 'utilisateurs_suggeres': [], 'error': true};
    }
  }

  Future<bool> checkDataHealth() async {
    try {
      final response = await _dataDio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Erreur health check Data: $e');
      return false;
    }
  }

  // ============================================================
  // POSTS
  // ============================================================
  Future<List<dynamic>> getFeed({int page = 0}) async {
    final res = await _dio.get(
      '/api/posts/feed',
      queryParameters: {
        'limit': 20,
        'offset': page * 20,
        '_t': DateTime.now().millisecondsSinceEpoch,
      },
    );
    return res.data;
  }

  Future<Map<String, dynamic>> getPost(String postId) async {
    final res = await _dio.get(
      '/api/posts/$postId',
      queryParameters: {'_t': DateTime.now().millisecondsSinceEpoch},
    );
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
    List<String>? mentions,
  }) async {
    final form = FormData();
    if (content?.isNotEmpty == true) form.fields.add(MapEntry('content', content!));
    if (tags?.isNotEmpty == true) form.fields.add(MapEntry('tags', tags!));
    if (isInstitutional) form.fields.add(const MapEntry('is_institutional', 'true'));
    if (mentions != null && mentions.isNotEmpty) {
      form.fields.add(MapEntry('mentions', mentions.join(',')));
    }

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

  Future<Map<String, dynamic>> commentPost(
    String postId,
    String content, {
    List<String>? mentions,
  }) async {
    final data = <String, dynamic>{
      'content': content,
    };
    if (mentions != null && mentions.isNotEmpty) {
      data['mentions'] = mentions.join(',');
    }
    final res = await _dio.post('/api/posts/$postId/comment', data: data);
    return res.data;
  }

  Future<void> deletePost(String postId) => _dio.delete('/api/posts/$postId');
  Future<void> deleteComment(String commentId) => _dio.delete('/api/comments/$commentId');

  // ============================================================
  // REPOSTS
  // ============================================================
  Future<void> repost(String postId, {String? comment}) async {
    final data = <String, dynamic>{};
    if (comment != null && comment.isNotEmpty) data['comment'] = comment;
    await _dio.post('/api/posts/$postId/repost', data: data);
  }

  Future<void> unrepost(String postId) async {
    await _dio.delete('/api/posts/$postId/repost');
  }

  Future<List<dynamic>> getReposts(String postId) async {
    final res = await _dio.get('/api/posts/$postId/reposts');
    return res.data;
  }

  // ============================================================
  // LIKERS
  // ============================================================
  Future<List<Liker>> getLikers(String postId) async {
    final res = await _dio.get('/api/posts/$postId/likers');
    return (res.data as List).map((j) => Liker.fromJson(j)).toList();
  }

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
  // BLOQUER / DÉBLOQUER
  // ============================================================
  Future<void> blockUser(String userId) async {
    try {
      await _dio.post('/api/users/$userId/block', data: {});
    } on DioException catch (e) {
      if (e.response != null) print('❌ Erreur blocage : ${e.response?.data}');
      rethrow;
    }
  }

  Future<void> unblockUser(String userId) async {
    await _dio.delete('/api/users/$userId/block');
  }

  Future<List<dynamic>> getBlockedUsers() async {
    final res = await _dio.get('/api/users/blocked');
    return res.data;
  }

  Future<bool> isUserBlocked(String userId) async {
    try {
      final res = await _dio.get('/api/users/$userId/block-status');
      return res.data['isBlocked'] ?? false;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // COMMENTAIRES & RÉPONSES (avec mentions)
  // ============================================================
  Future<void> likeComment(String commentId) async => await _dio.post('/api/comments/$commentId/like');
  Future<void> unlikeComment(String commentId) async => await _dio.delete('/api/comments/$commentId/like');

  Future<List<dynamic>> getReplies(String commentId) async {
    final res = await _dio.get('/api/replies/$commentId');
    return res.data;
  }

  Future<Map<String, dynamic>> addReply(
    String commentId,
    String content, {
    List<String>? mentions,
  }) async {
    final data = <String, dynamic>{
      'content': content,
    };
    if (mentions != null && mentions.isNotEmpty) {
      data['mentions'] = mentions.join(',');
    }
    final res = await _dio.post('/api/replies/$commentId', data: data);
    return res.data;
  }

  Future<Map<String, dynamic>> addComment(
    String postId,
    String content, {
    String? parentId,
    List<String>? mentions,
  }) async {
    if (parentId != null && parentId.isNotEmpty) {
      return addReply(parentId, content, mentions: mentions);
    } else {
      return commentPost(postId, content, mentions: mentions);
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

  // ✅ SUPPRIMER UN MESSAGE PRIVÉ (pour tout le monde)
  Future<void> deleteMessage(String messageId) async {
    await _dio.delete('/api/messages/$messageId');
  }

  // ✅ MODIFIER UN MESSAGE PRIVÉ
  Future<Map<String, dynamic>> editMessage(String messageId, String content) async {
    final res = await _dio.put('/api/messages/$messageId/edit', data: {'content': content});
    return res.data;
  }

  // ✅ SUPPRIMER UN MESSAGE PRIVÉ "POUR MOI"
  Future<void> deleteMessageForMe(String messageId) async {
    await _dio.delete('/api/messages/$messageId/for-me');
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

  Future<Map<String, dynamic>> createGroup(
    String name,
    List<String> memberIds, {
    String? description,
  }) async {
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

  // ✅ SUPPRIMER UN MESSAGE DE GROUPE (pour tout le monde)
  Future<void> deleteGroupMessage(String groupId, String messageId) async {
    await _dio.delete('/api/groups/$groupId/messages/$messageId');
  }

  // ✅ MODIFIER UN MESSAGE DE GROUPE
  Future<Map<String, dynamic>> editGroupMessage(String groupId, String messageId, String content) async {
    final res = await _dio.put('/api/groups/$groupId/messages/$messageId/edit', data: {'content': content});
    return res.data;
  }

  // ✅ SUPPRIMER UN MESSAGE DE GROUPE "POUR MOI"
  Future<void> deleteGroupMessageForMe(String groupId, String messageId) async {
    await _dio.delete('/api/groups/$groupId/messages/$messageId/for-me');
  }

  // ============================================================
  // MESSAGES DE GROUPE (avec reply_to_id et mentions)
  // ============================================================
  Future<Map<String, dynamic>> sendGroupMessage(
    String groupId,
    String content, {
    String? replyToId,
    List<String>? mentions,
  }) async {
    final data = <String, dynamic>{
      'content': content,
    };
    if (replyToId != null && replyToId.isNotEmpty) {
      data['reply_to_id'] = replyToId;
    }
    if (mentions != null && mentions.isNotEmpty) {
      data['mentions'] = mentions.join(',');
    }
    final res = await _dio.post('/api/groups/$groupId/messages', data: data);
    return res.data;
  }

  // ============================================================
  // ⭐ MÉTHODE CORRIGÉE : envoi de fichier dans un groupe
  // ============================================================
  Future<Map<String, dynamic>> sendGroupMessageWithFile(
    String groupId,
    String filePath, {
    String? content,
    String? originalName,
    String? replyToId,
    List<String>? mentions,
  }) async {
    final fileName = originalName ?? filePath.split('/').last;
    final xFile = XFile(filePath);
    final bytes = await xFile.readAsBytes();

    final formData = FormData();
    // ✅ On ajoute TOUJOURS content, même vide (le backend l'exige)
    formData.fields.add(MapEntry('content', content ?? ''));
    if (replyToId != null && replyToId.isNotEmpty) {
      formData.fields.add(MapEntry('reply_to_id', replyToId));
    }
    if (mentions != null && mentions.isNotEmpty) {
      formData.fields.add(MapEntry('mentions', mentions.join(',')));
    }
    formData.files.add(MapEntry(
      'file',
      MultipartFile.fromBytes(bytes, filename: fileName),
    ));

    try {
      final res = await _dio.post(
        '/api/groups/$groupId/messages',
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );
      return res.data;
    } on DioException catch (e) {
      // Log détaillé pour faciliter le débogage
      print('❌ Erreur upload groupe: ${e.response?.statusCode}');
      print('   → Corps: ${e.response?.data}');
      rethrow;
    }
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

  Future<void> markNotifRead(String notificationId) async =>
      await _dio.put('/api/notifications/$notificationId/read');
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
  // ÉPINGLAGE (groupes)
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

  // ============================================================
  // FOLLOW BATCH
  // ============================================================
  Future<Map<String, dynamic>> getFollowStatusBatch(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final idsParam = userIds.join(',');
    final res = await _dio.get('/api/users/follow-status-batch', queryParameters: {'ids': idsParam});
    return res.data;
  }
}