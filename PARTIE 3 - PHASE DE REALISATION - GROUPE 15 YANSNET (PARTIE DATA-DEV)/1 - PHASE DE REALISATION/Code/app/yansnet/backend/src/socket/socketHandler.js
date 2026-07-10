// socket/socketHandler.js — Version avec ping/pong et timeouts
module.exports = (io) => {
  global.io = io;

  // 🔧 Configurer les timeouts pour éviter les déconnexions intempestives
  io.engine.pingTimeout = 60000;   // 60 secondes
  io.engine.pingInterval = 25000;  // 25 secondes

  io.on('connection', (socket) => {
    const socketId = socket.id;
    console.log(`🔌 Nouveau socket connecté: ${socketId}`);

    // Envoyer un ping régulier pour garder la connexion active
    const keepAliveInterval = setInterval(() => {
      if (socket.connected) {
        socket.emit('ping');
        console.log(`📤 Ping envoyé à ${socketId}`);
      }
    }, 30000); // toutes les 30 secondes

    // Répondre au pong du client
    socket.on('pong', () => {
      console.log(`📥 Pong reçu de ${socketId}`);
    });

    // Enregistrement de l'utilisateur
    socket.on('register', (userId) => {
      if (!userId) {
        console.warn(`⚠️ ${socketId} a essayé de s'enregistrer sans userId`);
        return;
      }
      const roomName = `user_${userId}`;
      socket.join(roomName);
      socket.userId = userId.toString();
      console.log(`✅ User ${userId} enregistré dans la room ${roomName} (socket ${socketId})`);
    });

    // Messages privés
    socket.on('private_message', async (data, callback) => {
      try {
        const { receiverId, content, senderId } = data;
        if (!receiverId || !content) {
          return callback?.({ error: 'Données manquantes' });
        }
        io.to(`user_${receiverId}`).emit('new_message', {
          senderId: senderId || socket.userId,
          receiverId,
          content,
          created_at: new Date().toISOString(),
        });
        console.log(`📨 Message privé de ${socket.userId} vers ${receiverId}`);
        callback?.({ success: true });
      } catch (err) {
        console.error(`❌ private_message error: ${err.message}`);
        callback?.({ error: 'Erreur serveur' });
      }
    });

    // Messages de groupe
    socket.on('group_message', async (data, callback) => {
      try {
        const { groupId, content, senderId } = data;
        if (!groupId || !content) {
          return callback?.({ error: 'Données manquantes' });
        }
        const roomName = `group_${groupId}`;
        io.to(roomName).emit('new_group_message', {
          groupId,
          senderId: senderId || socket.userId,
          content,
          created_at: new Date().toISOString(),
        });
        console.log(`📨 Message de groupe ${groupId} de ${socket.userId}`);
        callback?.({ success: true });
      } catch (err) {
        console.error(`❌ group_message error: ${err.message}`);
        callback?.({ error: 'Erreur serveur' });
      }
    });

    // Marquer comme lu
    socket.on('mark_read', (messageId) => {
      console.log(`📖 Message ${messageId} marqué comme lu par ${socket.userId}`);
      // Optionnel : notifier l'expéditeur
    });

    // Rejoindre un groupe
    socket.on('join_group', ({ groupId }) => {
      if (!groupId) return;
      const roomName = `group_${groupId}`;
      socket.join(roomName);
      console.log(`👥 Socket ${socketId} (user ${socket.userId}) a rejoint ${roomName}`);
    });

    // Quitter un groupe
    socket.on('leave_group', ({ groupId }) => {
      if (!groupId) return;
      const roomName = `group_${groupId}`;
      socket.leave(roomName);
      console.log(`🚪 Socket ${socketId} a quitté ${roomName}`);
    });

    // Typing
    socket.on('typing', ({ receiverId, isTyping }) => {
      if (!receiverId) return;
      io.to(`user_${receiverId}`).emit('user_typing', {
        userId: socket.userId,
        isTyping: isTyping || false,
      });
      console.log(`⌨️ ${socket.userId} ${isTyping ? 'commence à taper' : 'arrête de taper'} vers ${receiverId}`);
    });

    // Déconnexion
    socket.on('disconnect', (reason) => {
      clearInterval(keepAliveInterval);
      console.log(`❌ Socket déconnecté: ${socketId} (user ${socket.userId}) - Raison: ${reason}`);
    });

    socket.on('error', (err) => {
      console.error(`⚠️ Socket error ${socketId}: ${err.message}`);
    });
  });
};