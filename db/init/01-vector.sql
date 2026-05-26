-- pgvector 확장 활성화 (POSTGRES_DB = n8n_rag 에 적용됨).
-- RAG용 telegram_docs 테이블은 n8n PGVector 노드가 첫 문서 인덱싱 시 자동 생성한다.
CREATE EXTENSION IF NOT EXISTS vector;

-- 복약 일정 저장(med.html이 n8n 웹훅으로 동기화, med_scheduler가 5분마다 읽어 알림 발송)
CREATE TABLE IF NOT EXISTS med_schedules (
  chat_id    text PRIMARY KEY,
  schedule   jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz DEFAULT now()
);

-- 단말기(device)별 어르신 프로필/기억(care.html이 device_id 기준으로 저장·복원, care_api가 관리)
CREATE TABLE IF NOT EXISTS care_profiles (
  device_id  text PRIMARY KEY,
  name       text DEFAULT '',
  region     text DEFAULT '',
  voice      text DEFAULT '',
  env        text DEFAULT '',
  speed      text DEFAULT '',
  memo       text DEFAULT '',
  visits     int DEFAULT 0,
  status       text DEFAULT 'pending',   -- pending(신규,승인대기) | approved | blocked
  block_reason text DEFAULT '',          -- 차단 사유(사용자에게 표시)
  blocked      boolean DEFAULT false,    -- (구버전 호환, status로 대체)
  last_ping  timestamptz,
  first_seen timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 통화 접속 로그(접속횟수·통화시간·토큰사용량·대화기록 → admin.html 모니터링 대시보드 집계)
CREATE TABLE IF NOT EXISTS care_sessions (
  id            bigserial PRIMARY KEY,
  device_id     text NOT NULL,
  started_at    timestamptz,
  ended_at      timestamptz,
  duration_sec  int DEFAULT 0,
  turns         int DEFAULT 0,
  input_tokens  int DEFAULT 0,
  output_tokens int DEFAULT 0,
  total_tokens  int DEFAULT 0,
  transcript    text DEFAULT '',
  summary_in_tok   int DEFAULT 0,   -- 통화 후 요약 LLM 입력 토큰
  summary_out_tok  int DEFAULT 0,   -- 통화 후 요약 LLM 출력 토큰
  summary_provider text DEFAULT '', -- 'openai' | 'ollama' (요약에 쓰인 LLM, 비용 분리용)
  created_at    timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS care_sessions_dev_idx ON care_sessions(device_id, started_at DESC);

-- LLM 라우팅 설정(단일 행). admin.html에서 변경 → care-summary 등 텍스트 작업이 해당 LLM 사용
-- provider: 'openai' | 'ollama'.  로컬 LLM 선택 시 통화(realtime)는 클라우드 유지·요약은 로컬 → 하이브리드.
CREATE TABLE IF NOT EXISTS llm_config (
  id         int PRIMARY KEY DEFAULT 1,
  provider   text DEFAULT 'openai',
  model      text DEFAULT 'gpt-4o-mini',
  endpoint   text DEFAULT 'https://api.openai.com/v1/chat/completions',
  updated_at timestamptz DEFAULT now()
);
INSERT INTO llm_config (id) VALUES (1) ON CONFLICT DO NOTHING;

-- 로컬 서버 시스템/LLM 부하 지표(단일 행, tools/metrics-agent.cjs가 /sys-push로 갱신 → admin.html 표시)
CREATE TABLE IF NOT EXISTS sys_metrics (
  id         int PRIMARY KEY DEFAULT 1,
  cpu        numeric,
  mem        numeric,
  disk       numeric,
  gpu        numeric,
  gpu_name   text DEFAULT '',
  uptime     bigint,
  host       text DEFAULT '',
  updated_at timestamptz DEFAULT now()
);
