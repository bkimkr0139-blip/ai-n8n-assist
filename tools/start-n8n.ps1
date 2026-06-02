# Start the live ai-n8n-assist n8n instance (npx-cache 2.20.11) with all required env.
# - Decrypts the Telegram bot token from the n8n credential (for the Send Voice node).
# - Raises N8N_PAYLOAD_SIZE_MAX so long meeting-recorder uploads (~2h ≈ 22MB) aren't 413'd.
# Pair with ngrok on the reserved static domain (see below) for Telegram/web access.
# Usage:  pwsh -File tools/start-n8n.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

# Intact 2.20.11 cache (the 83f51bd5 cache is corrupt — missing breaking-changes loader).
$cache = 'C:\Users\User\AppData\Local\npm-cache\_npx\a8a7eec953f1f314\node_modules'
$n8nBin = Join-Path $cache 'n8n\bin\n8n'

# Stop any n8n already listening on 5678 so the restart binds cleanly.
$pids = Get-NetTCPConnection -LocalPort 5678 -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
foreach ($p in $pids) { try { Stop-Process -Id $p -Force -ErrorAction Stop; Write-Host "stopped n8n PID $p" } catch {} }
if ($pids) { Start-Sleep -Seconds 2 }

# Decrypt the Telegram bot token to a temp file, load into env, then delete the file.
$tmp = Join-Path $env:TEMP 'tg_token.txt'
node (Join-Path $PSScriptRoot 'extract-tg-token.cjs') $tmp
if ($LASTEXITCODE -eq 0 -and (Test-Path $tmp)) {
  $env:TELEGRAM_BOT_TOKEN = (Get-Content $tmp -Raw).Trim()
  Remove-Item $tmp -Force
  Write-Host "TELEGRAM_BOT_TOKEN loaded (len=$($env:TELEGRAM_BOT_TOKEN.Length))"
} else {
  Write-Warning "Telegram token not loaded — voice replies will fail (everything else works)."
}

$env:WEBHOOK_URL = 'https://hardware-finalize-faceted.ngrok-free.dev'
$env:N8N_HOST = 'localhost'; $env:N8N_PORT = '5678'; $env:N8N_PROTOCOL = 'http'
$env:GENERIC_TIMEZONE = 'Asia/Seoul'; $env:TZ = 'Asia/Seoul'
$env:N8N_BLOCK_ENV_ACCESS_IN_NODE = 'false'
$env:N8N_DIAGNOSTICS_ENABLED = 'false'
$env:N8N_PAYLOAD_SIZE_MAX = '64'   # MiB — long meeting audio uploads

Write-Host "starting n8n 2.20.11 (payload max ${env:N8N_PAYLOAD_SIZE_MAX}MB)..."
node $n8nBin start
