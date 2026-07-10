import 'package:flutter/material.dart';
import '../utils/constants.dart';

class SharedPostCard extends StatelessWidget {
  final Map<String, dynamic> metadata;
  final VoidCallback? onTap;
  final String? sharedBy; // nom de la personne qui a partagé

  const SharedPostCard({
    super.key,
    required this.metadata,
    this.onTap,
    this.sharedBy,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.grey[50],
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Badge "Partagé par"
              if (sharedBy != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9E1B22).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.share_rounded, size: 14, color: Color(0xFF9E1B22)),
                      const SizedBox(width: 4),
                      Text(
                        'Partagé par $sharedBy',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9E1B22)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              // Auteur du post
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundImage: metadata['avatarUrl'] != null
                        ? NetworkImage('${AppConstants.baseUrl}${metadata['avatarUrl']}')
                        : null,
                    child: metadata['avatarUrl'] == null
                        ? Text(
                            (metadata['fullName'] ?? '?')[0].toUpperCase(),
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metadata['fullName'] ?? 'Utilisateur',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Text(
                        '@${metadata['username'] ?? ''}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Contenu
              if (metadata['content'] != null && metadata['content'].toString().isNotEmpty)
                Text(
                  metadata['content'],
                  style: const TextStyle(fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              if (metadata['mediaUrl'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      '${AppConstants.baseUrl}${metadata['mediaUrl']}',
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: const [
                  Icon(Icons.open_in_new_rounded, size: 14, color: Colors.grey),
                  SizedBox(width: 4),
                  Text(
                    'Voir la publication',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}