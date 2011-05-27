// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.colorizer;

import visuald.windows;
import std.string;
import std.ctype;
import std.utf;
import std.conv;
import std.algorithm;

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

import sdk.port.vsi;
import sdk.vsi.textmgr;
import sdk.vsi.textmgr2;

// version = LOG;

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
	bool mParseSource;
	
	const int kIndexVersion = 0;
	const int kIndexDebug   = 1;
	
	// index 0 for version, index 1 for debug
	int[wstring][2] mVersionIds; // positive: lineno defined
	int mVersionLevel[2] = [ -1, -1 ];
	int mVersionLevelLine[2] = [ -2, -2 ];  // -2 never defined, -1 if set on command line

	int[wstring] mDebugIds; // positive: lineno defined
	int mDebugLevel = -1;
	int mDebugLevelLine = -2;  // -2 never defined, -1 if set on command line

	string mConfigVersions[2];
	bool mConfigRelease;
	bool mConfigUnittest;
	
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
	}
	
	this(Source src)
	{
		mSource = src;
		mParser = new ParserBase!wstring;
		
		mColorizeVersions = Package.GetGlobalOptions().ColorizeVersions;
		mParseSource = Package.GetGlobalOptions().parseSource;
		UpdateConfig();
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
			
			if(mColorizeVersions)
			{
				if(Lexer.isCommentOrSpace(type, tok) || (inTokenString || nowInTokenString))
				{
					int parseState = getParseState(state);
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
			inTokenString = nowInTokenString;
				
			while(prevpos < pos)
				pAttributes[prevpos++] = type;
		}
		pAttributes[iLength] = TokenColor.Text;

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

	int versionPredefined(wstring ident)
	{
		switch(ident)
		{
			case "DigitalMars":     return 1;
			case "X86":             return 1;
			case "X86_64":          return -1;
			case "Windows":         return 1;
			case "Win32":           return 1;
			case "Win64":           return -1;
			case "linux":           return -1;
			case "Posix":           return -1;
			case "LittleEndian":    return 1;
			case "BigEndian":       return -1;
			case "D_Coverage":      return -1;
			case "D_Ddoc":          return -1;
			case "D_InlineAsm_X86": return 1;
			case "D_InlineAsm_X86_64": return -1;
			case "D_LP64":          return -1;
			case "D_PIC":           return -1;
			case "unittest":        return mConfigUnittest ? 1 : -1;
			case "D_Version2":      return 1;
			case "none":            return -1;
			case "all":             return 1;
			default:                return 0;
		}
	}
	
	bool isVersionEnabled(int line, wstring ident, int debugOrVersion)
	{
		if(dLex.isInteger(ident))
			return isVersionEnabled(line, to!int(ident), debugOrVersion);
		
		if (debugOrVersion)
		{
			if(mConfigRelease)
				return false;
			if(ident.length == 0)
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
			case TokenColor.Operator:    return TokenColor.StringOperator;
			default: break;
		}
		return type;
	}
	
	static assert(VersionParseState.max <= 15);
	
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
			break;
			
		case VersionParseState.VersionParsed:
			if(text == "=")
				parseState = VersionParseState.AssignParsed;
			else if(text == "(")
				parseState = VersionParseState.ParenLParsed;
			else if(debugOrVersion)
			{
				if(isVersionEnabled(iLine, "", debugOrVersion))
					parseState = VersionParseState.IdleEnabled;
				else
					parseState = VersionParseState.IdleDisabled;
			}
			else
				parseState = VersionParseState.IdleEnabled;
			break;
			
		case VersionParseState.AssignParsed:
			if(dLex.isIdentifier(text))
			{
				if(!defineVersion(iLine, text, debugOrVersion, versionsChanged))
					ntype |= 5 << 14; // red ~~~~
			}
			else if(dLex.isInteger(text))
				defineVersion(iLine, to!int(text), debugOrVersion, versionsChanged);
			parseState = VersionParseState.IdleEnabled;
			break;
			
		case VersionParseState.ParenLParsed:
			if(dLex.isIdentifier(text) || dLex.isInteger(text))
			{
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
		
		if(versionsChanged || state != prevState)
		{
			ln++;
			while(ln < mLineState.length)
				mLineState[ln++] = -1;
			
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
			changes += modifyValue(mConfig.GetProjectOptions().versionids, mConfigVersions[kIndexVersion]);
			changes += modifyValue(mConfig.GetProjectOptions().debugids,   mConfigVersions[kIndexDebug]);
			changes += modifyValue(mConfig.GetProjectOptions().release,    mConfigRelease);
			changes += modifyValue(mConfig.GetProjectOptions().useUnitTests, mConfigUnittest);
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
	
	void OnConfigModified()
	{
		int changes = UpdateConfig();
		changes += modifyValue(Package.GetGlobalOptions().ColorizeVersions, mColorizeVersions);
		
		if(changes)
		{
			mLineState[] = -1;
			mSource.ReColorizeLines(0, -1);
		}
	}
	
}

