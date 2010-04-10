// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module completion;

import std.c.windows.windows;
import std.c.windows.com;
import std.ctype;
import std.string;
import std.utf;
import std.file;
import std.path;

version(D_Version2) import std.algorithm;
else import std.math2;

import comutil;
import logutil;
import hierutil;
import fileutil;
import simplelexer;
import dpackage;
import dproject;
import dlangsvc;
import dimagelist;
import config;

import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.vsshell;

///////////////////////////////////////////////////////////////

const int kCompletionSearchLines = 500;

///////////////////////////////////////////////////////////////
Config getProjectConfig(string file)
{
	auto srpSolution = queryService!(IVsSolution);
	scope(exit) release(srpSolution);
	auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
	scope(exit) release(solutionBuildManager);

	if(srpSolution && solutionBuildManager)
	{
		scope auto wfile = _toUTF16z(file);
		IEnumHierarchies pEnum;
		if(srpSolution.GetProjectEnum(EPF_LOADEDINSOLUTION|EPF_MATCHTYPE, &g_projectFactoryCLSID, &pEnum) == S_OK)
		{
			scope(exit) release(pEnum);
			IVsHierarchy pHierarchy;
			while(pEnum.Next(1, &pHierarchy, null) == S_OK)
			{
				scope(exit) release(pHierarchy);
				VSITEMID itemid;
				if(pHierarchy.ParseCanonicalName(wfile, &itemid) == S_OK)
				{
					IVsProjectCfg activeCfg;
					if(solutionBuildManager.FindActiveProjectCfg(null, null, pHierarchy, &activeCfg) == S_OK)
					{
						scope(exit) release(activeCfg);
						if(Config cfg = qi_cast!Config(activeCfg))
							return cfg;
					}
				}
			}
		}
	}
	return null;
}

class ImageList {};

struct Declaration
{
}

class Declarations
{
	string[] mNames;
	string[] mDescriptions;
	int[] mGlyphs;

	this()
	{
	}

	int GetCount()
	{
		return mNames.length;
	}

	dchar OnAutoComplete(IVsTextView textView, string committedWord, dchar commitChar, int commitIndex)
	{ 
		return 0;
	}
	int GetGlyph(int index)
	{
		if(index < 0 || index >= mGlyphs.length)
			return 0;
		return mGlyphs[index];
	}
	string GetDisplayText(int index)
	{
		return GetName(index);
	}
	string GetDescription(int index)
	{
		if(index < 0 || index >= mDescriptions.length)
			return "";
		return mDescriptions[index];
	}
	string GetName(int index)
	{
		if(index < 0 || index >= mNames.length)
			return "";
		return mNames[index];
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
		return ch == '\n' || ch == '\r'; // !(isalnum(ch) || ch == '_');
	}
	string OnCommit(IVsTextView textView, string textSoFar, dchar ch, int index, ref TextSpan initialExtent)
	{
		return GetName(index); // textSoFar;
	}

	///////////////////////////////////////////////////////////////
	string[] GetImportPaths(string file)
	{
		string[] imports;
		if(Config cfg = getProjectConfig(file))
		{
			scope(exit) release(cfg);
			ProjectOptions opt = cfg.GetProjectOptions();
			string imp = cfg.GetProjectOptions().imppath;
			imp = opt.replaceEnvironment(imp, cfg);
			imports = split(imp, ";");
			string projectpath = cfg.GetProjectDir();
			makeFilenamesAbsolute(imports, projectpath);
			addunique(imports, projectpath);
		}
		imports ~= Package.GetGlobalOptions().getImportPaths();
		return imports;
	}

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

		mNames = mNames.init;
		foreach(string impdir; imports)
		{
			impdir = impdir ~ dir;
			foreach(string name; dirEntries(impdir, SpanMode.shallow))
			{
				string base = getBaseName(name);
				string ext = tolower(getExt(name));
				bool canImport = false;
				bool dir = isdir(name);
				if(dir)
					canImport = (ext.length == 0);
				else if(ext == "d" || ext == "di")
				{
					base = base[0 .. $-1-ext.length];
					canImport = true;
				}
				if(canImport && base.startsWith(imp) && array_find(mNames, base) < 0)
				{
					mNames ~= base;
					mGlyphs ~= dir ? kImageFolderClosed : kImageDSource;
				}
			}
		}
		return mNames.length > 0;
	}

	bool ImportExpansions(IVsTextView textView, Source src)
	{
		int line, idx;
		if(int hr = textView.GetCaretPos(&line, &idx))
			return false;

		TokenInfo[] info = src.GetLineInfo(line);
		if(info.length <= 0)
			return false;
		
		wstring text = src.GetText(line, 0, line, -1);
		int t = 0;
		while(t < info.length)
		{
			wstring tok = text[ info[t].StartIndex .. info[t].EndIndex ];
			if(tok == "import")
				break;
			if(tok != "public" && tok != "static" && tok != "private")
				return false;
			t++;
		}
		if(t >= info.length)
			return false; // no import found
		if(idx < info[t].EndIndex)
			return false; // not after import

		string txt = toUTF8(text[info[t].EndIndex .. idx]);
		txt = strip(txt);
		return ImportExpansions(txt, src.GetFileName());
	}

	///////////////////////////////////////////////////////////////
	string GetTokenBeforeCaret(IVsTextView textView, Source src)
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
		int line, idx;
		if(int hr = textView.GetCaretPos(&line, &idx))
			return false;
		int lineCount;
		src.mBuffer.GetLineCount(&lineCount);

		mNames.length = 0;
		int start = max(0, line - kCompletionSearchLines);
		int end = min(lineCount, line + kCompletionSearchLines);

		string tok = GetTokenBeforeCaret(textView, src);
		if(tok.length && !isalnum(tok[0]) && tok[0] != '_')
			tok = "";

		for(int ln = start; ln < end; ln++)
		{
			int iState = src.mColorizer.GetLineState(ln);
			if(iState < 0)
				break;

			wstring text = src.GetText(ln, 0, ln, -1);
			uint pos = 0;
			while(pos < text.length)
			{
				uint ppos = pos;
				int type = SimpleLexer.scan(iState, text, pos);
				if(ln != line || pos < idx || ppos > idx)
					if(type == TokenColor.Identifier || type == TokenColor.Keyword)
					{
						string txt = toUTF8(text[ppos .. pos]);
						if(txt.startsWith(tok) && array_find(mNames, txt) < 0)
							mNames ~= txt;
					}
			}
		}
		return mNames.length > 0;
	}
}

class CompletionSet : DisposingComObject, IVsCompletionSet, IVsCompletionSetEx
{
	HIMAGELIST mImageList;
	bool mDisplayed;
	bool mCompleteWord;
	string mCommittedWord;
	dchar mCommitChar;
	int mCommitIndex;
	IVsTextView mTextView;
	Declarations mDecls;
	Source mSource;
	TextSpan mInitialExtent;
	bool mIsCommitted;
	bool mWasUnique;

	this(ImageList imageList, Source source)
	{
		mImageList = ImageList_LoadImageA(g_hInst, kImageBmp, 16, 10, CLR_DEFAULT,
						  IMAGE_BITMAP, LR_LOADTRANSPARENT);
		mSource = source;
	}

	override HRESULT QueryInterface(IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsCompletionSetEx) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsCompletionSet) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	void Init(IVsTextView textView, Declarations declarations, bool completeWord)
	{
		Close();
		mTextView = textView;
		mDecls = declarations;
		mCompleteWord = completeWord;

		//check if we have members
		int count = mDecls.GetCount();
		if (count <= 0) return;

		//initialise and refresh      
		UpdateCompletionFlags flags = UCS_NAMESCHANGED;
		if (mCompleteWord)
			flags |= UCS_COMPLETEWORD;

		mWasUnique = false;

		int hr = textView.UpdateCompletionStatus(this, flags);
		assert(hr == S_OK);

		mDisplayed = (!mWasUnique || !completeWord);
	}

	void Dispose()
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
		mTextView = null;
		mDecls = null;
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
		mixin(LogCallMix);

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

		int hr = S_OK;
		if (mDecls.GetInitialExtent(mTextView, line, startIdx, endIdx))
			goto done;

		int idx;
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
		
		string textSoFar = to_string(wtextSoFar);
		if (commitChar != 0)
		{
			// if the char is in the list of given member names then obviously it
			// is not a commit char.
			int i = textSoFar.length;
			for (int j = 0, n = mDecls.GetCount(); j < n; j++)
			{
				string name = mDecls.GetName(j);
				if (name.length > i && name[i] == commitChar)
				{
					if (i == 0 || name[0 .. i] == textSoFar)
						goto nocommit; // cannot be a commit char if it is an expected char in a matching name
				}
			}
			isCommitChar = mDecls.IsCommitChar(textSoFar, (selected == 0) ? -1 : index, ch);
		}

		if (isCommitChar)
		{
			mCommittedWord = mDecls.OnCommit(mTextView, textSoFar, ch, selected == 0 ? -1 : index, mInitialExtent);
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
}

/+
    //-------------------------------------------------------------------------------------
    public class MethodData : IVsMethodData, IDisposable {
        IServiceProvider provider;
        IVsMethodTipWindow methodTipWindow;
        Methods methods;
        int currentParameter;
        int currentMethod;
        bool displayed;
        IVsTextView textView;
        TextSpan context;

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.MethodData"]/*' />
        public MethodData(IServiceProvider site) {
            mProvider = site;
            Microsoft.VisualStudio.Shell.Package pkg = (Microsoft.VisualStudio.Shell.Package)site.GetService(typeof(Microsoft.VisualStudio.Shell.Package));
            if (pkg == null) {
                throw new NullReferenceException(typeof(Microsoft.VisualStudio.Shell.Package).FullName);
            }
            Guid riid = typeof(IVsMethodTipWindow).GUID;
            Guid clsid = typeof(VsMethodTipWindowClass).GUID;
            mMethodTipWindow = (IVsMethodTipWindow)pkg.CreateInstance(ref clsid, ref riid, typeof(IVsMethodTipWindow));
            if (mMethodTipWindow != null) {
                NativeMethods.ThrowOnFailure(methodTipWindow.SetMethodData(this));
            }
        }
        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.Provider;"]/*' />
        protected IServiceProvider Provider {
            get { return mProvider; }
            set { mProvider = value; }
        }
        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.MethodTipWindow;"]/*' />
        protected IVsMethodTipWindow MethodTipWindow {
            get { return mMethodTipWindow; }
            set { mMethodTipWindow = value; }
        }
        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.Methods;"]/*' />
        protected Methods Methods {
            get { return mMethods; }
            set { mMethods = value; }
        }
        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.TextView;"]/*' />
        protected IVsTextView TextView {
            get { return mTextView; }
            set { mTextView = value; }
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.IsDisplayed"]/*' />
        public bool IsDisplayed {
            get {
                return mDisplayed;
            }
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.Refresh"]/*' />
        public void Refresh(IVsTextView textView, Methods methods, int currentParameter, TextSpan context) {
            if (!mDisplayed) {
                mCurrentMethod = methods.DefaultMethod;
            }
            mMethods = methods;
            mContext = context;

            // Apparently this Refresh() method is called as a result of event notification
            // after the currentMethod is changed, so we do not want to Dismiss anything or
            // reset the currentMethod here. 
            //Dismiss();  
            mTextView = textView;
            mMethods = methods;

            mCurrentParameter = currentParameter;
            mAdjustCurrentParameter(0);
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.AdjustCurrentParameter"]/*' />
        public void AdjustCurrentParameter(int increment) {
            mCurrentParameter += increment;
            if (mCurrentParameter < 0)
                mCurrentParameter = -1;
            else if (mCurrentParameter >= mGetParameterCount(mCurrentMethod))
                mCurrentParameter = mGetParameterCount(mCurrentMethod);

            mUpdateView();
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.Close"]/*' />
        public void Close() {
            mDismiss();
            mTextView = null;
            mMethods = null;
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.Dismiss"]/*' />
        public void Dismiss() {
            if (mDisplayed && mTextView != null) {
                NativeMethods.ThrowOnFailure(mTextView.UpdateTipWindow(mMethodTipWindow, (uint)TipWindowFlags.UTW_DISMISS));
            }

            mOnDismiss();
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.Dispose"]/*' />
        public virtual void Dispose() {
            Close();
            if (mMethodTipWindow != null)
                NativeMethods.ThrowOnFailure(mMethodTipWindow.SetMethodData(null));
            mMethodTipWindow = null;
            mProvider = null;
        }

        //========================================================================
        //IVsMethodData
        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.GetOverloadCount"]/*' />
        public int GetOverloadCount() {
            if (mTextView == null || mMethods == null) return 0;
            return mMethods.GetCount();
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.GetCurMethod"]/*' />
        public int GetCurMethod() {
            return mCurrentMethod;
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.NextMethod"]/*' />
        public int NextMethod() {
            if (mCurrentMethod < GetOverloadCount() - 1) mCurrentMethod++;

            return mCurrentMethod;
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.PrevMethod"]/*' />
        public int PrevMethod() {
            if (mCurrentMethod > 0) mCurrentMethod--;

            return mCurrentMethod;
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.GetParameterCount"]/*' />
        public int GetParameterCount(int method) {
            if (mMethods == null) return 0;

            if (method < 0 || method >= GetOverloadCount()) return 0;

            return mMethods.GetParameterCount(method);
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.GetCurrentParameter"]/*' />
        public int GetCurrentParameter(int method) {
            return mCurrentParameter;
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.OnDismiss"]/*' />
        public void OnDismiss() {
            mTextView = null;
            mMethods = null;
            mCurrentMethod = 0;
            mCurrentParameter = 0;
            mDisplayed = false;
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.UpdateView"]/*' />
        public void UpdateView() {
            if (mTextView != null) {
                NativeMethods.ThrowOnFailure(mTextView.UpdateTipWindow(mMethodTipWindow, (uint)TipWindowFlags.UTW_CONTENTCHANGED | (uint)TipWindowFlags.UTW_CONTEXTCHANGED));
                mDisplayed = true;
            }
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.GetContextStream"]/*' />
        public int GetContextStream(out int pos, out int length) {
            pos = 0;
            length = 0;
            int line, idx;
            NativeMethods.ThrowOnFailure(mTextView.GetCaretPos(out line, out idx));
            line = Math.Max(line, mContext.iStartLine);
            int vspace;
            NativeMethods.ThrowOnFailure(mTextView.GetNearestPosition(line, mContext.iStartIndex, out pos, out vspace));
            line = Math.Max(line, mContext.iEndLine);
            int endpos;
            NativeMethods.ThrowOnFailure(mTextView.GetNearestPosition(line, mContext.iEndIndex, out endpos, out vspace));
            length = endpos - pos;
            return NativeMethods.S_OK;
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.GetMethodText"]/*' />
        public IntPtr GetMethodText(int method, MethodTextType type) {
            if (mMethods == null) return IntPtr.Zero;

            if (method < 0 || method >= GetOverloadCount()) return IntPtr.Zero;

            string result = null;

            //a type
            if ((type == MethodTextType.MTT_TYPEPREFIX && mMethods.TypePrefixed) ||
                (type == MethodTextType.MTT_TYPEPOSTFIX && !mMethods.TypePrefixed)) {
                string str = mMethods.GetType(method);

                if (str == null) return IntPtr.Zero;

                result = mMethods.TypePrefix + str + mMethods.TypePostfix;
            } else {
                //other
                switch (type) {
                case MethodTextType.MTT_OPENBRACKET:
                result = mMethods.OpenBracket;
                break;

                case MethodTextType.MTT_CLOSEBRACKET:
                result = mMethods.CloseBracket;
                break;

                case MethodTextType.MTT_DELIMITER:
                result = mMethods.Delimiter;
                break;

                case MethodTextType.MTT_NAME:
                result = mMethods.GetName(method);
                break;

                case MethodTextType.MTT_DESCRIPTION:
                result = mMethods.GetDescription(method);
                break;

                case MethodTextType.MTT_TYPEPREFIX:
                case MethodTextType.MTT_TYPEPOSTFIX:
                default:
                break;
                }
            }

            return result == null ? IntPtr.Zero : Marshal.StringToBSTR(result);
        }

        /// <include file='doc\Source.uex' path='docs/doc[@for="MethodData.GetParameterText"]/*' />
        public IntPtr GetParameterText(int method, int parameter, ParameterTextType type) {
            if (mMethods == null) return IntPtr.Zero;

            if (method < 0 || method >= GetOverloadCount()) return IntPtr.Zero;

            if (parameter < 0 || parameter >= GetParameterCount(method)) return IntPtr.Zero;

            string name;
            string description;
            string display;

            mMethods.GetParameterInfo(method, parameter, out name, out display, out description);

            string result = null;

            switch (type) {
            case ParameterTextType.PTT_NAME:
            result = name;
            break;

            case ParameterTextType.PTT_DESCRIPTION:
            result = description;
            break;

            case ParameterTextType.PTT_DECLARATION:
            result = display;
            break;

            default:
            break;
            }
            return result == null ? IntPtr.Zero : Marshal.StringToBSTR(result);
        }
    }
+/