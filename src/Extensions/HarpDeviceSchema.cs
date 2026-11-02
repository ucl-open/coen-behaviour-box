using System;
using System.ComponentModel;
using System.IO;
using System.Reactive.Linq;
using Bonsai;

namespace UclOpenCoenBehaviourBox
{
    /// <summary>
    /// Writes the Behavior board's register map, Harp.Behavior's device.yml, into the session as
    /// &lt;Name&gt;\&lt;Name&gt;.yml: the Open Rigs logging spec (section 5) wants it beside a
    /// multi-channel device's files, so &lt;Name&gt;_44_&lt;DateTime&gt;.bin can be decoded from the
    /// session alone. OpenRigs.Logging's LogHarpDevice does not write it. The map is the one embedded
    /// in the Harp.Behavior package that decoded the board, so it cannot drift from it.
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Sink)]
    [Description("Writes Harp.Behavior's device.yml into the session folder as <Name>\\<Name>.yml, for each session folder path (PathPrefix).")]
    public class HarpDeviceSchema
    {
        const string Resource = "Harp.Behavior.device.yml";

        [Description("The device's log name, its folder in the session (BehaviorBoard-Main).")]
        public string Name { get; set; }

        public IObservable<string> Process(IObservable<string> source)
        {
            // Name read at the write, not here: the workflow maps it from the board's subject, after it is built.
            return source.Do(pathPrefix => Write(pathPrefix, Name));
        }

        /// <summary>The written file's path. A .tmp then a rename, so no reader sees half of it.</summary>
        public static string Write(string pathPrefix, string name)
        {
            if (string.IsNullOrEmpty(name))
            {
                throw new ArgumentException("HarpDeviceSchema has no Name, so it has no folder to write the board's register map into.");
            }
            var folder = Path.Combine(pathPrefix, name);
            var path = Path.Combine(folder, name + ".yml");
            Directory.CreateDirectory(folder);
            using (var stream = typeof(Harp.Behavior.Device).Assembly.GetManifestResourceStream(Resource))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException(string.Format(
                        "Harp.Behavior {0} carries no {1}, so the board's register map cannot be written.",
                        typeof(Harp.Behavior.Device).Assembly.GetName().Version, Resource));
                }
                var tmp = path + ".tmp";
                using (var file = File.Create(tmp)) stream.CopyTo(file);
                if (File.Exists(path)) File.Delete(path);
                File.Move(tmp, path);
            }
            return path;
        }
    }
}
