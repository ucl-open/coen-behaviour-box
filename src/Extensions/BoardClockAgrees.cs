using System;
using System.ComponentModel;
using System.Reactive.Linq;
using Bonsai;
using Bonsai.Harp;

namespace UclOpenCoenBehaviourBox
{
    /// <summary>
    /// Passes the board's timestamped messages whose Harp time agrees (or, with Agrees false,
    /// disagrees) with the PC's UTC clock. The Clock group decides from the board's own
    /// timestamps that its clock is set, rather than from catching the one reply to its write:
    /// Bonsai subscribes a workflow's branches one after another while the board is already
    /// talking, so the branch that waits for that reply can subscribe after it came (2 Nov 2026:
    /// about 1 start in 4 stopped on the clock Watchdog that way, the board's clock long set).
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Combinator)]
    [Description("Passes the board's timestamped messages whose time agrees (Agrees true) or disagrees (Agrees false) with the PC's UTC time, within Tolerance.")]
    public class BoardClockAgrees
    {
        // Harp time is seconds since this (Bonsai.Harp's CreateTimestamped.ReferenceTime, internal there).
        static readonly DateTime HarpEpoch = new DateTime(1904, 1, 1, 0, 0, 0, DateTimeKind.Utc);

        public BoardClockAgrees()
        {
            Agrees = true;
            ToleranceSeconds = 2;
        }

        [Description("True passes messages whose time agrees with the PC's; false passes those whose time does not.")]
        public bool Agrees { get; set; }

        // SynchronizeTimestamp sets whole seconds, truncated, so a set clock reads up to 1 s behind.
        [Description("How far, in seconds, the board's time may be from the PC's UTC time and still agree. SynchronizeTimestamp sets whole seconds, so a set board reads up to 1 s behind.")]
        public double ToleranceSeconds { get; set; }

        public IObservable<HarpMessage> Process(IObservable<HarpMessage> source)
        {
            var agrees = Agrees;
            var tolerance = ToleranceSeconds;
            return source.Where(message =>
            {
                double timestamp;
                if (!message.TryGetTimestamp(out timestamp)) return false;
                var now = DateTime.UtcNow.Subtract(HarpEpoch).TotalSeconds;
                return (Math.Abs(now - timestamp) <= tolerance) == agrees;
            });
        }
    }
}
