const express = require('express');
const { body } = require('express-validator');
const router = express.Router();
const qrController = require('../controllers/qrController');

router.post('/scan', [body('code').notEmpty()], qrController.scan);

module.exports = router;
