import 'package:flutter/cupertino.dart';
import 'screens/messages/messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:app_links/app_links.dart';
import 'package:video_compress/video_compress.dart'; // ✅ AJOUT pour la compression vidéo
import 'providers/auth_provider.dart';
import 'services/api_service.dart';
import 'services/socket_service.dart';
import 'services/notification_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/feed/feed_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/posts/post_detail_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 1. Initialiser ApiService (Dio) AVANT les notifications
  final api = ApiService();
  api.init(); // initialise le Dio, baseUrl, interceptors, etc.

  // ✅ 2. Initialiser la compression vidéo (réduit les logs)
  await VideoCompress.setLogLevel(0);

  // ✅ 3. Initialiser les notifications push (Firebase)
  await NotificationService.init();

  timeago.setLocaleMessages('fr', timeago.FrMessages());

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider()..init(),
      child: const YansnetApp(),
    ),
  );
}

class AppColors {
  static const primary = Color(0xFF9E1B22);
  static const primaryDark = Color(0xFF6E0E13);
  static const primaryLight = Color(0xFFC8383F);
  static const background = Color(0xFFF7F6F8);
  static const surface = Colors.white;
}

class YansnetApp extends StatefulWidget {
  const YansnetApp({super.key});

  @override
  State<YansnetApp> createState() => _YansnetAppState();
}

class _YansnetAppState extends State<YansnetApp> {
  void _listenToUnauthorized() {
    ApiService.onUnauthorized.listen((_) {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.isLoggedIn) {
        authProvider.logout();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session expirée. Veuillez vous reconnecter.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenToUnauthorized();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'YANSNET',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primary,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: Colors.white,
        ),
        textTheme: ThemeData.light().textTheme.apply(
              fontFamily: 'Poppins',
              bodyColor: const Color(0xFF1F1F1F),
              displayColor: const Color(0xFF1F1F1F),
            ),
        splashFactory: InkSparkle.splashFactory,
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: Consumer<AuthProvider>(
        builder: (_, auth, __) {
          if (auth.loading) {
            return const _SplashLoader();
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: child,
            ),
            child: auth.isLoggedIn
                ? const EcranPrincipal(key: ValueKey('main'))
                : const LoginScreen(key: ValueKey('login')),
          );
        },
      ),
    );
  }
}

class _SplashLoader extends StatelessWidget {
  const _SplashLoader();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'YANSNET',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 24),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EcranPrincipal extends StatefulWidget {
  const EcranPrincipal({super.key});

  @override
  State<EcranPrincipal> createState() => _EcranPrincipalState();
}

class _EcranPrincipalState extends State<EcranPrincipal>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  int _unreadCount = 0;
  int _unreadMessages = 0;
  final SocketService _socket = SocketService();

  final List<Widget> _screens = const [
    FeedScreen(),
    SearchScreen(),
    MessagesScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  String? _pendingLink;

  @override
  void initState() {
    super.initState();

    _socket.addUnreadListener((count) {
      if (mounted) {
        setState(() {
          _unreadCount = count;
        });
      }
    });

    _socket.addUnreadMessagesListener((count) {
      if (mounted) {
        setState(() {
          _unreadMessages = count;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _unreadCount = _socket.unreadCount;
        _unreadMessages = _socket.unreadMessagesCount;
      });
    });

    _initDeepLinks();
  }

  @override
  void dispose() {
    _socket.removeUnreadListener((count) {});
    _socket.removeUnreadMessagesListener((count) {});
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();

    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        _handleLink(initialLink.toString());
      }
    } catch (e) {
      print('❌ Erreur lien initial: $e');
    }

    appLinks.uriLinkStream.listen((Uri link) {
      _handleLink(link.toString());
    }, onError: (err) {
      print('❌ Erreur stream deep link: $err');
    });
  }

  void _handleLink(String link) {
    final uri = Uri.parse(link);
    final pathSegments = uri.pathSegments;

    if ((uri.scheme == 'yansnet' && uri.host == 'post') ||
        (uri.scheme.startsWith('http') &&
            pathSegments.isNotEmpty &&
            pathSegments.first == 'post')) {
      final postId = pathSegments.last;
      print('📱 Deep link vers le post: $postId');
      _navigateToPost(postId);
    } else {
      print('🔗 Lien non reconnu: $link');
    }
  }

  void _navigateToPost(String postId) {
    if (!mounted) {
      _pendingLink = postId;
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: postId),
      ),
    );
  }

  void _onTap(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingLink != null && mounted) {
      final postId = _pendingLink!;
      _pendingLink = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToPost(postId);
      });
    }

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: _FluidBottomNav(
        index: _index,
        unreadCount: _unreadCount,
        unreadMessages: _unreadMessages,
        onTap: _onTap,
      ),
    );
  }
}

class _FluidBottomNav extends StatelessWidget {
  const _FluidBottomNav({
    required this.index,
    required this.unreadCount,
    required this.unreadMessages,
    required this.onTap,
  });

  final int index;
  final int unreadCount;
  final int unreadMessages;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Accueil'),
    (icon: Icons.search_outlined, activeIcon: Icons.search_rounded, label: 'Découvrir'),
    (icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Messages'),
    (icon: Icons.notifications_outlined, activeIcon: Icons.notifications_rounded, label: 'Notifs'),
    (icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / _items.length;
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    left: itemWidth * index + (itemWidth - 48) / 2,
                    top: 8,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(_items.length, (i) {
                      final item = _items[i];
                      final selected = i == index;
                      final showBadge = (i == 3 && unreadCount > 0) ||
                          (i == 2 && unreadMessages > 0);
                      final badgeCount = i == 3
                          ? unreadCount
                          : i == 2
                              ? unreadMessages
                              : 0;

                      return Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => onTap(i),
                          child: SizedBox(
                            height: 64,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                AnimatedScale(
                                  duration: const Duration(milliseconds: 220),
                                  scale: selected ? 1.0 : 0.92,
                                  curve: Curves.easeOutBack,
                                  child: Icon(
                                    selected ? item.activeIcon : item.icon,
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.grey.shade500,
                                    size: 25,
                                  ),
                                ),
                                if (showBadge)
                                  Positioned(
                                    top: 6,
                                    right: itemWidth / 2 - 22,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: Colors.white, width: 1.5),
                                      ),
                                      constraints: const BoxConstraints(
                                          minWidth: 18, minHeight: 18),
                                      child: Text(
                                        badgeCount > 99 ? '99+' : '$badgeCount',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}