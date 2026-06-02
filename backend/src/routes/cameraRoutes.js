const express = require('express');
const { body } = require('express-validator');
const router = express.Router();
const cameraController = require('../controllers/cameraController');

router.post('/flash', [body('mode').isString().notEmpty()], cameraController.flash);
router.post('/zoom', [body('zoom').isFloat()], cameraController.zoom);

module.exports = router;
