param(
    # Internal: the step this script runs in a fresh process of its own (assemblies stay loaded).
    [ValidateSet('', 'Build', 'RigDevice', 'Checks')][string]$Step = ''
)
# Checks a change to src\ without the rig and without opening Bonsai: no window, no device.
#   1. Compiles src\Extensions under C# 5, the language Bonsai compiles it with.
#   2. Builds src\main.bonsai with Bonsai's own expression builders, as Bonsai does at Start
#      before it subscribes anything: every type, selector, include, subject and mapping. It
#      checks that every node typed with where rig.yml is has the same root, then builds against
#      the template filled in as a rig's, and checks what RecordHarpDevices made from it and what
#      ExperimentManifest expects, and that each window in config\main.layout is on a node it fits.
#   3. Runs RigDevice on config\rig-template.yml: the names the workflow asks for are found,
#      and a missing entry or a name breaking the naming rules stops it; and every key in it
#      reaches the Settings_Rig JSON the experiment logs.
#   4. ExposureFitsTrigger's limit (19,000 us passes at 50 Hz, 19,001 and 30,000 stop),
#      SessionKey on an experiment folder's path, no dump or register map of the workflow's own, Watchdog's own message, and CameraOverrides'
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
    # The nodes that read rig.yml when the workflow is built (RecordHarpDevices, StreamDevices,
    # ExperimentManifest) read a copy of the template with its placeholders filled, as a rig's, so
    # the build makes what it makes on a rig: this machine need not have a rig.yml.
    $rigDir = Join-Path $bin "config\$([Environment]::MachineName)"
    $null = New-Item -ItemType Directory -Path $rigDir -Force
    $rigYml = Join-Path $rigDir 'rig.yml'
    $template = [IO.File]::ReadAllText((Join-Path $repo 'config\rig-template.yml'))
    $template = $template.Replace('COM-CHANGE-ME', 'COM3').Replace('usbSerial: CHANGE-ME', 'usbSerial: AB0M7PLB').Replace('rigId: CHANGE-ME', 'rigId: B1').Replace('serialNumber: CHANGE-ME', "serialNumber: '1'").Replace('rootPath: C:\Coen-Lab-Local\Acquired-Data', "rootPath: $bin")
    # Never the real recordings folder: a template rootPath this no longer matches fails here.
    if (-not $template.Contains("rootPath: $bin")) { throw "check-workflow: config\rig-template.yml's rootPath is not C:\Coen-Lab-Local\Acquired-Data; update the Replace above." }
    [IO.File]::WriteAllText($rigYml, $template)
    # Before they are overwritten below: every node's own copy of where rig.yml is (RigConfig's
    # ResolveRigConfigDirectory, RecordHarpDevices, ExperimentManifest's ConfigFiles, LiveView) is
    # typed by hand into main.bonsai, and they must all be the same root.
    function Get-ConfigRoots($graph) {
        foreach ($n in $graph) {
            $b = [Bonsai.Expressions.ExpressionBuilder]::Unwrap($n.Value)
            $owner = if ($b -is [Bonsai.Expressions.CombinatorBuilder]) { $b.Combinator } else { $b }
            if ($owner -and $owner.GetType().Namespace -like 'OpenRigs.*' -and $owner.PSObject.Properties['ConfigRoot']) { "$($owner.GetType().Name)=$($owner.ConfigRoot)" }
            if ($b.GetType().Name -eq 'ExperimentManifest') {
                foreach ($file in $b.ConfigFiles -split ';') { if ($file -match '^(.*)\\%COMPUTERNAME%\\rig\.yml$') { "ExperimentManifest.ConfigFiles=$($Matches[1])" } }
            }
            if ($b -is [Bonsai.Expressions.IWorkflowExpressionBuilder] -and $b.Workflow) { Get-ConfigRoots $b.Workflow }
        }
    }
    $roots = @(Get-ConfigRoots $wb.Workflow)
    $distinct = @($roots | ForEach-Object { ($_ -split '=', 2)[1].TrimEnd('\') } | Sort-Object -Unique)
    $rootsOk = $roots.Count -ge 4 -and $distinct.Count -eq 1
    if ($rootsOk) { "  ok    every node reads rig.yml under the same root, $($distinct[0]) ($($roots.Count) nodes)" }
    else { "  FAIL  the nodes' rig.yml roots differ, or fewer than 4 were found: $($roots -join '; ')" }
    # ConfigRoot set as Bonsai's launcher sets --property:ConfigRoot: one workflow property, mapped
    # to every node that reads rig.yml by root (RigConfig, RecordHarpDevices, LiveView; HarpDevices
    # 0.1.0-local.5 and LiveView local.8 let it, 3 Nov 2026), so a node it misses reads the
    # machine's own rig.yml and fails here. ExperimentManifest's ConfigFiles names rig.yml's own path
    # and is set by hand.
    [Bonsai.Expressions.ExpressionBuilderGraphExtensions]::SetWorkflowProperty($wb.Workflow, 'ConfigRoot', (Join-Path $bin 'config'))
    $stayed = @(Get-ConfigRoots $wb.Workflow | Where-Object { $_ -notlike 'ExperimentManifest.*' -and ($_ -split '=', 2)[1] -ne (Join-Path $bin 'config') })
    if ($stayed.Count) { "  FAIL  --property:ConfigRoot did not reach $($stayed -join '; ')"; $rootsOk = $false }
    else { "  ok    --property:ConfigRoot reaches every node that reads rig.yml by root" }
    function Set-ConfigFiles($graph) {
        foreach ($n in $graph) {
            $b = [Bonsai.Expressions.ExpressionBuilder]::Unwrap($n.Value)
            if ($b.GetType().Name -eq 'ExperimentManifest') { $b.ConfigFiles = $rigYml }
            if ($b -is [Bonsai.Expressions.IWorkflowExpressionBuilder] -and $b.Workflow) { Set-ConfigFiles $b.Workflow }
        }
    }
    Set-ConfigFiles $wb.Workflow
    try {
        $built = [Bonsai.Expressions.ExpressionBuilderGraphExtensions]::Build($wb.Workflow)
    } catch {
        $x = $_.Exception
        while ($x) { "  $($x.GetType().Name): $($x.Message)"; $x = $x.InnerException }
        exit 1
    }
    # What the build made, read from the objects in the built expression: RecordHarpDevices'
    # record and dump request for the board, and ExperimentManifest's expected files (harp: the
    # board's record and register map).
    Add-Type -ReferencedAssemblies System.Core -TypeDefinition @'
public class BuiltObjects : System.Linq.Expressions.ExpressionVisitor {
    public System.Collections.Generic.List<object> Found = new System.Collections.Generic.List<object>();
    protected override System.Linq.Expressions.Expression VisitConstant(System.Linq.Expressions.ConstantExpression node) {
        if (node.Value != null) Found.Add(node.Value);
        return base.VisitConstant(node);
    }
}
'@
    $objects = New-Object BuiltObjects
    $null = $objects.Visit($built)
    $failed = if ($rootsOk) { 0 } else { 1 }
    $record = @($objects.Found | Where-Object { $_.GetType().FullName -eq 'OpenRigs.HarpDevices.RecordHarpDevice' })
    if ($record.Count -eq 1 -and $record[0].Name -eq 'BehaviorBoard-Main' -and $record[0].PortName -eq 'COM3' -and $record[0].UsbSerial -eq 'AB0M7PLB' -and $record[0].ExpectedWhoAmI -eq 1216) {
        "  ok    RecordHarpDevices records BehaviorBoard-Main from rig.yml (COM3, usbSerial AB0M7PLB, WhoAmI 1216)"
    } else { "  FAIL  RecordHarpDevices made $($record.Count) record(s): $(@($record | ForEach-Object { $_.Name }) -join ', ')"; $failed++ }
    $dumps = @($objects.Found | Where-Object { $_.GetType().FullName -eq 'OpenRigs.HarpDevices.RequestRegisterDump' }).Count
    if ($dumps -eq 1) { "  ok    ... and asks for its dump on BehaviorBoard-Main.Commands" } else { "  FAIL  $dumps dump request(s): is the board's command subject BehaviorBoard-Main.Commands?"; $failed++ }
    $recorder = @($objects.Found | Where-Object { $_.GetType().Name -eq 'ManifestRecorder' })
    $planField = if ($recorder.Count) { $recorder[0].GetType().GetFields([Reflection.BindingFlags]'Instance,NonPublic,Public') | Where-Object { $_.FieldType.Name -eq 'ExpectedPlan' } | Select-Object -First 1 }
    $expected = if ($planField) { @($planField.GetValue($recorder[0]).Entries | ForEach-Object { $_.Path }) } else { @() }
    $want = 'BehaviorBoard-Main/', 'Camera-Overhead/', 'BehaviorBoard-Main/BehaviorBoard-Main_device.json', 'BehaviorBoard-Main/BehaviorBoard-Main.yml', 'Settings/Settings_Rig_', 'Settings/Settings_Experiment_'
    if (($expected -join ', ') -eq ($want -join ', ')) { "  ok    ExperimentManifest expects $($expected -join ', ')" }
    else {
        "  FAIL  ExperimentManifest expects '$($expected -join ', ')', not '$($want -join ', ')'"; $failed++
        if ($planField) { foreach ($note in $planField.GetValue($recorder[0]).Notes) { "        its note: $note" } }
    }
    # config\main.layout's windows, on the nodes as the editor has them: Bonsai loads each group
    # in topological order, not file order, so a node fed from later in the file moves up and
    # shifts the indices after it (3096c9f moved the preview's SampleInterval from 14 to 28). A
    # window on the wrong node makes the editor offer to delete the layout, and --start waits.
    $inspectable = [Bonsai.Expressions.ExpressionBuilderGraphExtensions]::ToInspectableGraph($wb.Workflow)
    $null = [Bonsai.Expressions.ExpressionBuilderGraphExtensions]::Build($inspectable)
    $wanted = @{ 'Bonsai.Vision.Design.IplImageVisualizer' = 'OpenCV.Net.IplImage'; 'Bonsai.Design.ObjectTextVisualizer' = '' }
    function Test-Layout($settings, $graph, $where) {
        $nodes = @($graph)
        foreach ($window in $settings.WindowSettings) {
            $i = [int]$window.Index
            if ($i -ge $nodes.Count) { "  FAIL  layout $where$i`: the workflow has $($nodes.Count) nodes there"; continue }
            $node = $nodes[$i].Value
            $at = "$where$i ($($node.Builder.GetType().Name))"
            if ($window.NestedLayout) {
                if ($node.Builder -is [Bonsai.Expressions.IWorkflowExpressionBuilder]) { Test-Layout $window.NestedLayout $node.Builder.Workflow "$at > " }
                else { "  FAIL  layout $at holds windows but is not a group" }
            }
            if ($window.VisualizerTypeName) {
                $type = $wanted[$window.VisualizerTypeName]
                if ($null -eq $type) { "  FAIL  layout $at`: $($window.VisualizerTypeName) is not one this check knows" }
                elseif ($type -and "$($node.ObservableType)" -ne $type) { "  FAIL  layout $at`: $($window.VisualizerTypeName) on a node of $($node.ObservableType), not $type" }
                else { "  ok    layout window $($window.VisualizerTypeName) on $at" }
            }
        }
    }
    [xml]$layout = Get-Content (Join-Path $repo 'config\main.layout') -Raw
    $layoutLines = @(Test-Layout $layout.VisualizerLayout $inspectable '')
    $layoutLines
    $failed += @($layoutLines | Where-Object { $_ -like '  FAIL*' }).Count
    exit $(if ($failed) { 1 } else { 0 })
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
        $des.Type = [Activator]::CreateInstance([Bonsai.Expressions.TypeMapping`1].MakeGenericType([UclOpenCoenBehaviourBox.BehaviourBoxRig]))
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
        @('Camera', 'Camera-Face', 'KeyNotFoundException', 'Its camera entries: overhead.'),
        @('Camera', 'Camera-overhead', 'ArgumentException', 'starting with a capital'),
        @('Camera', 'Camera-Overhead_2', 'ArgumentException', 'only letters and digits'),
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
    # The experiment's Settings_Rig JSON is rig.yml as parsed, and the manifest keeps only rig.yml's hash
    # (OpenRigs.Manifest 0.1.0-local.7), so every key in rig.yml must reach the JSON.
    try {
        $x = $E::Constant([System.Reactive.Linq.Observable]::Return($yaml), [IObservable[string]])
        $des = New-Object UclOpenCoenBehaviourBox.DeserializeFromYaml
        $des.Type = [Activator]::CreateInstance([Bonsai.Expressions.TypeMapping`1].MakeGenericType([UclOpenCoenBehaviourBox.BehaviourBoxRig]))
        $x = $des.Build([Linq.Expressions.Expression[]]@($x))
        $cb = New-Object Bonsai.Expressions.CombinatorBuilder
        $ser = New-Object UclOpenCoenBehaviourBox.SerializeToJson; $ser.Formatting = 'Indented'; $cb.Combinator = $ser
        $x = $cb.Build([Linq.Expressions.Expression[]]@($x))
        $json = $E::Lambda($E::Call($wait.MakeGenericMethod([string]), $x)).Compile().DynamicInvoke()
        # A foreach statement, not a pipeline: a pipeline unrolls each JObject into its properties.
        $jsonKeys = New-Object System.Collections.Generic.List[string]
        foreach ($t in [Newtonsoft.Json.Linq.JToken]::Parse($json).Descendants()) {
            if ($t -is [Newtonsoft.Json.Linq.JProperty]) { $jsonKeys.Add(($t.Path -replace '\[\d+\]', '[]')) }
        }
        $yamlKeys = New-Object System.Collections.Generic.List[string]
        function Add-YamlKeys($node, [string]$at) {
            if ($node -is [System.Collections.IDictionary]) { foreach ($k in $node.Keys) { $p = if ($at) { "$at.$k" } else { "$k" }; $yamlKeys.Add($p); Add-YamlKeys $node[$k] $p } }
            elseif ($node -is [System.Collections.IList]) { foreach ($i in $node) { Add-YamlKeys $i "$at[]" } }
        }
        Add-YamlKeys ((New-Object YamlDotNet.Serialization.Deserializer).Deserialize((New-Object IO.StringReader $yaml))) ''
        $lost = @($yamlKeys | Where-Object { $jsonKeys -notcontains $_ })
        if ($yamlKeys.Count -gt 0 -and $lost.Count -eq 0) { "  ok    Settings_Rig JSON keeps all $($yamlKeys.Count) keys of rig-template.yml" }
        else { "  FAIL  Settings_Rig JSON lost $($lost.Count) of $($yamlKeys.Count) keys of rig-template.yml: $($lost -join ', ')"; $failed++ }
    } catch { $x = $_.Exception; while ($x.InnerException) { $x = $x.InnerException }; "  FAIL  Settings_Rig JSON: $($x.Message)"; $failed++ }
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
        $x = Get-Refusal { [UclOpenCoenBehaviourBox.ExposureFitsTrigger]::Check('Camera-Overhead', $c[0], 50, 1000) }
        if ($c[1] -and $x) { "  FAIL  ExposureTime $($c[0]) refused: $($x.Message)"; $failed++ }
        elseif (-not $c[1] -and -not $x) { "  FAIL  ExposureTime $($c[0]) accepted at 50 Hz"; $failed++ }
        elseif (-not $c[1] -and -not $x.Message.Contains('to 19000 or less')) { "  FAIL  ExposureTime $($c[0]): $($x.Message)"; $failed++ }
        elseif ($c[1]) { "  ok    ExposureTime $($c[0]) fits 50 Hz" }
        else { "  ok    ExposureTime $($c[0]) refused: $($x.Message)" }
    }
    $key = [UclOpenCoenBehaviourBox.SessionKey]::FromPathPrefix('C:\Data\sub-M1\ses-01_date-2026-10-30T17-46-16')
    if ($key -eq 'sub-M1/ses-01_date-2026-10-30T17-46-16') { "  ok    SessionKey $key" } else { "  FAIL  SessionKey gave '$key'"; $failed++ }
    $x = Get-Refusal { [UclOpenCoenBehaviourBox.SessionKey]::FromPathPrefix('C:\Data\not-an-experiment') }
    if ($x -and $x.Message.Contains('does not end in sub-')) { "  ok    SessionKey refused a path that is not an experiment folder" } else { "  FAIL  SessionKey accepted 'C:\Data\not-an-experiment'"; $failed++ }
    $x = Get-Refusal { [UclOpenCoenBehaviourBox.SessionKey]::FromPathPrefix('C:\Data\sub-M1\ses-03/1_date-2026-10-30T17-46-16') }
    if ($x -and $x.Message.Contains('in SubjectId or SessionId')) { "  ok    SessionKey refused a SessionId with a slash, naming the cause" } else { "  FAIL  SessionKey on a SessionId with a slash: $(if ($x) { $x.Message } else { 'accepted' })"; $failed++ }
    $experiment = Join-Path ([IO.Path]::GetTempPath()) ("hds-" + [guid]::NewGuid().ToString('N'))
    try {
        # The board's dump and register map come from RecordHarpDevices (OpenRigs.HarpDevices), from
        # rig.yml: nothing in the workflow asks the board for its dump or names its register map itself.
        $wf = Get-Content (Join-Path $repo 'src\main.bonsai') -Raw
        if ($wf -match 'DumpRegisters>true</harp:DumpRegisters>\s*<harp:MuteReplies' -or $wf -match 'ext:HarpDeviceSchema' -or $wf -match '>BehaviorCommands<') {
            "  FAIL  main.bonsai still asks for the board's dump, writes its register map, or names its commands BehaviorCommands, itself"; $failed++
        } else { "  ok    main.bonsai leaves the board's dump and register map to RecordHarpDevices" }
        $json =[UclOpenCoenBehaviourBox.SessionJson]::Write($experiment, 'Settings_Rig', '{"a":1}', [datetime]::SpecifyKind([datetime]'2026-11-02T09:05:07', 'Utc'))
        if ($json -eq (Join-Path $experiment 'Settings\Settings_Rig_2026-11-02T09-05-07.json') -and [IO.File]::ReadAllText($json) -eq '{"a":1}' -and -not (Test-Path "$json.tmp")) {
            "  ok    SessionJson wrote Settings\Settings_Rig_<DateTime>.json under the experiment folder it was given"
        } else { "  FAIL  SessionJson wrote '$json'"; $failed++ }
        # LogDataSchema in OpenRigs.Logging 0.1.0-bbox.1 reads its file name before the experiment folder exists.
        if ((Get-Content (Join-Path $repo 'src\main.bonsai') -Raw) -match 'LogDataSchema\.bonsai') { "  FAIL  main.bonsai uses LogDataSchema, which writes to the include's saved path in this build"; $failed++ }
        else { "  ok    main.bonsai does not use LogDataSchema" }
    } finally { Remove-Item $experiment -Recurse -Force -ErrorAction SilentlyContinue }

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
    $over.Binning = 0
    $camera = New-Object 'UclOpenCoenBehaviourBox.NamedDevice[UclOpenCoenBehaviourBox.SpinnakerCamera]' 'Camera-Overhead', (New-Object UclOpenCoenBehaviourBox.SpinnakerCamera)
    $x = Get-Refusal { $null = Invoke-Process $over $null ($return.MakeGenericMethod($camera.GetType()).Invoke($null, @(, $camera.PSObject.BaseObject))) }
    if ($x -and $x.Message.Contains('must be 1 or more') -and -not $x.Message.Contains('Parameter name')) { "  ok    CameraOverrides refused Binning 0 in one message" } else { "  FAIL  CameraOverrides on Binning 0: $(if ($x) { $x.Message } else { 'accepted' })"; $failed++ }
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
