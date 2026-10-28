# Tester and reviewer step for a builder's branch (agent team).
#
#   powershell -File tool\team_check.ps1 -Worktree C:\dev\wt\P1-21 [-SkipReview]
#
# In the worktree: flutter analyze, dart format check and the full test
# suite, then a read-only Codex review of the branch against main.
# Reports go to tool\logs\team\<branch>-test.log and <branch>-review.md.
# Exit code 0 only when analysis, format and tests pass. The review is
# advice for the Lead; it does not change the exit code.
# The Windows journey test is not run here: it drives the shared desktop,
# so the Lead runs it on main after merging.

param(
    [Parameter(Mandatory)] [string]$Worktree,
    [switch]$SkipReview
)

$ErrorActionPreference = 'Continue'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$env:Path = "C:\dev\flutter\bin;$env:Path"
$logDir = Join-Path $repo 'tool\logs\team'
New-Item -ItemType Directory -Force $logDir | Out-Null

Push-Location $Worktree
try {
    $branch = (git branch --show-current).Trim()
    $slug = $branch -replace '[^A-Za-z0-9-]', '_'
    $testLog = Join-Path $logDir "$slug-test.log"
    $failed = @()

    "== $branch at $(git rev-parse --short HEAD), $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Set-Content $testLog -Encoding utf8
    "`n== flutter analyze" | Add-Content $testLog -Encoding utf8
    flutter analyze *>&1 | Add-Content $testLog -Encoding utf8
    if ($LASTEXITCODE -ne 0) { $failed += 'analyze' }
    "`n== dart format" | Add-Content $testLog -Encoding utf8
    dart format --output=none --set-exit-if-changed lib test *>&1 | Add-Content $testLog -Encoding utf8
    if ($LASTEXITCODE -ne 0) { $failed += 'format' }
    "`n== flutter test" | Add-Content $testLog -Encoding utf8
    flutter test --reporter compact *>&1 | Select-Object -Last 40 | Add-Content $testLog -Encoding utf8
    if ($LASTEXITCODE -ne 0) { $failed += 'test' }

    if (-not $SkipReview) {
        $codex = Get-ChildItem "$env:USERPROFILE\.vscode\extensions\openai.chatgpt-*-win32-x64\bin\windows-x86_64\codex.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
        $review = Join-Path $logDir "$slug-review.md"
        if ($codex) {
            # ToString() turns PowerShell 5.1's stderr error records back into plain lines.
            & $codex review --base main *>&1 | ForEach-Object { $_.ToString() } |
                Where-Object { $_ -notmatch 'ERROR codex_core::session: failed to record rollout|^System\.Management\.Automation\.RemoteException$' } |
                Set-Content $review -Encoding utf8
        } else {
            'Codex not found; review skipped.' | Set-Content $review -Encoding utf8
        }
        Write-Host "Review:  $review"
    }

    Write-Host "Tests:   $testLog"
    if ($failed) { Write-Host "FAILED:  $($failed -join ', ')"; exit 1 }
    Write-Host 'PASSED:  analyze, format, test'
    exit 0
}
finally {
    Pop-Location
}
