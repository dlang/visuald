// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2016 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Classification;
using Microsoft.VisualStudio.Utilities;
using Microsoft.VisualStudio.Language.Intellisense;
using Microsoft.VisualStudio.Language.StandardClassification;
using Microsoft.VisualStudio.Shell.Interop;
using Microsoft.VisualStudio.Text.Editor;
using Microsoft.VisualStudio.Text.Adornments;

using System;
using System.ComponentModel.Composition;
using System.Collections.Generic;
using System.Windows.Controls;
using System.Windows;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Documents;
using System.Runtime.InteropServices; // DllImport

namespace vdext15
{
	class ClassifiedTextBlock : TextBlock
	{
		public ClassifiedTextBlock(string text)
			: base(new Run(text))
		{
		}

		public void setForeground(System.Windows.Media.Brush brush)
		{
			Foreground = brush;
			foreach (var inl in Inlines)
				inl.Foreground = brush;
		}

		public void enableLink()
		{
			MouseLeftButtonDown += new System.Windows.Input.MouseButtonEventHandler(
				delegate (object sender, System.Windows.Input.MouseButtonEventArgs args)
				{
					// Text = "clicked!";
				});
			MouseEnter += new System.Windows.Input.MouseEventHandler(
				delegate (object sender, System.Windows.Input.MouseEventArgs args)
				{
					TextDecorations.Add(System.Windows.TextDecorations.Underline);
				});
			MouseLeave += new System.Windows.Input.MouseEventHandler(
				delegate (object sender, System.Windows.Input.MouseEventArgs args)
				{
					foreach (var td in System.Windows.TextDecorations.Underline)
						TextDecorations.Remove(td);
				});
		}
	}

	internal sealed class VisualDQuickInfoSource : IAsyncQuickInfoSource
	{
		private ITextBuffer _textBuffer;
		private string _filename;

		VisualDQuickInfoSourceProvider _provider;

		public VisualDQuickInfoSource(VisualDQuickInfoSourceProvider provider, ITextBuffer textBuffer)
		{
			_provider = provider;
			_textBuffer = textBuffer;
			_filename = GetFileName(_textBuffer);
		}

		[DllImport("visuald.dll")]
		public static extern int GetTooltip([MarshalAs(UnmanagedType.BStr)] string fname, int line, int col);
		[DllImport("visuald.dll")]
		public static extern bool GetTooltipResult(int request,
		                                           [MarshalAs(UnmanagedType.BStr)] out string tip,
		                                           [MarshalAs(UnmanagedType.BStr)] out string fmt);

		static bool GetQuickInfo(string fname, int line, int col, out string info, out string fmt,
		                         CancellationToken cancellationToken)
		{
			try
			{
				int req = GetTooltip(fname, line, col);
				if (req != 0)
				{
					while (!GetTooltipResult(req, out info, out fmt))
					{
						if (cancellationToken.IsCancellationRequested)
							return false;
						Thread.Sleep(100);
					}
					return true;
				}
			}
			catch
			{
			}
			info = "";
			fmt = "";
			return false;
		}

		public static string GetFileName(ITextBuffer buffer)
		{
			Microsoft.VisualStudio.TextManager.Interop.IVsTextBuffer bufferAdapter;
			buffer.Properties.TryGetProperty(typeof(Microsoft.VisualStudio.TextManager.Interop.IVsTextBuffer), out bufferAdapter);
			if (bufferAdapter != null)
			{
				var persistFileFormat = bufferAdapter as IPersistFileFormat;
				if (persistFileFormat != null)
				{
					string ppzsFilename = null;
					persistFileFormat.GetCurFile(out ppzsFilename, out _);
					return ppzsFilename;
				}
			}
			return null;
		}

		public System.Windows.Media.Brush GetBrush(ITextView view, string type)
		{
			if (_provider.typeRegistry != null && _provider.formatMap != null)
			{
				var ctype = _provider.typeRegistry.GetClassificationType(type);
				var cmap = _provider.formatMap.GetClassificationFormatMap(view);
				if (ctype != null && cmap != null)
				{
					var tprop = cmap.GetTextProperties(ctype);
					if (tprop != null)
						return tprop.ForegroundBrush;
				}
			}
			return null;
		}

		public ClassifiedTextBlock createClassifiedTextBlock(ITextView view, string text, string type)
		{
			var tb = new ClassifiedTextBlock(text);
			if (String.IsNullOrEmpty(text) || String.IsNullOrEmpty(text.Trim()))
				return tb;

			if (type == "Identifier")
				tb.enableLink();

			// Foreground cannot be set from the constructor?!
			tb.setForeground(GetBrush(view, type));
			return tb;
		}

		// This is called on a background thread.
		public Task<QuickInfoItem> GetQuickInfoItemAsync(IAsyncQuickInfoSession session, CancellationToken cancellationToken)
		{
			var triggerPoint = session.GetTriggerPoint(_textBuffer.CurrentSnapshot);

			if (triggerPoint != null)
			{
				var line = triggerPoint.Value.GetContainingLine();
				var lineNumber = triggerPoint.Value.GetContainingLine().LineNumber;
				var lineSpan = _textBuffer.CurrentSnapshot.CreateTrackingSpan(line.Extent, SpanTrackingMode.EdgeInclusive);

				var column = triggerPoint.Value.Position - line.Start.Position;
				string info, fmt;
				if (!GetQuickInfo(_filename, lineNumber, column, out info, out fmt, cancellationToken))
					return System.Threading.Tasks.Task.FromResult<QuickInfoItem>(null);

				ContainerElement infoElm = null;
				Application.Current.Dispatcher.Invoke(delegate
				{
					// back in the UI thread to allow creation of UIElements
					var rows = new List<object>();
					var secs = new List<object>();

					string[] ops = fmt.Split(';');
					int prevpos = 0;
					string prevtype = null;
					foreach (var op in ops)
					{
						if (prevtype == null)
							prevtype = op;
						else
						{
							string[] colname = op.Split(':');
							if (colname.Length == 2)
							{
								int pos;
								if (Int32.TryParse(colname[0], out pos) && pos > prevpos)
								{
									string sec = info.Substring(prevpos, pos - prevpos);
									var nls = sec.Split('\n');
									for (int n = 0; n < nls.Length - 1; n++)
									{
										secs.Add(createClassifiedTextBlock(session.TextView, nls[n], prevtype));
										rows.Add(new ContainerElement(ContainerElementStyle.Wrapped, secs));
										secs = new List<object>();
									}
									secs.Add(createClassifiedTextBlock(session.TextView, nls[nls.Length-1], prevtype));

									prevtype = colname[1];
									prevpos = pos;
								}
							}
						}
					}
					if (prevtype != null && prevpos < info.Length)
					{
						string sec = info.Substring(prevpos, info.Length - prevpos);
						secs.Add(createClassifiedTextBlock(session.TextView, sec, prevtype));
					}
					else
					{
						secs.Add(createClassifiedTextBlock(session.TextView, info, PredefinedClassificationTypeNames.SymbolDefinition));
					}
					if (secs.Count > 0)
						rows.Add(new ContainerElement(ContainerElementStyle.Wrapped, secs));

					// var tb = createClassifiedTextBlock(session.TextView, " Hello again", PredefinedClassificationTypeNames.Keyword);

/*
					var lineNumberElm = new ContainerElement(
						ContainerElementStyle.Wrapped,
						new ClassifiedTextElement(
							new ClassifiedTextRun(PredefinedClassificationTypeNames.Identifier, _filename),
							new ClassifiedTextRun(PredefinedClassificationTypeNames.Keyword, " Line number: "),
							new ClassifiedTextRun(PredefinedClassificationTypeNames.Identifier, $"{lineNumber + 1}"),
							new ClassifiedTextRun(PredefinedClassificationTypeNames.Keyword, " Column: "),
							new ClassifiedTextRun(PredefinedClassificationTypeNames.Identifier, $"{column}")));

					rows.Add(lineNumberElm);
*/

					infoElm = new ContainerElement(ContainerElementStyle.Stacked, rows);
				});
				return System.Threading.Tasks.Task.FromResult(new QuickInfoItem(lineSpan, infoElm));
			}

			return System.Threading.Tasks.Task.FromResult<QuickInfoItem>(null);
		}

		public void Dispose()
		{
			// This provider does not perform any cleanup.
		}
	}

	[Export(typeof(IAsyncQuickInfoSourceProvider))]
	[Name("Visual D Quick Info Provider")]
	[ContentType("d")]
	[Order]
	internal sealed class VisualDQuickInfoSourceProvider : IAsyncQuickInfoSourceProvider
	{
		// these imports don't work in VisualDQuickInfoSource, maybe because created in another thread?
		[Import]
		public IClassificationFormatMapService formatMap = null;
		[Import]
		public IClassificationTypeRegistryService typeRegistry = null;

		public IAsyncQuickInfoSource TryCreateQuickInfoSource(ITextBuffer textBuffer)
		{
			//if (!textBuffer.ContentType.IsOfType("d"))
			//	return null;

			// This ensures only one instance per textbuffer is created
			return textBuffer.Properties.GetOrCreateSingletonProperty(()
				=> new VisualDQuickInfoSource(this, textBuffer));
		}
	}
}
