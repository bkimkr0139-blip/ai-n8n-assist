#!/usr/bin/env bash
# setup-searxng.sh — govt_grants_local 워크플로우용 SearXNG(메타 검색 엔진) 로컬 설치
#
# 무료·로컬 RAG 파이프라인의 검색 단계를 담당:
#   SearXNG(검색) → 본문수집/정제 → nomic-embed-text(임베딩) → qwen2.5:3b(요약)
#
# 전제: Docker, Ollama(127.0.0.1:11434) 설치됨.
# 실행: bash tools/setup-searxng.sh
set -e

NAME="searxng"
PORT="8888"

echo "==> 임베딩/요약 모델 확인 (Ollama)"
curl -s http://127.0.0.1:11434/api/tags | grep -q nomic-embed-text \
  && echo "  - nomic-embed-text OK" \
  || { echo "  - nomic-embed-text 설치..."; ollama pull nomic-embed-text; }
curl -s http://127.0.0.1:11434/api/tags | grep -q qwen2.5:3b \
  && echo "  - qwen2.5:3b OK" \
  || { echo "  - qwen2.5:3b 설치..."; ollama pull qwen2.5:3b; }

echo "==> 기존 SearXNG 컨테이너 정리"
docker rm -f "$NAME" 2>/dev/null || true

echo "==> SearXNG 컨테이너 실행 (포트 $PORT)"
docker run -d --name "$NAME" -p "${PORT}:8080" \
  -e SEARXNG_BASE_URL="http://localhost:${PORT}/" \
  searxng/searxng:latest

echo "==> settings.yml 생성 대기"
sleep 8

echo "==> JSON 출력 형식 활성화 (formats에 json 추가)"
# 기본 settings.yml의 search.formats 에는 html 만 있음 → json 추가
docker exec "$NAME" sh -c "grep -q '^    - json' /etc/searxng/settings.yml || sed -i '/^    - html\$/a\\    - json' /etc/searxng/settings.yml"

echo "==> 재시작"
docker restart "$NAME" >/dev/null
sleep 6

echo "==> JSON 검색 검증"
RES=$(curl -s "http://127.0.0.1:${PORT}/search?q=NIPA%20AI%20%EA%B3%B5%EB%AA%A8&format=json&language=ko-KR" -H "User-Agent: Mozilla/5.0" | head -c 200)
if echo "$RES" | grep -q '"results"\|"url"\|"query"'; then
  echo "  ✅ SearXNG JSON 검색 정상 (http://127.0.0.1:${PORT})"
else
  echo "  ⚠️ JSON 검색 응답 확인 필요:"
  echo "  $RES"
fi

echo ""
echo "완료. n8n govt_grants_local 워크플로우가 http://127.0.0.1:${PORT} 를 사용합니다."
echo "워크플로우를 활성화하면 매일 08:30 KST에 자동 실행됩니다."
