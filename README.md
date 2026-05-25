# ai-n8n-assist

n8n으로 만든 **텔레그램 개인 비서 봇**. 텔레그램으로 대화하고, 자연어로 이메일을 발송하며, 등록한 문서 기반으로 **RAG 질의응답**을 한다.

> 이어서 개발하려면 [HANDOFF.md](HANDOFF.md)를 먼저 읽으세요. 상태·핵심 제약·디버깅 교훈이 거기 있습니다.

## 기능

- 💬 텔레그램 대화 + 대화 메모리(채팅별)
- 📧 자연어 이메일 발송 ("OO한테 제목 본문으로 메일 보내줘")
- 📄 문서 첨부 시 자동 인덱싱(PGVector) → 질문하면 문서 근거로 답변(RAG)
- 🖼️ **사진 분석**: 사진을 보내면 비전(gpt-4o-mini)으로 내용을 설명하고, "사진 등록"이라고 답하면 그 설명을 RAG에 임베딩(staticData에 임시 보관 후 확인 시 저장)
- 💊 **복약 일정 관리 UI**: [`realtime-voice/med.html`](realtime-voice/med.html) — 시간 선택기 폼 + 자연어 입력("매일 아침 식후 치매약, 점심 후 혈당약…")을 AI가 일정표로 정리, 시간순 표로 추가/삭제. localStorage `med_schedule`에 저장되어 care.html 복약 통화에 자동 반영. 텔레그램 **"복약 설정/복약 등록"** → med.html 링크
- 💊 **복약 알림(일정 연동)**: med.html에서 등록한 일정을 n8n `med_scheduler`로 동기화(웹훅, CORS) → 5분마다 현재 시각 확인 → 해당 약 시간에 어르신에게 텔레그램 알림 + 복약통화 링크(care.html?purpose=med). 일정은 med.html(유저별 localStorage)이 원본, n8n은 알림만 담당. ⚠️ 브라우저는 스스로 전화벨/자동발신 불가 → "알림(=벨)→탭하면 통화". SMS/전화/웹푸시·자동발신은 Twilio 등 전화망 연동 필요(향후)
- 🌤️ **날씨**: 텔레그램에서 날씨를 물으면 지역을 되묻고 해당 지역 날씨를 검색해 답(Open-Meteo, 무료·키 불필요). 돌봄 통화(care.html)에선 거주지역(기본 서울, 수정 가능)을 Realtime function calling으로 조회해 맥락있게 안내
- 📰 **뉴스**: 돌봄 통화(care.html)에서 "오늘 뉴스 뭐 있어?" 물으면 "찾아볼게요" 추임새 후 헤드라인 2~4개를 자연스럽게 읽어줌(get_news function tool). 뉴스 소스는 **n8n `news_api` 웹훅**이 서버에서 Google News RSS(한국, 키 불필요)를 가져와 CORS로 응답(브라우저 CORS 프록시는 불안정해서 서버 경유). 주제를 말하면(예: "건강 뉴스") 주제별 검색
- 🎙️ **음성 대화**: 음성 메시지를 보내면 Whisper로 전사 → 같은 파이프라인 처리 → 답변을 TTS 음성으로 회신 (텍스트로 보내면 텍스트로 답)
- 📞 **실시간 음성대화(별도 웹앱)**: 텔레그램은 턴 기반이라 핸즈프리 실시간이 불가 → [`realtime-voice/`](realtime-voice/)에 OpenAI Realtime API 기반 브라우저 웹앱(마이크 안 누르고 연속 음성↔음성, `gpt-realtime`). **GitHub Pages 고정 URL**: https://bkimkr0139-blip.github.io/ai-n8n-assist/realtime-voice/ . 텔레그램 **"음성대화"** → 이 링크 회신
- ⚙️ **돌봄 관리자 설정 모드**: [`realtime-voice/care-admin.html`](realtime-voice/care-admin.html) — 관리자가 음성 대화로 돌봄 AI의 말투·추임새·안내사항·맥락관리를 맞춤 설정 → `localStorage.care_config`에 저장 → care.html이 통화 시 주입(같은 Pages 도메인이라 공유). 텔레그램 **"돌봄 설정/관리자/통화 조정"** → care-admin.html 링크
- 💚 **어르신 돌봄 상담 모드**: [`realtime-voice/care.html`](realtime-voice/care.html) — 따뜻한 여성 음성·존댓말 생활지원사 페르소나로 안부확인. **세션 간 기억**(localStorage에 어르신 메모 저장→다음 통화에 맥락 주입), 어르신용 큰 UI, VAD 1.1초(끊김 방지). 텔레그램 **"돌봄/어르신 통화/복지상담"** → care.html 링크 회신. URL: https://bkimkr0139-blip.github.io/ai-n8n-assist/realtime-voice/care.html . **소음/에코 대응**: getUserMedia 에코제거·소음억제 + OpenAI Realtime `noise_reduction`(near/far)·VAD 민감도(소음환경 선택: 조용/보통/TV소음) + "잡음·다른 사람·AI 자기 음성에 반응 말 것" 지시 → TV·외부소음·AI 에코에 덜 반응. **+ 어르신 목소리 학습·화자 필터**: 통화 중 어르신 목소리의 음높이(F0) 범위를 자동 학습→단말기에 기억(localStorage `care_voice_<deviceid>`)하고, 마이크 오디오를 OpenAI로 보내기 전 Web Audio `GainNode` 게이트로 **학습된 음역과 다른 TV·타인 목소리를 음소거**해 AI가 반응하지 않게 함(자기상관 피치 추정, "어르신 목소리만 듣기" 체크/다시학습 버튼). ⚠️ 피치 기반 근사 — 음역이 비슷한 목소리까지 완벽 구분은 못 함(진짜 생체인식 아님)
- 🔑 **키 없이 외부 사용(care.html)**: 외부 사용자가 OpenAI 키 입력 없이 링크만으로 바로 통화. **API 키는 브라우저에 노출하지 않고 n8n 서버(`care_api`)에만 보관** — 통화 시작 시 서버가 OpenAI **단기 토큰(ephemeral, 60초)** 을 발급(`/realtime-token`)해 브라우저는 그 토큰으로만 WebRTC 접속하고, 통화 후 기억 요약도 서버(`/care-summary`)가 처리. ⚠️ **비용 주의**: 토큰 발급 웹훅이 공개라 URL을 아는 누구나 호출→사용자 OpenAI 과금 가능. 권장: OpenAI 대시보드에서 **월 사용량 한도 설정** + 테스트 안 할 땐 `care_api` 비활성화(또는 웹훅 `allowedOrigins`를 배포 도메인으로 제한)
- 🧑‍🦳 **단말기 기준 개인화(care.html)**: 최초 접속 시 단말기 고유 ID(`care_device_id`)를 만들어 영구 보관. 같은 단말기로 **재접속하면 서버(Postgres `care_profiles`)에서 그 단말기의 이름·지역·목소리·소음환경·누적 기억을 불러와 "같은 분"으로 인식**하고 대화를 이어감. 설정 변경/통화종료 시 device_id 기준으로 서버에 저장(`/care-profile`, `/care-profile-save`, `/care-summary`). (참고: 진짜 음성 생체인식은 미지원 — 단말기 식별 + 서버 기억 + 소음/VAD 튜닝으로 개인화)
- 🩺 **통합 관리자 모니터링 대시보드**: [`realtime-voice/admin.html`](realtime-voice/admin.html) — 모바일·PC 반응형. **단말기별 접속상태(🟢통화중/⚪오프라인)·접속횟수·통화시간·토큰사용량**을 카드로, 최근 통화 로그를 표로 보여주고, 카드를 누르면 그 단말기의 **누적 기억(메모) + 통화별 대화기록**을 상세히 확인. 관리자 패스코드로 보호(`admin_api` 워크플로우 `인증` 코드 노드에서 설정·변경). 데이터: care.html이 통화 중 핑(`/care-ping`, 온라인표시)·종료 시 세션로그(`/care-session`)를 서버에 적재 → `admin_api`의 `/admin-data`가 집계. 텔레그램 **"모니터링/대시보드/접속현황"** → admin.html 링크. ⚠️ 토큰사용량은 Realtime `response.done`의 usage를 합산한 근사치

| 워크플로우 | 역할 |
|---|---|
| `workflows/telegram_bot.json` | 메인. Telegram Trigger → (문서)인덱싱 / (텍스트)RAG검색 → AI Agent → 이메일·대화 분기 |
| `workflows/send_email_tool.json` | 서브. SMTP 이메일 발송 (Execute Workflow + Webhook 트리거) |
| `workflows/med_scheduler.json` | 복약 알림. Webhook(/med-config, CORS)로 med.html 일정 수신→**Postgres `med_schedules`** 저장 + Schedule(5분)로 DB 읽어 시각 매칭 시 텔레그램 알림. (staticData 캐시 이슈 회피 위해 DB 사용, 한글 인코딩 정상) |
| `workflows/news_api.json` | 뉴스 헤드라인 API. Webhook(GET /news, CORS)→Google News RSS(한국) 서버측 fetch→헤드라인 top5 JSON 응답. care.html `get_news`가 호출 |
| `workflows/care_api.json` | care.html 클라이언트 API. `POST /realtime-token`→OpenAI 단기토큰(ek_) 발급, `POST /care-summary`→기억 요약(device_id 기준 `care_profiles.memo` 저장), `GET /care-profile`·`POST /care-profile-save`→단말기 프로필 조회/저장, `POST /care-session`→통화 로그 적재, `POST /care-ping`→온라인 핑. OpenAI/Postgres 자격증명 사용·CORS 허용 |
| `workflows/admin_api.json` | 관리자 대시보드 API. `GET /admin-data?pass=`→패스코드 검증 후 단말기별 집계(접속상태·횟수·시간·토큰)+최근 통화로그(대화기록) JSON 반환. admin.html이 호출. **패스코드는 `인증` 코드 노드에서 변경**(저장소 export엔 `CHANGE_ME_ADMIN_PASS` 플레이스홀더) |

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
