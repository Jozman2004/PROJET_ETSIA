// lib/screens/messages/dm_info_screen.dart
import 'package:flutter/material.dart';

class DmInfoScreen extends StatelessWidget {
  final String userId;
  final String userName;
  const DmInfoScreen({super.key, required this.userId, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Informations sur $userName')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('User ID: $userId'),
            const SizedBox(height: 8),
            Text('Nom: $userName'),
          ],
        ),
      ),
    );
  }
}