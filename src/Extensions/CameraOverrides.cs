using System;
using System.ComponentModel;
using System.Reactive.Linq;
using Bonsai;

namespace UclOpenCoenBehaviourBox
{
    /// <summary>
    /// Replaces a camera's exposure, gain and binning from rig.yml with the values set here, for
    /// as long as they stay set (in the editor, until cleared or Bonsai closes unsaved). Each is
    /// blank by default, and blank keeps rig.yml's value, so rig.yml stays the rig's standing
    /// settings and these are the per-session knobs the Properties panel shows
    /// (the old hw-behaviour-box workflow had them there). The serial number is not here: it is
    /// what binds the camera's name to its hardware, which is rig.yml's job. The output is a copy;
    /// the RigConfig subject keeps rig.yml as read, and everything downstream of the camera's
    /// subject (the camera itself, the CSV's ExposureTime column) sees the values in use.
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Transform)]
    [Description("Overrides the camera's exposure, gain and binning from rig.yml while set. Blank keeps rig.yml's value.")]
    public class CameraOverrides
    {
        [Description("Exposure time in microseconds. At most the trigger period less 1,000 (19,000 at 50 Hz): ExposureFitsTrigger stops the workflow otherwise. Blank: rig.yml's exposureTime.")]
        public double? ExposureTime { get; set; }

        [Description("Gain in dB. Blank: rig.yml's gain.")]
        public double? Gain { get; set; }

        [Description("Binning, 1 for full resolution. Blank: rig.yml's binning.")]
        public int? Binning { get; set; }

        public IObservable<NamedDevice<SpinnakerCamera>> Process(IObservable<NamedDevice<SpinnakerCamera>> source)
        {
            return source.Select(device =>
            {
                var exposureTime = ExposureTime;
                var gain = Gain;
                var binning = Binning;
                if (exposureTime.HasValue && exposureTime.Value <= 0)
                {
                    // InvalidOperationException: its message reaches the operator without a "Parameter name" line.
                    throw new InvalidOperationException(string.Format(
                        "CameraOverrides' ExposureTime is {0}; it must be above 0 microseconds, or blank to use rig.yml's.", exposureTime.Value));
                }
                if (binning.HasValue && binning.Value < 1)
                {
                    throw new InvalidOperationException(string.Format(
                        "CameraOverrides' Binning is {0}; it must be 1 or more, or blank to use rig.yml's.", binning.Value));
                }
                var settings = device.Settings.Copy();
                if (exposureTime.HasValue) settings.ExposureTime = exposureTime.Value;
                if (gain.HasValue) settings.Gain = gain.Value;
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
