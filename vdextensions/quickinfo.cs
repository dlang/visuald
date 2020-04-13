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
using Microsoft.VisualStudio.Shell;
using Microsoft.VisualStudio;
using Microsoft.VisualStudio.TextManager.Interop;

using System;
using System.ComponentModel.Composition;
using System.Collections.Generic;
using System.Windows.Controls;
using System.Windows;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Documents;
using System.Runtime.InteropServices; // DllImport
using System.Diagnostics;

namespace vdext15
{
	struct SymLink
	{
		public int start;
		public int length;
		public string filename;
		public int line;
		public int column;
	}

	class ClassifiedTextBlock : TextBlock
	{
		VisualDQuickInfoSourceProvider _provider;

		public ClassifiedTextBlock(string text, VisualDQuickInfoSourceProvider provider)
			: base(new Run(text))
		{
			_provider = provider;
		}

		public void setForeground(System.Windows.Media.Brush brush, bool bold)
		{
			Foreground = brush;
			foreach (var inl in Inlines)
			{
				inl.Foreground = brush;
				inl.FontWeight = FontWeight.FromOpenTypeWeight(bold ? 700 : 400);
			}
		}

		public void enableLink(SymLink link)
		{
			MouseLeftButtonDown += new System.Windows.Input.MouseButtonEventHandler(
				delegate (object sender, System.Windows.Input.MouseButtonEventArgs args)
				{
					try
					{
						NavigateTo(link.filename, link.line, link.column);
					}
					catch { }
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

		public int NavigateTo(string file, int line, int column)
		{
			int hr = VSConstants.S_OK;
			var openDoc = _provider.globalServiceProvider.GetService(typeof(SVsUIShellOpenDocument)) as IVsUIShellOpenDocument;
			if (openDoc == null)
			{
				Debug.Fail("Failed to get SVsUIShellOpenDocument service.");
				return VSConstants.E_UNEXPECTED;
			}

			Microsoft.VisualStudio.OLE.Interop.IServiceProvider sp = null;
			IVsUIHierarchy hierarchy = null;
			uint itemID = 0;
			IVsWindowFrame frame = null;
			Guid viewGuid = VSConstants.LOGVIEWID_TextView;

			hr = openDoc.OpenDocumentViaProject(file, ref viewGuid, out sp, out hierarchy, out itemID, out frame);
			Debug.Assert(hr == VSConstants.S_OK, "OpenDocumentViaProject did not return S_OK.");

			hr = frame.Show();
			Debug.Assert(hr == VSConstants.S_OK, "Show did not return S_OK.");

			IntPtr viewPtr = IntPtr.Zero;
			Guid textLinesGuid = typeof(IVsTextLines).GUID;
			hr = frame.QueryViewInterface(ref textLinesGuid, out viewPtr);
			Debug.Assert(hr == VSConstants.S_OK, "QueryViewInterface did not return S_OK.");

			IVsTextLines textLines = Marshal.GetUniqueObjectForIUnknown(viewPtr) as IVsTextLines;

			var textMgr = _provider.globalServiceProvider.GetService(typeof(SVsTextManager)) as IVsTextManager;
			if (textMgr == null)
			{
				Debug.Fail("Failed to get SVsTextManager service.");
				return VSConstants.E_UNEXPECTED;
			}

			IVsTextView textView = null;
			hr = textMgr.GetActiveView(0, textLines, out textView);
			Debug.Assert(hr == VSConstants.S_OK, "QueryViewInterface did not return S_OK.");

			if (textView != null)
			{
				if (line > 0)
				{
					textView.SetCaretPos(line - 1, Math.Max(column - 1, 0));
				}
			}

			return VSConstants.S_OK;
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
		                                           [MarshalAs(UnmanagedType.BStr)] out string fmt,
		                                           [MarshalAs(UnmanagedType.BStr)] out string links);

		static bool GetQuickInfo(string fname, int line, int col,
		                         out string info, out string fmt, out string links,
		                         CancellationToken cancellationToken)
		{
			try
			{
				int req = GetTooltip(fname, line, col);
				if (req != 0)
				{
					while (!GetTooltipResult(req, out info, out fmt, out links))
					{
						if (cancellationToken.IsCancellationRequested)
							return false;
						Thread.Sleep(100);
					}
					return !string.IsNullOrEmpty(info);
				}
			}
			catch
			{
			}
			info = "";
			fmt = "";
			links = "";
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

		public ClassifiedTextBlock createClassifiedTextBlock(ITextView view, string text, string type, bool bold)
		{
			var tb = new ClassifiedTextBlock(text, _provider);
			if (String.IsNullOrEmpty(text) || String.IsNullOrEmpty(text.Trim()))
				return tb;

			// Foreground cannot be set from the constructor?!
			tb.setForeground(GetBrush(view, type), bold);
			return tb;
		}

		static SymLink[] stringToSymLinks(string links)
		{
			string[] strlinks = links.Split(';');
			SymLink[] symlinks = new SymLink[strlinks.Length];
			for (int i = 0; i < strlinks.Length; i++)
			{
				string[] tok = strlinks[i].Split(',');
				if (tok.Length >= 3 && !String.IsNullOrEmpty(tok[2]))
				{
					Int32.TryParse(tok[0], out symlinks[i].start);
					Int32.TryParse(tok[1], out symlinks[i].length);
					symlinks[i].filename = tok[2];
					if (tok.Length >= 5)
					{
						Int32.TryParse(tok[3], out symlinks[i].line);
						Int32.TryParse(tok[4], out symlinks[i].column);
					}
				}
			}
			return symlinks;
		}

		static int findSymLink(SymLink[] symLinks, int pos)
		{
			for (int i = 0; i < symLinks.Length; i++)
				if (symLinks[i].start <= pos && pos < symLinks[i].start + symLinks[i].length)
					return i;
			return -1;
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
				string info, fmt, links;
				if (!GetQuickInfo(_filename, lineNumber, column, out info, out fmt, out links, cancellationToken))
					return System.Threading.Tasks.Task.FromResult<QuickInfoItem>(null);

				SymLink[] symlinks = stringToSymLinks(links);
				ContainerElement infoElm = null;
				Application.Current.Dispatcher.Invoke(delegate
				{
					// back in the UI thread to allow creation of UIElements
					var rows = new List<object>();
					var secs = new List<object>();
					bool bold = false;
					Func<int, string, string, string> addClassifiedTextBlock = (int off, string txt, string type) =>
					{
						while (!String.IsNullOrEmpty(txt))
						{
							string tag = bold ? "</b>" : "<b>";
							string sec;
							bool secbold = bold;
							var pos = txt.IndexOf(tag);
							if (pos >= 0)
							{
								bold = !bold;
								sec = txt.Substring(0, pos);
								txt = txt.Substring(pos + tag.Length);
							}
							else
							{
								sec = txt;
								txt = null;
							}
							if (!String.IsNullOrEmpty(sec))
							{
								var tb = createClassifiedTextBlock(session.TextView, sec, type, secbold);
								int symidx = findSymLink(symlinks, off);
								if (symidx >= 0)
									tb.enableLink(symlinks[symidx]);
								secs.Add(tb);
								off += sec.Length;
							}
						}
						return txt;
					};

					Func<int, string, string, string> addTextSection = (int off, string sec, string type) =>
					{
						var nls = sec.Split(new char[1] { '\n' }, StringSplitOptions.None);
						for (int n = 0; n < nls.Length - 1; n++)
						{
							addClassifiedTextBlock(off, nls[n], type);
							rows.Add(new ContainerElement(ContainerElementStyle.Wrapped, secs));
							secs = new List<object>();
							off += nls[n].Length + 1;
						}
						addClassifiedTextBlock(off, nls[nls.Length - 1], type);
						return sec;
					};

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
									addTextSection(prevpos, sec, prevtype);
									prevtype = colname[1];
									prevpos = pos;
								}
							}
						}
					}
					if (prevpos < info.Length)
					{
						if (prevtype != null)
						{
							string sec = info.Substring(prevpos, info.Length - prevpos);
							addTextSection(prevpos, sec, prevtype);
						}
						else
						{
							addClassifiedTextBlock(prevpos, info, PredefinedClassificationTypeNames.SymbolDefinition);
						}
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
		[Import]
		public SVsServiceProvider globalServiceProvider = null;

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
