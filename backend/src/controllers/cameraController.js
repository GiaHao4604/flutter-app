const { validationResult } = require('express-validator');
const cameraModel = require('../models/cameraModel');

async function flash(req, res) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });

    const { mode } = req.body;
    await cameraModel.insertFlash(mode);
    return res.json({ success: true, data: { mode } });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

async function zoom(req, res) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });

    const { zoom } = req.body;
    await cameraModel.insertZoom(zoom);
    return res.json({ success: true, data: { zoom } });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

module.exports = { flash, zoom };
