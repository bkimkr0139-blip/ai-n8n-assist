-- pgvector 확장 활성화 (POSTGRES_DB = n8n_rag 에 적용됨).
-- RAG용 telegram_docs 테이블은 n8n PGVector 노드가 첫 문서 인덱싱 시 자동 생성한다.
CREATE EXTENSION IF NOT EXISTS vector;
