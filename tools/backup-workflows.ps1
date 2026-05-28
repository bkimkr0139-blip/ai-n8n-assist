# backup-workflows.ps1 — n8n 라이브 워크플로우 전체 재해복구 백업
#
# 모든 워크플로우를 raw JSON으로 받아 workflows-backup/<날짜시각>/ 에 저장.
# raw export에는 일부 노드 파라미터에 실값(이메일·하드코딩 토큰 등)이 있을 수 있으므로
# 이 폴더는 .gitignore 처리됨 (로컬 재해복구 보관용, GitHub에 올리지 않음).
# repo의 형상관리용 sanitized export는 workflows/*.json 에 별도 유지.
#
# 사용:
#   $env:N8N_API_URL = 'http://localhost:5678/api/v1'   # 또는 ngrok URL/api/v1
#   $env:N8N_API_KEY = '<n8n Settings → API → Create API key>'
#   pwsh -File .\tools\backup-workflows.ps1

param(
  [string]$ApiUrl = $env:N8N_API_URL,
  [string]$ApiKey = $env:N8N_API_KEY
)

if (-not $ApiUrl) { $ApiUrl = "http://localhost:5678/api/v1" }
if (-not $ApiKey) {
  Write-Error "환경변수 N8N_API_KEY가 필요합니다. n8n Settings → API → Create API key."
  exit 1
}
$ApiUrl = $ApiUrl.TrimEnd('/')
$Headers = @{ "X-N8N-API-KEY" = $ApiKey; "Accept" = "application/json" }

$root = Join-Path $PSScriptRoot ".."
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $root ("workflows-backup\" + $stamp)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host ""
Write-Host "==> n8n 워크플로우 백업: $outDir" -ForegroundColor Cyan

# 전체 워크플로우 목록 (페이지네이션)
$all = @()
$cursor = $null
do {
  $uri = "$ApiUrl/workflows?limit=100"
  if ($cursor) { $uri += "&cursor=$cursor" }
  $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers
  $all += $resp.data
  $cursor = $resp.nextCursor
} while ($cursor)

Write-Host ("총 " + $all.Count + "개 워크플로우 발견") -ForegroundColor Yellow

$idx = 0
foreach ($wf in $all) {
  $idx++
  try {
    $full = Invoke-RestMethod -Method Get -Uri "$ApiUrl/workflows/$($wf.id)" -Headers $Headers
    # 파일명 안전화 (특수문자 제거)
    $safe = ($wf.name -replace '[\\/:*?"<>|\[\]·]', '_').Trim('_ ')
    if (-not $safe) { $safe = $wf.id }
    $file = Join-Path $outDir ("{0}__{1}.json" -f $safe, $wf.id)
    $full | ConvertTo-Json -Depth 100 | Out-File -FilePath $file -Encoding utf8
    $act = if ($wf.active) { "●활성" } else { "○비활성" }
    Write-Host ("  [{0}/{1}] {2} {3}" -f $idx, $all.Count, $act, $wf.name)
  } catch {
    Write-Warning ("  ! " + $wf.name + " 백업 실패: " + $_.Exception.Message)
  }
}

# 매니페스트 (목록 요약)
$manifest = $all | Select-Object id, name, active, @{n='nodeCount';e={$_.nodes.Count}}, updatedAt
$manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $outDir "_manifest.json") -Encoding utf8

Write-Host ""
Write-Host "==> 완료: $($all.Count)개 백업됨" -ForegroundColor Green
Write-Host "복원: n8n UI → Workflows → Import from File → 해당 .json 선택"
Write-Host "(또는 REST API POST $ApiUrl/workflows 로 본문 전송)"
Write-Host ""
