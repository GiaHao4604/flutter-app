const { validationResult } = require('express-validator');
const qrModel = require('../models/qrModel');

function parseQR(code) {
  // simple heuristics: PAYMENT_..., INVOICE_..., URL with pay param
  if (!code || typeof code !== 'string') return { valid: false };

  if (code.startsWith('PAYMENT_')) {
    return { valid: true, type: 'payment', amount: 250000, receiver: 'Coffee Shop' };
  }

  if (code.startsWith('INVOICE_')) {
    return { valid: true, type: 'invoice', invoiceId: code.split('_')[1] || null };
  }

  if (code.includes('pay=')) {
    return { valid: true, type: 'payment', amount: 100000, receiver: 'Shop' };
  }

  return { valid: false };
}

async function scan(req, res) {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });

    const { code } = req.body;
    const parsed = parseQR(code);

    await qrModel.insertQR({ qr_code: code, qr_type: parsed.type || 'unknown' });

    if (!parsed.valid) return res.status(400).json({ success: false, message: 'Invalid QR' });

    return res.json({ success: true, data: parsed });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

module.exports = { scan };
