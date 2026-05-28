# organize-workflows.ps1
# n8n 워크플로우 일괄 정리: 태그 5개 생성·색상 부여 + 워크플로우별 태그 부여 + 보관(archive) 처리
#
# 사용법:
#   $env:N8N_API_URL = "http://localhost:5678/api/v1"   # 또는 ngrok URL/api/v1
#   $env:N8N_API_KEY = "<your-n8n-personal-api-key>"     # n8n Settings → API → Create API key
#   pwsh -File .\tools\organize-workflows.ps1
#
# 안전 설계:
#   · 이미 같은 이름의 태그가 있으면 생성 스킵, 기존 태그 ID 재사용
#   · 워크플로우 태그 부여는 PUT(전체 교체) 대신 GET → merge → PUT 패턴
#   · 보관 처리 실패 시 (n8n 버전이 archive API 미지원) 경고만 출력하고 계속 진행

param(
  [string]$ApiUrl = $env:N8N_API_URL,
  [string]$ApiKey = $env:N8N_API_KEY
)

if (-not $ApiUrl) { $ApiUrl = "http://localhost:5678/api/v1" }
if (-not $ApiKey) {
  Write-Error "환경변수 N8N_API_KEY가 필요합니다. n8n Settings → API → Create API key 에서 발급 후 `$env:N8N_API_KEY = '...'` 로 설정하세요."
  exit 1
}
$ApiUrl = $ApiUrl.TrimEnd('/')

$Headers = @{ "X-N8N-API-KEY" = $ApiKey; "Accept" = "application/json" }
$HeadersJson = @{ "X-N8N-API-KEY" = $ApiKey; "Accept" = "application/json"; "Content-Type" = "application/json" }

Write-Host ""
Write-Host "================ n8n 워크플로우 일괄 정리 ================" -ForegroundColor Cyan
Write-Host ("Base URL: " + $ApiUrl)
Write-Host ""

# --- 1) 태그 5개 정의 -----------------------------------------------------
$tagDefs = @(
  @{ name = "BC통합비서"; color = "#7c3aed" },  # 보라 — 전체 브랜드
  @{ name = "메인";       color = "#3d7be8" },  # 파랑 — 사용자 진입 메인
  @{ name = "서브";       color = "#16a34a" },  # 초록 — 메인이 호출하는 도구
  @{ name = "자동";       color = "#f59e0b" },  # 노랑 — cron 자동 실행
  @{ name = "보관";       color = "#94a3b8" }   # 회색 — 사용 안 함
)

# --- 2) 기존 태그 조회 (중복 생성 방지) ----------------------------------
Write-Host "[1/4] 기존 태그 조회..." -ForegroundColor Yellow
$existingTags = @{}
try {
  $resp = Invoke-RestMethod -Method Get -Uri "$ApiUrl/tags?limit=250" -Headers $Headers
  foreach ($t in $resp.data) { $existingTags[$t.name] = $t.id }
  Write-Host ("  기존 태그 " + $existingTags.Count + "개 확인")
} catch {
  Write-Warning ("기존 태그 조회 실패: " + $_.Exception.Message + "  - 모두 새로 만들기 시도")
}

# --- 3) 5개 태그 생성 (없을 때만) ----------------------------------------
Write-Host ""
Write-Host "[2/4] 태그 생성·확보..." -ForegroundColor Yellow
$tagIds = @{}
foreach ($t in $tagDefs) {
  if ($existingTags.ContainsKey($t.name)) {
    $tagIds[$t.name] = $existingTags[$t.name]
    Write-Host ("  · " + $t.name + " — 기존 사용 (" + $existingTags[$t.name] + ")")
    continue
  }
  try {
    $body = @{ name = $t.name; color = $t.color } | ConvertTo-Json -Compress
    $r = Invoke-RestMethod -Method Post -Uri "$ApiUrl/tags" -Headers $HeadersJson -Body $body
    $tagIds[$t.name] = $r.id
    Write-Host ("  · " + $t.name + " — 신규 생성 (" + $r.id + ", " + $t.color + ")")
  } catch {
    Write-Warning ("  ! " + $t.name + " 생성 실패: " + $_.Exception.Message)
  }
}

# --- 4) 워크플로우별 태그 매핑 -------------------------------------------
$assign = [ordered]@{
  "uBeeFnSZU9TSrHFX" = @("BC통합비서","메인")   # 텔레그램 통합 비서
  "z4QmSOzAuTnCuXYS" = @("BC통합비서","메인")   # 돌봄 통화 API
  "baXYKndRBzoSdYaL" = @("BC통합비서","메인")   # 관리자 API
  "8x40LUeQyzA4u1pZ" = @("BC통합비서","메인")   # 회의록 에이전트
  "41Ck1Tl3RbkbJDou" = @("BC통합비서","서브")   # 이메일 발송 도구
  "YsSCObXSFHHvoR9W" = @("BC통합비서","서브")   # 뉴스 API
  "cHhUe74nafcURodY" = @("BC통합비서","서브")   # 회의록 RAG 등록
  "EO2RJd43MSDAtvQk" = @("BC통합비서","자동")   # 복약 알림 스케줄러
  "C4AYFi4p95N224X0" = @("BC통합비서","자동")   # 비용 임계 알림
  "iohUfS4yR1f7SOMy" = @("보관")                 # AI 다이제스트(구버전)
  "TGe3d1jamkJIoprx" = @("보관")                 # 임시 워크플로우
}

Write-Host ""
Write-Host "[3/4] 워크플로우에 태그 부여..." -ForegroundColor Yellow
foreach ($wfId in $assign.Keys) {
  $wantTagNames = $assign[$wfId]
  $wantTagObjs = @()
  foreach ($n in $wantTagNames) {
    if ($tagIds.ContainsKey($n)) { $wantTagObjs += @{ id = $tagIds[$n] } }
  }
  if ($wantTagObjs.Count -eq 0) { continue }
  $body = @{ tagIds = ($wantTagObjs | ForEach-Object { $_.id }) } | ConvertTo-Json -Compress
  try {
    Invoke-RestMethod -Method Put -Uri "$ApiUrl/workflows/$wfId/tags" -Headers $HeadersJson -Body $body | Out-Null
    Write-Host ("  · " + $wfId + " ← " + ($wantTagNames -join ", "))
  } catch {
    Write-Warning ("  ! " + $wfId + " 태그 부여 실패: " + $_.Exception.Message)
  }
}

# --- 5) 보관 2개 archive 처리 --------------------------------------------
Write-Host ""
Write-Host "[4/4] 보관 워크플로우 archive 처리..." -ForegroundColor Yellow
$archives = @(
  @{ id = "iohUfS4yR1f7SOMy"; label = "AI 기술 뉴스 다이제스트(구버전)" },
  @{ id = "TGe3d1jamkJIoprx"; label = "임시 워크플로우 (My workflow)" }
)
foreach ($a in $archives) {
  try {
    Invoke-RestMethod -Method Post -Uri ($ApiUrl + "/workflows/" + $a.id + "/archive") -Headers $Headers | Out-Null
    Write-Host ("  · 보관 처리됨: " + $a.label)
  } catch {
    Write-Warning ("  ! 보관 처리 실패(이 n8n 버전이 archive API 미지원일 수 있음): " + $a.label + " — " + $_.Exception.Message)
    Write-Host ("    수동 처리: n8n UI에서 워크플로우 우측 ⋮ → Archive")
  }
}

Write-Host ""
Write-Host "================ 완료 ================" -ForegroundColor Green
Write-Host "n8n Workflows 화면을 새로고침하면:"
Write-Host "  · 좌측 사이드바에 5개 태그(색상)가 표시됩니다."
Write-Host "  · 워크플로우 행에 색깔 태그 배지가 붙어 있습니다."
Write-Host "  · 보관 2개는 'Show archived'를 켜야 보입니다."
Write-Host ""
