// adapted from
// https://github.com/microsoft/VSSDK-Extensibility-Samples/blob/master/Intra-text_Adornment/C%23/Support/IntraTextAdornmentTagger.cs
//***************************************************************************

using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices; // DllImport
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Forms;
using System.Windows.Media;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Classification;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Text.Tagging;
using Microsoft.VisualStudio.TextManager.Interop;
using Microsoft.VisualStudio.Utilities;

namespace vdext15
{
	/// <summary>
	/// Helper class for interspersing adornments into text.
	/// </summary>
	/// <remarks>
	/// To avoid an issue around intra-text adornment support and its interaction with text buffer changes,
	/// this tagger reacts to text and paramStorage tag changes with a delay. It waits to send out its own TagsChanged
	/// event until the WPF Dispatcher is running again and it takes care to report adornments
	/// that are consistent with the latest sent TagsChanged event by storing that particular snapshot
	/// and using it to query for the data tags.
	/// </remarks>
	internal abstract class IntraTextAdornmentTagger<TData, TAdornment>
		: ITagger<IntraTextAdornmentTag>
		where TAdornment : UIElement
	{
		protected readonly IWpfTextView view;
		protected Dictionary<SnapshotSpan, TAdornment> adornmentCache = new Dictionary<SnapshotSpan, TAdornment>();
		protected ITextSnapshot snapshot { get; private set; }
		private readonly List<SnapshotSpan> invalidatedSpans = new List<SnapshotSpan>();
		protected SnapshotSpan _lastTagSpan;

        protected IntraTextAdornmentTagger(IWpfTextView view)
		{
			this.view = view;
			snapshot = view.TextBuffer.CurrentSnapshot;

			this.view.LayoutChanged += HandleLayoutChanged;
			this.view.TextBuffer.Changed += HandleBufferChanged;
		}

		/// <param name="span">The span of text that this adornment will elide.</param>
		/// <returns>Adornment corresponding to given data. May be null.</returns>
		protected abstract TAdornment CreateAdornment(TData data, SnapshotSpan span);

		/// <returns>True if the adornment was updated and should be kept. False to have the adornment removed from the view.</returns>
		protected abstract bool UpdateAdornment(TAdornment adornment, TData data);

		/// <param name="spans">Spans to provide adornment data for. These spans do not necessarily correspond to text lines.</param>
		/// <remarks>
		/// If adornments need to be updated, call <see cref="RaiseTagsChanged"/> or <see cref="InvalidateSpans"/>.
		/// This will, indirectly, cause <see cref="GetAdornmentData"/> to be called.
		/// </remarks>
		/// <returns>
		/// A sequence of:
		///  * adornment data for each adornment to be displayed
		///  * the span of text that should be elided for that adornment (zero length spans are acceptable)
		///  * and affinity of the adornment (this should be null if and only if the elided span has a length greater than zero)
		/// </returns>
		protected abstract IEnumerable<Tuple<SnapshotSpan, PositionAffinity?, TData>> GetAdornmentData(NormalizedSnapshotSpanCollection spans);

		private void HandleBufferChanged(object sender, TextContentChangedEventArgs args)
		{
			var editedSpans = args.Changes.Select(change => new SnapshotSpan(args.After, change.NewSpan)).ToList();
			InvalidateSpans(editedSpans);
		}

		/// <summary>
		/// Causes intra-text adornments to be updated asynchronously.
		/// </summary>
		protected void InvalidateSpans(IList<SnapshotSpan> spans)
		{
			lock (invalidatedSpans)
			{
				bool wasEmpty = invalidatedSpans.Count == 0;
				invalidatedSpans.AddRange(spans);

				if (wasEmpty && this.invalidatedSpans.Count > 0)
					view.VisualElement.Dispatcher.BeginInvoke(new Action(AsyncUpdate));
			}
        }

		public void InvokeAsyncUpdate()
		{
            view.VisualElement.Dispatcher.BeginInvoke(new Action(RedoAsyncUpdate));
		}
        public void RedoAsyncUpdate()
		{
            if (snapshot != null)
                RaiseTagsChanged(new SnapshotSpan(snapshot, 0, snapshot.Length));
        }

		private void AsyncUpdate()
		{
			// Store the snapshot that we're now current with and send an event
			// for the text that has changed.
			if (snapshot != view.TextBuffer.CurrentSnapshot)
			{
				snapshot = view.TextBuffer.CurrentSnapshot;

				Dictionary<SnapshotSpan, TAdornment> translatedAdornmentCache = new Dictionary<SnapshotSpan, TAdornment>();

				foreach (var keyValuePair in adornmentCache)
				{
					var span = keyValuePair.Key.TranslateTo(snapshot, SpanTrackingMode.EdgeExclusive);
					if (!translatedAdornmentCache.ContainsKey(span))
						translatedAdornmentCache.Add(span, keyValuePair.Value);
				}

				adornmentCache = translatedAdornmentCache;
			}

			List<SnapshotSpan> translatedSpans;
			lock (invalidatedSpans)
			{
				translatedSpans = invalidatedSpans.Select(s => s.TranslateTo(snapshot, SpanTrackingMode.EdgeInclusive)).ToList();
				invalidatedSpans.Clear();
			}

			if (translatedSpans.Count == 0)
				return;

			var start = translatedSpans.Select(span => span.Start).Min();
			var end = translatedSpans.Select(span => span.End).Max();

			_lastTagSpan = new SnapshotSpan(start, end);
            RaiseTagsChanged(_lastTagSpan);
		}

		/// <summary>
		/// Causes intra-text adornments to be updated synchronously.
		/// </summary>
		protected void RaiseTagsChanged(SnapshotSpan span)
		{
			var handler = TagsChanged;
			if (handler != null)
				handler(this, new SnapshotSpanEventArgs(span));
		}

		private void HandleLayoutChanged(object sender, TextViewLayoutChangedEventArgs e)
		{
			SnapshotSpan visibleSpan = view.TextViewLines.FormattedSpan;

			// Filter out the adornments that are no longer visible.
			List<SnapshotSpan> toRemove = new List<SnapshotSpan>(
				from keyValuePair
				in adornmentCache
				where !keyValuePair.Key.TranslateTo(visibleSpan.Snapshot, SpanTrackingMode.EdgeExclusive).IntersectsWith(visibleSpan)
				select keyValuePair.Key);

			foreach (var span in toRemove)
				adornmentCache.Remove(span);
		}


		// Produces tags on the snapshot that the tag consumer asked for.
		public virtual IEnumerable<ITagSpan<IntraTextAdornmentTag>> GetTags(NormalizedSnapshotSpanCollection spans)
		{
			if (spans == null || spans.Count == 0)
				yield break;

			// Translate the request to the snapshot that this tagger is current with.

			ITextSnapshot requestedSnapshot = spans[0].Snapshot;

			var translatedSpans = new NormalizedSnapshotSpanCollection(spans.Select(span => span.TranslateTo(snapshot, SpanTrackingMode.EdgeExclusive)));

			// Grab the adornments.
			foreach (var tagSpan in GetAdornmentTagsOnSnapshot(translatedSpans))
			{
				// Translate each adornment to the snapshot that the tagger was asked about.
				SnapshotSpan span = tagSpan.Span.TranslateTo(requestedSnapshot, SpanTrackingMode.EdgeExclusive);

				IntraTextAdornmentTag tag = new IntraTextAdornmentTag(tagSpan.Tag.Adornment, tagSpan.Tag.RemovalCallback, tagSpan.Tag.Affinity);
				yield return new TagSpan<IntraTextAdornmentTag>(span, tag);
			}
		}

		// Produces tags on the snapshot that this tagger is current with.
		private IEnumerable<TagSpan<IntraTextAdornmentTag>> GetAdornmentTagsOnSnapshot(NormalizedSnapshotSpanCollection spans)
		{
			if (spans.Count == 0)
				yield break;

			ITextSnapshot snapshot = spans[0].Snapshot;

			System.Diagnostics.Debug.Assert(snapshot == this.snapshot);

			// Since WPF UI objects have state (like mouse hover or animation) and are relatively expensive to create and lay out,
			// this code tries to reuse controls as much as possible.
			// The controls are stored in this.adornmentCache between the calls.

			// Mark which adornments fall inside the requested spans with Keep=false
			// so that they can be removed from the cache if they no longer correspond to data tags.
			HashSet<SnapshotSpan> toRemove = new HashSet<SnapshotSpan>();
			foreach (var ar in adornmentCache)
				if (spans.IntersectsWith(new NormalizedSnapshotSpanCollection(ar.Key)))
					toRemove.Add(ar.Key);

			foreach (var spanDataPair in GetAdornmentData(spans).Distinct(new Comparer()))
			{
				// Look up the corresponding adornment or create one if it's new.
				TAdornment adornment;
				SnapshotSpan snapshotSpan = spanDataPair.Item1;
				PositionAffinity? affinity = spanDataPair.Item2;
				TData adornmentData = spanDataPair.Item3;
				if (adornmentCache.TryGetValue(snapshotSpan, out adornment))
				{
					if (UpdateAdornment(adornment, adornmentData))
						toRemove.Remove(snapshotSpan);
				}
				else
				{
					adornment = CreateAdornment(adornmentData, snapshotSpan);

					if (adornment == null)
						continue;

					// Get the adornment to measure itself. Its DesiredSize property is used to determine
					// how much space to leave between text for this adornment.
					// Note: If the size of the adornment changes, the line will be reformatted to accommodate it.
					// Note: Some adornments may change size when added to the view's visual tree due to inherited
					// dependency properties that affect layout. Such options can include SnapsToDevicePixels,
					// UseLayoutRounding, TextRenderingMode, TextHintingMode, and TextFormattingMode. Making sure
					// that these properties on the adornment match the view's values before calling Measure here
					// can help avoid the size change and the resulting unnecessary re-format.
					adornment.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));

					adornmentCache.Add(snapshotSpan, adornment);
				}
				var tag = new IntraTextAdornmentTag(adornment, null, null, 4, null, null, affinity);
				yield return new TagSpan<IntraTextAdornmentTag>(snapshotSpan, tag);
			}

			foreach (var snapshotSpan in toRemove)
				adornmentCache.Remove(snapshotSpan);
		}

		public event EventHandler<SnapshotSpanEventArgs> TagsChanged;

		private class Comparer : IEqualityComparer<Tuple<SnapshotSpan, PositionAffinity?, TData>>
		{
			public bool Equals(Tuple<SnapshotSpan, PositionAffinity?, TData> x, Tuple<SnapshotSpan, PositionAffinity?, TData> y)
			{
				if (x == null && y == null)
					return true;
				if (x == null || y == null)
					return false;
				return x.Item1.Equals(y.Item1);
			}

			public int GetHashCode(Tuple<SnapshotSpan, PositionAffinity?, TData> obj)
			{
				return obj.Item1.GetHashCode();
			}
		}

	}

	/// Provides paramStorage adornments in place of paramStorage constants.
	internal sealed class ParamStorageAdornmentTagger
		: IntraTextAdornmentTagger<ParamStorageTag, ParamStorageAdornment>
	{
		[DllImport("visuald.dll")]
		public static extern bool GetParameterStorageLocs(string fname,
			[MarshalAs(UnmanagedType.SafeArray, SafeArraySubType = VarEnum.VT_INT)] out int[] locs,
			out bool pending, out int changeCount);

		public static bool GetParameterStorageLocations(string fname, out int[] data, out bool pending, out int changeCount)
		{
			try
			{
				// grab triplets of (type, line, col)
				if (!GetParameterStorageLocs(fname, out data, out pending, out changeCount))
					return false;
				return true;
			}
			catch
			{
				data = new int[0];
				pending = true;
				changeCount = -1;
				return false;
			}
		}

		public SolidColorBrush storageColor = new SolidColorBrush(Colors.Green);
		IEditorFormatMap formatMap;

		private static SolidColorBrush toBrush(object obj)
		{
			if (obj == null)
				return new SolidColorBrush(Colors.Red);
			return (SolidColorBrush)obj;
		}

		public void UpdateColors()
		{
			try
			{
				ResourceDictionary rd = formatMap.GetProperties("ParamStorageClassificationFormatVisualD");
				storageColor = toBrush(rd[EditorFormatDefinition.ForegroundBrushId]);

				foreach (var tag in adornmentCache)
					tag.Value.Foreground = storageColor;
			}
			catch { }
		}

		internal static ITagger<IntraTextAdornmentTag> GetTagger(IWpfTextView view, IEditorFormatMap formatMap,
			Lazy<ITagAggregator<ParamStorageTag>> paramStorageTagger)
		{
			return view.Properties.GetOrCreateSingletonProperty<ParamStorageAdornmentTagger>(
				() => new ParamStorageAdornmentTagger(view, formatMap, paramStorageTagger.Value));
		}

		private ITagAggregator<ParamStorageTag> paramStorageTagger;

		private ParamStorageAdornmentTagger(IWpfTextView view, IEditorFormatMap formatMap,
				ITagAggregator<ParamStorageTag> paramStorageTagger)
			: base(view)
		{
			this.paramStorageTagger = paramStorageTagger;
            ITextBuffer buffer = view.TextBuffer;
            if (buffer != null)
            {
                ParamStorageTagger tagger;
                if (buffer.Properties.TryGetProperty(typeof(ParamStorageTagger), out tagger))
					tagger._adornmentTagger = this;
            }

            this.formatMap = formatMap;
			this.formatMap.FormatMappingChanged += (sender, args) => UpdateColors();
			UpdateColors();
		}

		public void Dispose()
		{
			paramStorageTagger.Dispose();

			view.Properties.RemoveProperty(typeof(ParamStorageAdornmentTagger));
		}

		// To produce adornments that don't obscure the text, the adornment tags
		// should have zero length spans. Overriding this method allows control
		// over the tag spans.
		protected override IEnumerable<Tuple<SnapshotSpan, PositionAffinity?, ParamStorageTag>>
			GetAdornmentData(NormalizedSnapshotSpanCollection spans)
		{
			if (spans.Count == 0)
				yield break;

			ITextSnapshot snapshot = spans[0].Snapshot;

			var paramStorageTags = paramStorageTagger.GetTags(spans);

			foreach (IMappingTagSpan<ParamStorageTag> dataTagSpan in paramStorageTags)
			{
				NormalizedSnapshotSpanCollection paramStorageTagSpans = dataTagSpan.Span.GetSpans(snapshot);

				// Ignore data tags that are split by projection.
				// This is theoretically possible but unlikely in current scenarios.
				if (paramStorageTagSpans.Count != 1)
					continue;

				SnapshotSpan adornmentSpan = new SnapshotSpan(paramStorageTagSpans[0].End, 0);

				yield return Tuple.Create(adornmentSpan, (PositionAffinity?)PositionAffinity.Predecessor, dataTagSpan.Tag);
			}
		}

		protected override ParamStorageAdornment CreateAdornment(ParamStorageTag dataTag, SnapshotSpan span)
		{
			return new ParamStorageAdornment(dataTag, storageColor);
		}

		protected override bool UpdateAdornment(ParamStorageAdornment adornment, ParamStorageTag dataTag)
		{
			adornment.Update(dataTag);
			return true;
		}
	}

	/// <summary>
	/// Determines which spans of text likely refer to paramStorage values.
	/// </summary>
	/// <remarks>
	/// <para>
	/// This is a data-only component. The tagging system is a good fit for presenting data-about-text.
	/// The <see cref="ParamStorageAdornmentTagger"/> takes paramStorage tags produced by this tagger and creates corresponding UI for this data.
	/// </para>
	/// </remarks>
	internal class ParamStorageTagger : ITagger<ParamStorageTag>
	{
		private string _fileName;
		int[] _stcLocs;
		ITextSnapshot _pendingSnapshot;
		ITextSnapshot _currentSnapshot;
		public ParamStorageAdornmentTagger _adornmentTagger;

        int _changeCount;

		public ParamStorageTagger(ITextBuffer buffer)
		{
			IVsTextBuffer vsbuffer;
			buffer.Properties.TryGetProperty(typeof(IVsTextBuffer), out vsbuffer);
			_fileName = "";
			if (vsbuffer != null)
			{
				IPersistFileFormat fileFormat = vsbuffer as IPersistFileFormat;
				if (fileFormat != null)
				{
					UInt32 format;
					fileFormat.GetCurFile(out _fileName, out format);
				}
			}

			buffer.Changed += (sender, args) => HandleBufferChanged(args);
			_pendingSnapshot = _currentSnapshot = buffer.CurrentSnapshot;
		}

		#region ITagger implementation

		public bool UpdateStcSpans()
		{
			int[] stcLocs;
			bool pending;
			int changeCount;
			ParamStorageAdornmentTagger.GetParameterStorageLocations(_fileName, out stcLocs, out pending, out changeCount);
			if (pending && _stcLocs != null)
                return pending;
			if (_pendingSnapshot == null && _changeCount == changeCount)
				return false;

			if (stcLocs != null)
			{
				int j = 0;
				for (int i = 0; i + 2 < stcLocs.Length; i += 3)
				{
					if (stcLocs[i] >= 0 && stcLocs[i] <= 2)
					{
						if (stcLocs[i + 1] >= _currentSnapshot.LineCount)
							continue;
						var line = _currentSnapshot.GetLineFromLineNumber(stcLocs[i + 1] - 1);
						stcLocs[j] = stcLocs[i];
						stcLocs[j + 1] = line.Start.Position + stcLocs[i + 2];
						j += 2;
					}
				}
				Array.Resize(ref stcLocs, j);
			}
			_stcLocs = stcLocs;
			_changeCount = changeCount;
			if (!pending)
				_pendingSnapshot = null;
			return pending;
		}

		public virtual IEnumerable<ITagSpan<ParamStorageTag>> GetTags(NormalizedSnapshotSpanCollection spans)
		{
			bool pending = UpdateStcSpans();

			// Note that the spans argument can contain spans that are sub-spans of lines or intersect multiple lines.
			if (_stcLocs != null)
				for (int i = 0; i + 1 < _stcLocs.Length; i += 2)
				{
					// need to compare manually as info is on different snapshots
					int pos = _stcLocs[i + 1];
					bool intersects = false;
					foreach (var span in spans)
						if (span.Start.Position <= pos && pos <= span.End.Position)
							intersects = true;

					if (intersects)
					{
						var point = new SnapshotPoint(spans.First().Snapshot, pos);
						SnapshotSpan span = new SnapshotSpan(point, 1);
						yield return new TagSpan<ParamStorageTag>(span, new ParamStorageTag(_stcLocs[i]));
					}
				}

			if (pending)
			{
                System.Threading.Timer timer = null;
                timer = new System.Threading.Timer((obj) =>
                {
                    timer.Dispose();
					if (_adornmentTagger != null)
						_adornmentTagger.InvokeAsyncUpdate();
                }, null, 1000, System.Threading.Timeout.Infinite);
            }
        }
		public event EventHandler<SnapshotSpanEventArgs> TagsChanged;

		#endregion

		/// <summary>
		/// Handle buffer changes. The default implementation expands changes to full lines and sends out
		/// a <see cref="TagsChanged"/> event for these lines.
		/// </summary>
		/// <param name="args">The buffer change arguments.</param>
		protected virtual void HandleBufferChanged(TextContentChangedEventArgs args)
		{
			if (args.Changes.Count == 0)
				return;

			if (TagsChanged == null)
				return;

			// adapt stcSpans, so any unmodified tags get moved with changes
			if (_stcLocs != null)
				foreach (var change in args.Changes)
					for (int i = 0; i + 1 < _stcLocs.Length; i += 2)
						if (_stcLocs[i + 1] >= change.OldPosition)
							_stcLocs[i + 1] += change.Delta;

			// Combine all changes into a single span so that
			// the ITagger<>.TagsChanged event can be raised just once for a compound edit
			// with many parts.
			_pendingSnapshot = _currentSnapshot = args.After;

			int start = args.Changes[0].NewPosition;
			int end = args.Changes[args.Changes.Count - 1].NewEnd;

            SnapshotSpan totalAffectedSpan = new SnapshotSpan(
				_currentSnapshot.GetLineFromPosition(start).Start,
				_currentSnapshot.GetLineFromPosition(end).End);

			if (TagsChanged != null)
				TagsChanged(this, new SnapshotSpanEventArgs(totalAffectedSpan));
		}
	}

	/// <summary>
	/// Data tag indicating that the tagged text represents a paramStorage.
	/// </summary>
	/// <remarks>
	/// Note that this tag has nothing directly to do with adornments or other UI.
	/// This sample's adornments will be produced based on the data provided in these tags.
	/// This separation provides the potential for other extensions to consume paramStorage tags
	/// and provide alternative UI or other derived functionality over this data.
	/// </remarks>
	internal class ParamStorageTag : ITag
	{
		internal ParamStorageTag(int type)
		{
			Type = type;
		}

		internal readonly int Type;
	}

	internal sealed class ParamStorageAdornment : TextBlock //Button
	{
		internal ParamStorageAdornment(ParamStorageTag paramStorageTag, Brush color)
		{
			//Text = "ref";
			FontSize = FontSize * 0.75;

			//Background = Brushes.AntiqueWhite;
			Foreground = color;
			TextAlignment = TextAlignment.Center;

			Update(paramStorageTag);
		}

		internal void Update(ParamStorageTag paramStorageTag)
		{
			var txt = paramStorageTag.Type == 0 ? "ref " : paramStorageTag.Type == 1 ? "out " : "lazy ";
			Inlines.Clear();
			Inlines.Add(new Italic(new Run(txt)));
		}
	}

//#if STC_ADORNMENT
	[Export(typeof(ITaggerProvider))]
	[ContentType("d")]
	[TagType(typeof(ParamStorageTag))]
	internal sealed class ParamStorageTaggerProvider : ITaggerProvider
	{
		public ITagger<T> CreateTagger<T>(ITextBuffer buffer) where T : ITag
		{
			if (buffer == null)
				throw new ArgumentNullException("buffer");

			return buffer.Properties.GetOrCreateSingletonProperty(() => new ParamStorageTagger(buffer)) as ITagger<T>;
		}
	}

	[Export(typeof(IViewTaggerProvider))]
	[ContentType("d")]
	[ContentType("projection")]
	[TagType(typeof(IntraTextAdornmentTag))]
	internal sealed class ParamStorageAdornmentTaggerProvider : IViewTaggerProvider
	{
		[Import]
		internal IBufferTagAggregatorFactoryService BufferTagAggregatorFactoryService = null;

		[Import]
		internal IClassificationTypeRegistryService ClassificationRegistry = null;

		[Import]
		internal IEditorFormatMapService FormatMapService = null;

		[Export(typeof(ClassificationTypeDefinition))]
		[Name("ParamStorageClassificationVisualD")]
		internal static ClassificationTypeDefinition paramStorageClassificationType = null;

		private static IClassificationType s_paramStorageClassification;

		public ITagger<T> CreateTagger<T>(ITextView textView, ITextBuffer buffer) where T : ITag
		{
			if (s_paramStorageClassification == null)
				s_paramStorageClassification = ClassificationRegistry.GetClassificationType("ParamStorageClassificationVisualD");

			if (textView == null)
				throw new ArgumentNullException("textView");

			if (buffer == null)
				throw new ArgumentNullException("buffer");

			if (buffer != textView.TextBuffer)
				return null;

			return ParamStorageAdornmentTagger.GetTagger(
				(IWpfTextView)textView, FormatMapService.GetEditorFormatMap(textView),
				new Lazy<ITagAggregator<ParamStorageTag>>(
					() => BufferTagAggregatorFactoryService.CreateTagAggregator<ParamStorageTag>(textView.TextBuffer)))
				as ITagger<T>;
		}
	}

	[Export(typeof(EditorFormatDefinition))]
	[ClassificationType(ClassificationTypeNames = "ParamStorageClassificationVisualD")]
	[Name("ParamStorageClassificationFormatVisualD")]
	[UserVisible(true)]
	[Order(After = Priority.High)]
	internal sealed class ParamStorageFormatDefinition : ClassificationFormatDefinition
	{
		public ParamStorageFormatDefinition()
		{
			this.DisplayName = "Visual D Parameter Storage";
			this.ForegroundColor = System.Windows.Media.Colors.LightSkyBlue;
		}
	}
//#endif
}
