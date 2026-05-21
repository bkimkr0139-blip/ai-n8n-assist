# HANDOFF — telegram_bot AI 비서 (이어서 작업용)

> 새 세션에서 이 프로젝트를 이어받는 사람(또는 AI)을 위한 인계 문서. 현재 상태, 핵심 제약, 다음 할 일을 담았다.

## 한 줄 요약

n8n으로 만든 **텔레그램 개인 비서 봇**. 현재 **대화(메모리) + 이메일 발송**이 작동한다. **RAG 검색은 미완성**(다음 작업).

## 환경 (중요)

- **n8n 2.20.11** self-hosted, **npx로 실행** (글로벌/Docker 아님). npm stable 최신이 2.20.11 (2.21.x는 beta만).
  - 빠른 재시작: `& "C:\Users\User\AppData\Local\npm-cache\_npx\<hash>\node_modules\.bin\n8n.cmd" start` (install 우회)
- **Telegram webhook은 HTTPS 필수** → **ngrok** 터널 사용. `WEBHOOK_URL` 환경변수에 ngrok HTTPS URL 넣고 n8n 시작.
  - ngrok·cloudflared 모두 설치됨. ngrok 대시보드: `http://127.0.0.1:4040`
  - **ngrok URL은 재시작 시 바뀜** → 바뀌면 `WEBHOOK_URL` 갱신 + n8n 재시작
- n8n REST: `http://localhost:5678`
- Docker에 `pgvector/pgvector:pg16`(5432), redis, minio 상시 가동 → RAG 영구저장에 pgvector 재사용 가능

## ⚠️ 핵심 제약 — AI Agent tool calling 불가

이 환경(n8n 2.20.11 + OpenAI Chat Model)에서 **AI Agent의 tool 연결이 전부 실패**한다:
```
Invalid schema for function '...': schema must be a JSON Schema of 'type: "object"', got 'type: "None"'.
```
- 시도해서 전부 실패한 노드: `emailSendTool`, `toolVectorStore`, `toolWorkflow`, `toolHttpRequest`(langchain/base 둘 다), `vectorStoreInMemory` retrieve-as-tool
- 모델(gpt-4o-mini/gpt-5.4-mini), OpenAI Chat Model typeVersion(1.2/1.3) 무관하게 동일
- 원인: n8n 2.20.11 langchain 패키지가 tool input schema를 OpenAI function 형식으로 변환 시 `parameters`를 None으로 보냄

### ✅ 작동하는 우회 패턴 (이걸로 이메일 구현함)

tool calling을 쓰지 말 것. 대신:
1. **AI Agent는 tool 없이** (model + memory만), systemMessage로 **JSON만 출력** 강제
   - `{"action":"email","to":..,"subject":..,"body":..}` 또는 `{"action":"chat","reply":..}`
2. **Code 노드**로 JSON 파싱 (실패 시 chat fallback)
3. **IF 노드**로 action 분기
4. 실제 기능은 **Execute Sub-workflow 노드**(일반 노드, tool 아님)로 별도 워크플로우 호출

## 현재 워크플로우

### telegram_bot (메인) — `workflows/telegram_bot.json`
```
Telegram Trigger → Document Attached?(IF)
   ├─ (문서첨부) → Download File → Insert to RAG → Reply: Indexed
   └─ (텍스트)   → AI Assistant(JSON출력) → Parse Response(Code) → Is Email?(IF)
                       ├─ email → Send Email Sub(Execute Workflow) → Reply: Email
                       └─ chat  → Reply: Chat
```
- AI Assistant: OpenAI Chat Model(gpt-4o-mini, v1.2) + Conversation Memory(채팅ID별, 10턴). **tool 없음**.
- 문서 인덱싱 경로는 살아있으나 **검색 도구가 없어 RAG 활용 불가** (다음 작업)

### send_email_tool (서브) — `workflows/send_email_tool.json`
```
Execute Workflow Trigger ┐
Webhook(POST /send_email_tool) ┘→ Send Email(SMTP, appendAttribution:false) → Return(결과메시지)
```
- input: to / subject / body
- **active 상태 유지 필수** (webhook trigger 때문)

## 작동 확인됨 (2026-05-21)
- ✅ 텔레그램 대화 + 메모리
- ✅ 자연어 이메일 발송 ("OO한테 제목 본문 메일 보내줘")
- ✅ 이메일 푸터(n8n attribution) 제거됨

## 다음 할 일 — RAG 검색 추가

이메일과 **같은 우회 패턴**으로:
1. AI Assistant systemMessage에 `{"action":"rag","query":".."}` 케이스 추가
2. Parse Response / Is Email? 옆에 RAG 분기 추가 (Switch로 바꾸거나 IF 체인)
3. RAG 검색용 sub-workflow 생성: Execute Workflow Trigger → Vector Store retrieve(일반 노드) → 결과 반환
4. 메인에서 Execute Sub-workflow로 호출

**RAG 주의:** Simple Vector Store(인메모리)는 워크플로우별 격리라 메인 인덱싱 ↔ 서브 검색이 데이터 공유 안 됨. → **pgvector(이미 Docker에 있음)로 전환**하거나, 인덱싱+검색을 같은 워크플로우에 둘 것.

## 자격 증명 (이 환경 기준, 새 환경이면 재생성)
- OpenAI: `OpenAI 2026-05`
- SMTP: `SMTP account 2` (Gmail, fromEmail `BC Kim <bkimkr0139@gmail.com>`)
- Telegram: `Telegram Bot`
- workflow.json들의 credentials.id는 비워뒀음 → import 후 UI에서 각 노드에 연결 필요

## 새 세션 시작 시 체크리스트
1. n8n 실행 중인지 (`http://localhost:5678`), ngrok 터널 살아있는지 확인
2. ngrok URL 바뀌었으면 `WEBHOOK_URL` 갱신 + n8n 재시작 + telegram_bot의 Telegram Trigger webhook 재등록(활성화 토글)
3. 두 워크플로우 active 상태 확인
4. RAG 작업 이어가기 (위 "다음 할 일")
