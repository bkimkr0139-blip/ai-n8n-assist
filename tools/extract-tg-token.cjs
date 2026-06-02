// Decrypt the stored Telegram bot token from n8n's sqlite DB and write it to the
// file path given as argv[2]. Prints only a masked confirmation (never the token).
// No secrets are embedded — it reads the local encryption key from ~/.n8n/config.
// Replicates n8n-core CipherAes256CBC (OpenSSL salted, MD5 EVP_BytesToKey).
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

// Intact n8n 2.20.11 npx cache (see tools/start-n8n.ps1 / memory run-service).
const CACHE = process.env.N8N_CACHE_DIR
  || 'C:\\Users\\User\\AppData\\Local\\npm-cache\\_npx\\a8a7eec953f1f314\\node_modules';
const sqlite3 = require(path.join(CACHE, 'sqlite3')).verbose();

const n8nDir = path.join(os.homedir(), '.n8n');
const key = JSON.parse(fs.readFileSync(path.join(n8nDir, 'config'), 'utf8')).encryptionKey;
const dbPath = path.join(n8nDir, 'database.sqlite');
const outFile = process.argv[2];
if (!outFile) { console.error('usage: node extract-tg-token.cjs <out-file>'); process.exit(64); }

function getKeyAndIv(salt, k) {
  const password = Buffer.concat([Buffer.from(k, 'binary'), salt]);
  const h1 = crypto.createHash('md5').update(password).digest();
  const h2 = crypto.createHash('md5').update(Buffer.concat([h1, password])).digest();
  const iv = crypto.createHash('md5').update(Buffer.concat([h2, password])).digest();
  return [Buffer.concat([h1, h2]), iv];
}
function decrypt(data, k) {
  const input = Buffer.from(data, 'base64');
  if (input.length < 16) return '';
  const salt = input.subarray(8, 16);
  const [dk, iv] = getKeyAndIv(salt, k);
  const d = crypto.createDecipheriv('aes-256-cbc', dk, iv);
  return Buffer.concat([d.update(input.subarray(16)), d.final()]).toString('utf-8');
}

const db = new sqlite3.Database(dbPath, sqlite3.OPEN_READONLY, (err) => {
  if (err) { console.error('DB open failed:', err.message); process.exit(1); }
});
db.all("SELECT name, type, data FROM credentials_entity WHERE type LIKE '%telegram%'", (err, rows) => {
  if (err) { console.error('Query failed:', err.message); process.exit(1); }
  if (!rows || rows.length === 0) { console.error('No telegram credential found.'); process.exit(2); }
  let token = null, picked = null;
  for (const r of rows) {
    try {
      const obj = JSON.parse(decrypt(r.data, key));
      const t = obj.accessToken || obj.token || obj.botToken;
      if (t && /^\d+:[\w-]+$/.test(t)) { token = t; picked = r.name; break; }
      if (t && !token) { token = t; picked = r.name; }
    } catch (e) { /* skip undecryptable */ }
  }
  if (!token) { console.error('Could not decrypt a usable token.'); process.exit(3); }
  fs.writeFileSync(outFile, token, { encoding: 'utf8' });
  console.log(`OK: "${picked}" -> ${token.slice(0, 4)}...${token.slice(-4)} (len=${token.length}, valid=${/^\d+:[\w-]+$/.test(token)})`);
  db.close();
});
