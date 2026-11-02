using System;
using System.ComponentModel;
using System.IO;
using System.Reactive.Linq;
using System.Text;
using Bonsai;

namespace UclOpenCoenBehaviourBox
{
    /// <summary>
    /// Writes settings JSON into the session folder as &lt;Name&gt;\&lt;Name&gt;_&lt;DateTime&gt;.json (the Open Rigs
    /// logging spec, section 6), from the text and the session folder (PathPrefix) together. In place of
    /// OpenRigs.Logging's LogDataSchema: in the 0.1.0-bbox.1 build its writer reads its file name when the
    /// workflow starts, before the session folder exists, so it writes to the path saved in the include
    /// (open-rigs 6badbdd fixes it, on a branch not yet in main or the build, 2 Nov 2026).
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Sink)]
    [Description("Writes the JSON text (Item1) into the session folder (Item2, PathPrefix) as <Name>\\<Name>_<DateTime>.json, DateTime the write's UTC time.")]
    public class SessionJson
    {
        [Description("The settings' name, their folder in the session (RigSchema).")]
        public string Name { get; set; }

        public IObservable<Tuple<string, string>> Process(IObservable<Tuple<string, string>> source)
        {
            // Name read at the write, not here: a property mapping sets it after the workflow is built.
            return source.Do(value => Write(value.Item2, Name, value.Item1, DateTime.UtcNow));
        }

        /// <summary>The written file's path. A .tmp then a rename, so no reader sees half of it.</summary>
        public static string Write(string pathPrefix, string name, string json, DateTime utc)
        {
            if (string.IsNullOrEmpty(name))
            {
                throw new ArgumentException("SessionJson has no Name, so it has no folder to write the settings into.");
            }
            var folder = Path.Combine(pathPrefix, name);
            var path = Path.Combine(folder, name + "_" + utc.ToString("yyyy-MM-ddTHH-mm-ss") + ".json");
            Directory.CreateDirectory(folder);
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, json, new UTF8Encoding(false));
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
            return path;
        }
    }
}
