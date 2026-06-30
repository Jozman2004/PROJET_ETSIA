import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/user.dart';
import '../../models/post.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../profile/profile_screen.dart';

class _Palette {
  static const primary = Color(0xFF9E1B22);
  static const primaryDark = Color(0xFF6E0E13);
  static const accent = Color(0xFFF39200);
  static const bg = Color(0xFFF7F6F8);
}

enum _SearchMode { people, posts }

enum _DatePeriod { all, today, last7, last30, custom }

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();

  // --- Données brutes ---
  List<User> _members = [];
  List<Post> _posts = [];
  bool _loadingMembers = true;
  bool _loadingPosts = true;

  // --- État de recherche ---
  _SearchMode _mode = _SearchMode.people;
  String _query = '';

  // --- Filtres ---
  final Set<String> _selectedPromos = {};
  final Set<String> _selectedFilieres = {};
  _DatePeriod _datePeriod = _DatePeriod.all;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadPosts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    try {
      final data = await _api.getAllMembers();
      setState(() {
        _members = data.map((j) => User.fromJson(j)).toList();
        _loadingMembers = false;
      });
    } catch (e) {
      setState(() => _loadingMembers = false);
    }
  }

  /// `ApiService.getFeed()` est paginé (20 posts/page). Pour que la
  /// recherche + les filtres aient un pool correct à parcourir, on
  /// charge plusieurs pages d'un coup (jusqu'à _maxFeedPages ou jusqu'à
  /// ce qu'une page revienne vide/incomplète). Si ton volume de posts
  /// est très grand, il serait préférable d'avoir un vrai endpoint de
  /// recherche côté backend plutôt que ce pré-chargement client.
  static const int _maxFeedPages = 5;

  Future<void> _loadPosts() async {
    setState(() => _loadingPosts = true);
    try {
      final all = <Post>[];
      for (int page = 0; page < _maxFeedPages; page++) {
        final data = await _api.getFeed(page: page);
        if (data.isEmpty) break;
        all.addAll(data.map((j) => Post.fromJson(j)));
        if (data.length < 20) break; // dernière page atteinte
      }
      setState(() {
        _posts = all;
        _loadingPosts = false;
      });
    } catch (e) {
      setState(() => _loadingPosts = false);
    }
  }

  Future<void> _refreshCurrent() {
    return _mode == _SearchMode.people ? _loadMembers() : _loadPosts();
  }

  // ----------------- Valeurs de filtre dynamiques -----------------

  /// Le modèle Post ne porte pas la promotion/filière de son auteur :
  /// on les retrouve via une recherche croisée sur userId. Si un post
  /// vient d'un auteur absent de `_members` (liste partielle/paginée),
  /// les filtres promo/filière ne pourront pas le retenir — pour une
  /// précision totale, le mieux serait que le backend renvoie
  /// `promotion`/`filiere` directement dans la réponse `/posts`.
  Map<String, User> get _membersById => {for (final u in _members) u.id: u};

  List<String> get _availablePromos {
    final set = <String>{};
    for (final u in _members) {
      final p = u.promotion;
      if (p != null && p.trim().isNotEmpty) set.add(p.trim());
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _availableFilieres {
    final set = <String>{};
    for (final u in _members) {
      if (u.filiere != null && u.filiere!.trim().isNotEmpty) set.add(u.filiere!.trim());
    }
    final list = set.toList()..sort();
    return list;
  }

  int get _activeFilterCount {
    var count = _selectedPromos.length + _selectedFilieres.length;
    if (_mode == _SearchMode.posts && _datePeriod != _DatePeriod.all) count++;
    return count;
  }

  void _clearFilters() {
    setState(() {
      _selectedPromos.clear();
      _selectedFilieres.clear();
      _datePeriod = _DatePeriod.all;
      _customRange = null;
    });
  }

  // ----------------- Logique de filtrage -----------------

  List<User> get _filteredMembers {
    final q = _query.toLowerCase();
    return _members.where((u) {
      final matchesQuery = q.isEmpty ||
          u.fullName.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q) ||
          (u.filiere?.toLowerCase().contains(q) ?? false);
      final matchesPromo = _selectedPromos.isEmpty || _selectedPromos.contains(u.promotion);
      final matchesFiliere = _selectedFilieres.isEmpty || _selectedFilieres.contains(u.filiere);
      return matchesQuery && matchesPromo && matchesFiliere;
    }).toList();
  }

  List<Post> get _filteredPosts {
    final q = _query.toLowerCase();
    final cutoff = _periodCutoff();
    final byId = _membersById;
    return _posts.where((p) {
      final author = byId[p.userId];
      final matchesQuery = q.isEmpty ||
          (p.content?.toLowerCase().contains(q) ?? false) ||
          p.fullName.toLowerCase().contains(q) ||
          p.username.toLowerCase().contains(q) ||
          p.tags.any((t) => t.toLowerCase().contains(q));
      final matchesPromo = _selectedPromos.isEmpty || (author != null && _selectedPromos.contains(author.promotion));
      final matchesFiliere = _selectedFilieres.isEmpty || (author != null && _selectedFilieres.contains(author.filiere));
      final matchesDate = switch (_datePeriod) {
        _DatePeriod.all => true,
        _DatePeriod.custom => _customRange == null
            ? true
            : !p.createdAt.isBefore(_customRange!.start) &&
                p.createdAt.isBefore(_customRange!.end.add(const Duration(days: 1))),
        _ => cutoff == null ? true : p.createdAt.isAfter(cutoff),
      };
      return matchesQuery && matchesPromo && matchesFiliere && matchesDate;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  DateTime? _periodCutoff() {
    final now = DateTime.now();
    switch (_datePeriod) {
      case _DatePeriod.today:
        return DateTime(now.year, now.month, now.day);
      case _DatePeriod.last7:
        return now.subtract(const Duration(days: 7));
      case _DatePeriod.last30:
        return now.subtract(const Duration(days: 30));
      default:
        return null;
    }
  }

  // ----------------- UI -----------------

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().user?.id ?? '';
    final loading = _mode == _SearchMode.people ? _loadingMembers : _loadingPosts;

    return Scaffold(
      backgroundColor: _Palette.bg,
      body: RefreshIndicator(
        color: _Palette.primary,
        onRefresh: _refreshCurrent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              backgroundColor: _Palette.primary,
              automaticallyImplyLeading: false,
              expandedHeight: 210,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_Palette.primaryDark, _Palette.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Découvrir',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              IconButton(
                                onPressed: _refreshCurrent,
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                                tooltip: 'Actualiser',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _buildSearchField()),
                              const SizedBox(width: 8),
                              _buildFilterButton(),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildModeSwitch(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (_activeFilterCount > 0)
              SliverToBoxAdapter(child: _buildActiveFilterChips()),

            if (loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: _Palette.primary)),
              )
            else if (_mode == _SearchMode.people)
              _buildPeopleSliver(currentUserId)
            else
              _buildPostsSliver(),
          ],
        ),
      ),
    );
  }

  // --- Barre de recherche ---
  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: _mode == _SearchMode.people ? 'Rechercher un étudiant...' : 'Rechercher un post...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[500]),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.grey[500]),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    );
  }

  // --- Bouton filtre avec badge ---
  Widget _buildFilterButton() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: IconButton(
            onPressed: _openFilterSheet,
            icon: const Icon(Icons.tune_rounded, color: _Palette.primary),
          ),
        ),
        if (_activeFilterCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: _Palette.accent, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                '$_activeFilterCount',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  // --- Sélecteur Personnes / Posts ---
  Widget _buildModeSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _buildModeTab('Personnes', Icons.people_alt_rounded, _SearchMode.people),
          _buildModeTab('Posts', Icons.article_rounded, _SearchMode.posts),
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, IconData icon, _SearchMode mode) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? _Palette.primary : Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? _Palette.primary : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Chips des filtres actifs ---
  Widget _buildActiveFilterChips() {
    final chips = <Widget>[
      ..._selectedPromos.map((p) => _activeChip('Promo $p', () => setState(() => _selectedPromos.remove(p)))),
      ..._selectedFilieres.map((f) => _activeChip(f, () => setState(() => _selectedFilieres.remove(f)))),
      if (_mode == _SearchMode.posts && _datePeriod != _DatePeriod.all)
        _activeChip(_periodLabel(_datePeriod), () => setState(() {
              _datePeriod = _DatePeriod.all;
              _customRange = null;
            })),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...chips,
          GestureDetector(
            onTap: _clearFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Tout effacer', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: _Palette.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: _Palette.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 14, color: _Palette.primary),
            ),
          ),
        ],
      ),
    );
  }

  String _periodLabel(_DatePeriod p) {
    switch (p) {
      case _DatePeriod.today:
        return "Aujourd'hui";
      case _DatePeriod.last7:
        return '7 derniers jours';
      case _DatePeriod.last30:
        return '30 derniers jours';
      case _DatePeriod.custom:
        if (_customRange == null) return 'Plage personnalisée';
        final s = _customRange!.start;
        final e = _customRange!.end;
        return '${s.day}/${s.month} → ${e.day}/${e.month}';
      default:
        return 'Tout';
    }
  }

  // --- Bottom sheet de filtres ---
  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        availablePromos: _availablePromos,
        availableFilieres: _availableFilieres,
        selectedPromos: Set.from(_selectedPromos),
        selectedFilieres: Set.from(_selectedFilieres),
        showDateFilter: _mode == _SearchMode.posts,
        datePeriod: _datePeriod,
        customRange: _customRange,
        onApply: (promos, filieres, period, range) {
          setState(() {
            _selectedPromos
              ..clear()
              ..addAll(promos);
            _selectedFilieres
              ..clear()
              ..addAll(filieres);
            _datePeriod = period;
            _customRange = range;
          });
        },
      ),
    );
  }

  // ----------------- Listes résultats -----------------

  Widget _buildPeopleSliver(String currentUserId) {
    final members = _filteredMembers;
    if (members.isEmpty) {
      return SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState('Aucun membre trouvé'));
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _animatedEntry(i, _buildUserCard(members[i], currentUserId)),
          childCount: members.length,
        ),
      ),
    );
  }

  Widget _buildPostsSliver() {
    final posts = _filteredPosts;
    if (posts.isEmpty) {
      return SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState('Aucun post trouvé'));
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _animatedEntry(i, _buildPostCard(posts[i])),
          childCount: posts.length,
        ),
      ),
    );
  }

  Widget _animatedEntry(int i, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + (i * 30).clamp(0, 300)),
      curve: Curves.easeOutCubic,
      builder: (_, value, c) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 16), child: c),
      ),
      child: child,
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: _Palette.primary.withOpacity(0.08), shape: BoxShape.circle),
            child: Icon(
              _mode == _SearchMode.people ? Icons.people_outline_rounded : Icons.article_outlined,
              size: 48,
              color: _Palette.primary.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.black54, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('Essaie d\'ajuster ta recherche ou tes filtres', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
    );
  }

  // --- Carte personne ---
  Future<void> _toggleFollow(User user) async {
    final isFollowing = user.isFollowing ?? false;
    final oldCount = user.followersCount ?? 0;
    try {
      if (isFollowing) {
        await _api.unfollowUser(user.id);
        user.isFollowing = false;
        user.followersCount = oldCount - 1;
      } else {
        await _api.followUser(user.id);
        user.isFollowing = true;
        user.followersCount = oldCount + 1;
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Widget _buildUserCard(User user, String currentUserId) {
    final isMe = user.id == currentUserId;
    final isFollowing = user.isFollowing ?? false;
    final avatarUrl = user.avatarUrl != null ? '${AppConstants.baseUrl}${user.avatarUrl}' : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: user.id))),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [_Palette.accent, _Palette.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.white,
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Text(
                            user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                            style: const TextStyle(color: _Palette.primary, fontWeight: FontWeight.bold, fontSize: 18),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('@${user.username}', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (user.filiere != null) _tag(user.filiere!, _Palette.accent),
                          if (user.promotion != null) _tag(user.promotion!, _Palette.primary),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                isMe
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
                        child: Text('Moi', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w600)),
                      )
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: isFollowing ? Colors.grey[100] : null,
                          gradient: isFollowing ? null : const LinearGradient(colors: [_Palette.primaryDark, _Palette.primary]),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _toggleFollow(user),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Text(
                                isFollowing ? 'Abonné' : 'Suivre',
                                style: TextStyle(color: isFollowing ? Colors.black87 : Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  // --- Carte post ---
  Widget _buildPostCard(Post post) {
    final avatarUrl = post.avatarUrl != null ? '${AppConstants.baseUrl}${post.avatarUrl}' : null;
    final author = _membersById[post.userId];
    // Premier média de la galerie, sinon mediaUrl simple, affiché seulement si c'est une image.
    final firstImage = (post.mediaGallery != null && post.mediaGallery!.isNotEmpty)
        ? post.mediaGallery!.first
        : post.mediaUrl;
    final firstType = (post.mediaTypes != null && post.mediaTypes!.isNotEmpty)
        ? post.mediaTypes!.first
        : post.mediaType;
    final showImage = firstImage != null && (firstType == null || firstType == 'image');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
        border: post.isInstitutional ? Border.all(color: _Palette.accent.withOpacity(0.4), width: 1.2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _Palette.accent,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(post.fullName.isNotEmpty ? post.fullName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(post.fullName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        ),
                        if (post.isInstitutional) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.verified_rounded, size: 14, color: _Palette.accent),
                        ],
                      ],
                    ),
                    Text(
                      timeago.format(post.createdAt, locale: 'fr'),
                      style: TextStyle(color: Colors.grey[500], fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              if (author?.filiere != null) _tag(author!.filiere!, _Palette.accent),
            ],
          ),
          if (post.content != null && post.content!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(post.content!, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
          if (showImage) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network('${AppConstants.baseUrl}$firstImage', fit: BoxFit.cover, height: 160, width: double.infinity),
            ),
          ],
          if (post.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: post.tags.map((t) => _tag('#$t', _Palette.primary)).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.favorite_rounded, size: 16, color: post.userLiked ? _Palette.primary : Colors.grey[400]),
              const SizedBox(width: 4),
              Text('${post.likeCount}', style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
              const SizedBox(width: 16),
              Icon(Icons.mode_comment_outlined, size: 16, color: Colors.grey[400]),
              const SizedBox(width: 4),
              Text('${post.commentCount}', style: TextStyle(color: Colors.grey[600], fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
//                    BOTTOM SHEET DE FILTRES
// ============================================================

class _FilterSheet extends StatefulWidget {
  final List<String> availablePromos;
  final List<String> availableFilieres;
  final Set<String> selectedPromos;
  final Set<String> selectedFilieres;
  final bool showDateFilter;
  final _DatePeriod datePeriod;
  final DateTimeRange? customRange;
  final void Function(Set<String> promos, Set<String> filieres, _DatePeriod period, DateTimeRange? range) onApply;

  const _FilterSheet({
    required this.availablePromos,
    required this.availableFilieres,
    required this.selectedPromos,
    required this.selectedFilieres,
    required this.showDateFilter,
    required this.datePeriod,
    required this.customRange,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _promos = Set.from(widget.selectedPromos);
  late Set<String> _filieres = Set.from(widget.selectedFilieres);
  late _DatePeriod _period = widget.datePeriod;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _range = widget.customRange;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filtres', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  TextButton(
                    onPressed: () => setState(() {
                      _promos.clear();
                      _filieres.clear();
                      _period = _DatePeriod.all;
                      _range = null;
                    }),
                    child: const Text('Réinitialiser', style: TextStyle(color: _Palette.primary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                children: [
                  if (widget.showDateFilter) ...[
                    _sectionTitle('Date de publication'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _periodChip('Tout', _DatePeriod.all),
                        _periodChip("Aujourd'hui", _DatePeriod.today),
                        _periodChip('7 jours', _DatePeriod.last7),
                        _periodChip('30 jours', _DatePeriod.last30),
                        _customRangeChip(),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],
                  _sectionTitle('Promo'),
                  const SizedBox(height: 8),
                  widget.availablePromos.isEmpty
                      ? _noDataHint('Aucune promo disponible pour le moment')
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.availablePromos.map((p) => _multiChip(p, _promos)).toList(),
                        ),
                  const SizedBox(height: 22),
                  _sectionTitle('Filière'),
                  const SizedBox(height: 8),
                  widget.availableFilieres.isEmpty
                      ? _noDataHint('Aucune filière disponible pour le moment')
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.availableFilieres.map((f) => _multiChip(f, _filieres)).toList(),
                        ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _Palette.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    widget.onApply(_promos, _filieres, _period, _range);
                    Navigator.pop(context);
                  },
                  child: const Text('Appliquer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87));

  Widget _noDataHint(String text) => Text(text, style: TextStyle(fontSize: 12.5, color: Colors.grey[400]));

  Widget _multiChip(String label, Set<String> group) {
    final selected = group.contains(label);
    return GestureDetector(
      onTap: () => setState(() => selected ? group.remove(label) : group.add(label)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _Palette.primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _periodChip(String label, _DatePeriod value) {
    final selected = _period == value;
    return GestureDetector(
      onTap: () => setState(() {
        _period = value;
        if (value != _DatePeriod.custom) _range = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _Palette.primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _customRangeChip() {
    final selected = _period == _DatePeriod.custom;
    return GestureDetector(
      onTap: () async {
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: _range,
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: _Palette.primary)),
            child: child!,
          ),
        );
        if (picked != null) {
          setState(() {
            _range = picked;
            _period = _DatePeriod.custom;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _Palette.primary : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_rounded, size: 14, color: selected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              selected && _range != null
                  ? '${_range!.start.day}/${_range!.start.month} → ${_range!.end.day}/${_range!.end.month}'
                  : 'Plage personnalisée',
              style: TextStyle(color: selected ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}