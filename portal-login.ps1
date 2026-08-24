[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Project = if ($env:AUTO_WIFI_PROJ) { $env:AUTO_WIFI_PROJ } else { $PSScriptRoot }
$NodeScript = Join-Path $Project 'portal-login.mjs'
$LogFile = Join-Path $Project 'portal-login.log'
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $Project 'ms-playwright'

function Write-Log([string]$Message) {
  Add-Content -LiteralPath $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" -Encoding utf8
}

function Get-HttpStatus([string]$Url, [int]$TimeoutMilliseconds = 5000) {
  try {
    $request = [System.Net.WebRequest]::Create($Url)
    $request.Method = 'HEAD'
    $request.Timeout = $TimeoutMilliseconds
    $request.ReadWriteTimeout = $TimeoutMilliseconds
    $request.AllowAutoRedirect = $false
    $response = $request.GetResponse()
    try { return [int]$response.StatusCode } finally { $response.Close() }
  } catch [System.Net.WebException] {
    if ($_.Exception.Response) {
      try { return [int]$_.Exception.Response.StatusCode } finally { $_.Exception.Response.Close() }
    }
  } catch {}
  return $null
}

function Test-Online {
  $probes = @(
    'http://neverssl.com/',
    'http://www.msftconnecttest.com/connecttest.txt',
    'http://captive.apple.com/hotspot-detect.html',
    'https://www.qq.com',
    'https://www.baidu.com'
  )

  foreach ($probe in $probes) {
    $status = Get-HttpStatus $probe
    if ($status -in 200, 301, 302) { return $true }
  }
  return $false
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Log 'node.js was not found.'
  return
}

if (Test-Online) {
  return
}

$portalStatus = Get-HttpStatus 'http://114.114.114.114:90/'
if ($portalStatus -notin 200, 301, 302, 303, 307) {
  return
}

Write-Log 'start login'
$output = & node $NodeScript 2>&1
$nodeExitCode = $LASTEXITCODE
foreach ($line in $output) {
  Write-Log ([string]$line)
}

Start-Sleep -Seconds 2
if ($nodeExitCode -eq 0 -and (Test-Online)) {
  Write-Log 'login ok'
} else {
  Write-Log 'login fail'
}
