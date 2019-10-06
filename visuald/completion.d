// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.completion;

import visuald.windows;
import std.ascii;
import std.string;
import std.utf;
import std.file;
import std.path;
import std.algorithm;
import std.array;
import std.conv;
import std.uni;

import stdext.array;
import stdext.file;
import stdext.ddocmacros;
import stdext.string;

import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.fileutil;
import visuald.pkgutil;
import visuald.stringutil;
import visuald.dpackage;
import visuald.dproject;
import visuald.dlangsvc;
import visuald.dimagelist;
import visuald.config;
import visuald.intellisense;

import vdc.lexer;

import sdk.port.vsi;
import sdk.win32.commctrl;
import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.textmgr121;
import sdk.vsi.vsshell;
import sdk.win32.wtypes;

///////////////////////////////////////////////////////////////

const int kCompletionSearchLines = 5000;

class ImageList {};

struct Declaration
{
	string name;
	string type;
	string description;
	string text;

	static Declaration split(string s)
	{
		Declaration decl;
		auto pos1 = indexOf(s, ':');
		if(pos1 >= 0)
		{
			decl.name = s[0 .. pos1];
			auto pos2 = indexOf(s[pos1 + 1 .. $], ':');
			if(pos2 >= 0)
			{
				decl.type = s[pos1 + 1 .. pos1 + 1 + pos2];
				decl.description = s[pos1 + 1 + pos2 + 1 .. $];
			}
			else
				decl.type = s[pos1 + 1 .. $];
		}
		else
			decl.name = s;

		auto pos3 = indexOf(decl.name, "|");
		if(pos3 >= 0)
		{
			decl.text = decl.name[pos3 + 1 .. $];
			decl.name = decl.name[0 .. pos3];
		}
		else
			decl.text = decl.name;

		return decl;
	}

	int compareByType(const ref Declaration other) const
	{
		int s1 = Type2Sorting(type);
		int s2 = Type2Sorting(other.type);
		if (s1 != s2)
			return s1 - s2;
		if (int res = icmp(name, other.name))
			return res;
		return 0;
	}

	int compareByName(const ref Declaration other) const
	{
		if (int res = icmp(name, other.name))
			return res;
		if (int res = icmp(type, other.type))
			return res;
		return 0;
	}

	static int Type2Glyph(string type)
	{
		switch(type)
		{
			case "KW":   return CSIMG_KEYWORD;
			case "SPRP": return CSIMG_KEYWORD;
			case "ASKW": return CSIMG_KEYWORD;
			case "ASOP": return CSIMG_KEYWORD;
			case "PROP": return CSIMG_PROPERTY;
			case "SNPT": return CSIMG_SNIPPET;
			case "TEXT": return CSIMG_TEXT;
			case "MOD":  return CSIMG_DMODULE;
			case "DIR":  return CSIMG_DFOLDER;
			case "PKG":  return CSIMG_PACKAGE;
			case "FUNC": return CSIMG_FUNCTION;
			case "MTHD": return CSIMG_MEMBER;
			case "STRU": return CSIMG_STRUCT;
			case "UNIO": return CSIMG_UNION;
			case "CLSS": return CSIMG_CLASS;
			case "IFAC": return CSIMG_INTERFACE;
			case "TMPL": return CSIMG_TEMPLATE;
			case "ENUM": return CSIMG_ENUM;
			case "EVAL": return CSIMG_ENUMMEMBER;
			case "NMIX": return CSIMG_UNKNOWN2;
			case "VAR":  return CSIMG_FIELD;
			case "ALIA": return CSIMG_ALIAS;
			case "OVR":  return CSIMG_UNKNOWN3;

			default:     return 0;
		}
	}

	static int Type2Sorting(string type)
	{
		switch(type)
		{
			case "PROP": return 1;
			case "VAR":  return 1;
			case "EVAL": return 1;

			case "MTHD": return 2;

			case "STRU": return 3;
			case "UNIO": return 3;
			case "CLSS": return 3;
			case "IFAC": return 3;
			case "ENUM": return 3;

			case "KW":   return 4;
			case "SPRP": return 4; // static meta property
			case "ASKW": return 4;
			case "ASOP": return 4;
			case "ALIA": return 4;

			case "MOD":  return 5;
			case "DIR":  return 5;
			case "PKG":  return 5;
			case "NMIX": return 5; // named teplate mixin mixin

			case "FUNC": return 6;
			case "TMPL": return 6;
			case "OVR":  return 6;

			case "TEXT": return 3;
			case "SNPT": return 3;
			default:     return 7;
		}
	}
}

class Declarations
{
	Declaration[] mDecls;
	int mExpansionState = kStateInit;

	enum
	{
		kStateInit,
		kStateImport,
		kStateSemantic,
		kStateNearBy,
		kStateSymbols,
		kStateCaseInsensitive
	}

	this()
	{
	}

	int GetCount()
	{
		return mDecls.length;
	}

	dchar OnAutoComplete(IVsTextView textView, string committedWord, dchar commitChar, int commitIndex)
	{
		return 0;
	}

	int GetGlyph(int index)
	{
		if(index < 0 || index >= mDecls.length)
			return 0;
		return Declaration.Type2Glyph(mDecls[index].type);
	}

	string GetDisplayText(int index)
	{
		return GetName(index);
	}
	string GetDescription(int index)
	{
		if(index < 0 || index >= mDecls.length)
			return "";
		string desc = mDecls[index].description;
		desc = replace(desc, "\a", "\n");

		string res = phobosDdocExpand(desc);
		return res;
	}
	string GetName(int index)
	{
		if(index < 0 || index >= mDecls.length)
			return "";
		return mDecls[index].name;
	}

	string GetText(IVsTextView view, int index)
	{
		if(index < 0 || index >= mDecls.length)
			return "";
		string text = mDecls[index].text;
		if(text.indexOf('\a') >= 0)
		{
			string nl = "\r\n";
			if(view)
			{
				// copy indentation from current line
				int line, idx;
				if(view.GetCaretPos(&line, &idx) == S_OK)
				{
					IVsTextLines pBuffer;
					if(view.GetBuffer(&pBuffer) == S_OK)
					{
						nl = GetLineBreakText(pBuffer, line);

						BSTR btext;
						if(pBuffer.GetLineText(line, 0, line, idx, &btext) == S_OK)
						{
							string txt = detachBSTR(btext);
							size_t p = 0;
							while(p < txt.length && std.ascii.isWhite(txt[p]))
								p++;
							nl ~= txt[0 .. p];
						}
						release(pBuffer);
					}
				}
			}
			text = text.replace("\a", nl);
		}
		return text;
	}

	bool GetInitialExtent(IVsTextView textView, int* line, int* startIdx, int* endIdx)
	{
		*line = 0;
		*startIdx = *endIdx = 0;
		return false;
	}
	void GetBestMatch(string textSoFar, int* index, bool *uniqueMatch)
	{
		*index = 0;
		*uniqueMatch = false;
	}
	bool IsCommitChar(string textSoFar, int index, dchar ch)
	{
		return ch == '\n' || ch == '\r'; // !(isAlphaNum(ch) || ch == '_');
	}
	string OnCommit(IVsTextView textView, string textSoFar, dchar ch, int index, ref TextSpan initialExtent)
	{
		return GetText(textView, index); // textSoFar;
	}

	///////////////////////////////////////////////////////////////
	bool ImportExpansions(string imp, string file)
	{
		string[] imports = GetImportPaths(file);

		string dir;
		int dpos = lastIndexOf(imp, '.');
		if(dpos >= 0)
		{
			dir = replace(imp[0 .. dpos], ".", "\\");
			imp = imp[dpos + 1 .. $];
		}

		int namesLength = mDecls.length;
		foreach(string impdir; imports)
		{
			impdir = impdir ~ dir;
			if(!isExistingDir(impdir))
				continue;
			foreach(string name; dirEntries(impdir, SpanMode.shallow))
			{
				string base = baseName(name);
				string ext = toLower(extension(name));
				bool canImport = false;
				bool issubdir = isDir(name);
				if(issubdir)
					canImport = (ext.length == 0);
				else if(ext == ".d" || ext == ".di")
				{
					base = base[0 .. $-ext.length];
					canImport = true;
				}
				if(canImport && base.startsWith(imp))
				{
					Declaration decl;
					decl.name = decl.text = base;
					decl.type = (issubdir ? "DIR" : "MOD");
					addunique(mDecls, decl);
				}
			}
		}
		return mDecls.length > namesLength;
	}

	bool ImportExpansions(IVsTextView textView, Source src)
	{
		int line, idx;
		if(int hr = textView.GetCaretPos(&line, &idx))
			return false;

		wstring wimp = src.GetImportModule(line, idx, true);
		if(wimp.empty)
			return false;
		string txt = to!string(wimp);
		ImportExpansions(txt, src.GetFileName());
		return true;
	}

	///////////////////////////////////////////////////////////////
	string GetWordBeforeCaret(IVsTextView textView, Source src)
	{
		int line, idx;
		int hr = textView.GetCaretPos(&line, &idx);
		assert(hr == S_OK);
		int startIdx, endIdx;
		if(!src.GetWordExtent(line, idx, WORDEXT_FINDTOKEN, startIdx, endIdx))
			return "";
		wstring txt = src.GetText(line, startIdx, line, idx);
		return toUTF8(txt);
	}

	bool NearbyExpansions(IVsTextView textView, Source src)
	{
		if(!Package.GetGlobalOptions().expandFromBuffer)
			return false;

		int line, idx;
		if(int hr = textView.GetCaretPos(&line, &idx))
			return false;
		int lineCount;
		src.mBuffer.GetLineCount(&lineCount);

		//mNames.length = 0;
		int start = max(0, line - kCompletionSearchLines);
		int end = min(lineCount, line + kCompletionSearchLines);

		string tok = GetWordBeforeCaret(textView, src);
		if(tok.length && !dLex.isIdentifierCharOrDigit(tok.front))
			tok = "";

		int iState = src.mColorizer.GetLineState(start);
		if(iState == -1)
			return false;

		int namesLength = mDecls.length;
		for(int ln = start; ln < end; ln++)
		{
			wstring text = src.GetText(ln, 0, ln, -1);
			uint pos = 0;
			while(pos < text.length)
			{
				uint ppos = pos;
				int type = dLex.scan(iState, text, pos);
				if(ln != line || pos < idx || ppos > idx)
					if(type == TokenCat.Identifier || type == TokenCat.Keyword)
					{
						string txt = toUTF8(text[ppos .. pos]);
						if(txt.startsWith(tok))
						{
							Declaration decl;
							decl.name = decl.text = txt;
							addunique(mDecls, decl);
						}
					}
			}
		}
		return mDecls.length > namesLength;
	}

	////////////////////////////////////////////////////////////////////////
	bool SymbolExpansions(IVsTextView textView, Source src)
	{
		if(!Package.GetGlobalOptions().expandFromJSON)
			return false;

		string tok = GetWordBeforeCaret(textView, src);
		if(tok.length && !dLex.isIdentifierCharOrDigit(tok.front))
			tok = "";
		if(!tok.length)
			return false;

		int namesLength = mDecls.length;
		string[] completions = Package.GetLibInfos().findCompletions(tok, true);
		foreach (c; completions)
		{
			Declaration decl;
			decl.name = decl.text = c;
			addunique(mDecls, decl);
		}
		return mDecls.length > namesLength;
	}

	////////////////////////////////////////////////////////////////////////
	bool SnippetExpansions(IVsTextView textView, Source src)
	{
		int line, idx;
		int hr = textView.GetCaretPos(&line, &idx);
		assert(hr == S_OK);
		wstring txt = src.GetText(line, 0, line, -1);
		if(idx > txt.length)
			idx = txt.length;
		int endIdx = idx;
		dchar ch;
		for(size_t p = idx; p > 0 && dLex.isIdentifierCharOrDigit(ch = decodeBwd(txt, p)); idx = p) {}
		int startIdx = idx;
		for(size_t p = idx; p > 0 && std.uni.isWhite(ch = decodeBwd(txt, p)); idx = p) {}
		if (ch == '.')
			return false;
		wstring tok = txt[startIdx .. endIdx];

		IVsTextManager2 textmgr = queryService!(VsTextManager, IVsTextManager2);
		if(!textmgr)
			return false;
		scope(exit) release(textmgr);

		IVsExpansionManager exmgr;
		textmgr.GetExpansionManager(&exmgr);
		if (!exmgr)
			return false;
		scope(exit) release(exmgr);

		int namesLength = mDecls.length;
		IVsExpansionEnumeration enumExp;
		hr = exmgr.EnumerateExpansions(g_languageCLSID, FALSE, null, 0, false, false, &enumExp);
		if(hr == S_OK && enumExp)
		{
			DWORD fetched;
			VsExpansion exp;
			VsExpansion* pexp = &exp;
			while(enumExp.Next(1, &pexp, &fetched) == S_OK && fetched == 1)
			{
				Declaration decl;
				decl.name = detachBSTR(exp.title);
				decl.description = detachBSTR(exp.description);
				decl.text = detachBSTR(exp.shortcut);
				decl.type = "SNPT";
				freeBSTR(exp.path);
				if(decl.text.startsWith(tok))
					addunique(mDecls, decl);
			}
		}
		return mDecls.length > namesLength;
	}

	///////////////////////////////////////////////////////////////////////////

	bool SemanticExpansions(IVsTextView textView, Source src)
	{
		if(!Package.GetGlobalOptions().expandFromSemantics)
			return false;

		try
		{
			string tok = GetWordBeforeCaret(textView, src);
			if(tok.length && !dLex.isIdentifierCharOrDigit(tok.front))
				tok = "";
			if (tok.length && !Package.GetGlobalOptions().exactExpMatch)
				tok ~= "*";

			int caretLine, caretIdx;
			int hr = textView.GetCaretPos(&caretLine, &caretIdx);

			src.ensureCurrentTextParsed(); // pass new text before expansion request

			auto langsvc = Package.GetLanguageService();
			mPendingSource = src;
			mPendingView = textView;
			mPendingRequest = langsvc.GetSemanticExpansions(src, tok, caretLine, caretIdx, &OnExpansions);
			return true;
		}
		catch(Error e)
		{
			writeToBuildOutputPane(e.msg);
		}
		return false;
	}

	extern(D) void OnExpansions(uint request, string filename, string tok, int line, int idx, string[] symbols)
	{
		if(request != mPendingRequest)
			return;

		// without a match, keep existing items
		bool hasMatch = GetCount() > 0 || symbols.length > 0;
		if(hasMatch && mPendingSource && mPendingView)
		{
			auto activeView = GetActiveView();
			scope(exit) release(activeView);

			int caretLine, caretIdx;
			int hr = mPendingView.GetCaretPos(&caretLine, &caretIdx);
			if (activeView == mPendingView && line == caretLine && idx == caretIdx)
			{
				// split after second ':' to combine same name and type
				static string splitName(string name, ref string desc)
				{
					auto pos = name.indexOf(':');
					if(pos < 0)
						return name;
					pos = name.indexOf(':', pos + 1);
					if(pos < 0)
						return name;
					desc = name[pos..$];
					return name[0..pos];
				}

				// go through assoc array for faster uniqueness check
				int[string] decls;

				// add existing declarations
				foreach(i, d; mDecls)
				{
					string desc;
					string name = d.name ~ ":" ~ d.type;
					decls[name] = i;
				}
				size_t num = mDecls.length;
				mDecls.length = num + symbols.length;
				foreach(s; symbols)
				{
					string desc;
					string name = splitName(s, desc);
					if(auto p = name in decls)
						mDecls[*p].description ~= "\a\a" ~ desc[1..$]; // strip ":"
					else
					{
						decls[name] = num;
						mDecls[num++] = Declaration.split(s);
					}
				}
				mDecls.length = num;

				// mode 2 keeps order of semantic engine
				if (Package.GetGlobalOptions().sortExpMode == 1)
					sort!("a.compareByType(b) < 0", SwapStrategy.stable)(mDecls);
				else if (Package.GetGlobalOptions().sortExpMode == 0)
					sort!("a.compareByName(b) < 0", SwapStrategy.stable)(mDecls);

				InitCompletionSet(mPendingView, mPendingSource);
			}
		}
		mPendingRequest = 0;
		mPendingView = null;
		mPendingSource = null;
	}

	uint mPendingRequest;
	IVsTextView mPendingView;
	Source mPendingSource;
	bool mAutoInsert;

	////////////////////////////////////////////////////////////////////////
	bool StartExpansions(IVsTextView textView, Source src, bool autoInsert)
	{
		mDecls = mDecls.init;
		mExpansionState = kStateInit;
		mAutoInsert = autoInsert;

		if(!_MoreExpansions(textView, src))
			return false;

		if(mPendingView)
			return false;

		return InitCompletionSet(textView, src);
	}

	bool InitCompletionSet(IVsTextView textView, Source src)
	{
		if(mAutoInsert)
		{
			while(GetCount() == 1 && _MoreExpansions(textView, src)) {}
			if(GetCount() == 1)
			{
				int line, idx, startIdx, endIdx;
				textView.GetCaretPos(&line, &idx);
				if(src.GetWordExtent(line, idx, WORDEXT_FINDTOKEN, startIdx, endIdx))
				{
					wstring txt = to!wstring(GetText(textView, 0));
					TextSpan changedSpan;
					src.mBuffer.ReplaceLines(line, startIdx, line, endIdx, txt.ptr, txt.length, &changedSpan);
					if (GetGlyph(0) == CSIMG_SNIPPET)
						if (auto view = Package.GetLanguageService().GetViewFilter(src, textView))
							view.HandleSnippet();
					return true;
				}
			}
		}
		src.GetCompletionSet().Init(textView, this, false);
		return true;
	}

	bool _MoreExpansions(IVsTextView textView, Source src)
	{
		switch(mExpansionState)
		{
		case kStateInit:
			if(ImportExpansions(textView, src))
			{
				mExpansionState = kStateSymbols; // do not try other symbols but file imports
				return true;
			}
			goto case;
		case kStateImport:
			SnippetExpansions(textView, src);
			if(SemanticExpansions(textView, src))
			{
				mExpansionState = kStateSemantic;
				return true;
			}
			goto case;
		case kStateSemantic:
			if(NearbyExpansions(textView, src))
			{
				mExpansionState = kStateNearBy;
				return true;
			}
			goto case;
		case kStateNearBy:
			if(SymbolExpansions(textView, src))
			{
				mExpansionState = kStateSymbols;
				return true;
			}
			goto default;
		default:
			break;
		}
		return false;
	}

	bool MoreExpansions(IVsTextView textView, Source src)
	{
		mAutoInsert = false;
		_MoreExpansions(textView, src);
		if (!mPendingView)
			src.GetCompletionSet().Init(textView, this, false);
		return true;
	}

	void StopExpansions()
	{
		mPendingRequest = 0;
		mPendingView = null;
		mPendingSource = null;
	}
}

class CompletionSet : DisposingComObject, IVsCompletionSet, IVsCompletionSet3, IVsCompletionSetEx
{
	HIMAGELIST mImageList;
	bool mDisplayed;
	bool mCompleteWord;
	bool mComittedShortcut;
	string mCommittedWord;
	dchar mCommitChar;
	int mCommitIndex;
	IVsTextView mTextView;
	Declarations mDecls;
	Source mSource;
	TextSpan mInitialExtent;
	bool mIsCommitted;
	bool mWasUnique;
	int mLastDeclCount;

	this(ImageList imageList, Source source)
	{
		mImageList = LoadImageList(g_hInst, MAKEINTRESOURCEA(BMP_COMPLETION), 16, 16);
		mSource = source;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsCompletionSetEx) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsCompletionSet) (this, riid, pvObject))
			return S_OK;

		version(none) if(*riid == uuid_IVsCompletionSet3)
		{
			*pvObject = cast(void*)cast(IVsCompletionSet3)this;
			AddRef();
			return S_OK;
		}

		if(*riid == uuid_IVsCoTaskMemFreeMyStrings) // avoid log message, implement?
			return E_NOTIMPL;
		return super.QueryInterface(riid, pvObject);
	}

	void Init(IVsTextView textView, Declarations declarations, bool completeWord)
	{
		if (mLastDeclCount < declarations.GetCount())
			Close(); // without closing first, the box does not update its width

		mTextView = textView;
		mDecls = declarations;
		mCompleteWord = completeWord;

		//check if we have members
		mLastDeclCount = mDecls.GetCount();
		if (mLastDeclCount <= 0)
			return;

		//initialise and refresh
		UpdateCompletionFlags flags = UCS_NAMESCHANGED;
		if (mCompleteWord)
			flags |= UCS_COMPLETEWORD;

		mWasUnique = false;

		int hr = textView.UpdateCompletionStatus(this, flags);
		assert(hr == S_OK);

		mDisplayed = (!mWasUnique || !completeWord);
	}

	bool isActive()
	{
		return mDisplayed || (mDecls && mDecls.mPendingSource);
	}

	override void Dispose()
	{
		Close();
		//if (imageList != null) imageList.Dispose();
		if(mImageList)
		{
			ImageList_Destroy(mImageList);
			mImageList = null;
		}
	}

	void Close()
	{
		if (mDisplayed && mTextView)
		{
			// Here we can't throw or exit because we need to call Dispose on
			// the disposable membres.
			try {
				mTextView.UpdateCompletionStatus(null, 0);
			} catch (Exception e) {
			}
		}
		mDisplayed = false;
		mComittedShortcut = false;

		mTextView = null;
		mDecls = null;
		mLastDeclCount = 0;
	}


	dchar OnAutoComplete()
	{
		mIsCommitted = false;
		if (mDecls)
			return mDecls.OnAutoComplete(mTextView, mCommittedWord, mCommitChar, mCommitIndex);
		return '\0';
	}

	//--------------------------------------------------------------------------
	//IVsCompletionSet methods
	//--------------------------------------------------------------------------
	override int GetImageList(HANDLE *phImages)
	{
		mixin(LogCallMix);

		*phImages = cast(HANDLE)mImageList;
		return S_OK;
	}

	override int GetFlags()
	{
		mixin(LogCallMix);

		return CSF_HAVEDESCRIPTIONS | CSF_CUSTOMCOMMIT | CSF_INITIALEXTENTKNOWN | CSF_CUSTOMMATCHING;
	}

	override int GetCount()
	{
		mixin(LogCallMix);

		return mDecls.GetCount();
	}

	override int GetDisplayText(in int index, WCHAR** text, int* glyph)
	{
		//mixin(LogCallMix);

		if (glyph)
			*glyph = mDecls.GetGlyph(index);
		*text = allocBSTR(mDecls.GetDisplayText(index));
		return S_OK;
	}

	override int GetDescriptionText(in int index, BSTR* description)
	{
		mixin(LogCallMix2);

		*description = allocBSTR(mDecls.GetDescription(index));
		return S_OK;
	}

	override int GetInitialExtent(int* line, int* startIdx, int* endIdx)
	{
		mixin(LogCallMix);

		int idx;
		int hr = S_OK;
		if (mDecls.GetInitialExtent(mTextView, line, startIdx, endIdx))
			goto done;

		hr = mTextView.GetCaretPos(line, &idx);
		assert(hr == S_OK);
		hr = GetTokenExtent(*line, idx, *startIdx, *endIdx);

	done:
		// Remember the initial extent so we can pass it along on the commit.
		mInitialExtent.iStartLine = mInitialExtent.iEndLine = *line;
		mInitialExtent.iStartIndex = *startIdx;
		mInitialExtent.iEndIndex = *endIdx;

		//assert(TextSpanHelper.ValidCoord(mSource, line, startIdx) &&
		//       TextSpanHelper.ValidCoord(mSource, line, endIdx));
		return hr;
	}

	int GetTokenExtent(int line, int idx, out int startIdx, out int endIdx)
	{
		int hr = S_OK;
		bool rc = mSource.GetWordExtent(line, idx, WORDEXT_FINDTOKEN, startIdx, endIdx);

		if (!rc && idx > 0)
		{
			//rc = mSource.GetWordExtent(line, idx - 1, WORDEXT_FINDTOKEN, startIdx, endIdx);
			if (!rc)
			{
				// Must stop core text editor from looking at startIdx and endIdx since they are likely
				// invalid.  So we must return a real failure here, not just S_FALSE.
				startIdx = endIdx = idx;
				hr = E_NOTIMPL;
			}
		}
		// make sure the span is positive.
		endIdx = max(endIdx, idx);
		return hr;
	}

	override int GetBestMatch(in WCHAR* wtextSoFar, in int length, int* index, uint* flags)
	{
		mixin(LogCallMix);

		*flags = 0;
		*index = 0;

		bool uniqueMatch = false;
		string textSoFar = to_string(wtextSoFar);
		if (textSoFar.length != 0)
		{
			mDecls.GetBestMatch(textSoFar, index, &uniqueMatch);
			if (*index < 0 || *index >= mDecls.GetCount())
			{
				*index = 0;
				uniqueMatch = false;
			} else {
				// Indicate that we want to select something in the list.
				*flags = GBM_SELECT;
			}
		}
		else if (mDecls.GetCount() == 1 && mCompleteWord)
		{
			// Only one entry, and user has invoked "word completion", then
			// simply select this item.
			*index = 0;
			*flags = GBM_SELECT;
			uniqueMatch = true;
		}
		if (uniqueMatch)
		{
			*flags |= GBM_UNIQUE;
			mWasUnique = true;
		}
		return S_OK;
	}

	override int OnCommit(in WCHAR* wtextSoFar, in int index, in BOOL selected, in WCHAR commitChar, BSTR* completeWord)
	{
		mixin(LogCallMix);

		dchar ch = commitChar;
		bool isCommitChar = true;

		int selIndex = (selected == 0) ? -1 : index;
		string textSoFar = to_string(wtextSoFar);
		if (commitChar != 0)
		{
			// if the char is in the list of given member names then obviously it
			// is not a commit char.
			int i = textSoFar.length;
			for (int j = 0, n = mDecls.GetCount(); j < n; j++)
			{
				string name = mDecls.GetText(mTextView, j);
				if (name.length > i && name[i] == commitChar)
				{
					if (i == 0 || name[0 .. i] == textSoFar)
						goto nocommit; // cannot be a commit char if it is an expected char in a matching name
				}
			}
			isCommitChar = mDecls.IsCommitChar(textSoFar, selIndex, ch);
		}

		if (isCommitChar)
		{
			mCommittedWord = mDecls.OnCommit(mTextView, textSoFar, ch, selIndex, mInitialExtent);
			mComittedShortcut = (mDecls.GetGlyph(selIndex) == CSIMG_SNIPPET);
			*completeWord = allocBSTR(mCommittedWord);
			mCommitChar = ch;
			mCommitIndex = index;
			mIsCommitted = true;
			return S_OK;
		}
	nocommit:
		// S_FALSE return means the character is not a commit character.
		*completeWord = allocBSTR(textSoFar);
		return S_FALSE;
	}

	override int Dismiss()
	{
		mixin(LogCallMix);

		mDisplayed = false;
		if (mComittedShortcut)
			if (auto view = Package.GetLanguageService().GetViewFilter(mSource, mTextView))
				view.HandleSnippet();

		mComittedShortcut = false;
		return S_OK;
	}

	// IVsCompletionSetEx Members
	override int CompareItems(in BSTR bstrSoFar, in BSTR bstrOther, in int lCharactersToCompare, int* plResult)
	{
		mixin(LogCallMix);

		*plResult = 0;
		return E_NOTIMPL;
	}

	override int IncreaseFilterLevel(in int iSelectedItem)
	{
		mixin(LogCallMix2);

		return E_NOTIMPL;
	}

	override int DecreaseFilterLevel(in int iSelectedItem)
	{
		mixin(LogCallMix2);

		return E_NOTIMPL;
	}

	override int GetCompletionItemColor(in int iIndex, COLORREF* dwFGColor, COLORREF* dwBGColor)
	{
		mixin(LogCallMix);

		*dwFGColor = *dwBGColor = 0;
		return E_NOTIMPL;
	}

	override int GetFilterLevel(int* iFilterLevel)
	{
		// if implementaed, adds tabs "Common" and "All"
		mixin(LogCallMix2);

		*iFilterLevel = 0;
		return E_NOTIMPL;
	}

	override int OnCommitComplete()
	{
		mixin(LogCallMix);

/+
		if(CodeWindowManager mgr = mSource.LanguageService.GetCodeWindowManagerForView(mTextView))
			if (ViewFilter filter = mgr.GetFilter(mTextView))
				filter.OnAutoComplete();
+/
		return S_OK;
	}

	// IVsCompletionSet3 adds icons on the right side of the completion list
	override HRESULT GetContextIcon(in int iIndex, int *piGlyph)
	{
		mixin(LogCallMix);

		*piGlyph = CSIMG_MEMBER;
		return S_OK;
	}

	override HRESULT GetContextImageList (HANDLE *phImageList)
	{
		mixin(LogCallMix);

		*phImageList = cast(HANDLE)mImageList;
		return S_OK;
	}
}

//-------------------------------------------------------------------------------------
class MethodData : DisposingComObject, IVsMethodData
{
	IServiceProvider mProvider;
	IVsMethodTipWindow mMethodTipWindow;

	Definition[] mMethods;
	bool mTypePrefixed = true;
	int mCurrentParameter;
	int mCurrentMethod;
	bool mDisplayed;
	IVsTextView mTextView;
	TextSpan mContext;

	this()
	{
		auto uuid = uuid_coclass_VsMethodTipWindow;
		mMethodTipWindow = VsLocalCreateInstance!IVsMethodTipWindow (&uuid, CLSCTX_INPROC_SERVER);
		if (mMethodTipWindow)
			mMethodTipWindow.SetMethodData(this);
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsMethodData) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	void Refresh(IVsTextView textView, Definition[] methods, int currentParameter, TextSpan context)
	{
		if (!mDisplayed)
			mCurrentMethod = 0; // methods.DefaultMethod;

		mContext = context;
		mMethods = mMethods.init;
	defLoop:
		foreach(ref def; methods)
		{
			foreach(ref d; mMethods)
				if(d.type == def.type)
				{
					if (!d.inScope.endsWith(" ..."))
						d.inScope ~= " ...";
					continue defLoop;
				}
			mMethods ~= def;
		}

		// Apparently this Refresh() method is called as a result of event notification
		// after the currentMethod is changed, so we do not want to Dismiss anything or
		// reset the currentMethod here.
		//Dismiss();
		mTextView = textView;

		mCurrentParameter = currentParameter;
		AdjustCurrentParameter(0);
	}

	void AdjustCurrentParameter(int increment)
	{
		mCurrentParameter += increment;
		if (mCurrentParameter < 0)
			mCurrentParameter = -1;
		else if (mCurrentParameter >= GetParameterCount(mCurrentMethod))
			mCurrentParameter = GetParameterCount(mCurrentMethod);

		UpdateView();
	}

	void Close()
	{
		Dismiss();
		mTextView = null;
		mMethods = null;
	}

	void Dismiss()
	{
		if (mDisplayed && mTextView)
			mTextView.UpdateTipWindow(mMethodTipWindow, UTW_DISMISS);

		OnDismiss();
	}

	override void Dispose()
	{
		Close();
		if (mMethodTipWindow)
			mMethodTipWindow.SetMethodData(null);
		mMethodTipWindow = release(mMethodTipWindow);
	}

    //IVsMethodData
	override int GetOverloadCount()
	{
		if (!mTextView || mMethods.length == 0)
			return 0;
		return mMethods.length;
	}

	override int GetCurMethod()
	{
		return mCurrentMethod;
	}

	override int NextMethod()
	{
		if (mCurrentMethod < GetOverloadCount() - 1)
			mCurrentMethod++;
		else
			mCurrentMethod = 0;
		return mCurrentMethod;
	}

	override int PrevMethod()
	{
		if (mCurrentMethod > 0)
			mCurrentMethod--;
		else
			mCurrentMethod = GetOverloadCount() - 1;
		return mCurrentMethod;
	}

	override int GetParameterCount(in int method)
	{
		if (mMethods.length == 0)
			return 0;
		if (method < 0 || method >= GetOverloadCount())
			return 0;

		return mMethods[method].GetParameterCount();
	}

	override int GetCurrentParameter(in int method)
	{
		return mCurrentParameter;
	}

	override void OnDismiss()
	{
		mTextView = null;
		mMethods = mMethods.init;
		mCurrentMethod = 0;
		mCurrentParameter = 0;
		mDisplayed = false;
	}

	override void UpdateView()
	{
		if (mTextView && mMethodTipWindow)
		{
			mTextView.UpdateTipWindow(mMethodTipWindow, UTW_CONTENTCHANGED | UTW_CONTEXTCHANGED);
			mDisplayed = true;
		}
	}

	override int GetContextStream(int* pos, int* length)
	{
		*pos = 0;
		*length = 0;
		int line, idx, vspace, endpos;
		if(HRESULT rc = mTextView.GetCaretPos(&line, &idx))
			return rc;

		line = max(line, mContext.iStartLine);
		if(HRESULT rc = mTextView.GetNearestPosition(line, mContext.iStartIndex, pos, &vspace))
			return rc;

		line = max(line, mContext.iEndLine);
		if(HRESULT rc = mTextView.GetNearestPosition(line, mContext.iEndIndex, &endpos, &vspace))
			return rc;

		*length = endpos - *pos;
		return S_OK;
	}

	override WCHAR* GetMethodText(in int method, in MethodTextType type)
	{
		if (mMethods.length == 0)
			return null;
		if (method < 0 || method >= GetOverloadCount())
			return null;

		string result;

		//a type
		if ((type == MTT_TYPEPREFIX && mTypePrefixed) ||
			(type == MTT_TYPEPOSTFIX && !mTypePrefixed))
		{
			string str = mMethods[method].GetReturnType();

			if (str.length == 0)
				return null;

			result = str; // mMethods.TypePrefix + str + mMethods.TypePostfix;
		}
		else
		{
			//other
			switch (type) {
			case MTT_OPENBRACKET:
				result = "("; // mMethods.OpenBracket;
				break;

			case MTT_CLOSEBRACKET:
				result = ")"; // mMethods.CloseBracket;
				string constraint = mMethods[method].GetConstraint();
				if (constraint.length)
					result ~= " " ~ constraint;
				break;

			case MTT_DELIMITER:
				result = ","; // mMethods.Delimiter;
				break;

			case MTT_NAME:
				result = mMethods[method].name;
				break;

			case MTT_DESCRIPTION:
				if(mMethods[method].help.length)
					result = phobosDdocExpand(mMethods[method].help);
				else if(mMethods[method].line > 0)
					result = format("%s %s @ %s(%d)", mMethods[method].kind, mMethods[method].inScope, mMethods[method].filename, mMethods[method].line);
				break;

			case MTT_TYPEPREFIX:
			case MTT_TYPEPOSTFIX:
			default:
				break;
			}
		}

		return result.length == 0 ? null : allocBSTR(result); // produces leaks?
	}

	override WCHAR* GetParameterText(in int method, in int parameter, in ParameterTextType type)
	{
		if (mMethods.length == 0)
			return null;
		if (method < 0 || method >= GetOverloadCount())
			return null;
		if (parameter < 0 || parameter >= GetParameterCount(method))
			return null;

		string name;
		string description;
		string display;

		mMethods[method].GetParameterInfo(parameter, name, display, description);

		string result;

		switch (type) {
		case PTT_NAME:
			result = name;
			break;

		case PTT_DESCRIPTION:
			result = description;
			break;

		case PTT_DECLARATION:
			result = display;
			break;

		default:
			break;
		}
		return result.length == 0 ? null : allocBSTR(result); // produces leaks?
	}
}
