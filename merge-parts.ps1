<#
  合并分卷文件并校验 SHA256
  用法:
    powershell -ExecutionPolicy Bypass -File .\merge-parts.ps1
    powershell -ExecutionPolicy Bypass -File .\merge-parts.ps1 -Base "oc2.2.6.zip"
#>
[CmdletBinding()]
param(
    # 目标文件名（默认自动找同目录下第一组分卷）
    [string]$Base
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $Base) {
    $first = Get-ChildItem -LiteralPath $dir -Filter '*.part001' |
             Sort-Object Name | Select-Object -First 1
    if (-not $first) { throw "当前目录没有找到 *.part001 分卷文件: $dir" }
    $Base = $first.Name -replace '\.part001$', ''
}

$parts = Get-ChildItem -LiteralPath $dir -Filter "$Base.part*" | Sort-Object Name
if ($parts.Count -eq 0) { throw "没有找到 $Base.part* 分卷文件" }

# 检查分卷编号是否连续（part001, part002, ...）
$expected = 1
foreach ($p in $parts) {
    $num = [int]($p.Name -replace '^.*\.part(\d+)$', '$1')
    if ($num -ne $expected) { throw "分卷编号不连续，缺少 part$('{0:D3}' -f $expected)" }
    $expected++
}

$outPath = Join-Path $dir $Base
if (Test-Path -LiteralPath $outPath) {
    Write-Host "已存在 $Base，将覆盖。"
    Remove-Item -LiteralPath $outPath -Force
}

Write-Host "正在合并 $($parts.Count) 个分卷 -> $Base"
$out = [System.IO.File]::Create($outPath)
try {
    foreach ($p in $parts) {
        $in = [System.IO.File]::OpenRead($p.FullName)
        try { $in.CopyTo($out, 1MB) } finally { $in.Close() }
        Write-Host ("  + {0}  ({1:N0} bytes)" -f $p.Name, $p.Length)
    }
} finally { $out.Close() }

$size = (Get-Item -LiteralPath $outPath).Length
Write-Host ("合并完成: {0}  {1:N0} bytes" -f $Base, $size)

# 如果存在 .sha256 文件则校验
$shaFile = "$outPath.sha256"
if (Test-Path -LiteralPath $shaFile) {
    $expectedHash = (Get-Content -LiteralPath $shaFile | Select-Object -First 1).Split(' ')[0].Trim().ToUpper()
    $actualHash = (Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash.ToUpper()
    Write-Host "期望 SHA256: $expectedHash"
    Write-Host "实际 SHA256: $actualHash"
    if ($actualHash -eq $expectedHash) {
        Write-Host "校验通过 ✔" -ForegroundColor Green
    } else {
        Write-Host "校验失败 ✘ 文件可能不完整，请重新下载缺失的分卷" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "未找到 $Base.sha256，跳过校验。"
}
