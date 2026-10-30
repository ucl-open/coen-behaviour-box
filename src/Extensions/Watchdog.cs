using System;
using System.ComponentModel;
using System.Reactive.Linq;
using System.Xml;
using System.Xml.Serialization;
using Bonsai;

namespace UclOpenCoenBehaviourBox
{
    /// <summary>
    /// Bonsai's Timeout with a message of its own. Timeout always says "The operation has timed
    /// out.", and the workflow has two of them (the board's clock and the camera's first frame),
    /// whose causes differ; an operator reading only the Runtime Error dialog could not tell which.
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Combinator)]
    [Description("Stops the workflow with the given message if no value arrives within DueTime of subscription, or of the last value.")]
    public class Watchdog
    {
        public Watchdog()
        {
            DueTime = TimeSpan.FromSeconds(10);
        }

        [XmlIgnore]
        [Description("How long to wait for a value.")]
        public TimeSpan DueTime { get; set; }

        [Browsable(false)]
        [XmlElement("DueTime")]
        public string DueTimeXml
        {
            get { return XmlConvert.ToString(DueTime); }
            set { DueTime = XmlConvert.ToTimeSpan(value); }
        }

        [Description("The Runtime Error message: what did not arrive, and what to check.")]
        public string Message { get; set; }

        public IObservable<TSource> Process<TSource>(IObservable<TSource> source)
        {
            var dueTime = DueTime;
            var message = Message;
            // TimeoutException, as Timeout throws: its message reaches the operator without a "Parameter name" line.
            return source.Timeout(dueTime, Observable.Defer(() => Observable.Throw<TSource>(new TimeoutException(message))));
        }
    }
}
