using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Reactive.Linq;
using Bonsai;

namespace UclOpenCoenBehaviourBox
{
    /// <summary>
    /// Takes one device's settings out of rig.yml by the device's name. rig.yml groups each
    /// kind's devices by name (camera: box:) and binds each to its hardware; the workflow asks
    /// for the names it drives, and the name in the data is the kind and the entry joined by a
    /// hyphen (Camera-Box). An entry the workflow does not ask for is ignored. A name it asks
    /// for and rig.yml does not have stops the workflow, saying which entries the file has,
    /// where Bonsai's Index would say only that the key was not present. The output carries the
    /// name with the settings, so a device's files take their name from the same place as its
    /// lookup and the name is typed once in the workflow.
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Transform)]
    [Description("Takes one device's settings from rig.yml by its name, Kind-Instance: Camera-Box is camera: box:. Outputs the name with them, for naming the device's files. Stops the workflow, naming the entries rig.yml has, if it has none by that name.")]
    public class RigDevice
    {
        [Description("The device's name in the data: its kind and its entry in rig.yml, joined by a hyphen, such as BehaviorBoard-Main.")]
        public string Name { get; set; }

        // Dictionary rather than IDictionary: it is the generated classes' own type, which
        // Bonsai has to match to infer TDevice.
        public IObservable<NamedDevice<TDevice>> Process<TDevice>(IObservable<Dictionary<string, TDevice>> source)
        {
            var name = Name;
            return source.Select(entries => new NamedDevice<TDevice>(name, Find(entries, name)));
        }

        /// <summary>The entry named by Name, or an exception that says what rig.yml has instead.</summary>
        public static TDevice Find<TDevice>(IDictionary<string, TDevice> entries, string name)
        {
            var parts = (name ?? string.Empty).Split('-');
            if (parts.Length != 2 || parts[0].Length == 0 || parts[1].Length == 0)
            {
                throw new ArgumentException($"RigDevice's Name is '{name}'; it must be Kind-Instance, such as Camera-Box.");
            }

            var kind = LowerFirst(parts[0]);
            var entry = LowerFirst(parts[1]);
            TDevice device;
            if (entries != null && entries.TryGetValue(entry, out device))
            {
                return device;
            }

            var has = entries == null || entries.Count == 0
                ? $"Its {kind} section has no entries."
                : $"Its {kind} entries: {string.Join(", ", entries.Keys.OrderBy(k => k, StringComparer.Ordinal))}.";
            throw new KeyNotFoundException(
                $"rig.yml has no {kind} named '{entry}', which this workflow records as {name}. {has} " +
                $"Add {entry} under {kind}: in this rig's rig.yml, or correct the name there.");
        }

        static string LowerFirst(string text)
        {
            return char.ToLowerInvariant(text[0]) + text.Substring(1);
        }
    }

    /// <summary>A device's name in the data, Kind-Instance, and its settings from rig.yml.</summary>
    public class NamedDevice<TDevice>
    {
        public NamedDevice(string name, TDevice settings)
        {
            Name = name;
            Settings = settings;
        }

        [Description("The device's name in the data, such as Camera-Box: its folder and the start of its files' names.")]
        public string Name { get; private set; }

        [Description("The device's entry in rig.yml.")]
        public TDevice Settings { get; private set; }
    }
}
