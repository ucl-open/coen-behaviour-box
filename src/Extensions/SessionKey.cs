using System;
using System.ComponentModel;
using System.IO;
using System.Reactive.Linq;
using Bonsai;

namespace UclOpenCoenBehaviourBox
{
    /// <summary>
    /// The live view's session key, sub-&lt;SubjectId&gt;/ses-&lt;SessionId&gt;_date-&lt;start&gt;, taken from the
    /// session folder LogController made (PathPrefix), so the key names that folder. OpenRigs.Streaming's
    /// StreamController stamps its own date at Start, about a second before LogController stamps the
    /// folder's, and the two differed by a second on GEEK-BBOX1 (30 Oct 2026).
    /// </summary>
    [Combinator]
    [WorkflowElementCategory(ElementCategory.Transform)]
    [Description("The live view's session key, sub-<SubjectId>/ses-<SessionId>_date-<start>, from the session folder's path.")]
    public class SessionKey
    {
        public IObservable<string> Process(IObservable<string> source)
        {
            return source.Select(FromPathPrefix);
        }

        /// <summary>The last two folders of the session path, joined by a forward slash.</summary>
        public static string FromPathPrefix(string pathPrefix)
        {
            var path = (pathPrefix ?? string.Empty).TrimEnd('\\', '/');
            var session = Path.GetFileName(path);
            var subject = Path.GetFileName(Path.GetDirectoryName(path) ?? string.Empty);
            if (!subject.StartsWith("sub-", StringComparison.Ordinal) || !session.StartsWith("ses-", StringComparison.Ordinal))
            {
                throw new ArgumentException(string.Format(
                    "The session folder '{0}' does not end in sub-<SubjectId>\\ses-<SessionId>_date-<start>, so the live view has no session key. A / or \\ in SubjectId or SessionId does this: remove it and Start again.",
                    pathPrefix));
            }
            return subject + "/" + session;
        }
    }
}
