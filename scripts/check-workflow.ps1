param(
    # Internal: the step this script runs in a fresh process of its own (assemblies stay loaded).
    [ValidateSet('', 'Build', 'RigDevice', 'Checks')][string]$Step = ''
)
# Checks a change to src\ without the rig and without opening Bonsai: no window, no device.
#   1. Compiles src\Extensions under C# 5, the language Bonsai compiles it with.
#   2. Builds src\main.bonsai with Bonsai's own expression builders, as Bonsai does at Start
#      before it subscribes anything: every type, selector, include, subject and mapping.
#   3. Runs RigDevice on config\rig-template.yml: the names the workflow asks for are found,
#      and a missing entry or a name breaking the naming rules stops it.
#   4. ExposureFitsTrigger's limit (19,000 us passes at 50 Hz, 19,001 and 30,000 stop),
#      SessionKey on a session folder's path, Watchdog's own message, and CameraOverrides'
#      refusal without a "Parameter name" line; in main.bonsai, every timeout is a Watchdog with a message.
# Needs a deployed clone (scripts\deploy.cmd: .bonsai\Packages). Exit 0 when all four pass.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$bin = Join-Path ([IO.Path]::GetTempPath()) 'coen-behaviour-box-check'
$bonsaiDir = Join-Path $repo '.bonsai'

# Assemblies from the environment's Bonsai.config, Extensions from step 1, resolved on demand.
function Initialize-Assemblies {
    [xml]$cfg = Get-Content (Join-Path $bonsaiDir 'Bonsai.config') -Raw
    $map = @{}
    foreach ($a in $cfg.PackageConfiguration.AssemblyLocations.AssemblyLocation) {
        if ($a.processorArchitecture -in 'MSIL', 'Amd64') { $map[$a.assemblyName] = Join-Path $bonsaiDir $a.location }
    }
    $map['Extensions'] = Join-Path $bin 'Extensions.dll'
    foreach ($n in 'YamlDotNet', 'Newtonsoft.Json') { $map[$n] = Join-Path $bin "$n.dll" }
    $script:resolveMap = $map; $script:resolvePkgs = Join-Path $bonsaiDir 'Packages'
    $script:resolver = [ResolveEventHandler]{
        param($s, $e)
        $n = (New-Object Reflection.AssemblyName $e.Name).Name
        $loaded = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq $n } | Select-Object -First 1
        if ($loaded) { return $loaded }
        $p = $script:resolveMap[$n]
        if (-not $p) {
            $p = Get-ChildItem $script:resolvePkgs -Recurse -Filter "$n.dll" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '\\lib\\net4' } | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
        }
        if ($p -and (Test-Path $p)) { return [Reflection.Assembly]::LoadFrom($p) }
        return $null
    }
    [AppDomain]::CurrentDomain.add_AssemblyResolve($script:resolver)
    foreach ($n in 'Bonsai.Core', 'Bonsai', 'Extensions') { $null = [Reflection.Assembly]::LoadFrom($map[$n]) }
}

if ($Step -eq 'Build') {
    Initialize-Assemblies
    $workflow = Join-Path $repo 'src\main.bonsai'
    # Every assembly the workflow's namespaces name, loaded first so the serializer finds them.
    foreach ($m in [regex]::Matches((Get-Content $workflow -Raw), 'assembly=([A-Za-z0-9\.]+)"')) {
        $null = [Reflection.Assembly]::Load($m.Groups[1].Value)
    }
    $reader = [Xml.XmlReader]::Create($workflow)
    try { $wb = [Bonsai.WorkflowBuilder]::Serializer.Deserialize($reader) } finally { $reader.Close() }
    try {
        $null = [Bonsai.Expressions.ExpressionBuilderGraphExtensions]::Build($wb.Workflow)
    } catch {
        $x = $_.Exception
        while ($x) { "  $($x.GetType().Name): $($x.Message)"; $x = $x.InnerException }
        exit 1
    }
    exit 0
}

if ($Step -eq 'RigDevice') {
    Initialize-Assemblies
    # A scriptblock resolver called from an Rx worker thread while this one waits deadlocks,
    # so everything is loaded now and the resolver removed before anything runs.
    foreach ($p in $script:resolveMap.Values) { if (Test-Path $p) { try { $null = [Reflection.Assembly]::LoadFrom($p) } catch {} } }
    [AppDomain]::CurrentDomain.remove_AssemblyResolve($script:resolver)
    $yaml = Get-Content (Join-Path $repo 'config\rig-template.yml') -Raw
    $E = [Linq.Expressions.Expression]
    $wait = [System.Reactive.Linq.Observable].GetMethods() | Where-Object { $_.Name -eq 'Wait' -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    # rig.yml text -> DeserializeFromYaml -> MemberSelector -> RigDevice, as RigConfig chains them.
    function Invoke-RigDevice([string]$Member, [string]$Name) {
        $x = $E::Constant([System.Reactive.Linq.Observable]::Return($yaml), [IObservable[string]])
        $des = New-Object UclOpenCoenBehaviourBox.DeserializeFromYaml
        $des.Type = [Activator]::CreateInstance([Bonsai.Expressions.TypeMapping`1].MakeGenericType([UclOpenCoenBehaviourBox.UclOpenCoenBehaviourBoxRig]))
        $x = $des.Build([Linq.Expressions.Expression[]]@($x))
        $sel = New-Object Bonsai.Expressions.MemberSelectorBuilder; $sel.Selector = $Member
        $x = $sel.Build([Linq.Expressions.Expression[]]@($x))
        $cb = New-Object Bonsai.Expressions.CombinatorBuilder
        $rd = New-Object UclOpenCoenBehaviourBox.RigDevice; $rd.Name = $Name; $cb.Combinator = $rd
        $x = $cb.Build([Linq.Expressions.Expression[]]@($x))
        $call = $E::Call($wait.MakeGenericMethod($x.Type.GetGenericArguments()[0]), $x)
        return $E::Lambda($E::Convert($call, [object])).Compile().DynamicInvoke()
    }
    $failed = 0
    # The names main.bonsai asks for, from its RigDevice nodes, each with the group it reads.
    $asked = [regex]::Matches((Get-Content (Join-Path $repo 'src\main.bonsai') -Raw),
        '<Selector>(\w+)</Selector>\s*</Expression>\s*<Expression xsi:type="Combinator">\s*<Combinator xsi:type="ext:RigDevice">\s*<ext:Name>([^<]*)</ext:Name>')
    if ($asked.Count -eq 0) { "  FAIL  found no RigDevice in main.bonsai"; $failed++ }
    foreach ($m in $asked) {
        $member = $m.Groups[1].Value; $name = $m.Groups[2].Value
        try {
            $r = Invoke-RigDevice $member $name
            if ($r.Name -ne $name) { throw "came back named '$($r.Name)'" }
            "  ok    $name is in the template"
        } catch { $x = $_.Exception; while ($x.InnerException) { $x = $x.InnerException }; "  FAIL  ${name}: $($x.Message)"; $failed++ }
    }
    # Each must stop the workflow, with the exception and the words that say why.
    $refused = @(
        @('Camera', 'Camera-Face', 'KeyNotFoundException', 'Its camera entries: box.'),
        @('Camera', 'Camera-box', 'ArgumentException', 'starting with a capital'),
        @('Camera', 'Camera-Box_2', 'ArgumentException', 'only letters and digits'),
        @('Camera', 'CameraBox', 'ArgumentException', 'Kind-Instance')
    )
    foreach ($c in $refused) {
        try { $null = Invoke-RigDevice $c[0] $c[1]; "  FAIL  $($c[1]) was accepted"; $failed++ }
        catch {
            $x = $_.Exception; while ($x.InnerException) { $x = $x.InnerException }
            if ($x.GetType().Name -eq $c[2] -and $x.Message.Contains($c[3])) { "  ok    $($c[1]) refused: $($x.Message)" }
            else { "  FAIL  $($c[1]): $($x.GetType().Name): $($x.Message)"; $failed++ }
        }
    }
    exit $(if ($failed) { 1 } else { 0 })
}

if ($Step -eq 'Checks') {
    Initialize-Assemblies
    $failed = 0
    function Get-Refusal([scriptblock]$Run) {
        try { & $Run; return $null } catch { $x = $_.Exception; while ($x.InnerException) { $x = $x.InnerException }; return $x }
    }
    # Exposure at 50 Hz with the workflow's 1000 us margin: 19,000 ran at the full rate on GEEK-BBOX1
    # (30 Oct 2026); 30,000 ran at 25 fps with every frame mistimed.
    foreach ($c in @(@(19000, $true), @(10000, $true), @(19001, $false), @(30000, $false))) {
        $x = Get-Refusal { [UclOpenCoenBehaviourBox.ExposureFitsTrigger]::Check('Camera-Box', $c[0], 50, 1000) }
        if ($c[1] -and $x) { "  FAIL  ExposureTime $($c[0]) refused: $($x.Message)"; $failed++ }
        elseif (-not $c[1] -and -not $x) { "  FAIL  ExposureTime $($c[0]) accepted at 50 Hz"; $failed++ }
        elseif (-not $c[1] -and -not $x.Message.Contains('to 19000 or less')) { "  FAIL  ExposureTime $($c[0]): $($x.Message)"; $failed++ }
        elseif ($c[1]) { "  ok    ExposureTime $($c[0]) fits 50 Hz" }
        else { "  ok    ExposureTime $($c[0]) refused: $($x.Message)" }
    }
    $key = [UclOpenCoenBehaviourBox.SessionKey]::FromPathPrefix('C:\Data\sub-M1\ses-01_date-2026-10-30T17-46-16')
    if ($key -eq 'sub-M1/ses-01_date-2026-10-30T17-46-16') { "  ok    SessionKey $key" } else { "  FAIL  SessionKey gave '$key'"; $failed++ }
    $x = Get-Refusal { [UclOpenCoenBehaviourBox.SessionKey]::FromPathPrefix('C:\Data\not-a-session') }
    if ($x -and $x.Message.Contains('does not end in sub-')) { "  ok    SessionKey refused a path that is not a session folder" } else { "  FAIL  SessionKey accepted 'C:\Data\not-a-session'"; $failed++ }
    $x = Get-Refusal { [UclOpenCoenBehaviourBox.SessionKey]::FromPathPrefix('C:\Data\sub-M1\ses-03/1_date-2026-10-30T17-46-16') }
    if ($x -and $x.Message.Contains('in SubjectId or SessionId')) { "  ok    SessionKey refused a SessionId with a slash, naming the cause" } else { "  FAIL  SessionKey on a SessionId with a slash: $(if ($x) { $x.Message } else { 'accepted' })"; $failed++ }

    # The Rx operators below run on worker threads: load everything now and drop the resolver,
    # as the RigDevice step does, so no scriptblock is called from those threads.
    foreach ($p in $script:resolveMap.Values) { if (Test-Path $p) { try { $null = [Reflection.Assembly]::LoadFrom($p) } catch {} } }
    [AppDomain]::CurrentDomain.remove_AssemblyResolve($script:resolver)
    $rx = [System.Reactive.Linq.Observable]
    $wait = $rx.GetMethods() | Where-Object { $_.Name -eq 'Wait' -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    $return = $rx.GetMethods() | Where-Object { $_.Name -eq 'Return' -and $_.GetParameters().Count -eq 1 } | Select-Object -First 1
    $never = $rx.GetMethods() | Where-Object { $_.Name -eq 'Never' -and $_.GetParameters().Count -eq 0 } | Select-Object -First 1
    function Invoke-Process($Operator, [type]$Type, $Source) {
        $out = $Operator.GetType().GetMethods() | Where-Object { $_.Name -eq 'Process' } | Select-Object -First 1
        if ($out.IsGenericMethodDefinition) { $out = $out.MakeGenericMethod($Type) }
        $wait.MakeGenericMethod($out.ReturnType.GetGenericArguments()[0]).Invoke($null, @(, $out.Invoke($Operator, @(, $Source))))
    }
    # Watchdog: silent past DueTime -> its own message; a value in time passes.
    $dog = New-Object UclOpenCoenBehaviourBox.Watchdog
    $dog.DueTime = [TimeSpan]::FromSeconds(0.2); $dog.Message = 'The board did not confirm its clock.'
    $x = Get-Refusal { Invoke-Process $dog ([int]) ($never.MakeGenericMethod([int]).Invoke($null, @())) }
    if ($x -is [TimeoutException] -and $x.Message -eq $dog.Message) { "  ok    Watchdog stopped with its own message" } else { "  FAIL  Watchdog on silence: $(if ($x) { $x.Message } else { 'no error' })"; $failed++ }
    $x = Get-Refusal { $null = Invoke-Process $dog ([int]) ($return.MakeGenericMethod([int]).Invoke($null, @(, 1))) }
    if (-not $x) { "  ok    Watchdog passed a value that came in time" } else { "  FAIL  Watchdog refused a value in time: $($x.Message)"; $failed++ }
    # CameraOverrides: a refusal reads as one message, with no "Parameter name" line.
    $over = New-Object UclOpenCoenBehaviourBox.CameraOverrides
    $over.ExposureTime = -1
    $camera = New-Object 'UclOpenCoenBehaviourBox.NamedDevice[UclOpenCoenBehaviourBox.SpinnakerCamera]' 'Camera-Box', (New-Object UclOpenCoenBehaviourBox.SpinnakerCamera)
    $x = Get-Refusal { $null = Invoke-Process $over $null ($return.MakeGenericMethod($camera.GetType()).Invoke($null, @(, $camera.PSObject.BaseObject))) }
    if ($x -and $x.Message.Contains('must be above 0') -and -not $x.Message.Contains('Parameter name')) { "  ok    CameraOverrides refused ExposureTime -1 in one message" } else { "  FAIL  CameraOverrides on ExposureTime -1: $(if ($x) { $x.Message } else { 'accepted' })"; $failed++ }
    $text = [IO.File]::ReadAllText((Join-Path $repo 'src\main.bonsai'))
    # Every timeout in the workflow says what did not arrive: Watchdog with a message, never a bare Timeout.
    $dogs = [regex]::Matches($text, 'xsi:type="ext:Watchdog">\s*<ext:DueTime>[^<]+</ext:DueTime>\s*<ext:Message>[^<]+</ext:Message>').Count
    $bare = [regex]::Matches($text, 'xsi:type="rx:Timeout"').Count
    if ($bare -eq 0 -and $dogs -eq [regex]::Matches($text, 'xsi:type="ext:Watchdog"').Count) { "  ok    $dogs Watchdog(s), each with a message; no bare Timeout" }
    else { "  FAIL  $bare bare rx:Timeout, or a Watchdog without a message"; $failed++ }
    exit $(if ($failed) { 1 } else { 0 })
}

if (-not (Test-Path (Join-Path $bonsaiDir 'Packages'))) { throw "No .bonsai\Packages in $repo. Run scripts\deploy.cmd first." }
$bad = 0
"1. Compiling src\Extensions as C# 5..."
Remove-Item $bin -Recurse -Force -ErrorAction SilentlyContinue
$log = & dotnet build (Join-Path $repo 'src\Extensions.csproj') -o $bin -nologo -v q `
    --source https://api.nuget.org/v3/index.json --source (Join-Path $repo 'local_packages') 2>&1
if ($LASTEXITCODE -ne 0) { $log | Where-Object { "$_" -match 'error' } | Select-Object -Unique | ForEach-Object { "  $_" }; "  FAILED"; exit 1 }
"  ok"
"2. Building src\main.bonsai with Bonsai's builders..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path -Step Build
if ($LASTEXITCODE -ne 0) { "  FAILED"; $bad++ } else { "  ok" }
"3. RigDevice on config\rig-template.yml..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path -Step RigDevice
if ($LASTEXITCODE -ne 0) { "  FAILED"; $bad++ }
"4. ExposureFitsTrigger, SessionKey, Watchdog and CameraOverrides..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path -Step Checks
if ($LASTEXITCODE -ne 0) { "  FAILED"; $bad++ }
if ($bad) { "check-workflow: $bad of 4 steps failed."; exit 1 }
"check-workflow: all 4 steps passed."
