# Overnight supervisor: runs one agent task at a time, Claude Code first,
# falling back to Google Antigravity (agy) when Claude hits a limit or stalls.
# Usage:  powershell -File tool\overnight.ps1 [-Until "08:00"] [-MaxRuns 40]
param(
    [string]$Until = "08:00",
    [int]$MaxRuns = 40,
    [int]$RunMinutes = 100
)

$ErrorActionPreference = "Continue"
$Repo = Split-Path $PSScriptRoot -Parent
Set-Location $Repo
$LogDir = Join-Path $Repo "tool\logs"
New-Item -ItemType Directory -Force $LogDir | Out-Null
$SupLog = Join-Path $LogDir "supervisor.log"

function Log($msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    Add-Content -Path $SupLog -Value $line -Encoding utf8
    Write-Host $line
}

# Toolchain for child processes
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot"
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA "Android\Sdk"
$env:Path = "C:\dev\flutter\bin;$env:ANDROID_HOME\platform-tools;$env:Path"

# Keep the PC awake while this script runs (released automatically on exit)
Add-Type -Namespace Win32 -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
[Win32.Power]::SetThreadExecutionState([uint32]"0x80000001") | Out-Null  # ES_CONTINUOUS | ES_SYSTEM_REQUIRED

$deadline = [datetime]::ParseExact($Until, "HH:mm", $null)
if ($deadline -le (Get-Date)) { $deadline = $deadline.AddDays(1) }

$ClaudeExe = Get-ChildItem "$env:USERPROFILE\.vscode\extensions\anthropic.claude-code-*\resources\native-binary\claude.exe" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
$AgyExe = Join-Path $env:USERPROFILE ".gemini\bin\agy.exe"
# Codex is not in the relay: its Windows sandbox runs as another user, so it
# cannot run Git or Flutter here and leaves uncommitted work on main.
$Prompt = '"Read tool/agent-prompt.md and follow it exactly."'

$Agents = @(
    @{ Name = "claude";      Exe = $ClaudeExe; Args = "-p $Prompt --dangerously-skip-permissions" },
    @{ Name = "agy-opus";    Exe = $AgyExe;    Args = "-p $Prompt --dangerously-skip-permissions --model claude-opus-4-6-thinking" },
    @{ Name = "agy-gemini";  Exe = $AgyExe;    Args = "-p $Prompt --dangerously-skip-permissions --model gemini-3.8-flash-high" }
)
$cooldown = @{}            # agent name -> time it may be used again
$LimitPattern = 'usage limit|session limit|rate limit|limit reached|out of credits|insufficient credit|quota|resets |429|overloaded|exhausted'

function CommitCount { [int](git rev-list --all --count 2>$null) }

Log "Supervisor started. Deadline $deadline. Claude: $ClaudeExe"
$noProgress = 0

for ($run = 1; $run -le $MaxRuns; $run++) {
    if ((Get-Date) -ge $deadline) { Log "Deadline reached."; break }
    # The marker must be a line on its own; prose that mentions it does not count.
    if ((Test-Path docs\PROGRESS.md) -and (Select-String -Path docs\PROGRESS.md -Pattern '^\s*OVERNIGHT-COMPLETE\s*$' -Quiet)) { Log "OVERNIGHT-COMPLETE found."; break }

    $agent = $Agents | Where-Object { $_.Exe -and (Test-Path $_.Exe) -and (-not $cooldown[$_.Name] -or $cooldown[$_.Name] -le (Get-Date)) } | Select-Object -First 1
    if (-not $agent) { Log "All agents cooling down. Waiting 15 min."; Start-Sleep -Seconds 900; $run--; continue }

    git checkout main 2>$null | Out-Null
    $before = CommitCount
    $out = Join-Path $LogDir ("run-{0:D2}-{1}-{2:HHmm}.log" -f $run, $agent.Name, (Get-Date))
    Log "Run $run with $($agent.Name) -> $out"

    $p = Start-Process -FilePath $agent.Exe -ArgumentList $agent.Args -WorkingDirectory $Repo -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    if (-not $p.WaitForExit($RunMinutes * 60 * 1000)) {
        Log "Run $run exceeded $RunMinutes min. Stopping it."
        & taskkill /PID $p.Id /T /F | Out-Null
    }
    $text = (Get-Content $out, "$out.err" -Raw -ErrorAction SilentlyContinue) -join "`n"
    $after = CommitCount
    Log ("Run {0} exit={1} commits +{2}" -f $run, $p.ExitCode, ($after - $before))

    if ($text -match $LimitPattern -and ($after - $before) -eq 0) {
        Log "$($agent.Name) looks limited. Cooling down 60 min."
        $cooldown[$agent.Name] = (Get-Date).AddMinutes(60)
        continue
    }
    if ($after -eq $before) {
        $noProgress++
        $cooldown[$agent.Name] = (Get-Date).AddMinutes(30)   # let another agent try
        if ($noProgress -ge 4) { Log "Four runs without a commit. Stopping to save credits."; break }
    } else {
        $noProgress = 0
    }
}

git checkout main 2>$null | Out-Null
Log "Supervisor finished."
