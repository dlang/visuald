// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.expansionprovider;

import visuald.windows;
import std.ascii;
import std.string;
import std.utf;

import stdext.array;

import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.dpackage;
import visuald.pkgutil;
import visuald.dlangsvc;

import vdc.lexer;

import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.vsshell;
import sdk.vsi.singlefileeditor;
import sdk.win32.xmldom;

///////////////////////////////////////////////////////////////////////////////

struct DefaultFieldValue
{
	string field;
	string value;
}

bool ContainsExclusive(ref TextSpan span, int line, int col)
{
	if (line > span.iStartLine && line < span.iEndLine)
		return true;

	if (line == span.iStartLine)
		return (col > span.iStartIndex && (line < span.iEndLine ||
		                                  (line == span.iEndLine && col < span.iEndIndex)));
	if (line == span.iEndLine)
		return col < span.iEndIndex;
	return false;
}

class ExpansionProvider : DisposingComObject, IVsExpansionClient
{
	IVsTextView mView;
	Source mSource;
	IVsExpansion vsExpansion;
	IVsExpansionSession expansionSession;

	bool expansionActive;
	bool expansionPrepared;
	bool completorActiveDuringPreExec;

	DefaultFieldValue[] fieldDefaults; // CDefaultFieldValues
	string titleToInsert;
	string pathToInsert;

	this(Source src)
	{
		mSource = src;
		vsExpansion = qi_cast!(IVsExpansion)(src.GetTextLines());
		assert(vsExpansion);
	}

	override void Dispose()
	{
		EndTemplateEditing(true);
		mSource = null;
		vsExpansion = release(vsExpansion);
		mView = release(mView);
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsExpansionClient) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	bool HandleQueryStatus(ref GUID guidCmdGroup, uint nCmdId, out int hr)
	{
		// in case there's something to conditinally support later on...
		hr = 0;
		return false;
	}

	bool GetExpansionSpan(TextSpan *span)
	{
		assert(expansionSession);

		int hr = expansionSession.GetSnippetSpan(span);
		return SUCCEEDED(hr);
	}


	bool HandlePreExec(const GUID* guidCmdGroup, uint nCmdId, uint nCmdexecopt, const VARIANT* pvaIn, VARIANT* pvaOut)
	{
		if(!expansionActive || !expansionSession)
			return false;

		completorActiveDuringPreExec = IsCompletorActive(mView);

		if(*guidCmdGroup == CMDSETID_StandardCommandSet2K)
		{
			switch (nCmdId) {
			case ECMD_CANCEL:
				if(completorActiveDuringPreExec)
					return false;
				EndTemplateEditing(true);
				return true;
			case ECMD_RETURN:
				bool leaveCaret = false;
				int line = 0, col = 0;
				if(SUCCEEDED(mView.GetCaretPos(&line, &col)))
				{
					TextSpan span;
					if(GetExpansionSpan(&span))
						if(!ContainsExclusive(span, line, col))
							leaveCaret = true;
				}
				if(completorActiveDuringPreExec)
					return false;
				EndTemplateEditing(leaveCaret);
				if(leaveCaret)
					return false;
				return true;
			case ECMD_BACKTAB:
				if(completorActiveDuringPreExec)
					return false;
				expansionSession.GoToPreviousExpansionField();
				return true;
			case ECMD_TAB:
				if(completorActiveDuringPreExec)
					return false;
				expansionSession.GoToNextExpansionField(0); // fCommitIfLast=false
				return true;
			default:
				break;
			}
		}
		return false;
	}

	bool HandlePostExec(const GUID* guidCmdGroup, uint nCmdId, uint nCmdexecopt, bool commit, const VARIANT* pvaIn, VARIANT* pvaOut)
	{
		if(*guidCmdGroup == CMDSETID_StandardCommandSet2K)
		{
			switch (nCmdId) {
			case ECMD_RETURN:
				if (completorActiveDuringPreExec && commit) {
					// if the completor was active during the pre-exec we want to let it handle the command first
					// so we didn't deal with this in pre-exec. If we now get the command, we want to end
					// the editing of the expansion. We also return that we handled the command so auto-indenting doesn't happen
					EndTemplateEditing(false);
					completorActiveDuringPreExec = false;
					return true;
				}
				break;
			default:
				break;
			}
		}
		completorActiveDuringPreExec = false;
		return false;
	}

	bool DisplayExpansionBrowser(IVsTextView view, string prompt, string[] types, bool includeNullType,
								      string[] kinds, bool includeNullKind)
	{
		if (expansionActive)
			EndTemplateEditing(true);

		if (mSource.IsCompletorActive())
			mSource.DismissCompletor();

		mView = view;
		IVsTextManager2 textmgr = queryService!(VsTextManager, IVsTextManager2);
		if(!textmgr)
			return false;
		scope(exit) release(textmgr);

		IVsExpansionManager exmgr;
		textmgr.GetExpansionManager(&exmgr);
		if (!exmgr)
			return false;
		scope(exit) release(exmgr);

		BSTR[] bstrTypes;
		foreach(type; types)
			bstrTypes ~= allocBSTR(type);

		BSTR[] bstrKinds;
		foreach(kind; kinds)
			bstrKinds ~= allocBSTR(kind);

		auto bstrPrompt = ScopedBSTR(prompt);
		int hr = exmgr.InvokeInsertionUI(mView, // pView
						 this, // pClient
						 g_languageCLSID, // guidLang
						 bstrTypes.ptr, // bstrTypes
						 bstrTypes.ilength, // iCountTypes
						 includeNullType ? 1 : 0,  // fIncludeNULLType
						 bstrKinds.ptr, // bstrKinds
						 bstrKinds.ilength, // iCountKinds
						 includeNullKind ? 1 : 0, // fIncludeNULLKind
						 bstrPrompt, // bstrPrefixText
						 ">"); //bstrCompletionChar

		foreach(type; bstrTypes)
			freeBSTR(type);
		foreach(kind; bstrKinds)
			freeBSTR(kind);

		return SUCCEEDED(hr);
	}

	bool InsertSpecificExpansion(IVsTextView view, IXMLDOMNode snippet, TextSpan pos, string relativePath)
	{
		if (expansionActive)
			EndTemplateEditing(true);

		if (mSource.IsCompletorActive())
			mSource.DismissCompletor();

		mView = view;

		auto bstrRelPath = ScopedBSTR(relativePath);
		int hr = vsExpansion.InsertSpecificExpansion(snippet, pos, this, g_languageCLSID, bstrRelPath, &expansionSession);
		if (hr != S_OK || !expansionSession)
			EndTemplateEditing(true);
		else
		{
			// When inserting a snippet it is possible that the edit session is ended inside the insert
			// function (e.g. if the template has no editable fields). In this case we should not stay
			// in template edit mode because otherwise our filter will stole messages to the editor.
			if (!expansionActive) {
				expansionSession = null;
			}
			return true;
		}
		return false;
	}

	bool IsCompletorActive(IVsTextView view)
	{
		if (mSource.IsCompletorActive())
			return true;

		IVsTextViewEx viewex = qi_cast!(IVsTextViewEx)(view);
		scope(exit) release(viewex);
		if (viewex)
			return viewex.IsCompletorWindowActive() == S_OK;
		return false;
	}

	bool InsertNamedExpansion(IVsTextView view, BSTR title, BSTR path, TextSpan pos, bool showDisambiguationUI)
	{
		if (mSource.IsCompletorActive())
			mSource.DismissCompletor();

		mView = view;
		if (expansionActive)
			EndTemplateEditing(true);

		int hr = vsExpansion.InsertNamedExpansion(title, path, pos, this,
		                                          g_languageCLSID, showDisambiguationUI ? 1 : 0, &expansionSession);

		if (hr != S_OK || !expansionSession)
		{
			EndTemplateEditing(true);
			return false;
		}
		if (hr == S_OK)
		{
			// When inserting a snippet it is possible that the edit session is ended inside the insert
			// function (e.g. if the template has no editable fields). In this case we should not stay
			// in template edit mode because otherwise our filter will stole messages to the editor.
			if (!expansionActive)
				expansionSession = null;
			return true;
		}
		return false;
	}

	/// Returns S_OK if match found, S_FALSE if expansion UI is shown, and error otherwise
	int InvokeExpansionByShortcut(IVsTextView view, wstring shortcut, ref TextSpan span, bool showDisambiguationUI, out string title, out string path)
	{
		if (expansionActive)
			EndTemplateEditing(true);

		mView = view;
		title = "";
		path = "";

		mView = view;
		IVsTextManager2 textmgr = queryService!(VsTextManager, IVsTextManager2);
		if(!textmgr)
			return E_FAIL;
		scope(exit) release(textmgr);

		IVsExpansionManager exmgr;
		textmgr.GetExpansionManager(&exmgr);
		if (!exmgr)
			return E_FAIL;
		scope(exit) release(exmgr);

		BSTR bstrPath, bstrTitle;
		int hr = exmgr.GetExpansionByShortcut(this, g_languageCLSID, _toUTF16zw(shortcut), mView,
											  &span, showDisambiguationUI ? 1 : 0, &bstrPath, &bstrTitle);
		if(FAILED(hr) || !bstrPath || !bstrTitle)
			return S_FALSE; // when no shortcut found, do nothing

		if(!InsertNamedExpansion(view, bstrTitle, bstrPath, span, showDisambiguationUI))
			hr = E_FAIL;

		path = detachBSTR(bstrPath);
		title = detachBSTR(bstrTitle);

		return hr;
	}

	// for an example of GetExpansionFunction, see
	// http://msdn.microsoft.com/en-us/library/microsoft.visualstudio.package.expansionfunction%28VS.80%29.aspx
	IVsExpansionFunction GetExpansionFunction(string func, string fieldName)
	{
		string functionName;
		string[] rgFuncParams;

		if (func.length == 0)
			return null;

		bool inIdent = false;
		bool inParams = false;
		int token = 0;

		// initialize the vars needed for our super-complex function parser :-)
		for (int i = 0, n = func.ilength; i < n; i++)
		{
			char ch = func[i];

			// ignore and skip whitespace
			if (!isWhite(ch))
			{
				switch (ch)
				{
				case ',':
					if (!inIdent || !inParams)
						i = n; // terminate loop
					else
					{
						// we've hit a comma, so end this param and move on...
						string name = func[token .. i];
						rgFuncParams ~= name;
						inIdent = false;
					}
					break;
				case '(':
					if (!inIdent || inParams)
						i = n; // terminate loop
					else
					{
						// we've hit the (, so we know the token before this is the name of the function
						functionName = func[token .. i];
						inIdent = false;
						inParams = true;
					}
					break;
				case ')':
					if (!inParams)
						i = n; // terminate loop
					else
					{
						if (inIdent)
						{
							// save last param and stop
							string name = func[token .. i];
							rgFuncParams ~= name;
							inIdent = false;
						}
						i = n; // terminate loop
					}
					break;
				default:
					if (!inIdent)
					{
						inIdent = true;
						token = i;
					}
					break;
				}
			}
		}

		if(functionName.length > 0)
		{
			if(ExpansionFunction expfunc = CreateExpansionFunction(functionName))
			{
				expfunc.fieldName = fieldName;
				expfunc.args = rgFuncParams;
				return expfunc;
			}
		}
		return null;
	}

	ExpansionFunction CreateExpansionFunction(string functionName)
	{
		return newCom!ExpansionFunction(this);
	}

	void PrepareTemplate(string title, string path)
	{
		assert(title.length);

		// stash the title and path for when we actually insert the template
		titleToInsert = title;
		pathToInsert = path;
		expansionPrepared = true;
	}

	void SetFieldDefault(string field, string value)
	{
		assert(expansionPrepared);
		//assert(field && value);

		// we have an expansion "prepared" to insert, so we can now save this
		// field default to set when the expansion is actually inserted
		fieldDefaults ~= DefaultFieldValue(field, value);
	}

	void BeginTemplateEditing(int line, int col)
	{
		assert(expansionPrepared);

		TextSpan tsInsert;
		tsInsert.iStartLine = tsInsert.iEndLine = line;
		tsInsert.iStartIndex = tsInsert.iEndIndex = col;

		auto bstrTitle = ScopedBSTR(titleToInsert);
		auto bstrPath = ScopedBSTR(pathToInsert);
		int hr = vsExpansion.InsertNamedExpansion(bstrTitle, bstrPath, tsInsert,
		                                          this, g_languageCLSID, 0, &expansionSession);

		if (hr != S_OK)
			EndTemplateEditing(true);
		pathToInsert = null;
		titleToInsert = null;
	}

	void EndTemplateEditing(bool leaveCaret)
	{
		if (!expansionActive || !expansionSession)
		{
			expansionActive = false;
			return;
		}

		expansionSession.EndCurrentExpansion(leaveCaret ? 1 : 0); // fLeaveCaret=true
		expansionSession = null;
		expansionActive = false;
	}

	bool GetFieldSpan(string field, TextSpan* pts)
	{
		assert(expansionSession);
		if (!expansionSession)
			return false;

		auto bstrField = ScopedBSTR(field);
		expansionSession.GetFieldSpan(bstrField, pts);

		return true;
	}

	bool GetFieldValue(string field, out string value)
	{
		assert(expansionSession);
		if (!expansionSession)
			return false;

		BSTR bstrValue;
		auto bstrField = ScopedBSTR(field);
		int hr = expansionSession.GetFieldValue(bstrField, &bstrValue);
		value = detachBSTR(bstrValue);
		return hr == S_OK;
	}

	override int EndExpansion()
	{
		mixin(LogCallMix);

		expansionActive = false;
		expansionSession = null;
		return S_OK;
	}

	override int FormatSpan(IVsTextLines buffer, const TextSpan* ts)
	{
		mixin(LogCallMix);

		assert(mSource.GetTextLines() is buffer);

		int rc = E_NOTIMPL;
		if (mSource.EnableFormatSelection())
		{
			// We should not merge edits in this case because it might clobber the
			// $varname$ spans which are markers for yellow boxes.

			// using (EditArray edits = new EditArray(mSource, mView, false, SR.GetString(SR.FormatSpan))) {
			// mSource.ReformatSpan(edits, span);
			// edits.ApplyEdits();
			//}
			rc = mSource.ReindentLines(mView, ts.iStartLine, ts.iEndLine);
		}
		return rc;
	}

	override int IsValidKind(IVsTextLines buffer, const TextSpan *ts, const BSTR bstrKind, BOOL *fIsValid)
	{
		mixin(LogCallMix);

		*fIsValid = 0;
		assert(mSource.GetTextLines() is buffer);

		*fIsValid = 1;
		return S_OK;
	}

	override int IsValidType(IVsTextLines buffer, const TextSpan* ts, const BSTR* rgTypes, const int iCountTypes, BOOL *fIsValid)
	{
		mixin(LogCallMix);

		*fIsValid = 0;
		assert(mSource.GetTextLines() is buffer);

		*fIsValid = 1;
		return S_OK;
	}

	override int OnItemChosen(const BSTR pszTitle, const BSTR pszPath)
	{
		mixin(LogCallMix2);

		TextSpan ts;
		mView.GetCaretPos(&ts.iStartLine, &ts.iStartIndex);
		ts.iEndLine = ts.iStartLine;
		ts.iEndIndex = ts.iStartIndex;

		if (expansionSession) // previous session should have been ended by now!
			EndTemplateEditing(true);

		// insert the expansion

		// TODO: Replace the last parameter with the right string to display as a name of undo operation
		// CompoundActionBase cab = CompoundActionFactory.GetCompoundAction(mView, mSource, SR.FormatSpan));
		return vsExpansion.InsertNamedExpansion(pszTitle, pszPath, // Bug: VSCORE gives us unexpanded path
							ts, this, g_languageCLSID, 0, // fShowDisambiguationUI, (FALSE)
							&expansionSession);
	}

	override int PositionCaretForEditing(IVsTextLines pBuffer, const TextSpan* ts)
	{
		mixin(LogCallMix2);

		// NOP
		return S_OK;
	}

	override int OnAfterInsertion(IVsExpansionSession session)
	{
		mixin(LogCallMix);

		return S_OK;
	}

	override int OnBeforeInsertion(IVsExpansionSession session)
	{
		mixin(LogCallMix);

		if (!session)
			return E_UNEXPECTED;

		expansionPrepared = false;
		expansionActive = true;

		// stash the expansion session pointer while the expansion is active
		if (!expansionSession)
			expansionSession = session;
		else
			// these better be the same!
			assert(expansionSession is session);

		// now set any field defaults that we have.
		foreach (ref DefaultFieldValue dv; fieldDefaults)
		{
			auto bstrField = ScopedBSTR(dv.field);
			auto bstrValue = ScopedBSTR(dv.value);
			expansionSession.SetFieldDefault(bstrField, bstrValue);
		}

		fieldDefaults.length = 0;
		return S_OK;
	}

	override int GetExpansionFunction(IXMLDOMNode xmlFunctionNode, const BSTR bstrFieldName, IVsExpansionFunction* func)
	{
		//mixin(LogCallMix);

		BSTR text;
		if(int hr = xmlFunctionNode.get_text(&text))
			return hr;
		string innerText = detachBSTR(text);
		*func = GetExpansionFunction(innerText, to_string(bstrFieldName));
		return S_OK;
	}
}


class ExpansionFunction : DComObject, IVsExpansionFunction
{
	ExpansionProvider mProvider;
	string fieldName;
	string[] args;
	string[] list;

	this(ExpansionProvider provider)
	{
		mProvider = addref(provider);
	}
	~this()
	{
		mProvider = release(mProvider);
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsExpansionFunction) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

/+
        /// <include file='doc\ExpansionProvider.uex' path='docs/doc[@for="ExpansionFunction.GetCurrentValue"]/*' />
        public abstract string GetCurrentValue();
+/

	/// <summary>Override this method if you want intellisense drop support on a list of possible values.</summary>
	string[] GetIntellisenseList()
	{
		return null;
	}

/+
	/// Gets the value of the specified argument, resolving any fields referenced in the argument.
	/// In the substitution, "$$" is replaced with "$" and any floating '$' signs are left unchanged,
	/// for example "$US 23.45" is returned as is.  Only if the two dollar signs enclose a string of
	/// letters or digits is this considered a field name (e.g. "$foo123$").  If the field is not found
	/// then the unresolved string "$foo" is returned.
	string GetArgument(int index)
	{
		if (index < 0 || index >= args.length)
			return null;
		string arg = args[index];
		if (arg.length == 0)
			return null;
		int i = indexOf(arg, '$');
		if (i >= 0)
		{
			int j = arg[
			StringBuilder sb = new StringBuilder();
			int len = arg.length;
			int start = 0;

			while (i >= 0 && i + 1 < len)
			{
                    sb.Append(arg.Substring(start, i - start));
                    start = i;
                    i++;
                    if (arg[i] == '$') {
                        sb.Append('$');
                        start = i + 1; // $$ is resolved to $.
                    } else {
                        // parse name of variable.
                        int j = i;
                        for (; j < len; j++) {
                            if (!Char.IsLetterOrDigit(arg[j]))
                                break;
                        }
                        if (j == len) {
                            // terminating '$' not found.
                            sb.Append('$');
                            start = i;
                            break;
                        } else if (arg[j] == '$') {
                            string name = arg.Substring(i, j - i);
                            string value;
                            if (GetFieldValue(name, out value)) {
                                sb.Append(value);
                            } else {
                                // just return the unresolved variable.
                                sb.Append('$');
                                sb.Append(name);
                                sb.Append('$');
                            }
                            start = j + 1;
                        } else {
                            // invalid syntax, e.g. "$US 23.45" or some such thing
                            sb.Append('$');
                            sb.Append(arg.Substring(i, j - i));
                            start = j;
                        }
                    }
                    i = arg.IndexOf('$', start);
                }
                if (start < len) {
                    sb.Append(arg.Substring(start, len - start));
                }
                arg = sb.ToString();
            }
            // remove quotes around string literals.
            if (arg.Length > 2 && arg[0] == '"' && arg[arg.Length - 1] == '"') {
                arg = arg.Substring(1, arg.Length - 2);
            } else if (arg.Length > 2 && arg[0] == '\'' && arg[arg.Length - 1] == '\'') {
                arg = arg.Substring(1, arg.Length - 2);
            }
            return arg;
        }
+/

	bool GetFieldValue(string name, out string value)
	{
		if (mProvider && mProvider.expansionSession)
		{
			auto fieldName = ScopedBSTR(name);
			BSTR fieldValue;
			int hr = mProvider.expansionSession.GetFieldValue(fieldName, &fieldValue);
			value = detachBSTR(fieldValue);
			return SUCCEEDED(hr);
		}
		return false;
	}

	public TextSpan GetSelection()
	{
		TextSpan result;
		if (mProvider && mProvider.mView)
		{
			int hr = GetSelectionForward(mProvider.mView, &result.iStartLine, &result.iStartIndex, &result.iEndLine, &result.iEndIndex);
			assert(SUCCEEDED(hr));
		}
		return result;
	}

	override int FieldChanged(const BSTR bstrField, BOOL *fRequeryValue)
	{
		// Returns true if we care about this field changing.
		// We care if the field changes if one of the arguments refers to it.
		if (args.length)
		{
			string var = "$" ~ to_string(bstrField) ~ "$";
			foreach (string arg; args)
			{
				if (arg == var)
				{
					*fRequeryValue = 1; // we care!
					return S_OK;
				}
			}
		}
		*fRequeryValue = 0;
		return S_OK;
	}

	override HRESULT GetDefaultValue(/+[out]+/BSTR *bstrValue, /+[out]+/ BOOL *fHasDefaultValue)
	{
		// This must call GetCurrentValue since during initialization of the snippet
		// VS will call GetDefaultValue and not GetCurrentValue.
		return GetCurrentValue(bstrValue, fHasDefaultValue);
	}

	override HRESULT GetCurrentValue(/+[out]+/BSTR *bstrValue, /+[out]+/ BOOL *fHasDefaultValue)
	{
		*bstrValue = allocBSTR(""); // _toUTF16z("");
		*fHasDefaultValue = !bstrValue ? 0 : 1;
		return S_OK;
	}

	override int GetFunctionType(DWORD* pFuncType)
	{
		if (!list.length)
			list = GetIntellisenseList();
		*pFuncType = list.length ? eft_List : eft_Value;
		return S_OK;
        }

	override int GetListCount(int* iListCount)
	{
		if (!list.length)
			list = GetIntellisenseList();
		*iListCount = list.ilength;
		return S_OK;
        }

	override int GetListText(const int iIndex, BSTR* ppszText)
	{
		if (!list.length)
			list = GetIntellisenseList();
		if (iIndex < list.length)
			*ppszText = allocBSTR(list[iIndex]);
		else
			*ppszText = null;
		return S_OK;
	}

	override int ReleaseFunction()
	{
		mProvider = release(mProvider);
		return S_OK;
	}

/+
    // todo: for some reason VsExpansionManager is wrong.
    [Guid("4970C2BC-AF33-4a73-A34F-18B0584C40E4")]
    internal class SVsExpansionManager {
    }
+/
}
