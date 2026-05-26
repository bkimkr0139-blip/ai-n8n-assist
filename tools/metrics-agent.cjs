// 로컬 서버 시스템 지표 수집기 → n8n /sys-push 로 푸시 (Node 18+ 내장 모듈만 사용, 의존성 없음)
//
// 실행:  node tools/metrics-agent.cjs
// 옵션(환경변수):
//   PUSH_URL    n8n sys-push 웹훅 (기본 http://localhost:5678/webhook/sys-push)
//   METRICS_KEY 푸시 인증 키 (기본 sysmetrics2026 — admin_api 지표저장빌드 노드와 일치해야 함)
//   INTERVAL_MS 수집 주기 ms (기본 10000)
//
// 윈도우 부팅 시 자동 실행하려면 작업 스케줄러(로그온 시 시작)에 등록하거나, pm2 사용.
const os = require('os');
const { execSync } = require('child_process');
const PUSH_URL = process.env.PUSH_URL || 'http://localhost:5678/webhook/sys-push';
const KEY = process.env.METRICS_KEY || 'sysmetrics2026';
const INTERVAL = parseInt(process.env.INTERVAL_MS || '10000', 10);

function cpuTimes(){ const c=os.cpus()||[]; let idle=0,total=0; for(const x of c){ for(const k in x.times) total+=x.times[k]; idle+=x.times.idle; } return {idle,total}; }
let prev = cpuTimes();
function cpuPct(){ const cur=cpuTimes(); const di=cur.idle-prev.idle, dt=cur.total-prev.total; prev=cur; if(dt<=0) return 0; return Math.round((1-di/dt)*1000)/10; }
function memPct(){ return Math.round((1-os.freemem()/os.totalmem())*1000)/10; }
function diskPct(){
  try{
    if(process.platform==='win32'){
      const out=execSync('wmic logicaldisk where DriveType=3 get Size,FreeSpace',{timeout:5000,windowsHide:true}).toString();
      let size=0,free=0; out.split(/\r?\n/).forEach(l=>{ const m=l.trim().match(/^(\d+)\s+(\d+)$/); if(m){ free+=+m[1]; size+=+m[2]; } });
      if(size>0) return Math.round((1-free/size)*1000)/10;
    } else {
      const out=execSync('df -kP / | tail -1',{timeout:5000}).toString().trim().split(/\s+/);
      const used=+out[2], avail=+out[3]; if(used+avail>0) return Math.round(used/(used+avail)*1000)/10;
    }
  }catch(e){}
  return null;
}
function gpu(){
  try{ const out=execSync('nvidia-smi --query-gpu=utilization.gpu,name --format=csv,noheader,nounits',{timeout:5000,windowsHide:true}).toString().trim();
    if(out){ const p=out.split('\n')[0].split(',').map(s=>s.trim()); return { util:parseFloat(p[0]), name:p[1]||'GPU' }; } }catch(e){}
  return { util:null, name:'' };
}
async function push(){
  const g=gpu();
  const body={ key:KEY, cpu:cpuPct(), mem:memPct(), disk:diskPct(), gpu:g.util, gpu_name:g.name, uptime:Math.round(os.uptime()), host:os.hostname() };
  try{ await fetch(PUSH_URL,{ method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body) }); process.stdout.write('.'); }
  catch(e){ process.stdout.write('x'); }
}
console.log('[metrics-agent] → '+PUSH_URL+' every '+(INTERVAL/1000)+'s (key='+(KEY?'set':'none')+')');
push(); setInterval(push, INTERVAL);
