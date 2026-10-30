param(
    # Root of the per-machine rig configuration directories. The rig workflow reads
    # <ConfigRoot>\<MACHINE-NAME>\rig.yml and calibration artefacts beside it. In
    # Coen-Lab-Local with the lab's other local files (Pip, 29 Oct 2026); rig-setup
    # moved C:\RigConfigs there and left a link at the old place.
    [string]$ConfigRoot = "C:\Coen-Lab-Local\RigConfigs"
)

$scriptPath = $MyInvocation.MyCommand.Path
$scriptDirectory = Split-Path -Parent $scriptPath
Set-Location (Split-Path -Parent $scriptDirectory)

# A failing native command does not stop a PowerShell script, so each one is checked.
function Assert-Success([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit code $LASTEXITCODE). The deploy is incomplete." }
}

Write-Output "Initializing and updating submodules..."
&git submodule update --init --recursive
Assert-Success "git submodule update"

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "The 'uv' command was not found. See https://docs.astral.sh/uv/getting-started/installation/ for instructions."
}

Write-Output "Creating a Python environment..."
if (Test-Path -Path ./.venv) {
    Remove-Item ./.venv -Recurse -Force
}
&uv venv
Assert-Success "uv venv"
.\.venv\Scripts\Activate.ps1
Write-Output "Synchronizing environment..."
&uv sync
Assert-Success "uv sync"

Write-Output "Regenerating JSON schema from pydantic models..."
&uv run regenerate-schemas
Assert-Success "Regenerating the schemas"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "The 'dotnet' command was not found. Install the .NET SDK: https://dotnet.microsoft.com/download"
}

Write-Output "Restoring dotnet tools..."
&dotnet tool restore
Assert-Success "dotnet tool restore"

# Derive C# namespace from schema filename (snake_case -> PascalCase).
$schemaFile = Get-ChildItem ".\src\DataSchemas\*.json" | Select-Object -First 1
if (-not $schemaFile) { throw "No JSON schema found in .\src\DataSchemas\. Run 'uv run regenerate-schemas' first." }
$namespace = ($schemaFile.BaseName -split "_" | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ""

if (-not (Test-Path -Path src\Extensions)) {
    New-Item -ItemType Directory -Path src\Extensions | Out-Null
}

Write-Output "Generating C# classes (namespace: $namespace, serializers: json yaml)..."
Push-Location .\src\Extensions
&dotnet bonsai.sgen $schemaFile.FullName --namespace $namespace --serializer json --serializer yaml
Pop-Location
Assert-Success "Generating the C# classes"

Write-Output "Writing the rig configuration template..."
&uv run python examples/rig.py
Assert-Success "Writing the rig configuration template"

# Same name the rig workflow resolves at startup (Environment.MachineName).
$machineDirectory = Join-Path $ConfigRoot ([Environment]::MachineName)
Write-Output "Preparing the rig configuration directory $machineDirectory..."
New-Item -ItemType Directory -Path (Join-Path $machineDirectory "calibration") -Force | Out-Null
$rigConfig = Join-Path $machineDirectory "rig.yml"
if (Test-Path -Path $rigConfig) {
    Write-Output "Keeping the existing $rigConfig"
} else {
    # The template's $schema path is relative to config\; point the copy at this checkout instead.
    $schemaDirectory = (Resolve-Path ".\src\DataSchemas").Path -replace "\\", "/"
    $text = [IO.File]::ReadAllText((Resolve-Path ".\config\rig-template.yml").Path)
    $text = $text.Replace('$schema=../src/DataSchemas/', '$schema=' + $schemaDirectory + '/')
    [IO.File]::WriteAllText($rigConfig, $text)
    Write-Output "Created $rigConfig from config\rig-template.yml; fill in this rig's values there."
}

Write-Output "Creating a Bonsai environment and installing packages..."
&.\.bonsai\Setup.cmd
Assert-Success "Installing Bonsai and its packages"

# The video is encoded by ffmpeg.exe, which Bonsai.FFmpeg starts from PATH, on Intel Quick Sync
# (h264_qsv). Without it, recording stops as soon as the first video file opens.
$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
    Write-Warning "FFmpeg was not found on PATH. Install it with: winget install --id Gyan.FFmpeg -e, then open a new window."
} else {
    & $ffmpeg.Source -v error -f lavfi -i color=black:s=320x240 -frames:v 1 -c:v h264_qsv -f null - 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Output "FFmpeg found, Intel Quick Sync encoding works."
    } else {
        Write-Warning "FFmpeg is installed, but Intel Quick Sync (h264_qsv) does not work on this machine."
    }
}
