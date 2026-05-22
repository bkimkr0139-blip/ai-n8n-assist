# HANDOFF — telegram_bot AI 비서 (이어서 작업용)

> 새 세션에서 이 프로젝트를 이어받는 사람(또는 AI)을 위한 인계 문서.

## 한 줄 요약

n8n으로 만든 **텔레그램 개인 비서 봇**. **대화(메모리) + 자연어 이메일 발송 + 문서 기반 RAG 질의응답**이 모두 작동한다.

## 실행 방법

두 가지 경로가 있다. 임포트/자격증명 절차는 [README.md](README.md)에 단계별로 있다.

### A. Docker Compose (이식성, 권장)
`docker-compose.yml` 하나로 **n8n(2.20.11) + pgvector** 동시 기동.
```bash
cp .env.example .env   # N8N_ENCRYPTION_KEY, WEBHOOK_URL 등 설정
docker compose up -d
```
- RAG 저장소: postgres 서비스의 `n8n_rag` DB(`vector` 확장은 `db/init/01-vector.sql`로 자동). n8n의 Postgres 자격증명 host는 컨테이너명 `postgres`.

### B. 로컬 npx (원개발 환경)
- **n8n 2.20.11** self-hosted, npx 실행. 빠른 재시작:
  `& "C:\Users\User\AppData\Local\npm-cache\_npx\<hash>\node_modules\.bin\n8n.cmd" start` (install 우회)
  - ⚠️ npx 캐시본이 여러 개일 수 있고 일부는 설치 손상(`breaking-changes` 모듈 누락 등). 온전한 2.20.11 캐시본을 골라야 함.
- RAG 저장소: 별도 Docker `pgvector/pgvector:pg16`(5432)에 `n8n_rag` DB + `CREATE EXTENSION vector`. n8n은 호스트에서 돌므로 host `localhost`.

### 공통 — Telegram webhook (HTTPS 필수)
- Telegram은 HTTPS만 허용 → **ngrok** 터널 사용. `WEBHOOK_URL`에 ngrok HTTPS URL 넣고 n8n 기동.
- **ngrok URL은 재시작 시 바뀜** → 바뀌면 `WEBHOOK_URL` 갱신 + n8n 재기동 + `telegram_bot` 비활성화→활성화(토글)로 webhook 재등록.
- ngrok 대시보드 `http://127.0.0.1:4040`, n8n REST `http://localhost:5678`.

## ⚠️ 핵심 제약 — AI Agent tool calling 불가

n8n 2.20.11 + OpenAI Chat Model에서 **AI Agent의 tool 연결이 전부 실패**한다:
```
Invalid schema for function '...': schema must be a JSON Schema of 'type: "object"', got 'type: "None"'.
```
- 전부 실패: `emailSendTool`, `toolVectorStore`, `toolWorkflow`, `toolHttpRequest`, vectorStore retrieve-as-tool. 모델/typeVersion 무관.
- 원인: 2.20.11 langchain이 tool input schema를 OpenAI function 변환 시 `parameters`를 None으로 보냄.

### ✅ 작동하는 우회 패턴
tool을 쓰지 말 것:
1. **AI Agent는 tool 없이** (model + memory만), systemMessage로 **JSON만 출력** 강제.
2. **Code 노드**로 JSON 파싱(실패 시 chat fallback).
3. **IF 노드**로 action 분기.
4. 실제 기능은 **Execute Sub-workflow 노드**(일반 노드)로 호출.

## 현재 워크플로우

### telegram_bot (메인) — `workflows/telegram_bot.json` (26 노드)
```
Telegram Trigger → Document Attached?(IF)
  ├─ (문서첨부) → Download File → Insert to RAG(PGVector insert) → Reply: Indexed
  └─ (else)     → Voice?(IF)
        ├─ (음성)   → Download Voice → Transcribe Voice(Whisper) → Prepare Input
        └─ (텍스트) → Prepare Input
                          → Search RAG(PGVector load, topK5) → Build Context(Code)
                          → AI Assistant(JSON출력, 메모리) → Parse Response(Code) → Is Email?(IF)
                              ├ email → Send Email Sub(Execute Workflow) → Reply: Email
                              └ chat  → Reply Voice?(IF)
                                          ├ (음성입력) → TTS → Tag Audio → Send Voice  (음성 노트 회신)
                                          └ (텍스트)   → Reply: Chat                    (텍스트 회신)
```
- AI Assistant: OpenAI Chat Model(gpt-4o-mini) + Conversation Memory(채팅ID별 10턴). tool 없음.
- `Prepare Input`(Code): 음성 전사(Whisper 출력 `.text`)와 텍스트(`message.text`)를 `{query, isVoice, chatId}`로 정규화해 두 입력 경로를 합류시킴. **주의: Code 노드는 "Run Once for All Items" 모드라 `$json` 못 씀 → `$input.first().json` 사용.**
- RAG 검색: `Embeddings (Query)`→`Search RAG`(ai_embedding). `Build Context`가 청크+`Prepare Input`의 query/isVoice/chatId를 모아 `{userMessage, context, chatId, isVoice}` 출력 → AI Assistant `text`=`{{ $json.userMessage }}`, systemMessage `[참고 문서]`=`{{ $json.context }}`(systemMessage는 `=`로 시작해야 평가됨!).
- `Search RAG`: `alwaysOutputData:true` + `onError:continueRegularOutput` → 검색 0건/테이블 미존재여도 안 멈춤.
- 음성 입력: `Transcribe Voice` = `@n8n/n8n-nodes-langchain.openAi`(v2.3, audio/transcribe). 바이너리 `data`로 연결.
- 음성 출력: n8n Telegram 노드에 `sendVoice`가 없어 **HTTP Request로 직접 호출**. `TTS`=HTTP→OpenAI `/v1/audio/speech`(tts-1, **response_format opus**; OpenAI 사전정의 자격증명) → `Tag Audio`(Code, 바이너리 `data`의 fileName=`voice.ogg`/mimeType=`audio/ogg` 지정 — sendVoice가 OGG/Opus 요구) → `Send Voice`=HTTP→`https://api.telegram.org/bot{{ $env.TELEGRAM_BOT_TOKEN }}/sendVoice`(multipart: chat_id + voice 바이너리). **봇 토큰은 워크플로우에 하드코딩 금지 → `TELEGRAM_BOT_TOKEN` 환경변수**(docker .env). 단, 현재 로컬 라이브 인스턴스는 env 미설정이라 URL에 토큰 하드코딩 상태일 수 있음(repo export 시 gen 스크립트가 자동으로 env 치환). openAi generate 노드는 opus 출력 옵션이 없어 HTTP 사용.

### send_email_tool (서브) — `workflows/send_email_tool.json` (4 노드)
```
Execute Workflow Trigger ┐
Webhook(POST /send_email_tool) ┘→ Send Email(SMTP, appendAttribution:false) → Return(결과메시지)
```
- input: to / subject / body. **active 유지 필수**(webhook trigger).

## RAG 설계 메모
- **인메모리(vectorStoreInMemory) 금지**: 재시작 시 색인 소실 + 워크플로우별 격리. → **PGVector(영구)** 사용.
- 테이블 `telegram_docs`는 첫 인덱싱 시 PGVector 노드가 자동 생성.
- 임베딩 모델은 insert/query **동일**해야 함(text-embedding-3-small, 1536). 다르면 검색 안 됨.

## 💡 디버깅 교훈 (꼭 기억)

1. **n8n 표현식은 필드 값이 `=`로 시작해야 평가된다.** AI Agent `systemMessage`에 `{{ $json.context }}`를 넣었는데 `=` 접두사가 없어 **literal 문자열로** LLM에 전달됐고, 모델은 늘 빈 [참고 문서]를 받아 "문서 없다"고 거부했다. → systemMessage를 `=`로 시작하게 고쳐 해결. (`text`는 `=`가 있어서 정상이었음.)
2. **AI Agent가 컨텍스트를 무시하면, LLM이 실제 받은 메시지를 먼저 확인**하라. 실행 원본의
   `runData["OpenAI Chat Model"][0].inputOverride.ai_languageModel[0][0].json.messages`
   에 최종 system/human 프롬프트가 들어 있다. REST: `GET /api/v1/executions/{id}?includeData=true`.
3. 위 1번을 메모리 오염으로 오진했었다(거부가 메모리에 쌓인 **증상**일 뿐). 메모리를 꺼도 거부가 지속되면 메모리가 원인이 아니다.
4. webhook 직접 트리거는 Telegram secret-token 검증으로 403 → 자체 테스트 불가, 실테스트는 텔레그램에서.

## 자격증명 (인스턴스마다 재생성)
- OpenAI(Chat+Embeddings 공용), SMTP(Gmail, fromEmail 본인 주소로), Telegram(BotFather 토큰), Postgres(pgvector RAG; docker는 host `postgres`/db `n8n_rag`).
- 워크플로우 JSON의 `credentials.id`는 비어 있음 → 임포트 후 UI에서 연결.

## 다음 후보
- RAG 품질 튜닝(청크 크기/overlap/topK, score 임계값으로 무관 문서 컷).
- 문서 외 업무 도구 추가(같은 우회 패턴).
- 작은 모델 한계 시 gpt-4o 등으로 상향.
