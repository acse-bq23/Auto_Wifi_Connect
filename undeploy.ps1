[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'AutoWiFi Portal Login'
& schtasks.exe /Query /TN $TaskName *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host '未找到 Windows 自动连接任务，可能已经卸载。'
  return
}

& schtasks.exe /End /TN $TaskName *> $null
& schtasks.exe /Delete /TN $TaskName /F
if ($LASTEXITCODE -ne 0) {
  throw '删除 Windows 自动连接任务失败。'
}

Write-Host '已移除 Windows 自动连接任务。'
