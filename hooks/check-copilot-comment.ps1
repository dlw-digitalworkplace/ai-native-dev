# Copilot CLI preToolUse hook (PowerShell; used on Windows). Two jobs:
#   1) SIGNING ENFORCEMENT — deny direct ADO comment POSTs that bypass aind-comment.sh (which signs
#      by agent name).
#   2) BASH NORMALIZATION — when the model runs a bash script, rewrite the call (via modifiedArgs) to
#      invoke Git's bash by FULL PATH. Windows ships a WSL `bash.exe` in System32 that sits ahead of
#      Git's bash on PATH and fails when no WSL distro is installed; forcing Git's bash here means the
#      user needs NO PATH/profile setup (git is already a plugin prerequisite, and Git ships bash).
#
# Copilot contract:
#   stdin  = JSON { sessionId, timestamp, cwd, toolName, toolArgs(JSON string) }
#   stdout = JSON { permissionDecision: allow|deny|ask, permissionDecisionReason?, modifiedArgs? }
#   (preToolUse errors/timeouts DENY, so this fails OPEN — allow, no rewrite — on any parse error: a
#    hook bug must not block every tool call. It only ever DENIES a positively-identified bypass.)

$ErrorActionPreference = 'SilentlyContinue'

function Resolve-GitBash {
  # Prefer the bash that ships next to git (git is on PATH via Git\cmd; bash is at <gitroot>\bin).
  $g = (Get-Command git -ErrorAction SilentlyContinue).Source
  if ($g) {
    $b = Join-Path (Split-Path (Split-Path $g)) 'bin\bash.exe'
    if (Test-Path $b) { return $b }
  }
  foreach ($c in @("$env:ProgramFiles\Git\bin\bash.exe",
                   "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
                   "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
    if ($c -and (Test-Path $c)) { return $c }
  }
  return $null
}

$raw = [Console]::In.ReadToEnd()
$cmd = ''
$decision = 'allow'
$reason = $null
$toolArgs = $null

try {
  $evt = $raw | ConvertFrom-Json
  if ($null -ne $evt.toolArgs) {
    try { $toolArgs = $evt.toolArgs | ConvertFrom-Json; $cmd = [string]$toolArgs.command }
    catch { $cmd = [string]$evt.toolArgs }
  }

  if ($cmd -match 'aind-comment\.sh') {
    # Sanctioned path — always allowed (still normalized to Git's bash below).
    $decision = 'allow'
  }
  elseif ($cmd -match '_apis/wit/work[Ii]tems/[^/]+/comments' -or $cmd -match 'devops\s+invoke[\s\S]*comment') {
    # Direct ADO comment write that bypasses the signer.
    $decision = 'deny'
    $reason = 'Post ADO work-item comments via the aind-comment script, which signs them by agent name. Direct comment calls bypass signing and are not allowed. Use scripts/aind-comment.sh <work-item-id> <agent-name>.'
  }
}
catch {
  $decision = 'allow'
}

function Write-Log($note) {
  try { "$(Get-Date -Format o)`t$note`tcmd=$cmd" | Out-File -Append -FilePath "$env:USERPROFILE/aind-hook.log" } catch {}
}

if ($decision -eq 'deny') {
  Write-Log 'decision=deny'
  @{ permissionDecision = 'deny'; permissionDecisionReason = $reason } | ConvertTo-Json -Compress
  exit 0
}

# Allowed. If this is a bash invocation, force Git's bash by full path (modifiedArgs replaces the
# whole args object, so rebuild it from the original and swap only .command).
if ($cmd -match '^\s*bash\b') {
  $gitBash = Resolve-GitBash
  if ($gitBash -and $toolArgs) {
    $newCmd = $cmd -replace '^\s*bash\b', ('& "' + $gitBash + '"')
    $newArgs = @{}
    foreach ($p in $toolArgs.PSObject.Properties) { $newArgs[$p.Name] = $p.Value }
    $newArgs['command'] = $newCmd
    Write-Log "decision=allow rewrite-bash=$gitBash"
    @{ permissionDecision = 'allow'; modifiedArgs = $newArgs } | ConvertTo-Json -Compress
    exit 0
  }
  Write-Log 'decision=allow rewrite-bash=NONE(git-bash-not-found)'
}

Write-Log 'decision=allow'
'{"permissionDecision":"allow"}'
