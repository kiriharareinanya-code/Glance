<#
.SYNOPSIS
    Lyricify 移植的**一条龙验收**：完整性 + 成员保真 + analyze + 全量测试。

.DESCRIPTION
    对照 docs/lyricify-port.md 的验收要求逐条跑，任一关不过就返回非 0。

.EXAMPLE
    pwsh -File tool\verify_port.ps1
    pwsh -File tool\verify_port.ps1 -SkipTests      # 只跑静态检查（改代码时用，快）
#>
[CmdletBinding()]
param(
    [switch]$SkipTests,
    [string]$FlutterBin = 'C:\src\flutter\bin'
)

$ErrorActionPreference = 'Continue'
$env:Path = "$env:Path;$FlutterBin"
Set-Location (Split-Path $PSScriptRoot -Parent)

$py = 'C:\Users\81157\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
$fail = @()

function Step($name, $block) {
    Write-Host ''
    Write-Host "=== $name ===" -ForegroundColor Cyan
    & $block
    if ($LASTEXITCODE -ne 0) { $script:fail += $name }
}

# 1) 完整性：上游 110 个 .cs 是否都有对应 Dart 实现
Step 'port_audit（文件级完整性）' { & $py tool\port_audit.py }

# 2) 契约：出处注释 / 不许 import Flutter / 关键方法签名 / LICENSE+NOTICE
Step 'check_contracts（硬约定）' { & $py tool\check_contracts.py }

# 3) 成员保真：有没有抄漏的方法/字段
Step 'member_audit（成员级保真）' { & $py tool\member_audit.py }

# 4) 静态检查：整个项目 0 error
Step 'flutter analyze' { flutter analyze }

if (-not $SkipTests) {
    # 5) 全量测试
    Step 'flutter test' { flutter test }
}

Write-Host ''
if ($fail.Count -eq 0) {
    Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
    exit 0
}
Write-Host "FAILED: $($fail -join ', ')" -ForegroundColor Red
exit 1