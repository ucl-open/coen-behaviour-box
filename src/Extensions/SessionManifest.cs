using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reactive.Disposables;
using System.Reactive.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Bonsai;

// The session manifest node. Copy this one file into a workflow's Extensions folder.
// Spec and tests: https://github.com/Coen-Lab/session-manifest (SPEC.md).
//
// Written in C# 5: Bonsai compiles an Extensions folder with the .NET Framework's own
// compiler, so no string interpolation, no nameof, no ?. and no expression-bodied members.
namespace CoenLab.SessionManifest
{
    /// <summary>
    /// Writes manifest.json into the session folder: once when the folder exists (status partial,
    /// run.outcome running) and again when the run ends (completed, stopped or error), listing the
    /// rig, the session, the workflow's git commit, how the run ended and every file in the folder.
    /// The first input is the session folder's path (LogController's PathPrefix); the second is the
    /// run: a sequence whose completion means the run finished (the frames written, say), whose
    /// error is the run's failure, and whose elements are counted as run.items. The output is the
    /// manifest's path, once, when it is first written. The overnight copy (rig-setup's rig-sync)
    /// finishes the manifest with sizes and hashes before the session goes to the server.
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Sink)]
    [Description("Writes manifest.json into the session folder (first input: its path) when it exists and again when the run (second input) completes, stops or fails: rig, session, workflow commit, outcome and every file.")]
    public class WriteSessionManifest
    {
        public WriteSessionManifest()
        {
            RigConfigPath = @"C:\Coen-Lab-Local\RigConfigs\%COMPUTERNAME%\rig.yml";
        }

        [Description("The name of the server's ingest script for this kind of data, as the server's registry has it. Blank: the server runs nothing but the copy.")]
        public string IngestScript { get; set; }

        [Description("The rig configuration file the workflow ran with, copied into the manifest. Environment variables are expanded. Blank, or a file that does not exist: no rig configuration is recorded.")]
        public string RigConfigPath { get; set; }

        public IObservable<string> Process<TRun>(IObservable<string> sessionPath, IObservable<TRun> run)
        {
            var ingestScript = IngestScript;
            var rigConfigPath = RigConfigPath;
            return Observable.Create<string>(observer =>
            {
                var gate = new object();
                var writer = new SessionManifestWriter(ingestScript, rigConfigPath);
                var items = 0L;
                // What the run has done so far, kept until the folder's path arrives: the run may
                // end before LogController has made the folder, and the manifest must still say so.
                string pendingOutcome = null;
                string pendingError = null;
                var begun = false;
                var finished = false;
                var subscriptions = new CompositeDisposable();

                Action<string, string> finish = (outcome, error) =>
                {
                    lock (gate)
                    {
                        if (finished) return;
                        if (!begun) { pendingOutcome = outcome; pendingError = error; return; }
                        finished = true;
                        writer.Finish(outcome, error, items);
                    }
                };

                subscriptions.Add(sessionPath.Take(1).Subscribe(path =>
                {
                    string manifestPath;
                    lock (gate)
                    {
                        if (begun) return;
                        begun = true;
                        manifestPath = writer.Begin(path);
                        if (pendingOutcome != null)
                        {
                            finished = true;
                            writer.Finish(pendingOutcome, pendingError, items);
                        }
                    }
                    observer.OnNext(manifestPath);
                    if (pendingOutcome != null)
                    {
                        if (pendingOutcome == "error") observer.OnError(new SessionManifestException(pendingError));
                        else observer.OnCompleted();
                    }
                }, observer.OnError));

                subscriptions.Add(run.Subscribe(
                    _ => { lock (gate) { items++; } },
                    error =>
                    {
                        finish("error", error.Message);
                        lock (gate) { if (!begun) return; }
                        observer.OnError(error);
                    },
                    () =>
                    {
                        finish("completed", null);
                        lock (gate) { if (!begun) return; }
                        observer.OnCompleted();
                    }));

                // Disposed before the run ended: the workflow was stopped.
                subscriptions.Add(Disposable.Create(() =>
                {
                    try { finish("stopped", null); }
                    catch (Exception ex) { Trace.TraceError("WriteSessionManifest: the final manifest was not written: " + ex.Message); }
                }));
                return subscriptions;
            });
        }
    }

    /// <summary>The error carried into the manifest when the run failed before the folder existed.</summary>
    public class SessionManifestException : Exception
    {
        public SessionManifestException(string message) : base(message) { }
    }

    /// <summary>
    /// The manifest's contents and the two writes, with no Rx, so a test can drive it on a temp folder.
    /// </summary>
    public class SessionManifestWriter
    {
        public const string FileName = "manifest.json";
        public const int Version = 1;

        readonly string ingestScript;
        readonly string rigConfigPath;
        string folder;
        string manifestPath;
        DateTime started;

        public SessionManifestWriter(string ingestScript, string rigConfigPath)
        {
            this.ingestScript = ingestScript;
            this.rigConfigPath = rigConfigPath;
        }

        public string ManifestPath { get { return manifestPath; } }

        /// <summary>The first write, status partial and run.outcome running. Throws if the folder does not exist or the file cannot be written: nothing recorded is the thing to stop for.</summary>
        public string Begin(string sessionFolder)
        {
            if (string.IsNullOrEmpty(sessionFolder)) throw new ArgumentException("WriteSessionManifest was given no session folder.");
            folder = Path.GetFullPath(sessionFolder.TrimEnd('\\', '/'));
            if (!Directory.Exists(folder))
            {
                throw new DirectoryNotFoundException(string.Format(
                    "WriteSessionManifest: the session folder '{0}' does not exist, so no manifest can be written there.", folder));
            }
            manifestPath = Path.Combine(folder, FileName);
            started = DateTime.UtcNow;
            Write("running", null, 0, started, null);
            return manifestPath;
        }

        /// <summary>The second write, with the outcome. Called once; a Begin that never happened writes nothing.</summary>
        public void Finish(string outcome, string error, long items)
        {
            if (folder == null) return;
            var ended = DateTime.UtcNow;
            Write(outcome, error, items, started, ended);
        }

        void Write(string outcome, string error, long items, DateTime runStarted, DateTime? runEnded)
        {
            var doc = new JsonObject();
            doc.Add("version", (long)Version);
            doc.Add("created", Iso(DateTime.UtcNow));
            doc.Add("status", "partial");
            if (!string.IsNullOrEmpty(ingestScript)) doc.Add("ingest_script", ingestScript);
            doc.Add("rig", RigSection(rigConfigPath));
            doc.Add("session", SessionSection(folder));
            doc.Add("source", SourceSection(Environment.CurrentDirectory));
            var run = new JsonObject();
            run.Add("outcome", outcome);
            run.Add("started", Iso(runStarted));
            run.Add("ended", runEnded.HasValue ? Iso(runEnded.Value) : null);
            run.Add("seconds", runEnded.HasValue ? (object)Math.Round((runEnded.Value - runStarted).TotalSeconds, 1) : null);
            run.Add("items", items);
            run.Add("error", error);
            doc.Add("run", run);
            doc.Add("files", FilesSection(folder));
            WriteAtomically(manifestPath, Json.Serialize(doc));
        }

        /// <summary>manifest.json.tmp, then the rename, so no reader sees half a file.</summary>
        public static void WriteAtomically(string path, string text)
        {
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, text, new UTF8Encoding(false));
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }

        public static JsonObject RigSection(string configPath)
        {
            var rig = new JsonObject();
            rig.Add("machine", Environment.MachineName);
            rig.Add("user", Environment.UserName);
            rig.Add("os", Environment.OSVersion.VersionString);
            var expanded = string.IsNullOrEmpty(configPath) ? null : Environment.ExpandEnvironmentVariables(configPath);
            if (expanded != null && File.Exists(expanded))
            {
                var bytes = File.ReadAllBytes(expanded);
                rig.Add("config_path", Path.GetFullPath(expanded));
                rig.Add("config_sha256", Sha256Hex(bytes));
                rig.Add("config_text", Encoding.UTF8.GetString(bytes));
            }
            return rig;
        }

        static readonly Regex SessionName = new Regex(@"^ses-(?<id>.+?)_(?:date-)?(?<dt>\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})$", RegexOptions.CultureInvariant);

        public static JsonObject SessionSection(string sessionFolder)
        {
            var session = new JsonObject();
            var name = Path.GetFileName(sessionFolder);
            var parent = Path.GetFileName(Path.GetDirectoryName(sessionFolder) ?? string.Empty);
            session.Add("subject", parent.StartsWith("sub-", StringComparison.Ordinal) ? parent.Substring(4) : null);
            var m = SessionName.Match(name);
            session.Add("id", m.Success ? m.Groups["id"].Value : null);
            string started = null;
            if (m.Success)
            {
                DateTime dt;
                if (DateTime.TryParseExact(m.Groups["dt"].Value, "yyyy-MM-dd'T'HH-mm-ss", CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out dt))
                {
                    started = Iso(dt);
                }
            }
            session.Add("started", started);
            session.Add("folder", sessionFolder);
            return session;
        }

        public static JsonObject SourceSection(string workingDirectory)
        {
            var source = new JsonObject();
            string workflow = null;
            foreach (var arg in Environment.GetCommandLineArgs())
            {
                if (arg.EndsWith(".bonsai", StringComparison.OrdinalIgnoreCase)) { workflow = arg; break; }
            }
            var root = Git.FindRoot(workingDirectory);
            if (workflow != null && root != null)
            {
                var full = Path.GetFullPath(Path.Combine(workingDirectory, workflow));
                if (full.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) workflow = full.Substring(root.Length + 1);
            }
            source.Add("workflow", workflow);
            source.Add("repo", root != null ? Git.OriginUrl(root) : null);
            source.Add("root", root);
            string branch = null, commit = null;
            if (root != null) Git.Head(root, out branch, out commit);
            source.Add("branch", branch);
            source.Add("commit", commit);
            source.Add("dirty", root != null ? Git.IsDirty(root) : null);
            var bonsai = typeof(CombinatorAttribute).Assembly.GetName().Version;
            source.Add("bonsai", string.Format("{0}.{1}.{2}", bonsai.Major, bonsai.Minor, bonsai.Build));
            return source;
        }

        public static List<object> FilesSection(string sessionFolder)
        {
            var files = new List<object>();
            var prefix = sessionFolder.TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
            var paths = Directory.GetFiles(sessionFolder, "*", SearchOption.AllDirectories);
            Array.Sort(paths, StringComparer.Ordinal);
            foreach (var path in paths)
            {
                var rel = path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ? path.Substring(prefix.Length) : path;
                rel = rel.Replace('\\', '/');
                if (rel == FileName || rel == FileName + ".tmp") continue;
                var info = new FileInfo(path);
                var entry = new JsonObject();
                entry.Add("path", rel);
                entry.Add("size", info.Length);
                entry.Add("mtime", Iso(info.LastWriteTimeUtc));
                entry.Add("closed", IsClosed(path));
                files.Add(entry);
            }
            return files;
        }

        /// <summary>Whether no other process holds the file: an exclusive open succeeds. A file we cannot open for another reason (an ACL) reads as closed, since that is not a write in progress.</summary>
        public static bool IsClosed(string path)
        {
            try
            {
                using (File.Open(path, FileMode.Open, FileAccess.Read, FileShare.None)) { }
                return true;
            }
            catch (FileNotFoundException) { return true; }
            catch (DirectoryNotFoundException) { return true; }
            catch (IOException) { return false; }
            catch (UnauthorizedAccessException) { return true; }
        }

        public static string Iso(DateTime utc)
        {
            return utc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);
        }

        public static string Sha256Hex(byte[] bytes)
        {
            using (var sha = SHA256.Create())
            {
                var hash = sha.ComputeHash(bytes);
                var sb = new StringBuilder(hash.Length * 2);
                foreach (var b in hash) sb.Append(b.ToString("x2", CultureInfo.InvariantCulture));
                return sb.ToString();
            }
        }
    }

    /// <summary>Reads .git without running git, except for the dirty flag, which is git's to answer.</summary>
    public static class Git
    {
        public static string FindRoot(string start)
        {
            try
            {
                var dir = new DirectoryInfo(Path.GetFullPath(start));
                while (dir != null)
                {
                    if (Directory.Exists(Path.Combine(dir.FullName, ".git")) || File.Exists(Path.Combine(dir.FullName, ".git"))) return dir.FullName;
                    dir = dir.Parent;
                }
            }
            catch (Exception) { }
            return null;
        }

        /// <summary>The .git directory, following a worktree's "gitdir:" file.</summary>
        public static string GitDir(string root)
        {
            var dotGit = Path.Combine(root, ".git");
            if (Directory.Exists(dotGit)) return dotGit;
            if (File.Exists(dotGit))
            {
                var text = File.ReadAllText(dotGit).Trim();
                if (text.StartsWith("gitdir:", StringComparison.Ordinal))
                {
                    var target = text.Substring(7).Trim();
                    return Path.IsPathRooted(target) ? target : Path.GetFullPath(Path.Combine(root, target));
                }
            }
            return null;
        }

        public static void Head(string root, out string branch, out string commit)
        {
            branch = null;
            commit = null;
            try
            {
                var gitDir = GitDir(root);
                if (gitDir == null) return;
                var head = File.ReadAllText(Path.Combine(gitDir, "HEAD")).Trim();
                if (head.StartsWith("ref:", StringComparison.Ordinal))
                {
                    var refName = head.Substring(4).Trim();
                    branch = refName.StartsWith("refs/heads/", StringComparison.Ordinal) ? refName.Substring(11) : refName;
                    // A worktree's gitdir is .git/worktrees/<name>; refs live in the common dir above it.
                    var common = gitDir;
                    var commonFile = Path.Combine(gitDir, "commondir");
                    if (File.Exists(commonFile)) common = Path.GetFullPath(Path.Combine(gitDir, File.ReadAllText(commonFile).Trim()));
                    var refFile = Path.Combine(common, refName.Replace('/', Path.DirectorySeparatorChar));
                    if (File.Exists(refFile)) commit = File.ReadAllText(refFile).Trim();
                    else commit = PackedRef(Path.Combine(common, "packed-refs"), refName);
                }
                else
                {
                    commit = head;
                }
            }
            catch (Exception) { }
        }

        static string PackedRef(string packedRefs, string refName)
        {
            if (!File.Exists(packedRefs)) return null;
            foreach (var line in File.ReadAllLines(packedRefs))
            {
                if (line.Length > 41 && line[40] == ' ' && line.Substring(41) == refName) return line.Substring(0, 40);
            }
            return null;
        }

        public static string OriginUrl(string root)
        {
            try
            {
                var gitDir = GitDir(root);
                if (gitDir == null) return null;
                var common = gitDir;
                var commonFile = Path.Combine(gitDir, "commondir");
                if (File.Exists(commonFile)) common = Path.GetFullPath(Path.Combine(gitDir, File.ReadAllText(commonFile).Trim()));
                var inOrigin = false;
                foreach (var raw in File.ReadAllLines(Path.Combine(common, "config")))
                {
                    var line = raw.Trim();
                    if (line.StartsWith("[", StringComparison.Ordinal)) inOrigin = line == "[remote \"origin\"]";
                    else if (inOrigin && line.StartsWith("url", StringComparison.Ordinal))
                    {
                        var eq = line.IndexOf('=');
                        if (eq > 0) return line.Substring(eq + 1).Trim();
                    }
                }
            }
            catch (Exception) { }
            return null;
        }

        /// <summary>True or false from git status --porcelain; null when git is not on PATH or did not answer within 10 s.</summary>
        public static bool? IsDirty(string root)
        {
            try
            {
                var psi = new ProcessStartInfo("git", "status --porcelain --untracked-files=no")
                {
                    WorkingDirectory = root,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (var p = Process.Start(psi))
                {
                    var output = p.StandardOutput.ReadToEndAsync();
                    p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit(10000)) { try { p.Kill(); } catch (Exception) { } return null; }
                    if (p.ExitCode != 0) return null;
                    return output.Result.Trim().Length > 0;
                }
            }
            catch (Exception) { return null; }
        }
    }

    /// <summary>An ordered JSON object: keys in the order they were added, as the spec lists them.</summary>
    public class JsonObject : List<KeyValuePair<string, object>>
    {
        public void Add(string key, object value) { Add(new KeyValuePair<string, object>(key, value)); }
    }

    /// <summary>Enough JSON to write the manifest, pretty-printed, with no dependency Bonsai does not already carry.</summary>
    public static class Json
    {
        public static string Serialize(object value)
        {
            var sb = new StringBuilder();
            Write(sb, value, 0);
            sb.Append('\n');
            return sb.ToString();
        }

        static void Write(StringBuilder sb, object value, int depth)
        {
            if (value == null) { sb.Append("null"); return; }
            var obj = value as JsonObject;
            if (obj != null)
            {
                if (obj.Count == 0) { sb.Append("{}"); return; }
                sb.Append("{\n");
                for (var i = 0; i < obj.Count; i++)
                {
                    Indent(sb, depth + 1);
                    WriteString(sb, obj[i].Key);
                    sb.Append(": ");
                    Write(sb, obj[i].Value, depth + 1);
                    sb.Append(i < obj.Count - 1 ? ",\n" : "\n");
                }
                Indent(sb, depth);
                sb.Append('}');
                return;
            }
            var list = value as List<object>;
            if (list != null)
            {
                if (list.Count == 0) { sb.Append("[]"); return; }
                sb.Append("[\n");
                for (var i = 0; i < list.Count; i++)
                {
                    Indent(sb, depth + 1);
                    Write(sb, list[i], depth + 1);
                    sb.Append(i < list.Count - 1 ? ",\n" : "\n");
                }
                Indent(sb, depth);
                sb.Append(']');
                return;
            }
            if (value is string) { WriteString(sb, (string)value); return; }
            if (value is bool) { sb.Append((bool)value ? "true" : "false"); return; }
            if (value is long || value is int) { sb.Append(Convert.ToInt64(value).ToString(CultureInfo.InvariantCulture)); return; }
            if (value is double) { sb.Append(((double)value).ToString("R", CultureInfo.InvariantCulture)); return; }
            throw new ArgumentException("Json cannot write a " + value.GetType().Name);
        }

        static void Indent(StringBuilder sb, int depth)
        {
            for (var i = 0; i < depth; i++) sb.Append("  ");
        }

        static void WriteString(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (var c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.AppendFormat(CultureInfo.InvariantCulture, "\\u{0:x4}", (int)c);
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }
    }
}
