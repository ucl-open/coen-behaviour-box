using System;
using System.ComponentModel;
using System.Reactive.Linq;
using Bonsai;

namespace UclOpenCoenBehaviourBox
{
    /// <summary>
    /// Replaces a camera's binning from rig.yml with the value set here, for as long as it stays
    /// set (in the editor, until cleared or Bonsai closes unsaved). Blank by default, and blank
    /// keeps rig.yml's value, so rig.yml stays the rig's standing setting. Exposure and gain are
    /// not here: they are session parameters the controller changes live while ready (Hardware >
    /// Camera). The serial number is not here either: it is what binds the camera's name to its
    /// hardware, which is rig.yml's job. The output is a copy; the RigConfig subject keeps
    /// rig.yml as read.
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Transform)]
    [Description("Overrides the camera's binning from rig.yml while set. Blank keeps rig.yml's value.")]
    public class CameraOverrides
    {
        [Description("Binning, 1 for full resolution. Blank: rig.yml's binning.")]
        public int? Binning { get; set; }

        public IObservable<NamedDevice<SpinnakerCamera>> Process(IObservable<NamedDevice<SpinnakerCamera>> source)
        {
            return source.Select(device =>
            {
                var binning = Binning;
                if (binning.HasValue && binning.Value < 1)
                {
                    // InvalidOperationException: its message reaches the operator without a "Parameter name" line.
                    throw new InvalidOperationException(string.Format(
                        "CameraOverrides' Binning is {0}; it must be 1 or more, or blank to use rig.yml's.", binning.Value));
                }
                var settings = device.Settings.Copy();
                if (binning.HasValue) settings.Binning = binning.Value;
                return new NamedDevice<SpinnakerCamera>(device.Name, settings);
            });
        }
    }

    public partial class SpinnakerCamera
    {
        /// <summary>A copy, so an override does not change the RigConfig subject's own entry.</summary>
        public SpinnakerCamera Copy()
        {
            return new SpinnakerCamera(this);
        }
    }
}
