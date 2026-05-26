# HANDOFF — 돌봄 AI 비서 (이어서 작업용)

> 새 세션에서 이 프로젝트를 이어받는 사람(또는 AI)을 위한 인계 문서.
> 인스턴스 고유값(자격증명 ID·ngrok URL·관리자 패스코드·봇 토큰)은 보안상 이 문서에 넣지 않는다 — 운영 중인 n8n/메모리에서 확인.

## 한 줄 요약

n8n + OpenAI로 만든 **텔레그램 개인비서 → 어르신 돌봄 AI 시스템**. 텔레그램 봇(대화·이메일·RAG·날씨·사진·복약알림·음성)과, GitHub Pages로 호스팅하는 **실시간 음성통화 웹앱(돌봄 통화/관리자 설정/복약 일정/모니터링 대시보드)**로 구성. 키 없이 외부 사용 가능(서버가 단기토큰 발급), 단말기 기준 개인화, 관리자 모니터링까지 구현됨.

## 구성요소 한눈에

**n8n 워크플로우** (`workflows/`): 모두 활성. JSON은 자격증명 id 빈값·토큰/패스코드 플레이스홀더로 sanitize됨.
| 파일 | 역할 |
|---|---|
| `telegram_bot.json` | 메인 봇(라우팅 56노드). 키워드 분기로 사진/문서/복약설정/돌봄설정/모니터링/돌봄통화/음성대화/음성/날씨/이메일/RAG 처리 |
| `send_email_tool.json` | SMTP 이메일 발송 서브(Execute Workflow + Webhook) |
| `med_scheduler.json` | 복약알림. /med-config(웹훅)→Postgres `med_schedules` 저장 + 5분 스케줄로 읽어 텔레그램 알림 |
| `news_api.json` | /news(웹훅, CORS)→Google News RSS(한국) 서버fetch→헤드라인 top5 JSON |
| `admin_api.json` | 관리자 대시보드 API: `/admin-data`(단말기+통화로그), `/admin-analytics`(기간/지역/단말기 다차원, json_agg 단일쿼리), `/sys-push`+`/admin-sys`(서버 CPU/메모리/디스크/GPU + LLM활동). 모두 패스코드(`인증`/`분석빌드`/`시스템빌드` 코드 노드). **비용 요율은 `admin.html`의 `COST` 상수 1곳에서 수정** |
| `care_api.json` | care.html 클라이언트 API: `/realtime-token`(승인 단말기에만 OpenAI 단기토큰), `/care-summary`(기억 요약·device_id 저장), `/care-profile`(GET)·`/care-profile-save`(POST, 신규는 Telegram 알림), `/care-session`(통화로그), `/care-ping`(온라인), `/care-block`(승인/차단+사유, 패스코드), `/care-reset`(기억 초기화), `/care-delete`(단말기 일괄삭제, 패스코드) |

**웹앱** (`realtime-voice/`, GitHub Pages: `https://bkimkr0139-blip.github.io/ai-n8n-assist/realtime-voice/`):
| 파일 | 역할 |
|---|---|
| `index.html` | 일반 실시간 음성대화(OpenAI Realtime, `gpt-realtime`). ※아직 클라이언트 키 입력 방식 |
| `care.html` | **어르신 돌봄 통화**. 키 없이 서버 단기토큰으로 접속, 여성음성·존댓말 페르소나, 날씨/뉴스/시간 function tool, 세션간 기억, **단말기 기준 개인화**, 통화 로깅, **목소리 학습+화자 필터**, **신규 단말기 승인요청 화면**, **무응답 자동 호출/마무리**(한·영). 설정 UI 모바일 그리드 |
| `care-admin.html` | 돌봄 AI 말투·추임새·안내 음성 설정(→`care_config`) + **대상자 음성/전체 초기화** |
| `med.html` | 복약 일정 관리 UI(폼+자연어). localStorage가 원본, n8n /med-config로 동기화→알림 |
| `admin.html` | **통합 관리자 대시보드**(모바일·PC 반응형, 패스코드). [📋 모니터링]/[📊 사용 분석] 탭. 모니터링: **🖥️ 서버/LLM 부하**(CPU·메모리·디스크·GPU 게이지 + 동시통화·1h 통화/토큰) + 단말기 카드(승인/차단·사유) + 통화로그 + **체크박스 선택/전체 삭제** + **예상 비용**. 분석: 기간(일/주/월/분기/년)·지표(통화수/시간/토큰/**비용**)·단말기·지역 필터로 다차원 분석(단말기 드릴다운) |

**Postgres 테이블** (`db/init/01-vector.sql`, DB `n8n_rag`):
- `telegram_docs` — RAG 벡터(PGVector 자동생성)
- `med_schedules` — 복약 일정(chat_id PK)
- `care_profiles` — 단말기별 어르신 프로필/기억(device_id PK: name/region/voice/env/speed/memo/visits/last_ping/**status[pending/approved/blocked]**/**block_reason**)
- `care_sessions` — 통화 로그(device_id/started·ended/duration_sec/turns/**input·output·total tokens**/transcript)
- `sys_metrics` — 로컬 서버 지표(단일행 id=1; cpu/mem/disk/gpu/gpu_name/uptime/host, `tools/metrics-agent.cjs`가 갱신)

**선택 로컬 도구** (`tools/`):
- `metrics-agent.cjs` — 무의존 Node 수집기(CPU/메모리/디스크/GPU `nvidia-smi`)가 10초마다 n8n `/sys-push`로 전송. 실행: `node tools/metrics-agent.cjs` (부팅 자동실행은 작업스케줄러/pm2)

## 실행/복구 방법

### 로컬 npx (원개발 환경, 현재 라이브)
- **n8n 2.20.11** self-hosted, npx 실행. 온전한 2.20.11 캐시본 사용(일부 캐시본은 `breaking-changes` 모듈 누락 등 손상).
- RAG/데이터 DB: Docker `pgvector/pgvector:pg16`(컨테이너 `aep-dt-postgres-1`, user/db는 운영값), DB `n8n_rag`에 `vector` 확장 + 위 테이블들. n8n은 호스트라 Postgres host `localhost`(자격증명에 설정).
- **Telegram webhook은 HTTPS 필수 → ngrok 터널**. `WEBHOOK_URL`에 ngrok HTTPS 넣고 기동. ngrok 대시보드 `http://127.0.0.1:4040`, n8n REST `http://localhost:5678`.
- **ngrok URL은 재시작 시 바뀜.** 바뀌면: ① `WEBHOOK_URL` 갱신+n8n 재기동+`telegram_bot` 토글로 webhook 재등록, ② **웹앱의 하드코딩된 n8n URL도 갱신** — `care.html`의 `N8N_BASE`, `admin.html`의 `N8N_BASE`, `med.html`의 동기화 URL(전부 GitHub Pages라 push 필요).

### Docker Compose (이식성)
`docker compose up -d`로 n8n + pgvector 동시 기동. `.env`에 `N8N_ENCRYPTION_KEY`, `WEBHOOK_URL`, `TELEGRAM_BOT_TOKEN` 등. 자격증명은 인스턴스마다 UI에서 재생성. 상세는 [README.md](README.md).

### 자격증명 (인스턴스마다 재생성, JSON엔 id 빈값)
OpenAI(Chat+Embeddings+Realtime+TTS+Whisper+Vision 공용), SMTP(Gmail 앱비번, fromEmail 본인), Telegram(BotFather 토큰), Postgres(host/db/user 운영값).

## ⚠️ 핵심 제약 — AI Agent tool calling 불가 (우회 패턴)
n8n 2.20.11 + OpenAI에서 **AI Agent의 tool 연결이 schema 버그로 전부 실패**(`parameters`를 None으로 보냄). 그래서 봇은 tool 없이:
1. AI Agent는 model+memory만, systemMessage로 **JSON만 출력** 강제.
2. **Code**로 JSON 파싱(실패 시 chat fallback) → **IF**로 action 분기 → 실제 기능은 **Execute Sub-workflow/일반 노드**.
(주의: care.html의 OpenAI **Realtime API는 function calling이 정상 작동** — 날씨/뉴스 tool은 거기서 동작. 위 버그는 n8n langchain AI Agent 한정.)

## 보안 (필수 준수)
- **OpenAI 키는 어디에도 하드코딩 금지** — n8n 자격증명에만. 웹앱(care.html)은 서버(`/realtime-token`)가 발급한 **단기토큰(ek_, 60초)**으로만 접속.
- **봇 토큰**은 repo export 시 `{{ $env.TELEGRAM_BOT_TOKEN }}`로 치환(라이브 Send Voice 노드엔 하드코딩될 수 있음).
- **관리자 패스코드**: `admin_api`의 `인증` 코드노드에 있음(repo엔 `CHANGE_ME_ADMIN_PASS` 플레이스홀더). 운영값은 변경 권장.
- **커밋 전 누출 스캔 필수**: 봇토큰/sk-proj 키/자격증명 id/패스코드/ngrok 도메인이 repo에 없는지 grep 확인.
- ⚠️ **비용**: /realtime-token·/admin-data 등 공개 웹훅이라 URL 아는 사람이 호출 가능 → OpenAI 월 한도 설정 + 미사용 시 워크플로우 비활성화 권장.

## 💡 디버깅 교훈 (꼭 기억)
1. **n8n 표현식은 필드 값이 `=`로 시작해야 평가**된다(예: AI Agent systemMessage의 `{{ $json.context }}`).
2. AI가 컨텍스트 무시하면 LLM이 실제 받은 메시지부터 확인: `GET /api/v1/executions/{id}?includeData=true`.
3. **staticData를 트리거 간 공유 저장소로 쓰지 말 것**(인메모리 캐시·불안정) → Postgres 사용(복약알림 ??? 한글깨짐도 이 때문).
4. **PowerShell `Invoke-WebRequest`로 한글 POST 금지**(인코딩 깨짐). docker exec psql로 한글 넣을 땐 `-c` 인라인 말고 **UTF-8 .sql 파일 + `psql -f`/stdin**.
5. **브라우저 CORS는 curl로 검증되지 않는다** — OPTIONS preflight(+`Access-Control-Request-Headers`)로 재현해야 진짜 확인. ngrok-free는 fetch에 `ngrok-skip-browser-warning: true` 헤더 필요.
6. **CSS `display:flex` 등은 `hidden` 속성을 덮어쓴다** → 모달/토글엔 `[hidden]{display:none!important;}` 전역 규칙 필요(admin.html 상세팝업 안 닫히던 버그).
7. Postgres COUNT/SUM은 **문자열로 반환** → 프론트에서 parseInt.
8. n8n UI에서 워크플로우 탭을 열어두면 MCP 편집이 덮어써질 수 있음 → **MCP 편집 중 UI 탭 닫기**.
9. webhook 직접 트리거는 Telegram secret-token 검증으로 403 → 실테스트는 텔레그램/브라우저에서.

## 알려진 한계 / 다음 후보
- **진짜 음성 생체인식(화자 분리/학습) 미지원** — 단말기 식별 + 서버 기억 + 소음/VAD 튜닝으로 근사.
- **자동 전화발신/SMS/웹푸시 미지원** — 텔레그램 알림+탭하면 통화 링크로 대체. 진짜 발신은 Twilio 등 전화망 연동 필요(미착수).
- `index.html`·`care-admin.html`은 아직 클라이언트 키 입력 방식 → 필요시 care.html처럼 서버 단기토큰으로 전환 가능.
- RAG 품질 튜닝(청크/overlap/topK/score 임계), 작은 모델 한계 시 상향.
- 데모 데이터: `care_profiles`/`care_sessions`에 `device_id='demo-sample-001'` 예시 1건 존재(삭제 가능).
