// 실시간 음성 웹앱을 n8n 웹훅으로 서빙하는 워크플로우를 생성/갱신·활성화한다.
// 추가 터널 없이 n8n의 기존 공개 URL(WEBHOOK_URL)에서 접속 가능:
//   {WEBHOOK_URL}/webhook/voice
//
// 사용:
//   set N8N_API_URL=http://localhost:5678   (선택, 기본값 동일)
//   set N8N_API_KEY=<n8n public API key>
//   node serve-via-n8n.cjs
const fs = require('fs');
const path = require('path');
const BASE = (process.env.N8N_API_URL || 'http://localhost:5678').replace(/\/$/, '') + '/api/v1';
const KEY = process.env.N8N_API_KEY;
if (!KEY) { console.error('N8N_API_KEY 환경변수가 필요합니다.'); process.exit(1); }

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const wf = {
  name: 'realtime_voice_page',
  nodes: [
    { id: 'wh', name: 'Webhook', type: 'n8n-nodes-base.webhook', typeVersion: 2.1, position: [0, 0],
      webhookId: 'realtime-voice-page',
      parameters: { httpMethod: 'GET', path: 'voice', responseMode: 'responseNode', options: {} } },
    { id: 'resp', name: 'Serve HTML', type: 'n8n-nodes-base.respondToWebhook', typeVersion: 1.1, position: [260, 0],
      parameters: { respondWith: 'text', responseBody: html,
        options: { responseHeaders: { entries: [{ name: 'Content-Type', value: 'text/html; charset=utf-8' }] } } } }
  ],
  connections: { 'Webhook': { main: [[{ node: 'Serve HTML', type: 'main', index: 0 }]] } },
  settings: { executionOrder: 'v1' }
};
const h = { 'X-N8N-API-KEY': KEY, 'Content-Type': 'application/json' };
(async () => {
  const list = await (await fetch(`${BASE}/workflows?limit=100`, { headers: h })).json();
  const existing = (list.data || []).find(w => w.name === 'realtime_voice_page');
  let id;
  if (existing) {
    id = existing.id;
    await fetch(`${BASE}/workflows/${id}`, { method: 'PUT', headers: h, body: JSON.stringify(wf) });
    console.log('updated', id);
  } else {
    const d = await (await fetch(`${BASE}/workflows`, { method: 'POST', headers: h, body: JSON.stringify(wf) })).json();
    id = d.id; console.log('created', id);
  }
  const a = await fetch(`${BASE}/workflows/${id}/activate`, { method: 'POST', headers: h, body: '{}' });
  console.log('activate status', a.status, '→ open {WEBHOOK_URL}/webhook/voice');
})().catch(e => { console.error(e); process.exit(1); });
