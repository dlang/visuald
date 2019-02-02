// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.colorizer;

import visuald.windows;
import std.string;
import std.ascii;
import std.utf;
import std.conv;
import std.algorithm;
import std.datetime;
static import std.file;

import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.fileutil;
import visuald.stringutil;
import visuald.pkgutil;
import visuald.simpleparser;
import visuald.dpackage;
import visuald.dlangsvc;
import visuald.config;

import vdc.lexer;
import vdc.versions;

import stdext.string;

import sdk.port.vsi;
import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;
import sdk.vsi.vsshell80;

// version = LOG;

enum TokenColor
{
	// assumed to match lexer.TokenCat and colorableItems in dlangsvc.d
	Text       = cast(int) TokenCat.Text,
	Keyword    = TokenCat.Keyword,
	Comment    = TokenCat.Comment,
	Identifier = TokenCat.Identifier,
	String     = TokenCat.String,
	Literal    = TokenCat.Literal,
	Text2      = TokenCat.Text2,
	Operator   = TokenCat.Operator,

	// colorizer specifics:
	AsmRegister,
	AsmMnemonic,
	UserType,
	Interface,
	Enum,
	EnumValue,
	Template,
	Class,
	Struct,
	Union,
	TemplateTypeParameter,

	Constant,
	LocalVariable,
	ParameterVariable,
	TLSVariable,
	SharedVariable,
	GSharedVariable,
	MemberVariable,
	Variable,

	Alias,
	Module,
	Function,
	Method,
	BasicType,

	Version,

	DisabledKeyword,
	DisabledComment,
	DisabledIdentifier,
	DisabledString,
	DisabledLiteral,
	DisabledText,
	DisabledOperator,
	DisabledAsmRegister,
	DisabledAsmMnemonic,
	DisabledUserType,
	DisabledVersion,

	StringKeyword,
	StringComment,
	StringIdentifier,
	StringString,
	StringLiteral,
	StringText,
	StringOperator,
	StringAsmRegister,
	StringAsmMnemonic,
	StringUserType,
	StringVersion,

	CoverageKeyword,
	NonCoverageKeyword,
}

int[wstring] parseUserTypes(string spec)
{
	int color = TokenColor.UserType;
	int[wstring] types;
	types["__ctfe"] = TokenColor.Keyword;
	foreach(t; tokenizeArgs(spec))
	{
		switch(t)
		{
			case "[Keyword]":	 color = TokenColor.Keyword;	break;
			case "[Comment]":	 color = TokenColor.Comment;	break;
			case "[Identifier]": color = TokenColor.Identifier; break;
			case "[String]":	 color = TokenColor.String;		break;
			case "[Number]":	 color = TokenColor.Literal;	break;
			case "[Text]":		 color = TokenColor.Text;		break;

			case "[Operator]":	 color = TokenColor.Operator;	break;
			case "[Register]":	 color = TokenColor.AsmRegister;break;
			case "[Mnemonic]":	 color = TokenColor.AsmMnemonic;break;
			case "[Type]":		 color = TokenColor.UserType;	break;
			case "[Version]":	 color = TokenColor.Version;	break;

			default: types[to!wstring(t)] = color; break;
		}
	}
	return types;
}

///////////////////////////////////////////////////////////////////////////////

class ColorableItem : DComObject, IVsColorableItem, IVsHiColorItem
{
	private string mDisplayName;
	private COLORINDEX mBackground;
	private COLORINDEX mForeground;

	private COLORREF mRgbForeground;
	private COLORREF mRgbBackground;

	this(string displayName, COLORINDEX foreground, COLORINDEX background,
	     COLORREF rgbForeground = 0, COLORREF rgbBackground = 0)
	{
		mDisplayName = displayName;
		mBackground = background;
		mForeground = foreground;
		mRgbForeground = rgbForeground;
		mRgbBackground = rgbBackground;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsColorableItem) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsHiColorItem) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsColorableItem
	HRESULT GetDefaultColors(/+[out]+/ COLORINDEX *piForeground, /+[out]+/ COLORINDEX *piBackground)
	{
		if(!piForeground || !piBackground)
			return E_INVALIDARG;

		*piForeground = mForeground;
		*piBackground = mBackground;
		return S_OK;
	}

	HRESULT GetDefaultFontFlags(/+[out]+/ DWORD *pdwFontFlags) // see FONTFLAGS enum
	{
		if(!pdwFontFlags)
			return E_INVALIDARG;

		*pdwFontFlags = 0;
		return S_OK;
	}

	HRESULT GetDisplayName(/+[out]+/ BSTR * pbstrName)
	{
		if(!pbstrName)
			return E_INVALIDARG;

		*pbstrName = allocBSTR(mDisplayName);
		return S_OK;
	}

	// IVsHiColorItem
	HRESULT GetColorData(in VSCOLORDATA cdElement, /+[out]+/ COLORREF* pcrColor)
	{
		if(cdElement == CD_FOREGROUND && mForeground == -1)
		{
			*pcrColor = mRgbForeground;
			return S_OK;
		}
		if(cdElement == CD_BACKGROUND && mBackground == -1)
		{
			*pcrColor = mRgbBackground;
			return S_OK;
		}
		return E_NOTIMPL;
	}

	final HRESULT SetDefaultForegroundColor(COLORREF color)
	{
		mRgbForeground = color;
		return S_OK;
	}
	final string GetDisplayName()
	{
		return mDisplayName;
	}

}

class Colorizer : DisposingComObject, IVsColorizer, ConfigModifiedListener
{
	// mLineState keeps track of evaluated states, assuming the interesting lines have been processed
	//  after the last changes
	// the lower 20 bits are used by the lexer, the upper 12 bits encode the version state
	//  TBBB_BBBB_PPPP
	//  PPPP - version parse state
	//  BBBB - brace count
	//  T    - toggle bit to force change
	int[] mLineState;
	int mLastValidLine;

	Source mSource;
	ParserBase!wstring mParser;
	Config mConfig;
	bool mColorizeVersions;
	bool mColorizeCoverage;
	bool mParseSource;

	enum int kIndexVersion = 0;
	enum int kIndexDebug   = 1;

	// index 0 for version, index 1 for debug
	int[wstring][2] mVersionIds; // positive: lineno defined
	int[2] mVersionLevel = [ -1, -1 ];
	int[2] mVersionLevelLine = [ -2, -2 ];  // -2 never defined, -1 if set on command line

	int[wstring] mDebugIds; // positive: lineno defined
	int mDebugLevel = -1;
	int mDebugLevelLine = -2;  // -2 never defined, -1 if set on command line

	string[2] mConfigVersions;
	ubyte mConfigRelease;
	bool mConfigUnittest;
	bool mConfigX64;
	bool mConfigMSVCRT;
	bool mConfigCoverage;
	bool mConfigDoc;
	ubyte mConfigBoundsCheck;
	ubyte mConfigCompiler;

	int[] mCoverage;
	float mCoveragePercent;
	string  mLastCoverageFile;
	SysTime mLastTestCoverageFile;
	SysTime mLastModifiedCoverageFile;

	enum VersionParseState
	{
		IdleEnabled,
		IdleDisabled,
		IdleEnabledVerify,         // verify enable state on next token
		IdleDisabledVerify,
		VersionParsed,             // version, expecting = or (
		AssignParsed,              // version=, expecting identifier or number
		ParenLParsed,              // version(, expecting identifier or number
		IdentNumberParsedEnable,   // version(identifier|number, expecting )
		IdentNumberParsedDisable,  // version(identifier|number, expecting )
		ParenRParsedEnable,        // version(identifier|number), check for '{'
		ParenRParsedDisable,       // version(identifier|number), check for '{'
		AsmParsedEnabled,          // enabled asm, expecting {
		AsmParsedDisabled,         // disabled asm, expecting {
		InAsmBlockEnabled,         // inside asm {}, expecting {
		InAsmBlockDisabled,        // inside disabled asm {}, expecting {
	}
	static assert(VersionParseState.max <= 15);

	this(Source src)
	{
		mSource = src;
		mParser = new ParserBase!wstring;

		mColorizeVersions = Package.GetGlobalOptions().ColorizeVersions;
		mColorizeCoverage = Package.GetGlobalOptions().ColorizeCoverage;
		mParseSource = Package.GetGlobalOptions().parseSource;
		UpdateConfig();

		UpdateCoverage(true);
	}

	~this()
	{
	}

	override void Dispose()
	{
		if(mConfig)
		{
			mConfig.RemoveModifiedListener(this);
			mConfig = null;
		}
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsColorizer) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsColorizer //////////////////////////////////////
	override int GetStateMaintenanceFlag(BOOL* pfFlag)
	{
		// version(LOG) mixin(LogCallMix2);

		*pfFlag = false;
		return S_OK;
	}

	override int GetStartState(int* piStartState)
	{
		version(LOG) mixin(LogCallMix2);

		*piStartState = 0;
		return S_OK;
	}

	override int ColorizeLine(in int iLine, in int iLength, in wchar* pText, in int iState, uint* pAttributes)
	{
		bool versionsChanged = false;
		int state = GetLineState(iLine);
		GetLineState(iLine + 1); // ensure the line has been parsed
		wstring text = to_cwstring(pText, iLength);

		version(LOG) logCall("%s.ColorizeLine(%d,%x): %s", this, iLine, state, text);
		version(LOG) mixin(_LogIndentNoRet);

		uint pos = 0;
		bool inTokenString = (Lexer.tokenStringLevel(state) > 0);

		int cov = -1;
		int covtype = TokenColor.CoverageKeyword;
		if(mColorizeCoverage && mCoverage.length)
		{
			int covLine = mSource.adjustLineNumberSinceLastBuildReverse(iLine, true);
			cov = covLine >= mCoverage.length ? -1 : mCoverage[covLine];
			covtype = cov == 0 ? TokenColor.NonCoverageKeyword : TokenColor.CoverageKeyword;
		}
		int back = 0; // COLOR_MARKER_MASK;
		LanguageService langsvc = Package.GetLanguageService();
		while(pos < iLength)
		{
			uint prevpos = pos;
			int type = dLex.scan(state, text, pos);
			bool nowInTokenString = (Lexer.tokenStringLevel(state) > 0);
			wstring tok = text[prevpos..pos];

			ParserSpan span;
			if (pos >= text.length)
				span = ParserSpan(prevpos, iLine, 0, iLine + 1);
			else
				span = ParserSpan(prevpos, iLine, pos, iLine);

			if(tok[0] == 'i')
				if(tok == "in" || tok == "is")
				{
					if(langsvc.isBinaryOperator(mSource, iLine + 1, prevpos, iLine + 1, pos))
						type = userColorType(tok, TokenColor.Operator);
					else
						type = TokenColor.Keyword;
				}

			if (type == TokenColor.Identifier)
				type = mSource.getIdentifierColor(tok, iLine + 1, prevpos);

			if(cov >= 0)
			{
				type = covtype;
			}
			else
			{
				if(mColorizeVersions)
				{
					if(Lexer.isCommentOrSpace(type, tok) || (inTokenString || nowInTokenString))
					{
						int parseState = getParseState(state);
						if(type == TokenColor.Identifier || type == TokenColor.Keyword)
							type = userColorType(tok, type);
						if(parseState == VersionParseState.IdleDisabled || parseState == VersionParseState.IdleDisabledVerify)
							type = disabledColorType(type);
					}
					else
					{
						type = parseVersions(span, type, tok, state, versionsChanged);
					}
				}
				if(inTokenString || nowInTokenString)
					type = stringColorType(type);
				//else if(mParseSource)
				//	type = parseErrors(span, type, tok);
			}
			inTokenString = nowInTokenString;

			while(prevpos < pos)
				pAttributes[prevpos++] = type | back;
		}
		pAttributes[iLength] = (cov >= 0 ? covtype : TokenColor.Text) | back;

		return S_OK;
	}

	override int GetStateAtEndOfLine(in int iLine, in int iLength, in wchar* pText, in int iState)
	{
		version(LOG) mixin(LogCallMix2);

		assert(_false); // should not be called if GetStateMaintenanceFlag return false

		bool versionsChanged;
		wstring text = to_cwstring(pText, iLength);
		return GetStateAtEndOfLine(iLine, text, iState, versionsChanged);
	}

	int ScanAndParse(int iLine, wstring text, bool doShift, ref int state, ref uint pos, ref bool versionsChanged)
	{
		uint prevpos = pos;
		int id;
		int type = dLex.scan(state, text, pos, id);
		if(mColorizeVersions)
		{
			wstring txt = text[prevpos..pos];
			if(!dLex.isCommentOrSpace(type, txt))
			{
				ParserToken!wstring tok;
				tok.type = type;
				tok.text = txt;
				tok.id = id;
				if (pos >= text.length)
					tok.span = ParserSpan(prevpos, iLine, 0, iLine + 1);
				else
					tok.span = ParserSpan(prevpos, iLine, pos, iLine);

				bool inTokenString = (dLex.tokenStringLevel(state) > 0);
				if(doShift)
					mParser.shift(tok);

				if (!inTokenString)
					type = parseVersions(tok.span, type, txt, state, versionsChanged);
			}
		}
		return type;
	}

	int GetStateAtEndOfLine(in int iLine, wstring text, in int iState, ref bool versionsChanged)
	{
		version(LOG) logCall("%s.GetStateAtEndOfLine(%d,%s,%x)", this, iLine, text, iState);
		version(LOG) mixin(_LogIndentNoRet);

		// SaveLineState(iLine, iState);
		if(mColorizeVersions)
		{
			versionsChanged = clearVersions(iLine);
			syncParser(iLine);
		}

		int state = iState;
		uint pos = 0;
		while(pos < text.length)
			ScanAndParse(iLine, text, true, state, pos, versionsChanged);

/*
		if(versionsChanged && iLine + 1 < mLineState.length)
		{
			int nextState = mLineState[iLine + 1];
			if(nextState == state)
				state ^= 1 << 31;
		}
*/
		lastParserLine = iLine + 1;
		lastParserIndex = 0;

		version(LOG) logCall("%s.GetStateAtEndOfLine returns state %x", this, state);
		return state;
	}

	override int CloseColorizer()
	{
		version(LOG) mixin(LogCallMix);

		return S_OK;
	}

	//////////////////////////////////////////////////////////////
	void drawCoverageOverlay(HWND hwnd, WPARAM wParam, LPARAM lParam, IVsTextView view)
	{
		if(!mColorizeCoverage || !mCoverage.length)
			return;

		HDC hDC = GetDC(hwnd);
		RECT r;
		GetClientRect(hwnd, &r);
		SelectObject(hDC, GetStockObject(BLACK_PEN));
		int h = 10;
		view.GetLineHeight(&h);
		int iMinUnit, iMaxUnit, iVisibleUnits, iFirstVisibleUnit;
		view.GetScrollInfo (1, &iMinUnit, &iMaxUnit, &iVisibleUnits, &iFirstVisibleUnit);

		LOGFONTW logfont;
		FontInfo fontInfo;
		ColorableItemInfo textColor, covColor, noncovColor, nocovColor;

		IVsFontAndColorStorage pIVsFontAndColorStorage = queryService!(IVsFontAndColorStorage);
		if(pIVsFontAndColorStorage)
		{
			scope(exit) release(pIVsFontAndColorStorage);
			auto flags = FCSF_READONLY|FCSF_LOADDEFAULTS|FCSF_NOAUTOCOLORS;
			if(pIVsFontAndColorStorage.OpenCategory(&GUID_TextEditorFC, flags) == S_OK)
			{
				pIVsFontAndColorStorage.GetFont(&logfont, &fontInfo);

				pIVsFontAndColorStorage.GetItem("Plain Text", &textColor);
				pIVsFontAndColorStorage.GetItem("Indicator Margin", &covColor);
				textColor.bBackgroundValid = covColor.bBackgroundValid;
				textColor.crBackground = covColor.crBackground;

				pIVsFontAndColorStorage.GetItem("Visual D Text Coverage", &covColor);
				pIVsFontAndColorStorage.GetItem("Visual D Text Non-Coverage", &noncovColor);
				pIVsFontAndColorStorage.GetItem("Visual D Margin No Coverage", &nocovColor);

				pIVsFontAndColorStorage.CloseCategory();
			}
		}
		HFONT fnt = CreateFontIndirect(&logfont);
		if(fnt)
			SelectObject(hDC, fnt);
		SetTextAlign(hDC, TA_RIGHT);

		int x0 = r.right - 40;

		for(int i = 0; i <= iVisibleUnits; i++)
		{
			RECT tr = { x0, h * i, r.right, h * i + h };

			int iLine = iFirstVisibleUnit + i;
			int covLine = mSource.adjustLineNumberSinceLastBuildReverse(iLine, true);
			int cov = covLine >= mCoverage.length ? -1 : mCoverage[covLine];

			string s;
			ColorableItemInfo *info = &covColor;
			if(cov < 0)
			{
				if (iLine == 0 && mCoveragePercent >= 0)
					s = text(mCoveragePercent) ~ "%";
				info = &nocovColor;
			}
			else if(cov == 0)
			{
				s = "0";
				info = &noncovColor;
			}
			else if(cov > 9999)
				s = ">9999";
			else
				s = text(cov);

			if(info.bForegroundValid)
				SetTextColor(hDC, info.crForeground);
			if(info.bBackgroundValid)
				SetBkColor(hDC, info.crBackground);

			ExtTextOutA(hDC, tr.right - 1, tr.top, ETO_OPAQUE, &tr, s.ptr, s.length, null);
		}

		MoveToEx(hDC, x0, r.top, null);
		LineTo(hDC, x0, r.bottom);

		if(fnt)
			DeleteObject(fnt);
		ReleaseDC(hwnd, hDC);
	}

	//////////////////////////////////////////////////////////////
	int lastParserLine;
	int lastParserIndex;

	void syncParser(int line)
	{
		if(line == lastParserLine && lastParserIndex == 0)
			return;

		lastParserLine = line;
		lastParserIndex = 0;
		mParser.prune(lastParserLine, lastParserIndex);
		if(line == lastParserLine && lastParserIndex == 0)
			return;

		assert(lastParserLine >= 0 && lastParserLine < line);
		assert(lastParserLine < mLineState.length);

		version(LOG) logCall("%s.syncParser(%d) restarts at [%d,%d]", this, line, lastParserLine, lastParserIndex);
		version(LOG) mixin(_LogIndentNoRet);

		int state = mLineState[lastParserLine];
		assert(state != -1);
		wstring text = mSource.GetText(lastParserLine, 0, lastParserLine, -1);

		bool versionsChanged;
		// scan until we find the position of the parser token
		uint pos = 0;
		while(pos < text.length && pos < lastParserIndex)
			ScanAndParse(lastParserLine, text, false, state, pos, versionsChanged);

		// parse the rest of the lines
		for( ; ; )
		{
			while(pos < text.length)
				ScanAndParse(lastParserLine, text, true, state, pos, versionsChanged);

			lastParserLine++;
			if(lastParserLine >= line)
				break;

			text = mSource.GetText(lastParserLine, 0, lastParserLine, -1);
			pos = 0;
		}
		lastParserIndex = 0;
	}

	//////////////////////////////////////////////////////////////
	bool _clearVersions(int debugOrVersion, int iLine)
	{
		wstring[] toremove;
		foreach(id, line; mVersionIds[debugOrVersion])
			if(line == iLine)
				toremove ~= id;

		foreach(id; toremove)
			mVersionIds[debugOrVersion].remove(id);

		if(mVersionLevelLine[debugOrVersion] == iLine)
		{
			mVersionLevelLine[debugOrVersion] = -2;
			mVersionLevel[debugOrVersion] = -1;
			return true;
		}
		return toremove.length > 0;
	}

	bool clearVersions(int iLine)
	{
		return _clearVersions(0, iLine)
			 | _clearVersions(1, iLine);
	}

	void defineVersion(int line, int num, int debugOrVersion, ref bool versionsChanged)
	{
		if(mVersionLevel[debugOrVersion] < 0 || line < mVersionLevelLine[debugOrVersion])
		{
			mVersionLevelLine[debugOrVersion] = line;
			mVersionLevel[debugOrVersion] = num;
			versionsChanged = true;
		}
	}

	bool isVersionEnabled(int line, int num, int debugOrVersion)
	{
		if(num == 0)
			return true;
		if(line >= mVersionLevelLine[debugOrVersion] && num <= mVersionLevel[debugOrVersion])
			return true;

		string versionids = mConfigVersions[debugOrVersion];
		string[] versions = tokenizeArgs(versionids);
		foreach(ver; versions)
			if(dLex.isInteger(ver) && to!int(ver) >= num)
				return true;
		return false;
	}

	bool defineVersion(int line, wstring ident, int debugOrVersion, ref bool versionsChanged)
	{
		if (debugOrVersion == 0)
		{
			int res = versionPredefined(ident);
			if(res != 0)
				return false;
		}

		int *pline = ident in mVersionIds[debugOrVersion];
		if(!pline)
			mVersionIds[debugOrVersion][ident] = line;
		else if(*pline < 0 && -*pline > line)
			*pline = line;
		else if(*pline >= 0 && *pline > line)
			*pline = line;
		else if(*pline >= 0 && *pline == line)
			return true;
		else
			return false;

		versionsChanged = true;
		return true;
	}

	__gshared int[wstring] predefinedVersions;
	shared static this()
	{
		foreach(v, p; vdc.versions.sPredefinedVersions)
			predefinedVersions[to!wstring(v)] = p;
	}

	int versionPredefined(wstring ident)
	{
		int* p = ident in predefinedVersions;
		if(!p)
			return 0;
		if(*p != 0)
			return *p;
		switch(ident)
		{
			case "unittest":
				return mConfigUnittest ? 1 : -1;
			case "assert":
				return mConfigUnittest || mConfigRelease != 1 ? 1 : -1;
			case "D_Coverage":
				return mConfigCoverage ? 1 : -1;
			case "D_Ddoc":
				return mConfigDoc ? 1 : -1;
			case "D_NoBoundsChecks":
				return mConfigBoundsCheck == 3 ? 1 : -1;
			case "Win32":
			case "X86":
			case "D_InlineAsm_X86":
				return mConfigX64 ? -1 : 1;
			case "Win64":
			case "X86_64":
			case "D_InlineAsm_X86_64":
			case "D_LP64":
				return mConfigX64 ? 1 : -1;
			case "GNU":
				return mConfigCompiler == Compiler.GDC ? 1 : -1;
			case "LDC":
				return mConfigCompiler == Compiler.LDC ? 1 : -1;
			case "DigitalMars":
				return mConfigCompiler == Compiler.DMD ? 1 : -1;
			case "CRuntime_DigitalMars":
				return mConfigCompiler == Compiler.DMD && !mConfigMSVCRT ? 1 : -1;
			case "CRuntime_Microsoft":
				return (mConfigCompiler == Compiler.DMD || mConfigCompiler == Compiler.LDC) && mConfigMSVCRT ? 1 : -1;
			case "MinGW":
				return mConfigCompiler == Compiler.GDC || (mConfigCompiler == Compiler.LDC && !mConfigMSVCRT) ? 1 : -1;

			default:
				assert(false, "inconsistent predefined versions");
		}
	}

	bool isVersionEnabled(int line, wstring ident, int debugOrVersion)
	{
		if(dLex.isInteger(ident))
			return isVersionEnabled(line, to!int(ident), debugOrVersion);

		if (debugOrVersion)
		{
			if(ident.length == 0 && mConfigRelease == 0)
				return true;
		}
		else
		{
			int res = versionPredefined(ident);
			if(res < 0)
				return false;
			if(res > 0)
				return true;
		}

		string versionids = mConfigVersions[debugOrVersion];
		string[] versions = tokenizeArgs(versionids);
		foreach(ver; versions)
			if(cmp(ver, ident) == 0)
				return true;

		int *pline = ident in mVersionIds[debugOrVersion];
		if(!pline || *pline < 0 || *pline > line)
			return false;
		return true;
	}

	int disabledColorType(int type)
	{
		switch(type)
		{
			case TokenColor.Text2:
			case TokenColor.Text:        return TokenColor.DisabledText;
			case TokenColor.Keyword:     return TokenColor.DisabledKeyword;
			case TokenColor.Comment:     return TokenColor.DisabledComment;
			case TokenColor.Identifier:  return TokenColor.DisabledIdentifier;
			case TokenColor.String:      return TokenColor.DisabledString;
			case TokenColor.Literal:     return TokenColor.DisabledLiteral;
			case TokenColor.Operator:    return TokenColor.DisabledOperator;
			case TokenColor.AsmRegister: return TokenColor.DisabledAsmRegister;
			case TokenColor.AsmMnemonic: return TokenColor.DisabledAsmMnemonic;
			case TokenColor.UserType:    return TokenColor.DisabledUserType;
			case TokenColor.Version:     return TokenColor.DisabledVersion;

			case TokenColor.Interface:   return TokenColor.DisabledIdentifier;
			case TokenColor.Enum:        return TokenColor.DisabledIdentifier;
			case TokenColor.EnumValue:   return TokenColor.DisabledIdentifier;
			case TokenColor.Template:    return TokenColor.DisabledIdentifier;
			case TokenColor.Class:       return TokenColor.DisabledIdentifier;
			case TokenColor.Struct:      return TokenColor.DisabledIdentifier;
			case TokenColor.TemplateTypeParameter: return TokenColor.DisabledIdentifier;

			case TokenColor.Constant:          return TokenColor.DisabledIdentifier;
			case TokenColor.LocalVariable:     return TokenColor.DisabledIdentifier;
			case TokenColor.ParameterVariable: return TokenColor.DisabledIdentifier;
			case TokenColor.TLSVariable:       return TokenColor.DisabledIdentifier;
			case TokenColor.SharedVariable:    return TokenColor.DisabledIdentifier;
			case TokenColor.GSharedVariable:   return TokenColor.DisabledIdentifier;
			case TokenColor.MemberVariable:    return TokenColor.DisabledIdentifier;
			case TokenColor.Variable:          return TokenColor.DisabledIdentifier;
			case TokenColor.Alias:             return TokenColor.DisabledIdentifier;
			case TokenColor.Module:            return TokenColor.DisabledIdentifier;
			case TokenColor.Function:          return TokenColor.DisabledIdentifier;
			case TokenColor.Method:            return TokenColor.DisabledIdentifier;
			case TokenColor.BasicType:         return TokenColor.DisabledIdentifier;
			default: break;
		}
		return type;
	}

	int stringColorType(int type)
	{
		switch(type)
		{
			case TokenColor.Text2:
			case TokenColor.Text:        return TokenColor.StringText;
			case TokenColor.Keyword:     return TokenColor.StringKeyword;
			case TokenColor.Comment:     return TokenColor.StringComment;
			case TokenColor.Identifier:  return TokenColor.StringIdentifier;
			case TokenColor.String:      return TokenColor.StringString;
			case TokenColor.Literal:     return TokenColor.StringLiteral;
			case TokenColor.AsmRegister: return TokenColor.StringAsmRegister;
			case TokenColor.AsmMnemonic: return TokenColor.StringAsmMnemonic;
			case TokenColor.UserType:    return TokenColor.StringUserType;
			case TokenColor.Version:     return TokenColor.StringVersion;

			case TokenColor.Interface:   return TokenColor.StringIdentifier;
			case TokenColor.Enum:        return TokenColor.StringIdentifier;
			case TokenColor.EnumValue:   return TokenColor.StringIdentifier;
			case TokenColor.Template:    return TokenColor.StringIdentifier;
			case TokenColor.Class:       return TokenColor.StringIdentifier;
			case TokenColor.Struct:      return TokenColor.StringIdentifier;
			case TokenColor.TemplateTypeParameter: return TokenColor.StringIdentifier;
			case TokenColor.Constant:          return TokenColor.StringIdentifier;
			case TokenColor.LocalVariable:     return TokenColor.StringIdentifier;
			case TokenColor.ParameterVariable: return TokenColor.StringIdentifier;
			case TokenColor.TLSVariable:       return TokenColor.StringIdentifier;
			case TokenColor.SharedVariable:    return TokenColor.StringIdentifier;
			case TokenColor.GSharedVariable:   return TokenColor.StringIdentifier;
			case TokenColor.MemberVariable:    return TokenColor.StringIdentifier;
			case TokenColor.Variable:          return TokenColor.StringIdentifier;
			case TokenColor.Alias:             return TokenColor.StringIdentifier;
			case TokenColor.Module:            return TokenColor.StringIdentifier;
			case TokenColor.Function:          return TokenColor.StringIdentifier;
			case TokenColor.Method:            return TokenColor.StringIdentifier;
			case TokenColor.BasicType:         return TokenColor.StringIdentifier;
			default: break;
		}
		return type;
	}

	__gshared int[wstring] asmIdentifiers;
	static const wstring[] asmKeywords = [ "__LOCAL_SIZE", "dword", "even", "far", "naked", "near", "ptr", "qword", "seg", "word", ];
	static const wstring[] asmRegisters = [
		"AL",   "AH",   "AX",   "EAX",
		"BL",   "BH",   "BX",   "EBX",
		"CL",   "CH",   "CX",   "ECX",
		"DL",   "DH",   "DX",   "EDX",
		"BP",   "EBP",  "SP",   "ESP",
		"DI",   "EDI",  "SI",   "ESI",
		"ES",   "CS",   "SS",   "DS",   "GS",   "FS",
		"CR0",  "CR2",  "CR3",  "CR4",
		"DR0",  "DR1",  "DR2",  "DR3",  "DR4",  "DR5",  "DR6",  "DR7",
		"TR3",  "TR4",  "TR5",  "TR6",  "TR7",
		"MM0",  "MM1",  "MM2",  "MM3",  "MM4",  "MM5",  "MM6",  "MM7",
		"XMM0", "XMM1", "XMM2", "XMM3", "XMM4", "XMM5", "XMM6", "XMM7",
	];
	static const wstring[] asmMnemonics = [
		"__emit",     "_emit",      "aaa",        "aad",        "aam",        "aas",
		"adc",        "add",        "addpd",      "addps",      "addsd",      "addss",
		"addsubpd",   "addsubps",   "and",        "andnpd",     "andnps",     "andpd",
		"andps",      "arpl",       "blendpd",    "blendps",    "blendvpd",   "blendvps",
		"bound",      "bsf",        "bsr",        "bswap",      "bt",         "btc",
		"btr",        "bts",        "call",       "cbw",        "cdq",        "cdqe",
		"clc",        "cld",        "clflush",    "cli",        "clts",       "cmc",
		"cmova",      "cmovae",     "cmovb",      "cmovbe",     "cmovc",      "cmove",
		"cmovg",      "cmovge",     "cmovl",      "cmovle",     "cmovna",     "cmovnae",
		"cmovnb",     "cmovnbe",    "cmovnc",     "cmovne",     "cmovng",     "cmovnge",
		"cmovnl",     "cmovnle",    "cmovno",     "cmovnp",     "cmovns",     "cmovnz",
		"cmovo",      "cmovp",      "cmovpe",     "cmovpo",     "cmovs",      "cmovz",
		"cmp",        "cmppd",      "cmpps",      "cmps",       "cmpsb",      "cmpsd",
		"cmpsq",      "cmpss",      "cmpsw",      "cmpxchg",    "cmpxchg16b", "cmpxchg8b",
		"comisd",     "comiss",     "cpuid",      "cqo",        "crc32",      "cvtdq2pd",
		"cvtdq2ps",   "cvtpd2dq",   "cvtpd2pi",   "cvtpd2ps",   "cvtpi2pd",   "cvtpi2ps",
		"cvtps2dq",   "cvtps2pd",   "cvtps2pi",   "cvtsd2si",   "cvtsd2ss",   "cvtsi2sd",
		"cvtsi2ss",   "cvtss2sd",   "cvtss2si",   "cvttpd2dq",  "cvttpd2pi",  "cvttps2dq",
		"cvttps2pi",  "cvttsd2si",  "cvttss2si",  "cwd",        "cwde",       "da",
		"daa",        "das",        "db",         "dd",         "de",         "dec",
		"df",         "di",         "div",        "divpd",      "divps",      "divsd",
		"divss",      "dl",         "dppd",       "dpps",       "dq",         "ds",
		"dt",         "dw",         "emms",       "enter",      "extractps",  "f2xm1",
		"fabs",       "fadd",       "faddp",      "fbld",       "fbstp",      "fchs",
		"fclex",      "fcmovb",     "fcmovbe",    "fcmove",     "fcmovnb",    "fcmovnbe",
		"fcmovne",    "fcmovnu",    "fcmovu",     "fcom",       "fcomi",      "fcomip",
		"fcomp",      "fcompp",     "fcos",       "fdecstp",    "fdisi",      "fdiv",
		"fdivp",      "fdivr",      "fdivrp",     "feni",       "ffree",      "fiadd",
		"ficom",      "ficomp",     "fidiv",      "fidivr",     "fild",       "fimul",
		"fincstp",    "finit",      "fist",       "fistp",      "fisttp",     "fisub",
		"fisubr",     "fld",        "fld1",       "fldcw",      "fldenv",     "fldl2e",
		"fldl2t",     "fldlg2",     "fldln2",     "fldpi",      "fldz",       "fmul",
		"fmulp",      "fnclex",     "fndisi",     "fneni",      "fninit",     "fnop",
		"fnsave",     "fnstcw",     "fnstenv",    "fnstsw",     "fpatan",     "fprem",
		"fprem1",     "fptan",      "frndint",    "frstor",     "fsave",      "fscale",
		"fsetpm",     "fsin",       "fsincos",    "fsqrt",      "fst",        "fstcw",
		"fstenv",     "fstp",       "fstsw",      "fsub",       "fsubp",      "fsubr",
		"fsubrp",     "ftst",       "fucom",      "fucomi",     "fucomip",    "fucomp",
		"fucompp",    "fwait",      "fxam",       "fxch",       "fxrstor",    "fxsave",
		"fxtract",    "fyl2x",      "fyl2xp1",    "haddpd",     "haddps",     "hlt",
		"hsubpd",     "hsubps",     "idiv",       "imul",       "in",         "inc",
		"ins",        "insb",       "insd",       "insertps",   "insw",       "int",
		"into",       "invd",       "invlpg",     "iret",       "iretd",      "ja",
		"jae",        "jb",         "jbe",        "jc",         "jcxz",       "je",
		"jecxz",      "jg",         "jge",        "jl",         "jle",        "jmp",
		"jna",        "jnae",       "jnb",        "jnbe",       "jnc",        "jne",
		"jng",        "jnge",       "jnl",        "jnle",       "jno",        "jnp",
		"jns",        "jnz",        "jo",         "jp",         "jpe",        "jpo",
		"js",         "jz",         "lahf",       "lar",        "lddqu",      "ldmxcsr",
		"lds",        "lea",        "leave",      "les",        "lfence",     "lfs",
		"lgdt",       "lgs",        "lidt",       "lldt",       "lmsw",       "lock",
		"lods",       "lodsb",      "lodsd",      "lodsq",      "lodsw",      "loop",
		"loope",      "loopne",     "loopnz",     "loopz",      "lsl",        "lss",
		"ltr",        "maskmovdqu", "maskmovq",   "maxpd",      "maxps",      "maxsd",
		"maxss",      "mfence",     "minpd",      "minps",      "minsd",      "minss",
		"monitor",    "mov",        "movapd",     "movaps",     "movd",       "movddup",
		"movdq2q",    "movdqa",     "movdqu",     "movhlps",    "movhpd",     "movhps",
		"movlhps",    "movlpd",     "movlps",     "movmskpd",   "movmskps",   "movntdq",
		"movntdqa",   "movnti",     "movntpd",    "movntps",    "movntq",     "movq",
		"movq2dq",    "movs",       "movsb",      "movsd",      "movshdup",   "movsldup",
		"movsq",      "movss",      "movsw",      "movsx",      "movupd",     "movups",
		"movzx",      "mpsadbw",    "mul",        "mulpd",      "mulps",      "mulsd",
		"mulss",      "mwait",      "neg",        "nop",        "not",        "or",
		"orpd",       "orps",       "out",        "outs",       "outsb",      "outsd",
		"outsw",      "pabsb",      "pabsd",      "pabsw",      "packssdw",   "packsswb",
		"packusdw",   "packuswb",   "paddb",      "paddd",      "paddq",      "paddsb",
		"paddsw",     "paddusb",    "paddusw",    "paddw",      "palignr",    "pand",
		"pandn",      /*"pause",*/  "pavgb",      "pavgusb",    "pavgw",      "pblendvb",
		"pblendw",    "pcmpeqb",    "pcmpeqd",    "pcmpeqq",    "pcmpeqw",    "pcmpestri",
		"pcmpestrm",  "pcmpgtb",    "pcmpgtd",    "pcmpgtq",    "pcmpgtw",    "pcmpistri",
		"pcmpistrm",  "pextrb",     "pextrd",     "pextrq",     "pextrw",     "pf2id",
		"pfacc",      "pfadd",      "pfcmpeq",    "pfcmpge",    "pfcmpgt",    "pfmax",
		"pfmin",      "pfmul",      "pfnacc",     "pfpnacc",    "pfrcp",      "pfrcpit1",
		"pfrcpit2",   "pfrsqit1",   "pfrsqrt",    "pfsub",      "pfsubr",     "phaddd",
		"phaddsw",    "phaddw",     "phminposuw", "phsubd",     "phsubsw",    "phsubw",
		"pi2fd",      "pinsrb",     "pinsrd",     "pinsrq",     "pinsrw",     "pmaddubsw",
		"pmaddwd",    "pmaxsb",     "pmaxsd",     "pmaxsw",     "pmaxub",     "pmaxud",
		"pmaxuw",     "pminsb",     "pminsd",     "pminsw",     "pminub",     "pminud",
		"pminuw",     "pmovmskb",   "pmovsxbd",   "pmovsxbq",   "pmovsxbw",   "pmovsxdq",
		"pmovsxwd",   "pmovsxwq",   "pmovzxbd",   "pmovzxbq",   "pmovzxbw",   "pmovzxdq",
		"pmovzxwd",   "pmovzxwq",   "pmuldq",     "pmulhrsw",   "pmulhrw",    "pmulhuw",
		"pmulhw",     "pmulld",     "pmullw",     "pmuludq",    "pop",        "popa",
		"popad",      "popcnt",     "popf",       "popfd",      "popfq",      "por",
		"prefetchnta","prefetcht0", "prefetcht1", "prefetcht2", "psadbw",     "pshufb",
		"pshufd",     "pshufhw",    "pshuflw",    "pshufw",     "psignb",     "psignd",
		"psignw",     "pslld",      "pslldq",     "psllq",      "psllw",      "psrad",
		"psraw",      "psrld",      "psrldq",     "psrlq",      "psrlw",      "psubb",
		"psubd",      "psubq",      "psubsb",     "psubsw",     "psubusb",    "psubusw",
		"psubw",      "pswapd",     "ptest",      "punpckhbw",  "punpckhdq",  "punpckhqdq",
		"punpckhwd",  "punpcklbw",  "punpckldq",  "punpcklqdq", "punpcklwd",  "push",
		"pusha",      "pushad",     "pushf",      "pushfd",     "pushfq",     "pxor",
		"rcl",        "rcpps",      "rcpss",      "rcr",        "rdmsr",      "rdpmc",
		"rdtsc",      "rep",        "repe",       "repne",      "repnz",      "repz",
		"ret",        "retf",       "rol",        "ror",        "roundpd",    "roundps",
		"roundsd",    "roundss",    "rsm",        "rsqrtps",    "rsqrtss",    "sahf",
		"sal",        "sar",        "sbb",        "scas",       "scasb",      "scasd",
		"scasq",      "scasw",      "seta",       "setae",      "setb",       "setbe",
		"setc",       "sete",       "setg",       "setge",      "setl",       "setle",
		"setna",      "setnae",     "setnb",      "setnbe",     "setnc",      "setne",
		"setng",      "setnge",     "setnl",      "setnle",     "setno",      "setnp",
		"setns",      "setnz",      "seto",       "setp",       "setpe",      "setpo",
		"sets",       "setz",       "sfence",     "sgdt",       "shl",        "shld",
		"shr",        "shrd",       "shufpd",     "shufps",     "sidt",       "sldt",
		"smsw",       "sqrtpd",     "sqrtps",     "sqrtsd",     "sqrtss",     "stc",
		"std",        "sti",        "stmxcsr",    "stos",       "stosb",      "stosd",
		"stosq",      "stosw",      "str",        "sub",        "subpd",      "subps",
		"subsd",      "subss",      "syscall",    "sysenter",   "sysexit",    "sysret",
		"test",       "ucomisd",    "ucomiss",    "ud2",        "unpckhpd",   "unpckhps",
		"unpcklpd",   "unpcklps",   "verr",       "verw",       "wait",       "wbinvd",
		"wrmsr",      "xadd",       "xchg",       "xlat",       "xlatb",      "xor",
		"xorpd",      "xorps",
	];
	shared static this()
	{
		foreach(id; asmKeywords)
			asmIdentifiers[id] = TokenColor.Keyword;
		foreach(id; asmRegisters)
			asmIdentifiers[id] = TokenColor.AsmRegister;
		foreach(id; asmMnemonics)
			asmIdentifiers[id] = TokenColor.AsmMnemonic;
	}

	private int asmColorType(wstring text)
	{
		if(auto p = text in asmIdentifiers)
			return *p;
		return TokenColor.Identifier;
	}

	private int userColorType(wstring text, int type)
	{
		if(auto p = text in Package.GetGlobalOptions().UserTypes)
			return *p;
		return type;
	}

	private static int getParseState(int iState)
	{
		return (iState >> 20) & 0x0f;
	}
	private static int getDebugOrVersion(int iState)
	{
		return (iState >> 24) & 0x1;
	}
	int parseVersions(ref ParserSpan span, int type, wstring text, ref int iState, ref bool versionsChanged)
	{
		int iLine = span.iStartLine;
	version(none)
	{
		// COLORIZER_ATTRIBUTE flags
		//  0x00100: gray background
		//  0x00200: black on dark blue
		//  0x40000: underlined
		//  COLOR_MARKER_MASK    = 0x00003f00: select color encoding, 0 standard, other from color list
		//  LINE_MARKER_MASK     = 0x000fc000: underline style: 0-none, 4~blue, 5~red, 6~magenta, 7-gray, 11~green,
		//                                     16-black, 23=magenta, 24=red, 35-maroon, 56-yellow, 58-ltgray
		//  PRIVATE_CLIENT_MASK1 = 0x00100000:
		//  PRIVATE_CLIENT_MASK2 = 0x00600000: ident marker style: 0-none, 1-blue start mark, 2,3-red end mark
		//  PRIVATE_CLIENT_MASK3 = 0x00800000: disable text coloring
		//  PRIVATE_EDITOR_MASK  = 0xfc000000:
		//  SEPARATOR_AFTER_ATTR = 0x02000000: if on char after line, draws line between text rows

		int lineMarker = 0; // iLine & 0x3f;
		int privClient = (iLine >> 0) & 0xf;
		int privEditor = (iLine >> 4) & 0x3f;
		int attr = (lineMarker << 14) | (privClient << 20) | (privEditor << 26);
		type |= attr;
	}
	version(all)
	{
		//if(dLex.isCommentOrSpace(type, text))
		//	return type;

		int parseState = getParseState(iState);
		int debugOrVersion = getDebugOrVersion(iState);
		int ntype = type;
		if(ntype == TokenColor.Identifier || ntype == TokenColor.Keyword)
			ntype = userColorType(text, ntype);

		final switch(cast(VersionParseState) parseState)
		{
		case VersionParseState.IdleDisabledVerify:
		case VersionParseState.IdleEnabledVerify:
			if(isAddressEnabled(span.iStartLine, span.iStartIndex))
			{
				parseState = VersionParseState.IdleEnabled;
				goto case VersionParseState.IdleEnabled;
			}
			parseState = VersionParseState.IdleDisabled;
			goto case VersionParseState.IdleDisabled;

		case VersionParseState.IdleDisabled:
			ntype = disabledColorType(ntype);
			if(text == "asm")
				parseState = VersionParseState.AsmParsedDisabled;
			else if(versionPredefined(text) && isVersionCondition(span))
				ntype = TokenColor.DisabledVersion;
			break;

		case VersionParseState.IdleEnabled:
			if(text == "version")
			{
				parseState = VersionParseState.VersionParsed;
				debugOrVersion = 0;
			}
			else if(text == "debug")
			{
				parseState = VersionParseState.VersionParsed;
				debugOrVersion = 1;
			}
			else if(text == "asm")
				parseState = VersionParseState.AsmParsedEnabled;
			break;

		case VersionParseState.VersionParsed:
			if(text == "=")
				parseState = VersionParseState.AssignParsed;
			else if(text == "(")
				parseState = VersionParseState.ParenLParsed;
			else if(debugOrVersion)
			{
				if(isVersionEnabled(iLine, "", debugOrVersion))
				{
					parseState = VersionParseState.IdleEnabled;
					goto case VersionParseState.IdleEnabled;
				}
				else
				{
					parseState = VersionParseState.IdleDisabled;
					goto case VersionParseState.IdleDisabled;
				}
			}
			else
				parseState = VersionParseState.IdleEnabled;
			break;

		case VersionParseState.AssignParsed:
			if(dLex.isIdentifier(text))
			{
				if(debugOrVersion == 0 && versionPredefined(text))
					ntype = TokenColor.Version;
				if(!defineVersion(iLine, text, debugOrVersion, versionsChanged))
					ntype |= 5 << 14; // red ~~~~ on VS2008
			}
			else if(dLex.isInteger(text))
				defineVersion(iLine, to!int(text), debugOrVersion, versionsChanged);
			parseState = VersionParseState.IdleEnabled;
			break;

		case VersionParseState.ParenLParsed:
			if(dLex.isIdentifier(text) || dLex.isInteger(text))
			{
				if(debugOrVersion == 0 && versionPredefined(text))
					ntype = TokenColor.Version;

				if(isVersionEnabled(iLine, text, debugOrVersion))
					parseState = VersionParseState.IdentNumberParsedEnable;
				else
					parseState = VersionParseState.IdentNumberParsedDisable;
			}
			else
				parseState = VersionParseState.IdleEnabled;
			break;

		case VersionParseState.IdentNumberParsedDisable:
			if(text == ")")
				parseState = VersionParseState.ParenRParsedDisable;
			else
				parseState = VersionParseState.IdleEnabled;
			break;

		case VersionParseState.IdentNumberParsedEnable:
			if(text == ")")
				parseState = VersionParseState.ParenRParsedEnable;
			else
				parseState = VersionParseState.IdleEnabled;
			break;

		case VersionParseState.ParenRParsedEnable:
			parseState = VersionParseState.IdleEnabled;
			goto case VersionParseState.IdleEnabled;

		case VersionParseState.ParenRParsedDisable:
			parseState = VersionParseState.IdleDisabled;
			goto case VersionParseState.IdleDisabled;

		// asm block
		case VersionParseState.AsmParsedEnabled:
			if(text == "{")
				parseState = VersionParseState.InAsmBlockEnabled;
			else if (text != "nothrow" && text != "pure" && !text.startsWith("@"))
				parseState = VersionParseState.IdleEnabled;
			break;
		case VersionParseState.AsmParsedDisabled:
			if(text == "{")
				parseState = VersionParseState.InAsmBlockDisabled;
			else if (text != "nothrow" && text != "pure" && !text.startsWith("@"))
				parseState = VersionParseState.IdleDisabled;
			goto case VersionParseState.IdleDisabled;

		case VersionParseState.InAsmBlockEnabled:
			if(text == "}")
				parseState = VersionParseState.IdleEnabled;
			else if(ntype == TokenColor.Identifier)
				ntype = asmColorType(text);
			break;
		case VersionParseState.InAsmBlockDisabled:
			if(text == "}")
				parseState = VersionParseState.IdleDisabled;
			else if(ntype == TokenColor.Identifier)
				ntype = asmColorType(text);
			goto case VersionParseState.IdleDisabled;
		}

		if(text == ";" || text == "}")
		{
			if(parseState == VersionParseState.IdleDisabled)
				parseState = text == ";" ? VersionParseState.IdleDisabledVerify : VersionParseState.IdleEnabledVerify;
		}
		else if(text == "else")
		{
			if(isAddressEnabled(span.iEndLine, span.iEndIndex))
			{
				parseState = VersionParseState.IdleEnabled;
				ntype = type; // restore enabled type
			}
			else
			{
				parseState = VersionParseState.IdleDisabled;
				ntype = disabledColorType(ntype);
			}
		}

		iState = (iState & 0x800fffff) | (parseState << 20) | (debugOrVersion << 24);
	}
		return ntype;
	}

	int parseErrors(ref ParserSpan span, int type, wstring tok)
	{
		if(!dLex.isCommentOrSpace(type, tok))
			if(mSource.hasParseError(span))
				type |= 5 << 14; // red ~

		return type;
	}

	wstring getVersionToken(LocationBase!wstring verloc)
	{
		if(verloc.children.length == 0)
			return "";

		ParserSpan span = verloc.children[0].span;
		wstring text = mSource.GetText(span.iStartLine, span.iStartIndex, span.iEndLine, span.iEndIndex);
		text = strip(text);
		if(text.length == 0 || text[0] != '(' || text[$-1] != ')')
			return ""; // parsing unfinished or debug statement without argument

		text = strip(text[1..$-1]);
		return text;
	}

	bool isAddressEnabled(int iLine, int iIndex)
	{
		mParser.fixExtend();
		LocationBase!wstring loc = mParser.findLocation(iLine, iIndex, true);
		LocationBase!wstring child = null;
		while(loc)
		{
			if(VersionStatement!wstring verloc = cast(VersionStatement!wstring) loc)
			{
				wstring ver = getVersionToken(verloc);
				if(isVersionEnabled(verloc.span.iStartLine, ver, 0))
				{
					if(verloc.children.length > 2 && child == verloc.children[2]) // spanContains(verloc.children[2].span, iLine, iIndex))
						return false; // else statement
				}
				else
				{
					if(verloc.children.length > 1 && child == verloc.children[1]) // spanContains(verloc.children[1].span, iLine, iIndex))
						return false; // then statement
				}
			}
			else if(DebugStatement!wstring dbgloc = cast(DebugStatement!wstring) loc)
			{
				wstring ver = getVersionToken(dbgloc);
				if(isVersionEnabled(dbgloc.span.iStartLine, ver, 1))
				{
					if(dbgloc.children.length > 2 && child == dbgloc.children[2]) // spanContains(dbgloc.children[2].span, iLine, iIndex))
						return false; // else statement
				}
				else
				{
					if(dbgloc.children.length > 1 && child == dbgloc.children[1]) // spanContains(dbgloc.children[1].span, iLine, iIndex))
						return false; // then statement
				}
			}
			child = loc;
			loc = loc.parent;
		}
		return true;
	}

	bool isVersionCondition(ref ParserSpan vspan)
	{
		mParser.fixExtend();
		LocationBase!wstring loc = mParser.findLocation(vspan.iStartLine, vspan.iStartIndex, true);
		LocationBase!wstring child = null;
		while(loc)
		{
			if(VersionStatement!wstring verloc = cast(VersionStatement!wstring) loc)
			{
				if(verloc.children.length > 0)
				{
					if(spanContains(verloc.children[0].span, vspan.iStartLine, vspan.iStartIndex))
						return true;
				}
			}
			child = loc;
			loc = loc.parent;
		}
		return false;
	}

	bool isInUnittest(int iLine, int iIndex)
	{
		mParser.fixExtend();
		LocationBase!wstring loc = mParser.findLocation(iLine, iIndex, true);
		LocationBase!wstring child = null;

		while(loc)
		{
			if(auto utloc = cast(UnittestStatement!wstring) loc)
				return true;

			child = loc;
			loc = loc.parent;
		}
		return false;
	}

	//////////////////////////////////////////////////////////////
	void SaveLineState(int iLine, int state)
	{
		if(iLine >= mLineState.length)
		{
			int i = mLineState.length;
			mLineState.length = iLine + 100;
			for( ; i < mLineState.length; i++)
				mLineState[i] = -1;
		}
		mLineState[iLine] = state;
	}

	void UpdateLineState(int line)
	{
		UpdateLineStates(line, line);
	}

	void UpdateLineStates(int line, int endline)
	{
		version(LOG) mixin(LogCallMix2);

		int ln = line;
		if(ln >= mLineState.length)
			ln = max(mLineState.length, 1) - 1;
		while(ln > 0 && mLineState[ln] == -1)
			ln--;

		if(ln == 0)
			SaveLineState(0, 0);
		int state = mLineState[ln];

		bool stateChanged = false;
		bool versionsChanged = false;
		while(ln <= endline)
		{
			SaveLineState(ln, state);
			wstring txt = mSource.GetText(ln, 0, ln, -1);
			state = GetStateAtEndOfLine(ln, txt, state, versionsChanged);
			ln++;
		}
		int prevState = ln < mLineState.length ? mLineState[ln] : -1;
		SaveLineState(ln, state);

		if(versionsChanged || mColorizeVersions || state != prevState)
		{
			ln++;
			while(ln < mLineState.length)
			{
				if(mLineState[ln] == -1)
					break;
				mLineState[ln++] = -1;
			}

			mSource.ReColorizeLines(line, -1);
		}
	}

	int GetLineState(int iLine)
	{
		int state = -1;
		if(iLine >= 0 && iLine < mLineState.length)
			state = mLineState[iLine];
		if(state == -1)
		{
			UpdateLineState(iLine);
			state = mLineState[iLine];
		}
		assert(state != -1);
		return state;
	}

	//////////////////////////////////////////////////////////////
	int OnLinesChanged(int iStartLine, int iOldEndLine, int iNewEndLine, bool fLast)
	{
		version(LOG) mixin(LogCallMix);

		int p;
		int diffLines = iNewEndLine - iOldEndLine;
		int lines = mSource.GetLineCount();   // new line count
		SaveLineState(lines, -1); // ensure mLineState[] is large enough

		if(diffLines > 0)
		{
			for(p = lines; p > iNewEndLine; p--)
				mLineState[p] = mLineState[p - diffLines];

			for(; p > iStartLine; p--)
				mLineState[p] = -1;
		}
		else if(diffLines < 0)
		{
			for(p = iStartLine + 1; p < iNewEndLine; p++)
				mLineState[p] = -1;
			for(; p - diffLines < lines; p++)
				mLineState[p] = mLineState[p - diffLines];
			for(; p < lines; p++)
				mLineState[p] = -1;
		}

		if(iStartLine < mLineState.length && mLineState[iStartLine] != -1)
			UpdateLineStates(iStartLine, iNewEndLine);
		return S_OK;
	}

	//////////////////////////////////////////////////////////////
	int modifyValue(V)(V val, ref V var)
	{
		if(var == val)
			return 0;
		var = val;
		return 1;
	}

	bool UpdateConfig()
	{
		int changes = 0;
		string file = mSource.GetFileName ();
		Config cfg = getProjectConfig(file);
		release(cfg); // we don't need a reference

		if(cfg != mConfig)
		{
			if(mConfig)
				mConfig.RemoveModifiedListener(this);
			mConfig = cfg;
			if(mConfig)
				mConfig.AddModifiedListener(this);
			changes++;
		}

		if(mConfig)
		{
			ProjectOptions opts = mConfig.GetProjectOptions();

			string versionids = mConfig.getCompilerVersionIDs();

			changes += modifyValue(versionids,         mConfigVersions[kIndexVersion]);
			changes += modifyValue(opts.debugids,      mConfigVersions[kIndexDebug]);
			changes += modifyValue(opts.release,       mConfigRelease);
			changes += modifyValue(opts.useUnitTests,  mConfigUnittest);
			changes += modifyValue(opts.isX86_64,      mConfigX64);
			changes += modifyValue(opts.useMSVCRT(),   mConfigMSVCRT);
			changes += modifyValue(opts.cov,           mConfigCoverage);
			changes += modifyValue(opts.doDocComments, mConfigDoc);
			changes += modifyValue(opts.boundscheck,   mConfigBoundsCheck);
			changes += modifyValue(opts.compiler,      mConfigCompiler);
		}
		return changes != 0;
	}

	Config GetConfig()
	{
		if(!mConfig)
		{
			UpdateConfig();
		}
		return mConfig;
	}

	// ConfigModifiedListener
	override void OnConfigModified()
	{
		OnConfigModified(false);
	}

	void OnConfigModified(bool force)
	{
		int changes = UpdateConfig();
		changes += modifyValue(Package.GetGlobalOptions().ColorizeVersions, mColorizeVersions);
		changes += modifyValue(Package.GetGlobalOptions().ColorizeCoverage, mColorizeCoverage);

		if(changes || force)
		{
			mLineState[] = -1;
			mSource.ReColorizeLines(0, -1);
		}
	}

	//////////////////////////////////////////////////////////

	static int[] ReadCoverageFile(string lstname, out float coveragePercent)
	{
		coveragePercent = -1;
		try
		{
			char[] lst = cast(char[]) std.file.read(lstname);
			char[][] lines = splitLines(lst);
			int[] coverage = new int[lines.length];
			foreach(i, ln; lines)
			{
				auto pos = std.string.indexOf(ln, '|');
				int cov = -1;
				if(pos > 0)
				{
					auto num = strip(ln[0..pos]);
					if(num.length)
						cov = parse!int(num);
				}
				coverage[i] = cov;
			}
			if (lines.length > 0)
			{
				char[] ln = lines[$-1];
				auto pos = std.string.indexOf(ln, "% covered");
				if(pos > 0)
				{
					auto end = pos;
					while(pos > 0 && isDigit(ln[pos-1]) || ln[pos - 1] == '.')
						pos--;
					auto num = ln[pos..end];
					if(num.length)
						coveragePercent = parse!float(num); // very last entry is percent
				}
			}
			return coverage;
		}
		catch(Error)
		{
		}
		return null;
	}

	bool lastCoverageFileIsValid()
	{
		return (mLastCoverageFile.length > 0 && std.file.exists(mLastCoverageFile) && std.file.isFile(mLastCoverageFile));
	}

	bool FindCoverageFile()
	{
		if(lastCoverageFileIsValid())
			return true;

		mLastCoverageFile = Package.GetGlobalOptions().findCoverageFile(mSource.GetFileName());
		return lastCoverageFileIsValid();
	}

	bool UpdateCoverage(bool force)
	{
		if(mColorizeCoverage)
		{
			auto now = Clock.currTime();
			if(!force && mLastTestCoverageFile + dur!"seconds"(2) >= now)
				return false;

			mLastTestCoverageFile = now;

			if(FindCoverageFile())
			{
				auto lsttm = std.file.timeLastModified(mLastCoverageFile);
				auto srctm = std.file.timeLastModified(mSource.GetFileName());

				if (lsttm < srctm)
				{
					ClearCoverage();
				}
				else if(force || lsttm != mLastModifiedCoverageFile)
				{
					mLastModifiedCoverageFile = lsttm;
					mCoverage = ReadCoverageFile(mLastCoverageFile, mCoveragePercent);

					mSource.ReColorizeLines(0, -1);
				}
				return true;
			}
		}
		ClearCoverage();
		return false;
	}

	void ClearCoverage()
	{
		mCoverage = mCoverage.init;
		if(mLastModifiedCoverageFile != SysTime(0))
		{
			mLastCoverageFile = null;
			mLastModifiedCoverageFile = SysTime(0);
			mSource.ReColorizeLines(0, -1);
		}
	}
}

