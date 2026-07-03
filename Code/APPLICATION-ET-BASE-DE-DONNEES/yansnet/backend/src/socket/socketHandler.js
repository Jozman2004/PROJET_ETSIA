// socket/socketHandler.js  (ou le fichier où vous initialisez socket.io)
// ✅ VERSION CORRIGÉE — gestion complète des rooms de groupe

module.exports = (io) => {
  // Rendre io accessible globalement pour les controllers
  global.io = io;

  io.on('connection', (socket) => {
    console.log('🔌 Nouveau socket connecté:', socket.id);

    // ── Enregistrement de l'utilisateur ──────────────────────────────────────
    // Le client Flutter émet 'register' avec son userId dès la connexion
    socket.on('register', (userId) => {
      if (!userId) return;
      const roomName = `user_${userId}`;
      socket.join(roomName);
      socket.userId = userId.toString();
      console.log(`✅ User ${userId} enregistré dans la room ${roomName}`);
    });

    // ── Messages privés ──────────────────────────────────────────────────────
    socket.on('private_message', async (data, callback) => {
      try {
        const { receiverId, content } = data;
        if (!receiverId || !content) {
          return callback?.({ error: 'Données manquantes' });
        }
        // Émettre au destinataire
        io.to(`user_${receiverId}`).emit('new_message', {
          senderId:   socket.userId,
          receiverId,
          content,
          created_at: new Date(),
        });
        callback?.({ success: true });
      } catch (err) {
        console.error('private_message error:', err);
        callback?.({ error: 'Erreur serveur' });
      }
    });

    // ── Marquer message comme lu ─────────────────────────────────────────────
    socket.on('mark_read', (messageId) => {
      console.log(`📖 Message ${messageId} marqué comme lu`);
      // Optionnel : mettre à jour en BDD ici ou via un endpoint REST
    });

    // ── Groupes ──────────────────────────────────────────────────────────────

    // ✅ FIX CRITIQUE : le client rejoint la room du groupe
    // Flutter émet 'join_group' avec { groupId }
    socket.on('join_group', ({ groupId }) => {
      if (!groupId) return;
      const roomName = `group_${groupId}`;
      socket.join(roomName);
      console.log(`👥 Socket ${socket.id} (user ${socket.userId}) a rejoint ${roomName}`);
    });

    // Le client quitte la room du groupe (ex: ferme l'écran de chat)
    socket.on('leave_group', ({ groupId }) => {
      if (!groupId) return;
      const roomName = `group_${groupId}`;
      socket.leave(roomName);
      console.log(`🚪 Socket ${socket.id} a quitté ${roomName}`);
    });

    // ── Déconnexion ──────────────────────────────────────────────────────────
    socket.on('disconnect', () => {
      console.log(`❌ Socket déconnecté: ${socket.id} (user ${socket.userId})`);
    });

    socket.on('error', (err) => {
      console.error('⚠️ Socket error:', err);
    });
  });
};