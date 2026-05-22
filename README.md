# ai-n8n-assist

n8n으로 만든 **텔레그램 개인 비서 봇**. 텔레그램으로 대화하고, 자연어로 이메일을 발송하며, 등록한 문서 기반으로 **RAG 질의응답**을 한다.

> 이어서 개발하려면 [HANDOFF.md](HANDOFF.md)를 먼저 읽으세요. 상태·핵심 제약·디버깅 교훈이 거기 있습니다.

## 기능

- 💬 텔레그램 대화 + 대화 메모리(채팅별)
- 📧 자연어 이메일 발송 ("OO한테 제목 본문으로 메일 보내줘")
- 📄 문서 첨부 시 자동 인덱싱(PGVector) → 질문하면 문서 근거로 답변(RAG)
- 🎙️ **음성 대화**: 음성 메시지를 보내면 Whisper로 전사 → 같은 파이프라인 처리 → 답변을 TTS 음성으로 회신 (텍스트로 보내면 텍스트로 답)
- 📞 **실시간 음성대화(별도 웹앱)**: 텔레그램은 턴 기반이라 핸즈프리 실시간이 불가 → [`realtime-voice/`](realtime-voice/)에 OpenAI Realtime API 기반 브라우저 웹앱(마이크 안 누르고 연속 음성↔음성). **GitHub Pages 고정 URL**: https://bkimkr0139-blip.github.io/ai-n8n-assist/realtime-voice/ . 텔레그램에 **"음성대화"** 입력 시 봇이 이 링크를 회신

| 워크플로우 | 역할 |
|---|---|
| `workflows/telegram_bot.json` | 메인. Telegram Trigger → (문서)인덱싱 / (텍스트)RAG검색 → AI Agent → 이메일·대화 분기 |
| `workflows/send_email_tool.json` | 서브. SMTP 이메일 발송 (Execute Workflow + Webhook 트리거) |

---

## 빠른 시작 — Docker Compose (권장, 어디서나 동일 실행)

필요한 것: Docker / Docker Compose.

```bash
git clone https://github.com/bkimkr0139-blip/ai-n8n-assist.git
cd ai-n8n-assist

cp .env.example .env
# .env 편집: 최소한 N8N_ENCRYPTION_KEY 채우기 (openssl rand -hex 32)
#           Telegram 쓰려면 WEBHOOK_URL(공개 HTTPS URL) + TELEGRAM_BOT_TOKEN(음성 답장용)

docker compose up -d
```

n8n이 `http://localhost:5678` 에서 뜨고, pgvector(RAG 저장소)가 함께 기동된다.

### 1) 자격증명 등록 (n8n UI → Credentials)

| 종류 | 비고 |
|---|---|
| **Telegram API** | BotFather 봇 토큰 |
| **OpenAI API** | OpenAI API 키 (Chat + Embeddings 공용) |
| **SMTP** | 메일 발송용 (Gmail이면 앱 비밀번호) |
| **Postgres** | host `postgres`, port `5432`, database `n8n_rag`, user/password = `.env` 값 |

> 비밀값은 저장소에 없다. 각자 인스턴스에서 위 4개를 만든다.

### 2) 워크플로우 임포트

UI → Workflows → **Import from File** 로 **`send_email_tool.json` 먼저**, 그다음 `telegram_bot.json`.

각 노드에서 위에서 만든 자격증명을 선택해 연결한다(JSON에는 빈 참조만 있음):
- Telegram 노드들 → Telegram API
- `OpenAI Chat Model`, `Embeddings (Insert)`, `Embeddings (Query)` → OpenAI API
- `Insert to RAG`, `Search RAG` → Postgres
- `send_email_tool`의 `Send Email` → SMTP

### 3) 연결 마무리

1. `telegram_bot` → `Send Email Sub` 노드의 `workflowId` 를 임포트된 `send_email_tool`의 실제 ID로 지정 (현재 값 `REPLACE_WITH_send_email_tool_ID`)
2. `send_email_tool` → `Send Email` 노드의 `fromEmail` 을 본인 주소로 변경
3. 두 워크플로우 모두 **Activate**

### 4) Telegram webhook (HTTPS 필수)

Telegram은 HTTPS만 허용한다.
- **로컬**: `ngrok http 5678` → 나온 HTTPS URL을 `.env`의 `WEBHOOK_URL`에 넣고 `docker compose up -d` 재기동. ngrok URL은 재시작 시 바뀌므로 그때마다 갱신.
- **클라우드**: 공개 도메인을 `WEBHOOK_URL`로. (리버스 프록시로 5678 앞단에 HTTPS 종단)

활성화 후 텔레그램에서 봇에게 메시지를 보내 확인한다.

> ⚠️ `WEBHOOK_URL`을 바꾼 뒤에는 `telegram_bot`을 비활성화→활성화(토글)해 Telegram webhook을 새 URL로 재등록해야 한다.

---

## 대안 — 로컬 npx 실행 (개발 머신)

Docker 없이 돌리던 원개발 환경. 자세한 절차·재시작 팁은 [HANDOFF.md](HANDOFF.md)의 "환경" 참조.
요약: `WEBHOOK_URL=<ngrok HTTPS>` 설정 후 `npx n8n@2.20.11 start`, 별도 pgvector(Docker)에 `n8n_rag` DB + `vector` 확장.

---

## 핵심 설계

### tool-calling 우회
이 환경(n8n 2.20.11 + OpenAI)에서는 **AI Agent의 tool calling이 schema 버그로 작동하지 않는다.** 그래서 tool을 붙이지 않고:

```
(검색) PGVector load → Build Context(Code) ┐
                                            ├→ AI Agent(JSON만 출력) → Code(파싱) → IF(분기)
                                            ┘                              ├ email → Execute Sub-workflow
                                                                           └ chat  → 답장
```

### RAG (PGVector)
- 문서 첨부 → `Insert to RAG`(PGVector insert, table `telegram_docs`)에 임베딩 저장(영구).
- 텍스트 질문 → `Search RAG`(PGVector load, 유사도 top 5) → `Build Context`가 청크를 모아 AI Agent의 systemMessage `[참고 문서]`에 주입.
- 임베딩은 insert/query 모두 OpenAI `text-embedding-3-small`(1536차원)로 **반드시 일치**.

### 음성 대화 (STT/TTS)
- 입력: 음성 메시지면 `Voice?` 분기 → `Download Voice` → `Transcribe Voice`(Whisper, ko) → `Prepare Input`이 전사 텍스트를 query로 정규화(`isVoice` 플래그 부여). 텍스트면 그대로 query.
- 이후 RAG/AI 파이프라인은 입력 종류와 무관하게 동일.
- 출력: `Reply Voice?`가 `isVoice`면 `TTS`(HTTP→OpenAI `/audio/speech`, tts-1, **opus**) → `Tag Audio`(파일명 `voice.ogg`) → `Send Voice`(HTTP→Telegram **sendVoice**)로 **음성 노트(voice note)** 회신. 아니면 텍스트 회신. 음성일 땐 짧은 구어체로 답하도록 프롬프트가 조정됨.
- n8n 기본 Telegram 노드에 `sendVoice`가 없어 HTTP Request로 Telegram API를 직접 호출. 토큰은 워크플로우에 하드코딩하지 않고 **`TELEGRAM_BOT_TOKEN` 환경변수**로 주입(.env 참고). OpenAI TTS는 HTTP Request의 OpenAI 사전정의 자격증명을 사용.

자세한 설계·함정은 [HANDOFF.md](HANDOFF.md) 참조.

## 보안

이 저장소에는 **API 키/비밀번호가 없다.** 자격증명은 각 n8n 인스턴스에 암호화 저장되며, 워크플로우 JSON에는 빈 참조만 있다. `.env`는 `.gitignore`로 제외된다.
