<#
.SYNOPSIS
  One-shot: Blackfrost-AI CYBER-FROST-3.8-FP4-Local, served natively on Windows 11 ARM64 on an NVIDIA RTX Spark.

.DESCRIPTION
  1. Checks the machine (Windows 11 ARM64, NVIDIA driver with CUDA 13, ~128 GB memory, disk space).
  2. Downloads the prebuilt engine from this repo's GitHub release and checks its SHA-256.
  3. Downloads the model (95.24 GiB) from Hugging Face at a pinned revision, resumable, and checks every
     large file's SHA-256 against the Hub's own record.
  4. Writes start.cmd / stop.cmd / status.cmd, starts the server, waits for it and sends a test request.
  5. Prints the OpenAI-compatible endpoint for your agent and writes agent-endpoint.json.

  Safe to re-run: finished downloads are kept, and an interrupted model download resumes.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\oneshot.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\oneshot.ps1 -ModelDir D:\models\CYBER-FROST-3.8-FP4-Local -Port 8000
#>
[CmdletBinding()]
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'CyberFrostRTX'),
  [string]$ModelDir   = 'C:\models\CYBER-FROST-3.8-FP4-Local',
  [int]$Port          = 8000,
  [int]$Context       = 32768,
  [int]$Parallel      = 4,
  [string]$Name       = 'cyberfrost',
  [string]$ApiKey     = '',
  [switch]$Lan,          # listen on all interfaces instead of 127.0.0.1 (set -ApiKey too)
  [switch]$Thinking,     # serve with reasoning on (default off: faster, cleaner for agents)
  [switch]$SkipModel,    # model already in -ModelDir; skip download + hash checks
  [switch]$SkipVerify,   # download but don't hash (faster re-runs)
  [switch]$NoStart,      # install only
  [switch]$Force         # continue past the hardware checks
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---- pins ---------------------------------------------------------------------------------------------
$RepoSlug     = 'drowzeys/keys-RTX-Spark-Windows11-Arm64-CyberFrost-3.8-BlackFrostAI'
$ReleaseTag   = 'v1.0.0'
$EngineZip    = 'cyberfrost-engine-win-arm64-sm121.zip'
$EngineSha256 = '6d45a65641caa22527aa10bbb940d1d31e9c0ff96dab7cd49909c88893e74dee'
$HfRepo       = 'Blackfrost-AI/CYBER-FROST-3.8-FP4-Local'
$HfRevision   = '15c68d90fbe2d91b28e32ac35bc739ce8d5648d2'
$ModelBytes   = 102265156823   # sum of all 45 files at $HfRevision
# -------------------------------------------------------------------------------------------------------

function Say($m)  { Write-Host "[cyberfrost] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[cyberfrost] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[cyberfrost] $m" -ForegroundColor Red; exit 1 }

# ---- 1. machine checks --------------------------------------------------------------------------------
Say 'Checking this machine'
$problems = @()
$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
if ($arch -ne 'ARM64') { $problems += "This build is for Windows on ARM64; this is $arch." }

$smi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if (-not $smi) { $smi = Get-Item "$env:WINDIR\System32\nvidia-smi.exe" -ErrorAction SilentlyContinue }
if (-not $smi) { Die 'nvidia-smi not found: install the NVIDIA driver for the RTX Spark first.' }
$smiPath = if ($smi.Source) { $smi.Source } else { $smi.FullName }
$gpu = (& $smiPath --query-gpu=name,driver_version,memory.total --format=csv,noheader | Select-Object -First 1)
$cudaVer = ((& $smiPath) | Select-String 'CUDA Version:\s*([0-9.]+)').Matches | Select-Object -First 1
Say "GPU: $gpu"
if ($cudaVer) {
  $cv = [version]$cudaVer.Groups[1].Value
  Say "Driver CUDA version: $cv"
  if ($cv.Major -lt 13) { $problems += "The engine is built with CUDA 13.4; the driver reports CUDA $cv. Update the NVIDIA driver." }
}
if ($gpu -notmatch 'RTX Spark') { $problems += 'GPU is not an NVIDIA RTX Spark (sm_121). The prebuilt engine targets that chip only.' }

# The RTX Spark's firmware splits its 128 GB between Windows and the GPU (e.g. 30 GB + 96 GB), so count both.
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$gpuMiB = 0
if ($gpu -match ',\s*([0-9]+)\s*MiB') { $gpuMiB = [int]$Matches[1] }
$gpuGB = [math]::Round($gpuMiB / 1024)
Say "Memory: $ramGB GB for Windows + $gpuGB GB reserved for the GPU"
if (($ramGB + $gpuGB) -lt 115) { $problems += "The model needs a 128 GB RTX Spark (weights alone are 95 GiB); this machine has $($ramGB + $gpuGB) GB in total." }
elseif ($gpuGB -lt 90) { $problems += "Only $gpuGB GB is reserved for the GPU. This was tested with 96 GB reserved; with less the 95 GiB model may not load." }

if ($problems.Count) {
  $problems | ForEach-Object { Warn $_ }
  if (-not $Force) { Die 'Stopping. Re-run with -Force to try anyway.' }
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path $ModelDir   | Out-Null

# stop an earlier server of ours so files can be replaced
Get-Process cyberfrost-engine -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# ---- 2. engine ----------------------------------------------------------------------------------------
$exe = Join-Path $InstallDir 'bin\cyberfrost-engine.exe'
$stamp = Join-Path $InstallDir '.engine-sha256'
if ((Test-Path $exe) -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $EngineSha256)) {
  Say 'Engine already installed'
} else {
  $zip = Join-Path $env:TEMP $EngineZip
  $url = "https://github.com/$RepoSlug/releases/download/$ReleaseTag/$EngineZip"
  Say "Downloading engine: $url"
  & curl.exe -fL --retry 5 --retry-delay 3 -o $zip $url
  if ($LASTEXITCODE -ne 0) { Die "Engine download failed (curl exit $LASTEXITCODE)." }
  $h = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $EngineSha256) { Die "Engine checksum mismatch: got $h, expected $EngineSha256." }
  Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
  Remove-Item $zip -Force
  Set-Content -Path $stamp -Value $EngineSha256 -NoNewline
  Say "Engine installed in $InstallDir"
}
$ver = & $exe --version 2>&1
Say "Engine: $ver"

# ---- 3. model -----------------------------------------------------------------------------------------
if (-not $SkipModel) {
  $have = 0
  if (Test-Path $ModelDir) { $have = (Get-ChildItem $ModelDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
  if (-not $have) { $have = 0 }
  $drive = (Get-Item $ModelDir).PSDrive
  $free = (Get-PSDrive $drive.Name).Free
  $need = $ModelBytes - $have + 2GB
  Say ("Model: {0:N1} GiB already present, {1:N1} GiB free on {2}:" -f ($have/1GB), ($free/1GB), $drive.Name)
  if ($need -gt $free) { Die ("Not enough disk: need about {0:N1} GiB more on {1}:. Free space or pass -ModelDir on another drive." -f (($need-$free)/1GB), $drive.Name) }

  Say "Listing $HfRepo @ $HfRevision"
  $tree = Invoke-RestMethod -Uri "https://huggingface.co/api/models/$HfRepo/tree/$HfRevision`?recursive=true" -UseBasicParsing
  $files = @($tree | Where-Object { $_.type -eq 'file' })
  function Get-HubFile($f, $dst, $size) {
    $url = "https://huggingface.co/$HfRepo/resolve/$HfRevision/$($f.path)"
    for ($try = 1; $try -le 5; $try++) {
      & curl.exe -fL --retry 5 --retry-delay 5 -C - -o $dst $url
      if ($LASTEXITCODE -eq 0 -and (Get-Item $dst).Length -eq $size) { return }
      if ((Test-Path $dst) -and (Get-Item $dst).Length -gt $size) { Remove-Item $dst -Force }
      Warn "Retrying $($f.path) (attempt $try, curl exit $LASTEXITCODE)"
      Start-Sleep 5
    }
    Die "Could not download $($f.path). Re-run to resume."
  }
  $i = 0
  foreach ($f in $files) {
    $i++
    $dst = Join-Path $ModelDir ($f.path -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    $size = [int64]$f.size
    $sha = $null
    if ($f.lfs) { $sha = $f.lfs.oid }
    if (-not ((Test-Path $dst) -and ((Get-Item $dst).Length -eq $size))) {
      Say ("[{0}/{1}] {2} ({3:N2} GiB)" -f $i, $files.Count, $f.path, ($size/1GB))
      Get-HubFile $f $dst $size
    }
    if ($sha -and -not $SkipVerify) {
      $marker = "$dst.sha256ok"
      if (-not ((Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq $sha))) {
        $h = (Get-FileHash $dst -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $sha) {
          # Keep the bad copy aside until a good one has arrived, then remove it.
          Warn "Checksum mismatch for $($f.path) (got $h); downloading a fresh copy"
          $bad = "$dst.mismatch"
          Move-Item $dst $bad -Force
          Get-HubFile $f $dst $size
          $h = (Get-FileHash $dst -Algorithm SHA256).Hash.ToLower()
          if ($h -ne $sha) { Die "The fresh copy of $($f.path) doesn't match either (got $h). Check the disk; the old copy is at $bad." }
          Remove-Item $bad -Force
        }
        Set-Content -Path $marker -Value $sha -NoNewline
      }
    }
  }
  Say 'Model complete and verified'
}
if (-not (Test-Path (Join-Path $ModelDir 'config.json'))) { Die "No config.json in $ModelDir." }

# ---- 4. launch scripts --------------------------------------------------------------------------------
$listen = if ($Lan) { '0.0.0.0' } else { '127.0.0.1' }
$think = if ($Thinking) { '--thinking' } else { '--no-thinking' }
$keyArg = if ($ApiKey) { "--api-key `"$ApiKey`"" } else { '' }
$log = Join-Path $InstallDir 'server.log'
$serveArgs = "serve `"$ModelDir`" --name $Name --host $listen --port $Port --context $Context --parallel $Parallel $think --no-update-check $keyArg"

Set-Content -Path (Join-Path $InstallDir 'start.cmd') -Encoding ASCII -Value @"
@echo off
rem Starts CYBER-FROST-3.8-FP4-Local on http://${listen}:$Port/v1 (OpenAI-compatible). Log: $log
start "cyberfrost" /min cmd /c ""$exe" $serveArgs > "$log" 2>&1"
echo Starting. Loading takes about 1-3 minutes; then: curl http://127.0.0.1:$Port/v1/models
"@
Set-Content -Path (Join-Path $InstallDir 'stop.cmd') -Encoding ASCII -Value @"
@echo off
taskkill /f /im cyberfrost-engine.exe
"@
Set-Content -Path (Join-Path $InstallDir 'status.cmd') -Encoding ASCII -Value @"
@echo off
curl -s http://127.0.0.1:$Port/v1/models
echo.
nvidia-smi --query-gpu=memory.used,utilization.gpu,power.draw --format=csv
"@

$endpoint = [ordered]@{
  provider = 'openai-compatible'
  base_url = "http://127.0.0.1:$Port/v1"
  model    = $Name
  api_key  = $(if ($ApiKey) { '<the -ApiKey you set>' } else { 'none (any string)' })
  context  = $Context
  parallel = $Parallel
  thinking = [bool]$Thinking
  start    = (Join-Path $InstallDir 'start.cmd')
  stop     = (Join-Path $InstallDir 'stop.cmd')
}
$endpoint | ConvertTo-Json | Set-Content -Path (Join-Path $InstallDir 'agent-endpoint.json') -Encoding UTF8

if ($NoStart) { Say "Installed. Start with: $(Join-Path $InstallDir 'start.cmd')"; exit 0 }

# ---- 5. start, wait, smoke test -----------------------------------------------------------------------
Say "Starting the server on http://${listen}:$Port/v1"
& cmd.exe /c (Join-Path $InstallDir 'start.cmd') | Out-Null
$headers = @{}
if ($ApiKey) { $headers['Authorization'] = "Bearer $ApiKey" }
$t0 = Get-Date
$ready = $false
while (((Get-Date) - $t0).TotalSeconds -lt 900) {
  Start-Sleep 5
  if (-not (Get-Process cyberfrost-engine -ErrorAction SilentlyContinue)) { Get-Content $log -Tail 30; Die "The server exited. Log: $log" }
  try { $m = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/models" -Headers $headers -TimeoutSec 3; if ($m.data) { $ready = $true; break } } catch {}
}
if (-not $ready) { Get-Content $log -Tail 30; Die "Not ready after 15 minutes. Log: $log" }
Say ("Ready in {0:N0} s" -f ((Get-Date) - $t0).TotalSeconds)

$body = @{ model = $Name; max_tokens = 32; temperature = 0; messages = @(@{ role = 'user'; content = 'Reply with exactly: cyberfrost ready' }) } | ConvertTo-Json -Depth 5
$r = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Method Post -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 120
Say ("Test reply: " + $r.choices[0].message.content)

Write-Host ''
Write-Host 'Point your agent at this OpenAI-compatible endpoint:' -ForegroundColor Green
Write-Host "  base_url : http://127.0.0.1:$Port/v1"
Write-Host "  model    : $Name"
Write-Host "  api_key  : $(if ($ApiKey) { 'the -ApiKey you set' } else { 'not required (any string)' })"
Write-Host "Saved to $(Join-Path $InstallDir 'agent-endpoint.json'). Stop: $(Join-Path $InstallDir 'stop.cmd')"
