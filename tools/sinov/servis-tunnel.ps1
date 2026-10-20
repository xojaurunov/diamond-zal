# Telefonda sinov (03d): kompyuterdagi Qobil servisi + ilovaning web nusxasi + Cloudflare Quick Tunnel.
# Telefonda chiqqan manzilni oching (".../sinov/"). Zaldagi APK va sayt O'ZGARMAYDI — bu alohida nusxa.
#
#   powershell -ExecutionPolicy Bypass -File tools\sinov\servis-tunnel.ps1 [-Qurma] [-Backend <papka>]
#
#   -Qurma    web nusxani qayta qurmaydi (oldingisi ishlatiladi)
#   -Backend  servis papkasi (standart: .\backend)
#
# Diqqat: tunnel yoqiq turganda servis internetdan ochiq (himoya — kirish va ruxsatlar, saytdagidek).
# Sinov tugagach Ctrl+C — servis ham, tunnel ham yopiladi.
param([switch]$Qurma, [string]$Backend = '')

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $Backend) { $Backend = Join-Path $repo 'backend' }
$python = Join-Path $repo 'backend\.venv\Scripts\python.exe'
$web = Join-Path $repo 'build\web'

# 1. Baza (Docker)
docker compose -f (Join-Path $repo 'backend\docker-compose.yml') up -d | Out-Null

# 2. Web nusxa: servis manzili sahifaning o'zidan (tunnel manzili har safar o'zgaradi)
if (-not $Qurma) {
    Push-Location $repo
    flutter build web --release --base-href /sinov/ --dart-define=API_URL=origin
    Pop-Location
}

# 3. cloudflared — Cloudflare'ning rasmiy dasturi (bir marta yuklab olinadi, loyihadan tashqarida)
$tools = Join-Path $env:LOCALAPPDATA 'qobil-tools'
$cf = Join-Path $tools 'cloudflared.exe'
if (-not (Test-Path $cf)) {
    New-Item -ItemType Directory -Force $tools | Out-Null
    Write-Host 'cloudflared yuklanmoqda (github.com/cloudflare/cloudflared)...'
    Invoke-WebRequest 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' -OutFile $cf
}

# 4. Servis (web nusxa bilan) va tunnel
$env:WEB_DIR = $web
$api = Start-Process -FilePath $python -ArgumentList '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000' `
    -WorkingDirectory $Backend -PassThru -NoNewWindow
$log = Join-Path $env:TEMP 'qobil-tunnel.log'
Remove-Item $log -ErrorAction SilentlyContinue
$tunnel = Start-Process -FilePath $cf -ArgumentList 'tunnel', '--no-autoupdate', '--url', 'http://127.0.0.1:8000' `
    -RedirectStandardError $log -PassThru -WindowStyle Hidden

try {
    $url = $null
    for ($i = 0; $i -lt 60 -and -not $url; $i++) {
        Start-Sleep 1
        if (Test-Path $log) {
            $m = Select-String -Path $log -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' | Select-Object -First 1
            if ($m) { $url = $m.Matches[0].Value }
        }
    }
    if (-not $url) { throw "Tunnel manzili chiqmadi — $log ga qarang" }
    Write-Host ''
    Write-Host "TELEFONDA OCHING:  $url/sinov/" -ForegroundColor Green
    Write-Host 'To''xtatish: Ctrl+C'
    Wait-Process -Id $api.Id
} finally {
    foreach ($p in @($tunnel, $api)) { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
    Write-Host 'Servis va tunnel yopildi.'
}
