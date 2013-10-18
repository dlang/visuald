// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

using System;
using System.Windows.Controls;
using System.Windows;
using System.Windows.Media;
using System.ComponentModel.Composition;
using System.Runtime.InteropServices; // DllImport

using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Utilities;
using Microsoft.VisualStudio.Text.Classification;
using Microsoft.VisualStudio.TextManager.Interop;
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio.Shell.Interop;

namespace vdextensions
{
	#region covmargin Factory
	/// <summary>
	/// Export a <see cref="IWpfTextViewMarginProvider"/>, which returns an 
	/// instance of the margin for the editor to use.
	/// </summary>
	[Export(typeof(IWpfTextViewMarginProvider))]
	[Name(CoverageMargin.MarginName)]
	[Order(After = PredefinedMarginNames.LineNumber)]
	[MarginContainer(PredefinedMarginNames.Left)]
	[ContentType("code")]
	[TextViewRole(PredefinedTextViewRoles.Document)]
	internal sealed class MarginFactory : IWpfTextViewMarginProvider
	{
		[Import]
		internal IEditorFormatMapService FormatMapService = null;
		
		public IWpfTextViewMargin CreateMargin(IWpfTextViewHost textViewHost, IWpfTextViewMargin containerMargin)
		{
			return new CoverageMargin(textViewHost.TextView, FormatMapService.GetEditorFormatMap(textViewHost.TextView));
		}
	}
#endregion

	/// <summary>
	/// A class detailing the margin's visual definition including both size and content.
	/// </summary>
	class CoverageMargin : Canvas, IWpfTextViewMargin //, IClassifier
	{
		#region Member Variables

		public const string MarginName = "CoverageMargin";
		public const string CovColorName = "Visual D Text Coverage";
		public const string NoCovColorName = "Visual D Text Non-Coverage";
		public const string MarginColorName = "Visual D Margin No Coverage";

		private IWpfTextView _textView;
		private bool _isDisposed = false;
		private Canvas _canvas;
		private double _labelOffsetX = 1.0;
		private FontFamily _fontFamily = null;
		private double _fontEmSize = 12.00;
		private IEditorFormatMap _formatMap;
		private string _fileName;
		private Color[] _backgroundColor = new Color[2];
		private Color[] _foregroundColor = new Color[2];
		#endregion

		[DllImport("visuald.dll")]
		public static extern bool GetCoverageData(string fname, int line, int[] data, int cnt);

		#region Constructor
		/// <summary>
		/// Creates a <see cref="CoverageMargin"/> for a given <see cref="IWpfTextView"/>.
		/// </summary>
		/// <param name="textView">The <see cref="IWpfTextView"/> to attach the margin to.</param>
		public CoverageMargin(IWpfTextView textView, IEditorFormatMap formatMap)
		{
			_textView = textView;
			_formatMap = formatMap;

			IVsTextBuffer buffer;
			textView.TextBuffer.Properties.TryGetProperty(typeof(IVsTextBuffer), out buffer);
			_fileName = "";
			if(buffer != null)
			{
				IPersistFileFormat fileFormat = buffer as IPersistFileFormat;
				if(fileFormat != null)
				{
					UInt32 format;
					fileFormat.GetCurFile(out _fileName, out format);
				}
			}

			_canvas = new Canvas();
			this.Children.Add(_canvas);

			this.ClipToBounds = true;

			_fontFamily = _textView.FormattedLineSource.DefaultTextProperties.Typeface.FontFamily;
			_fontEmSize = _textView.FormattedLineSource.DefaultTextProperties.FontRenderingEmSize;

			this.Width = GetMarginWidth(new Typeface(_fontFamily.Source), _fontEmSize) + 2 * _labelOffsetX;

			_textView.ViewportHeightChanged += (sender, args) => DrawLineNumbers();
			_textView.LayoutChanged += new EventHandler<TextViewLayoutChangedEventArgs>(OnLayoutChanged);
			_formatMap.FormatMappingChanged += (sender, args) => OnFormatMappingChanged();

			this.ToolTip = "To customize coverage margin colors select:\n" +
			               "  Tools -> Options -> Fonts and Colors -> " + CovColorName;
		}

		#endregion

		#region Event Handlers

		private void OnLayoutChanged(object sender, TextViewLayoutChangedEventArgs e)
		{
			if (e.VerticalTranslation || e.NewOrReformattedLines.Count > 1)
			{
				DrawLineNumbers();
			}
		}

		private void OnFormatMappingChanged()
		{
			_fontFamily = _textView.FormattedLineSource.DefaultTextProperties.Typeface.FontFamily;
			_fontEmSize = _textView.FormattedLineSource.DefaultTextProperties.FontRenderingEmSize;
			
			this.Width = GetMarginWidth(new Typeface(_fontFamily.Source), _fontEmSize) + 2 * _labelOffsetX;

			DrawLineNumbers();
		}
		#endregion

		#region DrawLineNumbers

		private void DrawLineNumbers()
		{
			// Get the index from the line collection where the cursor is currently sitting
			IVsTextBuffer buffer;
			_textView.TextBuffer.Properties.TryGetProperty(typeof(IVsTextBuffer), out buffer);
			int firstLine = 0;
			int lastLine = 0;
			int col;
			if(buffer == null)
				return;

			buffer.GetLineIndexOfPosition(_textView.TextViewLines.FirstVisibleLine.Start, out firstLine, out col);
			buffer.GetLineIndexOfPosition(_textView.TextViewLines.LastVisibleLine.End, out lastLine, out col);

			// Clear existing text boxes
			if (_canvas.Children.Count > 0)
			{
				_canvas.Children.Clear();
			}

			int lines = lastLine + 1 - firstLine;
			int[] covdata = new int[lines];
			bool hasCoverage = GetCoverageData(_fileName, firstLine, covdata, lines);
//			GetColors();
			if(!hasCoverage)
				return;

			ResourceDictionary rd = _formatMap.GetProperties(CovColorName);
			SolidColorBrush fgBrush = toBrush(rd[EditorFormatDefinition.ForegroundBrushId]);
			SolidColorBrush bgBrush = toBrush(rd[EditorFormatDefinition.BackgroundBrushId]);
			var bold = rd[ClassificationFormatDefinition.IsBoldId];
			FontWeight fontWeight = Convert.ToBoolean(bold) ? FontWeights.Bold : FontWeights.Normal;

			ResourceDictionary rd2 = _formatMap.GetProperties(NoCovColorName);
            SolidColorBrush fgBrush2 = toBrush(rd2[EditorFormatDefinition.ForegroundBrushId]);
			SolidColorBrush bgBrush2 = toBrush(rd2[EditorFormatDefinition.BackgroundBrushId]);
			var bold2 = rd2[ClassificationFormatDefinition.IsBoldId];
			FontWeight fontWeight2 = Convert.ToBoolean(bold2) ? FontWeights.Bold : FontWeights.Normal;

			ResourceDictionary rd3 = _formatMap.GetProperties(MarginColorName);
			this.Background = toBrush(rd3[EditorFormatDefinition.BackgroundBrushId]);

			for (int i = 0; i < _textView.TextViewLines.Count; i++)
			{
				var line = _textView.TextViewLines[i];
				int first, last;
				buffer.GetLineIndexOfPosition(line.Start, out first, out col);
				buffer.GetLineIndexOfPosition(line.End, out last, out col);
				int cov = -1;
				bool hasNonCov = false;
				for(int ln = first; ln <= last; ln++)
				{
					int c = ln < firstLine || ln > lastLine ? -1 : covdata[ln - firstLine];
					if(c == 0)
						hasNonCov = true;
					if(cov < 0)
						cov = c;
					else if(c >= 0)
						cov += c;
				}
				if(cov < 0)
					continue;

				TextBlock tb = new TextBlock();
				tb.Text = string.Format("{0,4}", cov);
				tb.FontFamily = _fontFamily;
				tb.FontSize = _fontEmSize;
				tb.Foreground = hasNonCov ? fgBrush2    : fgBrush;
				tb.FontWeight = hasNonCov ? fontWeight2 : fontWeight;
				tb.Background = hasNonCov ? bgBrush2    : bgBrush;
				Canvas.SetLeft(tb, _labelOffsetX);

				Canvas.SetTop(tb, _textView.TextViewLines[i].TextTop - _textView.ViewportTop);
				_canvas.Children.Add(tb);
			}
		}

		#endregion

		private SolidColorBrush toBrush(object obj)
		{
			if(obj == null)
				return new SolidColorBrush(Color.FromArgb(0xff, 0, 0, 0));
			return (SolidColorBrush) obj;
		}

		private void GetColors()
		{
			try
			{
				IVsFontAndColorStorage storage;
				storage = Package.GetGlobalService(typeof(SVsFontAndColorStorage)) as IVsFontAndColorStorage;
				var guid = new Guid("A27B4E24-A735-4d1d-B8E7-9716E1E3D8E0"); // text editor
				if (storage != null && storage.OpenCategory(ref guid, (uint)(__FCSTORAGEFLAGS.FCSF_NOAUTOCOLORS | 
				                                                             __FCSTORAGEFLAGS.FCSF_LOADDEFAULTS)) == 0)
				{
					var info = new ColorableItemInfo[1];
					storage.GetItem(NoCovColorName, info);
					_backgroundColor[0] = CoverageMargin.ConvertFromWin32Color(info[0].crBackground);
					_foregroundColor[0] = CoverageMargin.ConvertFromWin32Color(info[0].crBackground);

					storage.GetItem(CovColorName, info);
					_backgroundColor[1] = CoverageMargin.ConvertFromWin32Color(info[0].crBackground);
					_foregroundColor[1] = CoverageMargin.ConvertFromWin32Color(info[0].crBackground);

					storage.CloseCategory();
				}
				
			}
			catch { }
		}
		public static Color ConvertFromWin32Color(uint color)
		{
			byte r = (byte)(color & 0x000000FF);
			byte g = (byte)((color & 0x0000FF00) >> 8);
            byte b = (byte)((color & 0x00FF0000) >> 16);
			return Color.FromRgb(r, g, b);
		}
		#region GetMarginWidth

		private double GetMarginWidth(Typeface fontTypeFace, double fontSize)
		{
			FormattedText formattedText = new FormattedText("9999+", System.Globalization.CultureInfo.GetCultureInfo("en-us"),
										                    System.Windows.FlowDirection.LeftToRight, fontTypeFace, fontSize, Brushes.Black);

			return formattedText.MinWidth;
		}

		#endregion

		private void ThrowIfDisposed()
		{
			if (_isDisposed)
				throw new ObjectDisposedException(MarginName);
		}

		#region IWpfTextViewMargin Members

		public System.Windows.FrameworkElement VisualElement
		{
			get
			{
				ThrowIfDisposed();
				return this;
			}
		}

		#endregion

		#region ITextViewMargin Members

		public double MarginSize
		{
			get
			{
				ThrowIfDisposed();
				if (GetCoverageData(_fileName, 0, null, 0))
					return this.ActualWidth;
				return 0;
			}
		}

		public bool Enabled
		{
			get
			{
				ThrowIfDisposed();
				return GetCoverageData(_fileName, 0, null, 0);
			}
		}

		public ITextViewMargin GetTextViewMargin(string marginName)
		{
			return (marginName == CoverageMargin.MarginName) ? this : null;
		}

		public void Dispose()
		{
			if (!_isDisposed)
			{
				GC.SuppressFinalize(this);
				_isDisposed = true;
			}
		}

		#endregion
	}
}
