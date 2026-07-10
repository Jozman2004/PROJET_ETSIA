// routes/blockRoutes.js
const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const blockController = require('../controllers/blockController');

router.post('/:userId/block', auth, blockController.blockUser);
router.delete('/:userId/block', auth, blockController.unblockUser);
router.get('/:userId/block-status', auth, blockController.getBlockStatus);

module.exports = router;