const fs = require('fs');
const path = require('path');
const d = path.join(__dirname, '../src/routes');
fs.readdirSync(d).forEach(f => {
  if(!f.endsWith('.js')) return;
  const p = path.join(d, f);
  let c = fs.readFileSync(p, 'utf8');
  c = c.replace(/const authMiddleware = require\((['"])\.\.\/middlewares\/authMiddleware\1\);/g, 'const { authMiddleware } = require($1../middlewares/authMiddleware$1);');
  fs.writeFileSync(p, c);
});
console.log('Done');
