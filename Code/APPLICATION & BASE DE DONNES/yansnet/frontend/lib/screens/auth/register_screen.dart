// lib/screens/auth/register_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  bool _loading = false;
  bool _showPass = false;
  String? _selectedFiliere;
  String? _selectedResidence;

  static const filieres = [
    'Génie Informatique', 'Génie Civil',
    'Génie Mécanique', 'Génie Électrique', 'Management',
  ];
  static const residences = [
    'Minicité A', 'Minicité B', 'Minicité C', 'Minicité D', 'Hors campus',
  ];

  Future<void> _register() async {
    if (_fullNameCtrl.text.isEmpty || _usernameCtrl.text.isEmpty ||
        _emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      _showMsg('Remplissez tous les champs obligatoires', isError: true);
      return;
    }
    if (_passCtrl.text.length < 6) {
      _showMsg('Mot de passe : minimum 6 caractères', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      // ✅ CORRECTION : utiliser 'full_name' (snake_case) au lieu de 'fullName'
      final Map<String, dynamic> userData = {
        'email': _emailCtrl.text.trim().toLowerCase(),
        'password': _passCtrl.text,
        'username': _usernameCtrl.text.trim(),
        'full_name': _fullNameCtrl.text.trim(),  // ← clé corrigée
        'promotion': _promoCtrl.text.isNotEmpty ? _promoCtrl.text.trim() : null,
        'residence': _selectedResidence,
        'filiere': _selectedFiliere,
      };
      await context.read<AuthProvider>().register(userData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inscription réussie ! Connectez-vous'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Erreur inscription (brute): $e');
      String msg = 'Inscription impossible';
      if (e is DioException) {
        print('Réponse du backend: ${e.response?.data}');
        if (e.response?.data is Map) {
          msg = (e.response?.data as Map)['error'] ?? msg;
        } else if (e.response?.data is String) {
          msg = e.response?.data ?? msg;
        }
      } else {
        msg = e.toString();
      }
      _showMsg(msg, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMsg(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red[700] : Colors.green[700],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Créer un compte', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Rejoins la communauté UCAC-ICAM', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 28),

            _field(_fullNameCtrl, 'Nom complet *', Icons.person_outline),
            const SizedBox(height: 14),
            _field(_usernameCtrl, "Nom d'utilisateur *", Icons.alternate_email),
            const SizedBox(height: 14),
            _field(_emailCtrl, 'Email universitaire *', Icons.email_outlined, keyboard: TextInputType.emailAddress),
            const SizedBox(height: 14),

            TextField(
              controller: _passCtrl,
              obscureText: !_showPass,
              decoration: InputDecoration(
                labelText: 'Mot de passe *',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF9E1B22), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _field(_promoCtrl, 'Promotion (ex: X2027)', Icons.school_outlined),
            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              value: _selectedFiliere,
              decoration: InputDecoration(
                labelText: 'Filière *',
                prefixIcon: const Icon(Icons.book_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: filieres.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
              onChanged: (v) => setState(() => _selectedFiliere = v),
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              value: _selectedResidence,
              decoration: InputDecoration(
                labelText: 'Résidence',
                prefixIcon: const Icon(Icons.home_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: residences.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => setState(() => _selectedResidence = v),
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9E1B22),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : const Text('Créer mon compte', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {TextInputType? keyboard}) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF9E1B22), width: 2),
        ),
      ),
    );
  }
}