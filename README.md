# ai-n8n-assist

n8n으로 만든 **텔레그램 개인 비서 봇**. 텔레그램으로 대화하고, 자연어로 이메일을 발송하며, 문서 기반 RAG 답변(작업 중)을 목표로 한다.

> **이어서 작업하려면 [HANDOFF.md](HANDOFF.md)를 먼저 읽으세요.** 현재 상태·핵심 제약·다음 할 일이 거기 있습니다.

## 구성

| 워크플로우 | 역할 |
|---|---|
| `workflows/telegram_bot.json` | 메인. Telegram Trigger → AI Agent(대화/메모리) → 이메일/일반 분기 |
| `workflows/send_email_tool.json` | 서브. SMTP 이메일 발송 (Execute Workflow + Webhook 트리거) |

현재 작동: **대화 + 메모리 + 이메일 발송**. RAG 검색은 미완성.

## 핵심 설계 결정

이 환경(n8n 2.20.11 + OpenAI)에서는 **AI Agent의 tool calling이 schema 버그로 작동하지 않는다.** 그래서 tool을 붙이지 않고:

```
AI Agent(JSON만 출력) → Code(파싱) → IF(분기) → Execute Sub-workflow(기능 실행)
```

패턴으로 우회했다. 자세한 내용은 HANDOFF.md 참조.

## 가져오기 (Import)

1. n8n UI → Workflows → Import from File → `send_email_tool.json` 먼저, 그다음 `telegram_bot.json`
2. 각 노드의 자격 증명 연결 (JSON에는 ID를 비워둠):
   - Telegram Bot (telegramApi)
   - OpenAI (openAiApi)
   - Gmail SMTP (smtp)
3. `telegram_bot.json`의 `Send Email Sub` 노드 → `workflowId`를 import된 `send_email_tool`의 실제 ID로 지정
4. `send_email_tool`의 `Send Email` 노드 → `fromEmail`을 본인 주소로 변경
5. 두 워크플로우 모두 **Activate**

## 실행 환경

- n8n 2.20.11 (npx), Telegram webhook은 ngrok 터널 경유 (HTTPS 필수)
- 자세한 실행/재시작 방법은 HANDOFF.md "환경" 섹션 참조

## 보안

이 저장소에는 **API 키/비밀번호가 없다.** 자격 증명은 n8n 인스턴스에 암호화 저장되며, 여기 JSON에는 빈 참조만 있다.
