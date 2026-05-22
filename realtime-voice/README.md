# 🎙️ 실시간 음성 비서 (브라우저)

텔레그램 봇은 턴(메시지) 기반이라 **마이크를 계속 누르지 않는 핸즈프리 실시간 음성대화**가 구조적으로 불가능하다.
이 폴더는 그걸 가능하게 하는 **별도 브라우저 웹앱**이다 — OpenAI **Realtime API**(음성↔음성, 저지연, 서버 VAD가 말 끝을 자동 감지)를 WebRTC로 직접 연결한다.

- 모드 켜기(▶ 시작) → 그냥 말하면 됨 → 끝나면 자동으로 알아듣고 음성으로 답함 → 계속 대화
- 이미 가진 OpenAI 키 그대로 사용. 키는 브라우저 localStorage에만 저장(서버 전송·repo 커밋 없음).

## 실행

마이크 사용은 **보안 컨텍스트(localhost/https)** 가 필요하다. `file://` 로 바로 열면 크롬에서 마이크가 막히므로 로컬 서버로 띄운다.

```bash
# 방법 1 (node)
npx serve ai-n8n-assist/realtime-voice
# 방법 2 (python)
cd ai-n8n-assist/realtime-voice && python -m http.server 8080
```

브라우저에서 `http://localhost:3000`(serve) 또는 `http://localhost:8080`(python) 접속 →
OpenAI API 키 입력 → **목소리 선택** → **[음성 대화 시작]** → 말하기.

## 참고 / 한계

- **비용**: Realtime API는 Whisper+TTS 조합보다 비싸다(오디오 토큰 과금). 길게 켜두면 비용 누적.
- **모델**: 기본 `gpt-4o-realtime-preview`. 안 되면 `index.html` 상단 `MODEL` 을 `gpt-realtime` 으로 변경.
- **보안**: 표준 API 키를 브라우저에서 직접 사용한다(로컬 개인용 가정). 외부에 배포하려면 서버에서 **ephemeral token**을 발급하는 방식으로 바꿔야 한다.
- **CORS**: 브라우저→`api.openai.com/v1/realtime` 호출이 CORS로 막히면, 작은 토큰 발급 백엔드(ephemeral key)가 필요하다. 그 경우 알려주면 추가한다.
- 이 웹앱은 현재 **대화 전용**이다. 텔레그램 봇의 RAG(문서검색)·이메일 기능을 여기에 붙이려면 Realtime의 function calling으로 연동해야 한다(다음 단계 후보).
