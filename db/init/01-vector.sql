-- pgvector 확장 활성화 (POSTGRES_DB = n8n_rag 에 적용됨).
-- RAG용 telegram_docs 테이블은 n8n PGVector 노드가 첫 문서 인덱싱 시 자동 생성한다.
CREATE EXTENSION IF NOT EXISTS vector;

-- 복약 일정 저장(med.html이 n8n 웹훅으로 동기화, med_scheduler가 5분마다 읽어 알림 발송)
CREATE TABLE IF NOT EXISTS med_schedules (
  chat_id    text PRIMARY KEY,
  schedule   jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz DEFAULT now()
);
