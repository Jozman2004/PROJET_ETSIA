// lib/utils/constants.dart

class AppConstants {
  
  static const String baseUrl = 'http://localhost:5000';
  static const String socketUrl = 'http://localhost:5000';

  // Endpoints
  static const String loginEndpoint = '/api/auth/login';
  static const String registerEndpoint = '/api/auth/register';
  static const String feedEndpoint = '/api/posts/feed';
  static const String postsEndpoint = '/api/posts';
  static const String usersEndpoint = '/api/users';
  static const String messagesEndpoint = '/api/messages';
  static const String groupsEndpoint = '/api/groups';

  // Couleurs UCAC-ICAM
  static const int primaryColorValue = 0xFF9E1B22;   // Rouge Bordeaux
  static const int secondaryColorValue = 0xFF006838; // Vert Sapin
  static const int accentColorValue = 0xFFF39200;    // Orange
}