using System;
using System.ComponentModel;
using System.Reactive.Linq;
using Bonsai;

namespace UclOpenCoenBehaviourBox
{
    /// <summary>
    /// Stops the workflow at Start when the camera's exposure does not fit inside the period of the
    /// board's trigger that drives it. A camera still exposing when the next trigger comes ignores
    /// that trigger, so it runs at a fraction of the trigger rate with no gap in its FrameID, and
    /// every frame is then paired with the wrong trigger time: on GEEK-BBOX1, 30,000 us at 50 Hz
    /// gave 25 frames a second and Seconds 60 s adrift of the camera's clock after 3000 rows, with
    /// no error (30 Oct 2026). Checks the settings in use, after CameraOverrides, so a value from
    /// rig.yml is caught as well as one typed for a run.
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Transform)]
    [Description("Stops the workflow if the camera's exposure does not fit inside its trigger period, less a margin. Passes the camera on unchanged.")]
    public class ExposureFitsTrigger
    {
        public ExposureFitsTrigger()
        {
            MarginMicroseconds = 1000;
        }

        [Description("The board output that triggers this camera: 0 for Trigger0Frequency, 1 for Trigger1Frequency.")]
        public int TriggerOutput { get; set; }

        [Description("Time the camera needs between the end of one exposure and the next trigger, in microseconds (1,000, as OpenRigs.Video's own default exposure assumes). With it, an exposure of 19,000 us ran at the full 50 Hz on GEEK-BBOX1's camera.")]
        public double MarginMicroseconds { get; set; }

        public IObservable<NamedDevice<SpinnakerCamera>> Process(IObservable<Tuple<NamedDevice<SpinnakerCamera>, NamedDevice<BehaviorBoard>>> source)
        {
            var output = TriggerOutput;
            var margin = MarginMicroseconds;
            return source.Select(pair =>
            {
                var trigger = pair.Item2.Settings.CameraTriggerController;
                var frequency = output == 1 ? trigger.Trigger1Frequency : trigger.Trigger0Frequency;
                Check(pair.Item1.Name, pair.Item1.Settings.ExposureTime, frequency, margin);
                return pair.Item1;
            });
        }

        /// <summary>Throws, saying the largest exposure allowed, unless exposure + margin fits in one trigger period.</summary>
        public static void Check(string camera, double exposureTime, double frequency, double margin)
        {
            if (frequency <= 0)
            {
                throw new InvalidOperationException(string.Format(
                    "{0}'s trigger frequency in rig.yml is {1} Hz; it must be above 0.", camera, frequency));
            }
            // string.Format, not $"...": Bonsai compiles Extensions with the framework's csc, which is C# 5.
            var limit = 1e6 / frequency - margin;
            if (exposureTime > limit)
            {
                // InvalidOperationException: its message reaches the operator without a "Parameter name" line.
                throw new InvalidOperationException(string.Format(
                    "{0}'s ExposureTime is {1} us, longer than {2} us, the most that fits its {3} Hz trigger " +
                    "(a period of {4} us, less {5} us for the camera). The camera would skip triggers and every " +
                    "frame would get the wrong time. Set ExposureTime (or rig.yml's exposureTime) to {2} or less.",
                    camera, exposureTime, limit, frequency, 1e6 / frequency, margin));
            }
        }
    }
}
