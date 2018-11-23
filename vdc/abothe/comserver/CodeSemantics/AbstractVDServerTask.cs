using System.Runtime.InteropServices;
using System;
using System.Threading;
using System.Threading.Tasks;
using D_Parser.Completion;
using D_Parser.Dom;
using D_Parser.Misc;

namespace DParserCOMServer.CodeSemantics
{
	public abstract class AbstractVDServerTask<TaskReturnType, RunParametersType>
	{
		private CancellationTokenSource _cancellation, _hardCancel;
		private Task<TaskReturnType> _task;
		private readonly EditorDataProvider _editorDataProvider;
		private readonly VDServer _vdServer;

		private EditorData _editorData;
		private uint _editorDataModificationCount;

		protected AbstractVDServerTask(VDServer vdServer,EditorDataProvider editorDataProvider)
		{
			_vdServer = vdServer;
			_editorDataProvider = editorDataProvider;
		}

		public void Run(string handledModuleFile, CodeLocation caretLocation, RunParametersType runParameters)
		{
			if (_cancellation != null && !_cancellation.IsCancellationRequested)
				_cancellation.Cancel();
			if(_hardCancel != null && !_hardCancel.IsCancellationRequested)
				_hardCancel.CancelAfter(100);

			_cancellation = new CancellationTokenSource();
			if (CompletionOptions.Instance.CompletionTimeout > 0)
				_cancellation.CancelAfter(CompletionOptions.Instance.CompletionTimeout);
			_hardCancel = new CancellationTokenSource();

			var editorData = MakeInitialEditorData(handledModuleFile, caretLocation);
			_task = Task.Run(() =>
				Process(editorData, runParameters),
				_hardCancel.Token);
		}

		private EditorData MakeInitialEditorData(string handledModuleFile, CodeLocation caretLocation)
		{
			// if possible, keep the EditorData, especially resolution contexts
			EditorData editorData;
			uint modificationCount = _editorDataProvider.ModificationCount();
			if (_editorData == null || _editorDataModificationCount != modificationCount)
			{
				editorData = _editorDataProvider.MakeEditorData();
			}
			else
			{
				// wait for pending task to finish/cancel, so we do not access
				//  the context from different threads
				try
				{
					if (_task != null)
						_ = _task.Result;
				}
				catch (TaskCanceledException)
				{
				}
				catch (AggregateException)
				{
				}
				editorData = _editorData;
			}
			editorData.CancelToken = _cancellation.Token;
			handledModuleFile = EditorDataProvider.normalizePath(handledModuleFile);
			var ast = _vdServer.GetModule(handledModuleFile);
			editorData.SyntaxTree = ast ?? throw new COMException("module not found", 1);
			editorData.ModuleCode = _vdServer._sources[handledModuleFile];
			editorData.CaretLocation = caretLocation;
			editorData.CaretOffset = GetCodeOffset(editorData.ModuleCode, caretLocation);

			_editorData = editorData;
			_editorDataModificationCount = modificationCount;
			return editorData;
		}

		private static int GetCodeOffset(string s, CodeLocation loc)
		{
			// column/line 1-based
			int off = 0;
			for (int ln = 1; ln < loc.Line; ln++)
				off = s.IndexOf('\n', off) + 1;
			return off + loc.Column - 1;
		}

		protected abstract TaskReturnType Process(EditorData editorData, RunParametersType parameter);

		public TaskStatus TaskStatus => _task?.Status ?? TaskStatus.Canceled;
		public TaskReturnType Result => _task.Result;
	}
}