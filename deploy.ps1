[CmdletBinding()]
param(
  [ValidateRange(1, 1439)]
  [int]$IntervalMinutes = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Base = $PSScriptRoot
$EnvFile = Join-Path $Base '.env'
$TaskName = 'AutoWiFi Portal Login'
$LoginScript = Join-Path $Base 'portal-login.ps1'
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $Base 'ms-playwright'

function Get-DotEnvValue([string]$Name) {
  $pattern = '^\s*' + [regex]::Escape($Name) + '\s*=\s*(.*?)\s*$'
  foreach ($line in Get-Content -LiteralPath $EnvFile) {
    if ($line -match $pattern) {
      $value = $Matches[1].Trim()
      if ($value -match '^([''"])(.*)\1\s*(?:#.*)?$') {
        return $Matches[2]
      }
      return $value
    }
  }
  return ''
}

if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
  throw '需要先安装 Node.js 18 或更高版本，然后重新运行此脚本。'
}

$nodeMajor = [int](& node -p 'process.versions.node.split(".")[0]')
if ($nodeMajor -lt 18) {
  throw '需要 Node.js 18 或更高版本。'
}

if (-not (Test-Path (Join-Path $Base 'node_modules'))) {
  Write-Host '安装 Node.js 依赖...'
  Push-Location $Base
  try {
    & npm install
    if ($LASTEXITCODE -ne 0) { throw 'npm install 执行失败。' }
  } finally { Pop-Location }
}

Write-Host '检查 Playwright Chromium...'
Push-Location $Base
try {
  & npx playwright install chromium
  if ($LASTEXITCODE -ne 0) { throw 'Playwright Chromium 安装失败。' }
} finally { Pop-Location }

if (-not (Test-Path $EnvFile)) {
  $template = Join-Path $Base '.env.example'
  if (-not (Test-Path $template)) {
    throw '.env 不存在，且未找到 .env.example 模板。'
  }
  Copy-Item -LiteralPath $template -Destination $EnvFile
  throw '已创建 .env。请填写账号、密码和门户地址后，再次运行 deploy.ps1。'
}

$account = Get-DotEnvValue 'PORTAL_ACCOUNT'
$password = Get-DotEnvValue 'PORTAL_PASSWORD'
$candidates = Get-DotEnvValue 'PORTAL_LOGIN_CANDIDATES'
if ([string]::IsNullOrWhiteSpace($account) -or [string]::IsNullOrWhiteSpace($password) -or $account -eq 'your_account' -or $password -eq 'your_password') {
  throw '请先在 .env 中填写实际的 PORTAL_ACCOUNT 和 PORTAL_PASSWORD。'
}
if ([string]::IsNullOrWhiteSpace($candidates) -or $candidates -match 'portal\.example\.com') {
  throw '请先在 .env 中填写实际的 PORTAL_LOGIN_CANDIDATES。'
}

$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$LoginScript`""
$runAs = if ($env:USERDOMAIN) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USERNAME }

& schtasks.exe /Create /TN $TaskName /SC MINUTE /MO $IntervalMinutes /TR "powershell.exe $arguments" /RU $runAs /IT /F
if ($LASTEXITCODE -ne 0) {
  throw '创建 Windows 任务计划失败。请在已登录的普通用户 PowerShell 中重试。'
}

& schtasks.exe /Run /TN $TaskName
if ($LASTEXITCODE -ne 0) {
  throw '任务已创建，但无法立即启动。注销并重新登录后会自动启动。'
}

Write-Host "部署完成：已创建任务“$TaskName”，登录后按每 $IntervalMinutes 分钟巡检一次。"
Write-Host "日志：$Base\portal-login.log"
