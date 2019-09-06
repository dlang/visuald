// adapted from
// https://github.com/Microsoft/VS-PPT/blob/master/src/GoToDef/GoToDefMouseHandler.cs
//
// Productivity Power Tools for Visual Studio
// 
// Copyright(c) Microsoft Corporation
// 
// All rights reserved.
// 
// MIT License
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software
// and associated documentation files (the "Software"), to deal in the Software without restriction, 
// including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, 
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, 
// subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all copies or substantial
// portions of the Software.
// 
// THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
// LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

using Microsoft.VisualStudio;
using Microsoft.VisualStudio.OLE.Interop;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Classification;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Text.Operations;
using Microsoft.VisualStudio.Text.Tagging;
using Microsoft.VisualStudio.Utilities;
using System;
using System.Collections.Generic;
using System.ComponentModel.Composition;
using System.Windows;
using System.Windows.Input;

namespace vdext15
{
	public static class PredefinedTextViewRoles14
	{
		// not in older versions of PredefinedTextViewRoles
		public const string PreviewTextView = "ENHANCED_SCROLLBAR_PREVIEW";
		public const string EmbeddedPeekTextView = "EMBEDDED_PEEK_TEXT_VIEW";
		public const string CodeDefinitionView = "CODEDEFINITION";
		public const string Printable = "PRINTABLE";
	}

	[Export(typeof(IKeyProcessorProvider))]
    [TextViewRole(PredefinedTextViewRoles.Document)]
    [TextViewRole(PredefinedTextViewRoles14.EmbeddedPeekTextView)]
    [ContentType("code")]
    [Name("GotoDefVisualD")]
    [Order(Before = "VisualStudioKeyboardProcessor")]
    internal sealed class GoToDefKeyProcessorProvider : IKeyProcessorProvider
    {
        //[Import]
        //private SVsServiceProvider _serviceProvider;

        public KeyProcessor GetAssociatedProcessor(IWpfTextView view)
        {
            //IVsExtensionManager manager = _serviceProvider.GetService(typeof(SVsExtensionManager)) as IVsExtensionManager;
            //if (manager == null)
            //    return null;
			//
            //IInstalledExtension extension;
            //manager.TryGetInstalledExtension("GoToDef", out extension);
            //if (extension != null)
            //    return null;

            return view.Properties.GetOrCreateSingletonProperty(typeof(GoToDefKeyProcessor),
                                                                () => new GoToDefKeyProcessor(CtrlKeyState.GetStateForView(view)));
        }
    }

    [Export(typeof(EditorOptionDefinition))]
    [Name(ControlClickOpensPeekOption.OptionName)]
    public sealed class ControlClickOpensPeekOption : WpfViewOptionDefinition<bool>
    {
        public const string OptionName = "ControlClickOpensPeek";
        public readonly static EditorOptionKey<bool> OptionKey = new EditorOptionKey<bool>(ControlClickOpensPeekOption.OptionName);

        public override bool Default { get { return true; } }

        public override EditorOptionKey<bool> Key { get { return ControlClickOpensPeekOption.OptionKey; } }
    }

    /// <summary>
    /// The state of the control key for a given view, which is kept up-to-date by a combination of the
    /// key processor and the mouse processor.
    /// </summary>
    internal sealed class CtrlKeyState
    {
        internal static CtrlKeyState GetStateForView(ITextView view)
        {
            return view.Properties.GetOrCreateSingletonProperty(typeof(CtrlKeyState), () => new CtrlKeyState());
        }

        private bool _enabled;

        internal bool Enabled
        {
            get
            {
                // Check and see if ctrl is down but we missed it somehow.
                bool ctrlDown = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
                if (ctrlDown != _enabled)
                    Enabled = ctrlDown;

                return _enabled;
            }
            set
            {
                bool oldVal = _enabled;
                _enabled = value;
                if (oldVal != _enabled)
                {
                    var temp = CtrlKeyStateChanged;
                    if (temp != null)
                        temp(this, new EventArgs());
                }
            }
        }

        internal event EventHandler<EventArgs> CtrlKeyStateChanged;
    }

    /// <summary>
    /// Listen for the control key being pressed or released to update the CtrlKeyStateChanged for a view.
    /// </summary>
    internal sealed class GoToDefKeyProcessor : KeyProcessor
    {
        private CtrlKeyState _state;

        public GoToDefKeyProcessor(CtrlKeyState state)
        {
            _state = state;
        }

        private void UpdateState(KeyEventArgs args)
        {
            _state.Enabled = (args.KeyboardDevice.Modifiers & ModifierKeys.Control) != 0;
        }

        public override void PreviewKeyDown(KeyEventArgs args)
        {
            UpdateState(args);
        }

        public override void PreviewKeyUp(KeyEventArgs args)
        {
            UpdateState(args);
        }
    }

    [Export(typeof(IMouseProcessorProvider))]
    [TextViewRole(PredefinedTextViewRoles.Document)]
    [TextViewRole(PredefinedTextViewRoles14.EmbeddedPeekTextView)]
    [ContentType("code")]
    [Name("GotoDefVisualD")]
    [Order(Before = "WordSelection")]
    internal sealed class GoToDefMouseHandlerProvider : IMouseProcessorProvider
    {
        [Import]
        private IClassifierAggregatorService _aggregatorFactory;

        [Import]
        private ITextStructureNavigatorSelectorService _navigatorService;

        [Import]
        private SVsServiceProvider _globalServiceProvider;

        public IMouseProcessor GetAssociatedProcessor(IWpfTextView view)
        {
            var buffer = view.TextBuffer;

            IOleCommandTarget shellCommandDispatcher = GetShellCommandDispatcher(view);

            if (shellCommandDispatcher == null)
                return null;

			//IInstalledExtension extension;
			//manager.TryGetInstalledExtension("GoToDef", out extension);
			//if (extension != null)
			//    return null;

			if (!view.TextBuffer.ContentType.IsOfType("d"))
				return null;

			return new GoToDefMouseHandler(view,
                                           shellCommandDispatcher,
                                           _aggregatorFactory.GetClassifier(buffer),
                                           _navigatorService.GetTextStructureNavigator(buffer),
                                           CtrlKeyState.GetStateForView(view));
        }

        #region Private helpers

        /// <summary>
        /// Get the SUIHostCommandDispatcher from the global service provider.
        /// </summary>
        private IOleCommandTarget GetShellCommandDispatcher(ITextView view)
        {
            return _globalServiceProvider.GetService(typeof(SUIHostCommandDispatcher)) as IOleCommandTarget;
        }

        #endregion
    }

    /// <summary>
    /// Handle ctrl+click on valid elements to send GoToDefinition to the shell.  Also handle mouse moves
    /// (when control is pressed) to highlight references for which GoToDefinition will (likely) be valid.
    /// </summary>
    internal sealed class GoToDefMouseHandler : MouseProcessorBase
    {
        private IWpfTextView _view;
        private CtrlKeyState _state;
        private IClassifier _aggregator;
        private ITextStructureNavigator _navigator;
        private IOleCommandTarget _commandTarget;

        public GoToDefMouseHandler(IWpfTextView view, IOleCommandTarget commandTarget, 
            IClassifier aggregator, ITextStructureNavigator navigator, CtrlKeyState state)
        {
            _view = view;
            _commandTarget = commandTarget;
            _state = state;
            _aggregator = aggregator;
            _navigator = navigator;

            _state.CtrlKeyStateChanged += (sender, args) =>
            {
                if (_state.Enabled)
                    this.TryHighlightItemUnderMouse(RelativeToView(Mouse.PrimaryDevice.GetPosition(_view.VisualElement)));
                else
                    this.SetHighlightSpan(null);
            };

            // Some other points to clear the highlight span.
            _view.LostAggregateFocus += (sender, args) => this.SetHighlightSpan(null);
            _view.VisualElement.MouseLeave += (sender, args) => this.SetHighlightSpan(null);
        }

        #region Mouse processor overrides

        // Remember the location of the mouse on left button down, so we only handle left button up
        // if the mouse has stayed in a single location.
        private Point? _mouseDownAnchorPoint;

        public override void PostprocessMouseLeftButtonDown(MouseButtonEventArgs e)
        {
            //register the mouse down only if control is being pressed
            if (_state.Enabled)
            {
                _mouseDownAnchorPoint = RelativeToView(e.GetPosition(_view.VisualElement));
            }
        }

        public override void PreprocessMouseMove(MouseEventArgs e)
        {
            if (!_mouseDownAnchorPoint.HasValue && _state.Enabled && e.LeftButton == MouseButtonState.Released)
            {
                TryHighlightItemUnderMouse(RelativeToView(e.GetPosition(_view.VisualElement)));
            }
            else if (_mouseDownAnchorPoint.HasValue)
            {
                // Check and see if this is a drag; if so, clear out the highlight. 
                var currentMousePosition = RelativeToView(e.GetPosition(_view.VisualElement));
                if (InDragOperation(_mouseDownAnchorPoint.Value, currentMousePosition))
                {
                    _mouseDownAnchorPoint = null;
                    this.SetHighlightSpan(null);
                }
            }
        }

        private bool InDragOperation(Point anchorPoint, Point currentPoint)
        {
            // If the mouse up is more than a drag away from the mouse down, this is a drag 
            //the drag can happen also on the same row so just one of these condition should make the movement a drag
            return Math.Abs(anchorPoint.X - currentPoint.X) >= SystemParameters.MinimumHorizontalDragDistance ||
                   Math.Abs(anchorPoint.Y - currentPoint.Y) >= SystemParameters.MinimumVerticalDragDistance;
        }

        public override void PreprocessMouseLeave(MouseEventArgs e)
        {
            _mouseDownAnchorPoint = null;
        }

        public override void PreprocessMouseUp(MouseButtonEventArgs e)
        {
            if (_mouseDownAnchorPoint.HasValue && _state.Enabled)
            {
                var currentMousePosition = RelativeToView(e.GetPosition(_view.VisualElement));

                if (!InDragOperation(_mouseDownAnchorPoint.Value, currentMousePosition))
                {
                    _state.Enabled = false;

                    this.SetHighlightSpan(null);
                    _view.Selection.Clear();
                    this.DispatchGoToDef();

                    e.Handled = true;
                }
            }

            _mouseDownAnchorPoint = null;
        }


        #endregion

        #region Private helpers

        private Point RelativeToView(Point position)
        {
            return new Point(position.X + _view.ViewportLeft, position.Y + _view.ViewportTop);
        }

        private bool TryHighlightItemUnderMouse(Point position)
        {
            bool updated = false;

            try
            {
                var line = _view.TextViewLines.GetTextViewLineContainingYCoordinate(position.Y);
                if (line == null)
                    return false;

                var bufferPosition = line.GetBufferPositionFromXCoordinate(position.X);

                if (!bufferPosition.HasValue)
                    return false;

                // Quick check - if the mouse is still inside the current underline span, we're already set.
                var currentSpan = CurrentUnderlineSpan;
                if (currentSpan.HasValue && currentSpan.Value.Contains(bufferPosition.Value))
                {
                    updated = true;
                    return true;
                }


                var extent = _navigator.GetExtentOfWord(bufferPosition.Value);
                if (!extent.IsSignificant)
                    return false;

                // For C#, we ignore namespaces after using statements - GoToDef will fail for those.
                if (_view.TextBuffer.ContentType.IsOfType("csharp"))
                {
                    string lineText = bufferPosition.Value.GetContainingLine().GetText().Trim();
                    if (lineText.StartsWith("using", StringComparison.OrdinalIgnoreCase))
                        return false;
                }

                // Now, check for valid classification type.  C# and C++ (at least) classify the things we are interested
                // in as either "identifier" or "user types" (though "identifier" will yield some false positives).  VB, unfortunately,
                // doesn't classify identifiers.
                foreach (var classification in _aggregator.GetClassificationSpans(extent.Span))
                {
                    var name = classification.ClassificationType.Classification.ToLower();
                    if ((name.Contains("identifier") || name.Contains("user types")) &&
                        SetHighlightSpan(classification.Span))
                    {
                        updated = true;
                        return true;
                    }
                }

                // No update occurred, so return false.
                return false;
            }
            finally
            {
                if (!updated)
                    SetHighlightSpan(null);
            }
        }

        private SnapshotSpan? CurrentUnderlineSpan
        {
            get
            {
                var classifier = UnderlineClassifierProvider.GetClassifierForView(_view);
                if (classifier != null && classifier.CurrentUnderlineSpan.HasValue)
                    return classifier.CurrentUnderlineSpan.Value.TranslateTo(_view.TextSnapshot, SpanTrackingMode.EdgeExclusive);
                else
                    return null;
            }
        }

        private bool SetHighlightSpan(SnapshotSpan? span)
        {
            var classifier = UnderlineClassifierProvider.GetClassifierForView(_view);
            if (classifier != null)
            {
                if (span.HasValue)
                    Mouse.OverrideCursor = Cursors.Hand;
                else
                    Mouse.OverrideCursor = null;

                classifier.SetUnderlineSpan(span);
                return true;
            }

            return false;
        }

        private bool DispatchGoToDef()
        {
            bool showDefinitionsPeek = false; //  _view.Options.GetOptionValue(ControlClickOpensPeekOption.OptionKey);
            Guid cmdGroup = showDefinitionsPeek ? VSConstants.VsStd12 : VSConstants.GUID_VSStandardCommandSet97;
            uint cmdID = showDefinitionsPeek ? (uint)VSConstants.VSStd12CmdID.PeekDefinition : (uint)VSConstants.VSStd97CmdID.GotoDefn;

            // Don't block until we've finished executing the command
            int hr = _commandTarget.Exec(ref cmdGroup,
                                         cmdID,
                                         (uint)OLECMDEXECOPT.OLECMDEXECOPT_DODEFAULT,
                                         System.IntPtr.Zero,
                                         System.IntPtr.Zero);

            return ErrorHandler.Succeeded(hr);
        }

        #endregion
    }

	#region Classification type/format exports

	[Export(typeof(EditorFormatDefinition))]
	[ClassificationType(ClassificationTypeNames = "UnderlineClassificationVisualD")]
	[Name("UnderlineClassificationFormatVisualD")]
	[UserVisible(true)]
	[Order(After = Priority.High)]
	internal sealed class UnderlineFormatDefinition : ClassificationFormatDefinition
	{
		public UnderlineFormatDefinition()
		{
			this.DisplayName = "Visual D Goto Definition";
			this.TextDecorations = System.Windows.TextDecorations.Underline;
			this.ForegroundColor = System.Windows.Media.Colors.LightSkyBlue;
		}
	}

	#endregion

	#region Provider definition

	[Export(typeof(IViewTaggerProvider))]
	[ContentType("text")]
	[TagType(typeof(ClassificationTag))]
	internal class UnderlineClassifierProvider : IViewTaggerProvider
	{
		[Import]
		internal IClassificationTypeRegistryService ClassificationRegistry;

		//[Import]
		//private SVsServiceProvider _serviceProvider;

		[Export(typeof(ClassificationTypeDefinition))]
		[Name("UnderlineClassificationVisualD")]
		internal static ClassificationTypeDefinition underlineClassificationType;

		private static IClassificationType s_underlineClassification;
		public static UnderlineClassifier GetClassifierForView(ITextView view)
		{
			if (s_underlineClassification == null)
				return null;

			return view.Properties.GetOrCreateSingletonProperty(() => new UnderlineClassifier(view, s_underlineClassification));
		}

		public ITagger<T> CreateTagger<T>(ITextView textView, ITextBuffer buffer) where T : ITag
		{
			if (s_underlineClassification == null)
				s_underlineClassification = ClassificationRegistry.GetClassificationType("UnderlineClassificationVisualD");

			if (textView.TextBuffer != buffer)
				return null;

			//IVsExtensionManager manager = _serviceProvider.GetService(typeof(SVsExtensionManager)) as IVsExtensionManager;
			//if (manager == null)
			//	return null;
			//
			//IInstalledExtension extension;
			//manager.TryGetInstalledExtension("GoToDef", out extension);
			//if (extension != null)
			//	return null;

			return GetClassifierForView(textView) as ITagger<T>;
		}
	}

	#endregion

	internal class UnderlineClassifier : ITagger<ClassificationTag>
	{
		private IClassificationType _classificationType;
		private ITextView _textView;
		private SnapshotSpan? _underlineSpan;

		internal UnderlineClassifier(ITextView textView, IClassificationType classificationType)
		{
			_textView = textView;
			_classificationType = classificationType;
			_underlineSpan = null;
		}

		#region Private helpers

		private void SendEvent(SnapshotSpan span)
		{
			var temp = this.TagsChanged;
			if (temp != null)
				temp(this, new SnapshotSpanEventArgs(span));
		}

		#endregion

		#region UnderlineClassification public members

		public SnapshotSpan? CurrentUnderlineSpan { get { return _underlineSpan; } }

		public void SetUnderlineSpan(SnapshotSpan? span)
		{
			var oldSpan = _underlineSpan;
			_underlineSpan = span;

			if (!oldSpan.HasValue && !_underlineSpan.HasValue)
				return;

			else if (oldSpan.HasValue && _underlineSpan.HasValue && oldSpan == _underlineSpan)
				return;

			if (!_underlineSpan.HasValue)
			{
				this.SendEvent(oldSpan.Value);
			}
			else
			{
				SnapshotSpan updateSpan = _underlineSpan.Value;
				if (oldSpan.HasValue)
					updateSpan = new SnapshotSpan(updateSpan.Snapshot,
						Span.FromBounds(Math.Min(updateSpan.Start, oldSpan.Value.Start),
										Math.Max(updateSpan.End, oldSpan.Value.End)));

				this.SendEvent(updateSpan);
			}
		}

		#endregion

		public IEnumerable<ITagSpan<ClassificationTag>> GetTags(NormalizedSnapshotSpanCollection spans)
		{
			if (!_underlineSpan.HasValue || spans.Count == 0)
				yield break;

			SnapshotSpan request = new SnapshotSpan(spans[0].Start, spans[spans.Count - 1].End);
			SnapshotSpan underline = _underlineSpan.Value.TranslateTo(request.Snapshot, SpanTrackingMode.EdgeInclusive);
			if (underline.IntersectsWith(request))
			{
				yield return new TagSpan<ClassificationTag>(underline, new ClassificationTag(_classificationType));
			}
		}

		public event EventHandler<SnapshotSpanEventArgs> TagsChanged;
	}
}
