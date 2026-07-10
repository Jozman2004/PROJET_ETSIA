// lib/widgets/mention_text_field.dart
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';

class MentionTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;

  const MentionTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = 'Écrire...',
    this.maxLines = 4,
    this.onSubmitted,
    this.onChanged,
    this.suffixIcon,
  });

  @override
  State<MentionTextField> createState() => _MentionTextFieldState();
}

class _MentionTextFieldState extends State<MentionTextField> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _suggestionsOverlay;
  List<User> _allUsers = [];
  bool _loading = false;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    // Ajouter un écouteur sur le contrôleur parent pour détecter les changements
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    _loadUsers();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _removeSuggestionsOverlay();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final api = ApiService();
      final data = await api.getAllMembers();
      setState(() {
        _allUsers = data.map((j) => User.fromJson(j)).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Erreur chargement utilisateurs : $e');
      setState(() => _loading = false);
    }
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;
    if (cursorPos < 0) {
      _removeSuggestionsOverlay();
      return;
    }

    // Rechercher le dernier @ avant le curseur
    int atPos = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      if (text[i] == '@') {
        atPos = i;
        break;
      }
      if (text[i] == ' ' || text[i] == '\n') break;
    }

    if (atPos != -1) {
      final query = text.substring(atPos + 1, cursorPos).toLowerCase();
      final suggestions = _allUsers.where((u) =>
          u.username.toLowerCase().startsWith(query) ||
          u.fullName.toLowerCase().startsWith(query)
      ).toList().take(5).toList();

      if (suggestions.isNotEmpty) {
        _showSuggestions(suggestions);
        return;
      }
    }
    _removeSuggestionsOverlay();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeSuggestionsOverlay();
    }
  }

  void _showSuggestions(List<User> suggestions) {
    _removeSuggestionsOverlay();
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;

    _suggestionsOverlay = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        top: offset.dy + size.height + 2,
        left: offset.dx,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: const Offset(0, 2),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: suggestions.length,
                itemBuilder: (ctx, i) {
                  final user = suggestions[i];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundImage: user.avatarUrl != null
                          ? NetworkImage('${AppConstants.baseUrl}${user.avatarUrl}')
                          : null,
                      child: user.avatarUrl == null
                          ? Text(user.fullName[0].toUpperCase())
                          : null,
                    ),
                    title: Text(user.fullName),
                    subtitle: Text('@${user.username}'),
                    onTap: () {
                      _insertMention(user);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_suggestionsOverlay!);
  }

  void _removeSuggestionsOverlay() {
    _suggestionsOverlay?.remove();
    _suggestionsOverlay = null;
  }

  void _insertMention(User user) {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;

    // Trouver le @ avant le curseur
    int atPos = -1;
    for (int i = cursorPos - 1; i >= 0; i--) {
      if (text[i] == '@') {
        atPos = i;
        break;
      }
      if (text[i] == ' ' || text[i] == '\n') break;
    }
    if (atPos == -1) {
      _removeSuggestionsOverlay();
      return;
    }

    // Construire la nouvelle chaîne
    final before = text.substring(0, atPos);
    final after = text.substring(cursorPos);
    final String newText = '$before@${user.username} $after';
    final int newCursorPos = atPos + user.username.length + 2;

    // Mettre à jour le contrôleur parent
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    // Notifier les listeners (le parent est déjà mis à jour)
    widget.onChanged?.call(newText);

    // Fermer l'overlay
    _removeSuggestionsOverlay();

    // Forcer le rebuild pour mettre à jour l'UI (par exemple le compteur)
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        maxLines: widget.maxLines,
        minLines: 1,
        decoration: InputDecoration(
          hintText: widget.hintText,
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: widget.suffixIcon,
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}