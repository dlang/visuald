// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details
//
///////////////////////////////////////////////////////////////////////
//
// idl2d - convert IDL or header files to D
//
// 
//
module idl2d;

import tokenizer;
import tokutil;
import dgutil;

import std.string;
import std.file;
import std.path;
import std.stdio;
import std.ctype;
import std.algorithm;
import std.getopt;
import std.utf;
import std.windows.charset;
import core.memory;

version = remove_pp;
version = static_if_to_version;
version = vsi;
version = macro2template;
version = targetD2;

class Source
{
	string filename;
	string text;
	TokenList tokens;
}

// endsWith does not work reliable and crashes on page end
bool _endsWith(string s, string e)
{
	return (s.length >= e.length && s[$-e.length .. $] == e);
}

class idl2d
{
	///////////////////////////////////////////////////////
	// configuration
	string vsi_base_path = r"c:\l\vs9SDK";
	string dte_path   = r"m:\s\d\visuald\trunk\sdk\vsi\idl\";
	string win_path   = r"c:\Programme\Microsoft SDKs\Windows\v6.0A\Include\";
	string sdk_d_path = r"m:\s\d\visuald\trunk\sdk\";

	string packageVSI = "sdk.vsi.";
	string packageWin = "sdk.win32.";
	string packageNF  = "sdk.port.";
	string keywordPrefix = "sdk_";

	string vsi_path; //   = vsi_base_path ~ r"\VisualStudioIntegration\Common\IDL\";
	string vsi_hpath; //  = vsi_base_path ~ r"\VisualStudioIntegration\Common\Inc\";

	string vsi_d_path; // = sdk_d_path ~ r"vsi\";
	string win_d_path; // = sdk_d_path ~ r"win32\";

	string[] win_idl_files;
	string[] vsi_idl_files;
	string[] vsi_h_files;
	string[] dte_idl_files;
	
	version(vsi) bool vsi = true;
	else         bool vsi = false;
	
	void initFiles()
	{
		win_idl_files = [ "windef.h", "sdkddkver.h", "basetsd.h", "ntstatus.h", 
			"winnt.h", "winbase.h", "winuser.h", "ktmtypes.h", 
			"winerror.h", "winreg.h", "reason.h", "commctrl.h",
			"wingdi.h", "prsht.h", "rpcdce.h" /*, "rpcdcep.h"*/ ];
		
		win_idl_files ~= [ "unknwn.idl", "oaidl.idl", "objidl.idl", "wtypes.idl", "oleidl.idl", 
			"ocidl.idl", "docobj.idl", "oleauto.h", "objbase.h",
			"mshtmcid.h", "xmldom.idl", "xmldso.idl", "xmldomdid.h", "xmldsodid.h", "idispids.h" ];

		if(vsi)
		{
			vsi_idl_files = [ "shared.idh", "vsshell.idl", "*.idl", "*.idh" ];
			vsi_h_files   = [ "completionuuids.h", "contextuuids.h", "textmgruuids.h", "vsshelluuids.h", "vsdbgcmd.h",
				"venusids.h", "stdidcmd.h", "vsshlids.h", "mnuhelpids.h", "WCFReferencesIds.h",
				"vsdebugguids.h", "VSRegKeyNames.h", "SCGuids.h", "DSLToolsCmdID.h", "wbids.h", "sharedids.h",
				"vseeguids.h", "version.h"  ];
			dte_idl_files = [ "*.idl" ];
		}
	}

	// see also preDefined, isExpressionToken, convertDefine, convertText, translateToken
	///////////////////////////////////////////////////////

	string[string] tokImports;
	int[string] disabled_defines;
	int[string] disabled_ifdef;
	string[string] converted_defines;
	bool[] pp_enable_stack;
	string[] elif_braces_stack;
	bool convert_next_cpp_quote = true;
	bool cpp_quote_in_comment = false;
	bool[string] classes;
	string[string] aliases;
	bool[string] enums;

	string[] currentImports;
	string[] addedImports;

	static string cpp_string(string txt)
	{
		string ntxt;
		bool escapeNext = false;
		foreach(dchar ch; txt)
		{
			if(escapeNext)
			{
				switch(ch)
				{
				case '\\': ch = '\\'; break;
				case 'a':  ch = '\a'; break;
				case 'r':  ch = '\r'; break;
				case 'n':  ch = '\n'; break;
				case 't':  ch = '\t'; break;
				case '"':  ch = '\"'; break;
				case '\'': ch = '\''; break;
				default:   break;
				}
				escapeNext = false;
			}
			else if(ch == '\\')
			{
				escapeNext = true;
				continue;
			}
			ntxt ~= toUTF8((&ch)[0..1]);
		}
		return ntxt;
	}

	static string removeDuplicateEmptyLines(string txt)
	{
		string ntxt;
		uint npos = 0;
		uint pos = 0;
		while(pos < txt.length)
		{
			dchar ch = decode(txt, pos);
			if(ch == '\n')
			{
				uint nl = 0;
				uint nlpos = pos; // positions after nl
				uint lastnlpos = pos;
				while(pos < txt.length)
				{
					ch = decode(txt, pos);
					if(ch == '\n')
					{
						nl++;
						lastnlpos = pos;
					}
					else if(!isspace(ch))
						break;
				}
				if(nl > 1)
				{
					ntxt ~= txt[npos .. nlpos];
					ntxt ~= '\n';
					npos = lastnlpos;
				}
			}
		}
		ntxt ~= txt[npos .. pos];
		return ntxt;
	}
	
	unittest
	{
		string txt;
		txt = removeDuplicateEmptyLines("abc\n\n\nefg");
		assert(txt == "abc\n\nefg");
		txt = removeDuplicateEmptyLines("abc\n\nefg");
		assert(txt == "abc\n\nefg");
	}
	
	void comment_line(ref TokenIterator tokIt)
	{
		TokenIterator it = tokIt + 1;
		string txt = tokIt.pretext ~ "// " ~ tokIt.text;
		while(!it.atEnd() && it.pretext.indexOf('\n') < 0 && it.type != Token.EOF)
		{
			txt ~= it.pretext ~ it.text;
			it.advance();
		}
		if(!it.atEnd())
		{
			tokIt.eraseUntil(it);
			tokIt.pretext = txt ~ tokIt.pretext;
		}
		else
			tokIt.text = "// " ~ tokIt.text;
	}

	void reinsert_cpp_quote(ref TokenIterator tokIt)
	{
		TokenIterator it = tokIt;
		string text;
		while(!it.atEnd() && it.text == "cpp_quote")
		{
			assert(it[1].text == "(");
			assert(it[2].type == Token.String);
			assert(it[3].text == ")");
			text ~= it.pretext;
			text ~= strip(it[2].text[1..$-1]);
			it += 4;
		}
		bool endsWithBS = text.endsWith("\\") != 0;
		bool quote = text.indexOf("\\\n") >= 0 || endsWithBS || !convert_next_cpp_quote;
		if(quote)
			text = tokIt.pretext ~ "/+" ~ text[tokIt.pretext.length .. $] ~ "+/";
		convert_next_cpp_quote = !endsWithBS;

		TokenList tokens = scanText(text, tokIt.lineno, true);
		tokIt.eraseUntil(it);
		tokIt = insertTokenList(tokIt, tokens);
	}

	bool handle_cpp_quote(ref TokenIterator tokIt, bool inEnum)
	{
		// tokIt on "cpp_quote"
		TokenIterator it = tokIt;
		assert(it[1].text == "(");
		assert(it[2].type == Token.String);
		assert(it[3].text == ")");
		string text = strip(it[2].text[1..$-1]);
		
		string txt = text;
		bool convert = convert_next_cpp_quote;
		convert_next_cpp_quote = true;

		if(cpp_quote_in_comment || text.startsWith("/*"))
		{
			txt = replace(text, "\\\"", "\"");
			cpp_quote_in_comment = (text.indexOf("*/") < 0);
		}
		else if(text.startsWith("//"))
			txt = replace(text, "\\\"", "\"");
		else if(text.endsWith("\\")) // do not convert multi-line #define
		{
			convert_next_cpp_quote = false;
			convert = false;
		}
		else if(text.startsWith("#"))
		{
			txt = replace(txt, "\\\"", "\"");
			txt = convertPP(txt, tokIt.lineno, inEnum);
		}
		
		if(convert)
		{
			string pretext = tokIt.pretext;
			tokIt.erase();
			tokIt.erase();
			tokIt.erase();
			tokIt.erase();

			txt = cpp_string(txt);
			TokenList tokens = scanText(txt, tokIt.lineno, false);
			tokIt = insertTokenList(tokIt, tokens);
			tokIt.pretext = pretext ~ tokIt.pretext;
		}
		else
			tokIt.pretext ~= "// ";

		return convert;
	}

	void reinsertTextTokens(ref TokenIterator tokIt, string text)
	{
		string pretext;
		if(!tokIt.atEnd())
		{
			pretext = tokIt.pretext;
			tokIt.erase();
		}
		TokenList tokens = scanText(text, tokIt.lineno, false);
		tokIt = insertTokenList(tokIt, tokens);
		tokIt.pretext = pretext ~ tokIt.pretext;
	}

	bool isExpressionToken(TokenIterator tokIt, bool first)
	{
		int type = tokIt.type;
		switch(type)
		{
		case Token.Identifier:
			switch(tokIt.text)
			{
			case "_far":
			case "_pascal":
			case "_cdecl":
			case "void":
				return false;
			default:
				return !(tokIt.text in disabled_defines);
			}
		case Token.String:
		case Token.Number:
		case Token.ParenL:
		case Token.BracketL:
		case Token.BraceL:
			return true;
		case Token.ParenR:
		case Token.BracketR:
		case Token.BraceR:
			if(!first)
				return tokIt.type != Token.Identifier && tokIt.type != Token.Number && tokIt.type != Token.ParenL;
		case Token.Equal:
		case Token.Unequal:
		case Token.LessThan:
		case Token.LessEq:
		case Token.GreaterThan:
		case Token.GreaterEq:
		case Token.Shl:
		case Token.Shr:
		case Token.Ampersand:
		case Token.Assign:
		case Token.Dot:
		case Token.Div:
		case Token.Mod:
		case Token.Xor:
		case Token.Or:
		case Token.OrOr:
		case Token.AmpAmpersand:
			return !first;
		case Token.Plus:
		case Token.Minus:
		case Token.Asterisk:
		case Token.Tilde:
			return true; // can be unary or binary operator
		case Token.Colon:
		case Token.Question:
			if(vsi)
				goto default;
			return !first;
			
		case Token.Comma:
			return !first && !(tokIt + 1).atEnd() && tokIt[1].type != Token.EOF;
			
		case Token.Struct:
			// struct at beginning of a cast?
			if(!tokIt.atBegin() && tokIt[-1].type == Token.ParenL)
				return true;
			return false;
			
		default:
			return false;
		}
	}

	bool isExpression(TokenIterator start, TokenIterator end)
	{
		if(start == end || start.type == Token.EOF)
			return false;
		if(!isExpressionToken(start, true))
			return false;
		for(TokenIterator it = start + 1; it != end && !it.atEnd() && it.type != Token.EOF; ++it)
			if(!isExpressionToken(it, false))
				return false;
		return true;
	}

	bool isPrimaryExpr(TokenIterator it)
	{
		if(it.atEnd())
			return false;
		if(it.text == "(" || it.type == Token.Number || it.type == Token.Identifier)
			return true;
		return false;
	}

	string getExpressionType(string ident, TokenIterator start, TokenIterator end)
	{
		while(start != end && start.text == "(" && start[1].text == "(")
			++start;
		if(start.text == "(" && start[1].type == Token.Identifier && start[2].text == ")" && isPrimaryExpr(start + 3))
			return start[1].text;
		if(start.text == "(" && start[1].type == Token.Identifier && start[2].text == "*" && start[3].text == ")"
			 && isPrimaryExpr(start + 4))
			return start[1].text ~ start[2].text;
		if(start.text == "(" && start[1].text == "struct" && start[2].type == Token.Identifier && start[3].text == "*" && start[4].text == ")"
			 && isPrimaryExpr(start + 5))
			return start[2].text ~ start[3].text;
		return "int";
	}

	string getArgumentType(string ident, TokenIterator start, TokenIterator end, string rettype)
	{
		switch(ident)
		{
		case "IS_INTRESOURCE":
		case "MAKEINTRESOURCEA":
		case "MAKEINTRESOURCEW":
		case "MAKEINTATOM":
			return "int";
		default:
			return rettype;
		}
	}

	void collectClasses(TokenList tokens)
	{
		for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; ++tokIt)
			if(tokIt.text == "class" || tokIt.text == "interface" || tokIt.text == "coclass")
				classes[tokIt[1].text] = true;
	}

	bool isClassIdentifier(string ident)
	{
		if(ident in classes)
			return true;
		return false;
	}

	// 1: yes, 0: undecided, -1: no
	int _preDefined(string cond)
	{
		switch(cond)
		{
		case "FALSE":
			return -2; // not defined for expression, but for #define
			
		case "0":
		case "MAC":
		case "_MAC":
		case "_WIN64":
		case "_WIN32_WCE":
		case "_IA64_":
		case "_M_AMD64":
		case "RC_INVOKED":
		case "MIDL_PASS":
		case "DO_NO_IMPORTS":
		case "_IMM_":
		case "NONAMELESSUNION":
		case "WIN16":
		case "INTEROPLIB":
		case "__INDENTSTYLE__":
		case "__CTC__":
		case "_CTC_GUIDS_":
		case "CTC_INVOKED":
		case "VS_PACKAGE_INCLUDE":
		case "URTBUILD":
		case "NOGUIDS":
		case "SHOW_INCLUDES":
		case "RGS_INVOKED":
		case "__RE_E_DEFINED__":
		case "OLE2ANSI":
		
		// for winbase
		case "STRICT":
		case "_M_CEE":
		case "_M_CEE_PURE":
		case "_DCOM_OA_REMOTING_":
		case "_DCOM_OC_REMOTING_":
		case "_SLIST_HEADER_":
		case "_RTL_RUN_ONCE_DEF":
			return -1;

		case "WINAPI":
		case "WINAPI_INLINE":
		case "APIENTRY":
		case "NTAPI":
		case "NTAPI_INLINE":
		case "interface":
			return 3; // predefined for #define, but not in normal text
		case "TRUE":
			return 2; // predefined for expression, but not for #define
		case "1":
		case "__cplusplus": 
		case "UNICODE": 
		case "DEFINE_GUID": 
		case "UNIX":
		case "__midl":
		case "_X86_":
		case "_M_IX86":
		case "MULTIPLE_WATCH_WINDOWS":
		case "PROXYSTUB_BUILD":
		case "(defined(_WIN32)||defined(_WIN64))&&!defined(OLE2ANSI)":
		case "defined(_INTEGRAL_MAX_BITS)&&_INTEGRAL_MAX_BITS>=64": // needed to define LONGLONG
		case "!defined SENTINEL_Reason": // reason.h

		//case "!defined(CTC_INVOKED)&&!defined(RGS_INVOKED)":
		//case "!defined(_DCOM_OA_REMOTING_)&&!defined(_DCOM_OC_REMOTING_)":
		//case "!defined(_DCOM_OA_REMOTING_)":
		//case "!defined(_DCOM_OC_REMOTING_)":
		case "_HRESULT_DEFINED":
//		case "_PALETTEENTRY_DEFINED":
//		case "_LOGPALETTE_DEFINED":
		case "_REFPOINTS_DEFINED":
		case "COMBOX_SANDBOX":

		// defined to avoid #define translation
		case "MAKE_HRESULT":
		case "CBPCLIPDATA":
		case "FACILITY_ITF":
		case "PFN_TSHELL_TMP":
		case "V_INT_PTR":
		case "VT_INT_PTR":
		case "V_UINT_PTR":
		case "VT_UINT_PTR":
		case "PKGRESETFLAGS":
		case "VSLOCALREGISTRYROOTHANDLE_TO_HKEY":
		case "DTE":
		case "Project":
		case "ProjectItem":
		case "IDebugMachine2_V7":
		case "EnumMachines_V7":
		case "IEnumDebugMachines2_V7":
		case "IID_IEnumDebugMachines2_V7":

		case "NULL":
		case "VOID":
		case "CONST":
		case "CALLBACK":
		case "NOP_FUNCTION":
		case "DECLARE_HANDLE":
		case "STDMETHODCALLTYPE":
		case "STDMETHODVCALLTYPE":
		case "STDAPICALLTYPE":
		case "STDAPIVCALLTYPE":
		case "STDMETHODIMP":
		case "STDMETHODIMP_":
		case "STDOVERRIDEMETHODIMP":
		case "STDOVERRIDEMETHODIMP_":
		case "IFACEMETHODIMP":
		case "IFACEMETHODIMP_":
		case "STDMETHODIMPV":
		case "STDMETHODIMPV_":
		case "STDOVERRIDEMETHODIMPV":
		case "STDOVERRIDEMETHODIMPV_":
		case "IFACEMETHODIMPV":
		case "IFACEMETHODIMPV_":
		case "_WIN32_WINNT":
		case "GetLastError":
		case "MF_END": // defined twice in winuser.h, but said to be obsolete
		case "__int3264":
			return 1;
		
		// winnt.h
		case "_WINDEF_":
		case "_WINBASE_":
			//if(vsi)
			//	return 1;
			break;
		case "_WIN32":
			//if(!vsi)
				return 1;
			break;
		default: 
			break;
		}

		if(_endsWith(cond, "_DEFINED") ||
		   _endsWith(cond, "_INCLUDED") ||
		   _endsWith(cond, "_h__") ||
		   _endsWith(cond, "_H__") ||
		   _endsWith(cond, "_H_") ||
		   startsWith(cond, "_INC_") ||
		   _endsWith(cond, "_IDH"))
			return -1;

		if(cond == "_" ~ toupper(currentModule) ~ "_")
			return -1;

		if(indexOf(cond, "(") < 0 && indexOf(cond, "|") < 0 && indexOf(cond, "&") < 0)
		{
			if (startsWith(cond, "CMD_ZOOM_"))
				return 1;

			if(startsWith(cond, "WINVER>") || startsWith(cond, "_WIN32_WINNT>") || startsWith(cond, "NTDDI_VERSION>"))
				return 1;
			if(startsWith(cond, "WINVER<") || startsWith(cond, "_WIN32_WINNT<") || startsWith(cond, "NTDDI_VERSION<"))
				return -1;
			if(startsWith(cond, "_MSC_VER>") || startsWith(cond, "_MSC_FULL_VER>"))
				return -1; // disable all msc specials
			if(startsWith(cond, "_MSC_VER<") || startsWith(cond, "_MSC_FULL_VER<"))
				return 1; // disable all msc specials
			if(startsWith(cond, "_WIN32_IE>"))
				return 1; // assue newest IE
			if(startsWith(cond, "NO"))
				return -1; // used to disable parts, we want it all
		}
		return 0;
	}

	int findLogicalOp(string cond, string op)
	{
		int paren = 0;
		for(int i = 0; i <= cond.length - op.length; i++)
		{
			if(paren == 0 && cond[i .. i+op.length] == op)
				return i;
			if(cond[i] == '(')
				paren++;
			else if(cond[i] == ')')
				paren--;
		}
		return -1;
	}

	int preDefined(string cond)
	{
		int sign = 1;

		for( ; ; )
		{
			int rc = _preDefined(cond);
			if(rc != 0)
				return sign * rc;

			if(startsWith(cond, "(") && _endsWith(cond, ")") && findLogicalOp(cond[1..$], ")") == cond.length - 2)
				cond = cond[1..$-1];
			else if(startsWith(cond, "defined(") && findLogicalOp(cond[8..$], ")") == cond.length - 9)
				cond = cond[8..$-1];
			else if(startsWith(cond, "!") && indexOf(cond[1..$-1], "&") < 0 && indexOf(cond[1..$-1], "|") < 0)
			{
				cond = cond[1..$];
				sign = -sign;
			}
			else
			{
				int idx = findLogicalOp(cond, "||");
				if(idx < 0)
					idx = findLogicalOp(cond, "&&");
				if(idx >= 0)
				{
					int rc1 = preDefined(cond[0..idx]);
					int rc2 = preDefined(cond[idx+2..$]);
					if(cond[idx] == '|')
						return rc1 > 0 || rc2 > 0 ? 1 : rc1 < 0 && rc2 < 0 ? -1 : 0;
					else // '&'
						return rc1 > 0 && rc2 > 0 ? 1 : rc1 < 0 || rc2 < 0 ? -1 : 0;
				}
				break;
			}
		}
		return 0;
	}

	int preDefined(TokenIterator start, TokenIterator end)
	{
		string txt = tokenListToString(start, end, false, true);
		int rc = preDefined(txt);

		if(rc == 0 && verbose)
			writefln("\"" ~ txt ~ "\" not defined/undefined");
		return rc;
	}

	void handleCondition(TokenIterator tokIt, TokenIterator lastIt, string pp)
	{
		string elif_braces;
		int predef = preDefined(tokIt + 1, lastIt + 1);
		if(pp == "pp_ifndef")
			predef = -predef;
		if(predef < 0)
		{
			tokIt.text = "version(none) /* " ~ tokIt.text;
			lastIt.text ~= " */ {/+";
			elif_braces = "+/} ";
		}
		else if(predef > 0)
		{
			tokIt.text = "version(all) /* " ~ tokIt.text;
			lastIt.text ~= " */ {";
			elif_braces = "} ";
		}
		else
		{
version(static_if_to_version)
{
			tokIt.text = "version(" ~ pp ~ ") /* " ~ tokIt.text;
			lastIt.text ~= " */ {";
}
else
{
			tokIt.text = "static if(" ~ pp ~ "(r\"";
			tokIt[1].pretext = "";
			lastIt.text ~= "\")) {";
}
			elif_braces = "} ";
		}

		if(pp == "pp_elif")
		{
			tokIt.text = elif_braces_stack[$-1] ~ "else " ~ tokIt.text;
			elif_braces_stack[$-1] = elif_braces;
		}
		else
		{
			elif_braces_stack ~= elif_braces;
			pp_enable_stack ~= true;
		}

	}

	bool inDisabledPPBranch()
	{
		foreach (string s; elif_braces_stack)
			if(startsWith(s, "+/"))
				return true;
		return false;
	}

	string convertPP(string text, int lineno, bool inEnum)
	{
		if(inEnum)
			return "// " ~ text;

		TokenList tokens = scanText(text, lineno, false);
		TokenIterator tokIt = tokens.begin();
		TokenIterator lastIt = tokens.end() - 1;
		if(lastIt.type == Token.EOF)
			--lastIt;

		switch(tokIt.text)
		{
		case "#include":
			tokIt.text = "public import";
			if(tokIt[1].type == Token.String)
				tokIt[1].text = fixImport(tokIt[1].text) ~ ";";
			else if(tokIt[1].text == "<")
			{
				string inc;
				TokenIterator it = tokIt + 2;
				for( ; !it.atEnd() && it.text != ">"; it.erase())
					inc ~= it.pretext ~ it.text;

				tokIt[1].text = fixImport(inc);
				if(!it.atEnd())
					it.text = ";";
			}
			break;
		case "#if":
			handleCondition(tokIt, lastIt, "pp_if");
			break;
		case "#ifndef":
			handleCondition(tokIt, lastIt, "pp_ifndef");
			break;
		case "#ifdef":
			handleCondition(tokIt, lastIt, "pp_ifdef");
			break;
		case "#endif":
			if(pp_enable_stack.length == 0)
				throwException(tokIt.lineno, "unbalanced #endif");
			bool enabled = pp_enable_stack[$-1];
			pp_enable_stack = pp_enable_stack[0 .. $-1];
			if(!enabled)
				tokIt.pretext = "+/" ~ tokIt.pretext;
version(remove_pp)
			tokIt.text = elif_braces_stack[$-1] ~ "\n";
else
			tokIt.text = elif_braces_stack[$-1] ~ "// " ~ tokIt.text;
			elif_braces_stack = elif_braces_stack[0 .. $-1];
			break;
		case "#else":
			if(pp_enable_stack.length == 0)
				throwException(tokIt.lineno, "unbalanced #else");
			if(!pp_enable_stack[$-1])
			{
				tokIt.pretext = "+/" ~ tokIt.pretext;
				pp_enable_stack[$-1] = true;
			}
			if(elif_braces_stack[$-1].startsWith("+/"))
			{
version(remove_pp)
				tokIt.text = "+/} else {\n";
else
				tokIt.text = "+/} else { // " ~ tokIt.text;
				elif_braces_stack[$-1] = elif_braces_stack[$-1][2..$];
			}
			else
			{
version(remove_pp)
				tokIt.text = "} else {\n";
else
				tokIt.text = "} else { // " ~ tokIt.text;
			}
			break;
		case "#elif":
			if(pp_enable_stack.length == 0)
				throwException(tokIt.lineno, "unbalanced #elif");
			if(!pp_enable_stack[$-1])
			{
				tokIt.pretext = "+/" ~ tokIt.pretext;
				pp_enable_stack[$-1] = true;
			}
			handleCondition(tokIt, lastIt, "pp_elif");
			//tokIt[1].pretext = "";
			//lastIt.text ~= "\")) {";
			break;
		case "#define":
			convertDefine(tokIt);
			break;
		default:
			return "// " ~ text;
		}
		string txt = tokenListToString(tokens);
		return txt;
	}

	bool convertDefine(ref TokenIterator tokIt)
	{
		// tokIt on "#define"
		bool convert = true;
		bool predef = false;
		bool convertMacro = false;
		string argtype;
		string rettype;
		TokenIterator it = tokIt + 1;

		string ident = it.text;
		for( ; !it.atEnd(); ++it) {}
version(none){
			if(indexOf(it.pretext, "\\\n") >= 0)
			{
				convert = false;
				it.pretext = replace(it.pretext, "\\\n", "\\\n//");
			}
//			if(indexOf(it.pretext, '\n') >= 0)
//				break;
		}

		TokenIterator endIt = it;
		if(it[-1].type == Token.EOF)
			--endIt;

		int preDefType = preDefined(ident);
		if(ident in disabled_defines)
			predef = true;
		else if (preDefType == 3)
		{
			predef = true;
			convert = false;
		}
		else if (preDefType == 1 || preDefined("_" ~ ident ~ "_DEFINED") == 1)
			predef = true;
		else if(tokIt[2].text == "(" && tokIt[2].pretext.length == 0)
		{
			convert = false;
			if(tokIt[3].text == ")")
			{
				convertMacro = true;
				argtype = "";
				if(isExpression(tokIt + 4, endIt))
					rettype = getExpressionType(ident, tokIt + 4, endIt);
				else
					rettype = "void";
			}
			if(tokIt[3].type == Token.Identifier && tokIt[4].text == ")" && isExpression(tokIt + 5, endIt))
			{
				convertMacro = true;
				rettype = getExpressionType(ident, tokIt + 5, endIt);
				argtype = getArgumentType(ident, tokIt + 5, endIt, rettype);
			}
		}
		else if(ident.startsWith("CF_VS"))
		{
			convertMacro = true;
			rettype = "UINT";
		}
		else if(!isExpression(tokIt + 2, endIt))
			convert = false;
		else if(string* m = ident in converted_defines)
			if(*m != currentModule)
				predef = true;

		if((!convert && !convertMacro) || it[-1].text == "\\" || predef)
		{
			tokIt.pretext ~= "// ";
			convert = false;
		}

		if(convertMacro)
		{
			TokenIterator lastit = endIt;
			version(macro2template) tokIt.text = "auto";
			else tokIt.text = rettype;
			string ret = (rettype != "void" ? "return " : "");
			if(argtype.length)
			{
				version(macro2template) tokIt[3].pretext ~= "ARG)(ARG ";
				else tokIt[3].pretext ~= argtype ~ " ";
				tokIt[5].pretext ~= "{ " ~ ret;
				lastit = tokIt + 5;
			}
			else if(tokIt[2].text != "(" || tokIt[2].pretext != "")
			{
				tokIt[2].pretext = "() { " ~ ret ~ tokIt[2].pretext;
				lastit = tokIt + 2;
			}
			else
			{
				tokIt[4].pretext = " { " ~ ret ~ tokIt[4].pretext;
				lastit = tokIt + 4;
			}

			if(lastit == endIt)
				endIt.text ~= "; }";
			else
				endIt[-1].text ~= "; }";

			if(!inDisabledPPBranch())
				converted_defines[ident] = currentModule;
		}
		else if(convert)
		{
			if(it != tokIt + 1 && it != tokIt + 2 && it != tokIt + 3)
			{
				if(endIt == tokIt + 3 && tokIt[2].type == Token.Identifier && 
					!(tokIt[2].text in enums) && tokIt[2].text != "NULL")
				{
					if(tokIt[2].text in disabled_defines)
						tokIt.pretext ~= "// ";
					tokIt.text = "alias";
					tokIt[1].text = tokIt[2].text;
					tokIt[2].text = ident;
				}
				else
				{
					tokIt.text = "dconst";
					(tokIt+2).insertBefore(createToken(" ", "=", Token.Assign, tokIt.lineno));
					if(ident.startsWith("uuid_"))
					{
						tokIt.insertAfter(createToken(" ", "GUID", Token.Identifier, tokIt.lineno));
						tokIt[4].pretext ~= "uuid(\"";
						endIt[-1].text ~= "\")";
					}
					else if(ident.startsWith("SID_S") || ident.startsWith("guid"))
					{
						tokIt.insertAfter(createToken(" ", "GUID", Token.Identifier, tokIt.lineno));
					}
					// winnt.h
					else if(ident.startsWith("SECURITY_") && tokIt[3].text == "{" && tokIt[15].text == "}")
					{
						tokIt.insertAfter(createToken(" ", "SID_IDENTIFIER_AUTHORITY", Token.Identifier, tokIt.lineno));
						tokIt[4].text = "{[";
						tokIt[16].text = "]}";
					}
					else if(_endsWith(ident, "_LUID") && tokIt[3].text == "{")
					{
						tokIt.insertAfter(createToken(" ", "LUID", Token.Identifier, tokIt.lineno));
					}
				}
			}
			else
				tokIt.pretext ~= "// ";
			
			Token tok = createToken("", ";", Token.Comma, tokIt.lineno);
			endIt.insertBefore(tok);
			if(!inDisabledPPBranch())
				converted_defines[ident] = currentModule;
		}
		else if (!predef)
			disabled_defines[ident] = 1;

		string repl = (convert || convertMacro ? "\n" : "\\\n//");
		for(it = tokIt; !it.atEnd(); ++it)
			if(indexOf(it.pretext, "\\\n") >= 0)
				it.pretext = replace(it.pretext, "\\\n", repl);

		tokIt = it - 1;
		return convert || convertMacro;
	}

	void disable_macro(ref TokenIterator tokIt)
	{
		TokenIterator it = tokIt + 1;
		if(it.text == "(")
		{
			if(!advanceToClosingBracket(it))
				return;
		}
version(all) 
{
		tokIt.insertBefore(createToken("", "/", Token.Div, tokIt.lineno));
		tokIt.insertBefore(createToken("", "+", Token.Plus, tokIt.lineno));
		tokIt[-2].pretext = tokIt.pretext;
		tokIt.pretext = " ";
		it.insertBefore(createToken(" ", "+", Token.Plus, tokIt.lineno));
		it.insertBefore(createToken("", "/", Token.Div, tokIt.lineno));
		tokIt = it - 1;
} else {
		tokIt.pretext ~= "/+";
		it[-1].text ~= "+/"; // it.pretext = "+/" ~ it.pretext;
		tokIt = it - 1;
}
	}

	void replaceExpressionTokens(TokenList tokens)
	{
		//replaceTokenSequence(tokens, "= (", "= cast(", true);
		replaceTokenSequence(tokens,       "$_not $_ident($_ident1)$_ident2", "$_not cast($_ident1)$_ident2", true);
		replaceTokenSequence(tokens,       "$_not $_ident($_ident1)$_num2",   "$_not cast($_ident1)$_num2", true);
		replaceTokenSequence(tokens,       "$_not $_ident($_ident1)-$_num2",  "$_not cast($_ident1)-$_num2", true);
		replaceTokenSequence(tokens,       "$_not $_ident($_ident1)~",        "$_not cast($_ident1)~", true);
		while(replaceTokenSequence(tokens, "$_not $_ident($_ident1)($expr)",  "$_not cast($_ident1)($expr)", true) > 0) {}
		replaceTokenSequence(tokens,       "$_not $_ident($_ident1)cast", "$_not cast($_ident1)cast", true);
		replaceTokenSequence(tokens,       "$_not $_ident($_ident1*)$_not_semi;",    "$_not cast($_ident1*)$_not_semi", true);
		replaceTokenSequence(tokens,       "$_not $_ident(struct $_ident1*)$_not_semi;",   "$_not cast(struct $_ident1*)$_not_semi", true);
		replaceTokenSequence(tokens,       "$_not $_ident($_ident1 $_ident2*)", "$_not cast($_ident1 $_ident2*)", true);
		replaceTokenSequence(tokens, "HRESULT cast", "HRESULT", true);
		replaceTokenSequence(tokens, "extern cast", "extern", true);
		replaceTokenSequence(tokens, "!cast", "!", true);
		replaceTokenSequence(tokens, "reinterpret_cast<$_ident>", "cast($_ident)", true);
		replaceTokenSequence(tokens, "reinterpret_cast<$_ident*>", "cast($_ident*)", true);
		replaceTokenSequence(tokens, "const_cast<$_ident*>", "cast($_ident*)", true);
	}

	string getNameWithoutExt(string fname)
	{
		string bname = getBaseName(fname);
		string name = getName(bname);
		if(name.length == 0)
			name = bname;
		return name;
	}

	string translateModuleName(string name)
	{
		name = tolower(name);
		if(name == "version" || name == "shared" || name == "align")
			return keywordPrefix ~ name;
		return name;
	}

	string translateFilename(string fname)
	{
		string name = getNameWithoutExt(fname);
		string nname = translateModuleName(name);
		if(name == nname)
			return fname;

		string dir = getDirName(fname);
		if(dir == ".")
			dir = "";
		else
			dir ~= "\\";
		string ext = getExt(fname);
		if(ext.length > 0)
			ext = "." ~ ext;
		return dir ~ nname ~ ext;
	}

	string _fixImport(string text)
	{
		text = replace(text, "/", "\\");
		text = replace(text, "\"", "");
		text = tolower(getNameWithoutExt(text));
		string ntext = translateFilename(text);
		string name = translateModuleName(text);
		foreach(string file; srcfiles)
		{
			if(translateModuleName(getNameWithoutExt(file)) == name)
				if(file.startsWith(win_path))
					return packageWin ~ ntext;
				else
					return packageVSI ~ ntext;
		}
		return packageNF ~ ntext;
	}

	string fixImport(string text)
	{
		string imp = _fixImport(text);
		currentImports.addunique(imp);
		return imp;
	}

	void convertGUID(TokenIterator tokIt)
	{
		// tokIt after "{"
		static bool numberOrIdent(Token tok)
		{ 
			return tok.type == Token.Identifier || tok.type == Token.Number; 
		}
		static string toByteArray(string txt)
		{
			string ntxt;
			for(int i = 0; i + 1 < txt.length; i += 2)
			{
				if(i > 0)
					ntxt ~= ",";
				ntxt ~= "0x" ~ txt[i .. i + 2];
			}
			return ntxt;
		}

		if (numberOrIdent(tokIt[0]) && tokIt[1].text == "-" &&
		    numberOrIdent(tokIt[2]) && tokIt[3].text == "-" &&
		    numberOrIdent(tokIt[4]) && tokIt[5].text == "-" &&
		    numberOrIdent(tokIt[6]) && tokIt[7].text == "-" &&
		    numberOrIdent(tokIt[8]) && tokIt[9].text == "}" &&
		    tokIt[8].text.length == 12)
		{
			// 00020405-0000-0000-C000-000000000046
			tokIt[0].text = "0x" ~ tokIt[0].text; tokIt[1].text = ",";
			tokIt[2].text = "0x" ~ tokIt[2].text; tokIt[3].text = ",";
			tokIt[4].text = "0x" ~ tokIt[4].text; tokIt[5].text = ",";
			
			tokIt[6].text = "[ " ~ toByteArray(tokIt[6].text); tokIt[7].text = ",";
			tokIt[8].text = toByteArray(tokIt[8].text) ~ " ]";
		}
		else if (tokIt[0].type == Token.Identifier && tokIt[1].text == "}")
		{
			// simple identifer defined elsewhere
			tokIt[-1].text = "";
			tokIt[1].text = "";
		}
		else if (tokIt[0].type == Token.Number && tokIt[1].text == "," &&
			 tokIt[2].type == Token.Number && tokIt[3].text == "," &&
			 tokIt[4].type == Token.Number && tokIt[5].text == ",")
		{
			// 0x0c539790, 0x12e4, 0x11cf, 0xb6, 0x61, 0x00, 0xaa, 0x00, 0x4c, 0xd6, 0xd8
			if(tokIt[6].text == "{")
			{
				tokIt[6].pretext ~= "["; // use pretext to avoid later substitution
				tokIt[6].text = "";
				tokIt[22].pretext ~= "]";
				tokIt[22].text = "";
			}
			else if(tokIt[6].text != "[")
			{
				int i;
				for(i = 0; i < 8; i++)
					if(tokIt[5 + 2*i].text != "," || tokIt[6 + 2*i].type != Token.Number)
						break;
				if (i >= 8)
				{
					tokIt[6].pretext = " [" ~ tokIt[6].pretext; 
					tokIt[21].pretext = " ]" ~ tokIt[21].pretext; 
				}
			}
		}
		else if(tokIt.type == Token.String)
		{
			string txt = tokIt.text;
			// "af855397-c4dc-478b-abd4-c3dbb3759e72"
			if(txt.length == 38 && txt[9] == '-' && txt[14] == '-' && txt[19] == '-' && txt[24] == '-')
			{
				tokIt.text = "0x" ~ txt[1..9] ~ ", 0x" ~ txt[10..14] ~ ", 0x" ~ txt[15..19] ~ ", [ " 
					~ "0x" ~ txt[20..22] ~ ", 0x" ~ txt[22..24];
				for(int i = 0; i < 6; i++)
					tokIt.text ~= ", 0x" ~ txt[25 + 2*i .. 27 + 2*i];
				tokIt.text ~= " ]";
			}
		}
		else
		{
			tokIt.pretext ~= "\"";
			while(tokIt.text != "}")
			{
				++tokIt;
				if(tokIt.atEnd())
					return;
			}
			tokIt.pretext = "\"" ~ tokIt.pretext;
		}
	}

	string convertText(TokenList tokens)
	{
		string prevtext;

		int braceCount;
		int parenCount;
		int brackCount;
		int enumLevel = -1;

		//replaceTokenSequence(tokens, "enum Kind { $enums ;",   "class Kind { /+ $enums; +/", false);

		// do some preprocessor replacements to make the text bracket-balanced
		if(currentModule == "oaidl")
		{
			replaceTokenSequence(tokens, "__VARIANT_NAME_1", "", true);
			replaceTokenSequence(tokens, "__VARIANT_NAME_2", "", true);
			replaceTokenSequence(tokens, "__VARIANT_NAME_3", "", true);
			replaceTokenSequence(tokens, "__VARIANT_NAME_4", "", true);
		}

		if(currentModule == "windef")
		{
			// avoid removal of #define TRUE 1
			replaceTokenSequence(tokens, "#ifndef TRUE\n#define TRUE$def\n#endif\n", "#define TRUE 1\n", false);
		}

		if(currentModule == "winnt")
		{
			replaceTokenSequence(tokens, "#if defined(MIDL_PASS)\ntypedef struct $_ident {\n"
				~ "#else$comment_else\n$else\n#endif$comment_endif", "$else", false);
			// remove int64 operations
			replaceTokenSequence(tokens, "#if defined(MIDL_PASS)$if_more\n#define Int32x32To64$def_more\n$defines\n"
				~ "#error Must define a target architecture.\n#endif\n", "/+\n$*\n+/", false);
			// remove rotate operations
			replaceTokenSequence(tokens, "#define RotateLeft8$def_more\n$defines\n"
				~ "#pragma intrinsic(_rotr16)\n", "/+\n$*\n+/", false);

			replaceTokenSequence(tokens, "typedef struct DECLSPEC_ALIGN($_num)", "align($_num) typedef struct", true);
			replaceTokenSequence(tokens, "struct DECLSPEC_ALIGN($_num)", "align($_num) struct", true);
		}

		if(currentModule == "commctrl")
		{
			// typos
			replaceTokenSequence(tokens, "PCCOMBOEXITEMW", "PCCOMBOBOXEXITEMW", true);
			replaceTokenSequence(tokens, "LPTBSAVEPARAMW", "LPTBSAVEPARAMSW", true);
		}
		if(currentModule == "oleauto")
		{
			replaceTokenSequence(tokens, "WINOLEAUTAPI_($_rettype)", "extern(Windows) $_rettype", true);
			replaceTokenSequence(tokens, "WINOLEAUTAPI", "extern(Windows) HRESULT", true);
		}
		replaceTokenSequence(tokens, "STDAPI", "extern(Windows) HRESULT", true);
		replaceTokenSequence(tokens, "STDAPICALLTYPE", "extern(Windows)", true);
		replaceTokenSequence(tokens, "WINOLEAPI_($_rettype)", "extern(Windows) $_rettype", true);
		replaceTokenSequence(tokens, "WINOLEAPI", "extern(Windows) HRESULT", true);
		
		replaceTokenSequence(tokens, "RPCRTAPI", "export", true);
		replaceTokenSequence(tokens, "RPC_STATUS", "int", true);
		replaceTokenSequence(tokens, "RPC_ENTRY", "extern(Windows)", true);
		replaceTokenSequence(tokens, "__RPC_USER", "extern(Windows)", true);
		replaceTokenSequence(tokens, "__RPC_STUB", "extern(Windows)", true);
		replaceTokenSequence(tokens, "__RPC_API", "extern(Windows)", true);
		replaceTokenSequence(tokens, "RPC_MGR_EPV", "void", true);
		replaceTokenSequence(tokens, "__RPC_FAR", "", true);
		
		// windef.h and ktmtypes.h
		replaceTokenSequence(tokens, "UOW UOW;", "UOW uow;", true);

		// enc.idl (FIELD_OFFSET already defined in winnt.h)
		replaceTokenSequence(tokens, "typedef struct _FIELD_OFFSET { $data } FIELD_OFFSET;",
		                             "struct _FIELD_OFFSET { $data };", true);

		// select unicode version of the API when defining without postfix A/W
		replaceTokenSequence(tokens, "#ifdef UNICODE\nreturn $_identW(\n#else\nreturn $_identA(\n#endif\n", 
			"    return $_identW(", false);

		replaceTokenSequence(tokens, "#ifdef __cplusplus\nextern \"C\" {\n#endif\n", "extern \"C\" {\n", false);
		replaceTokenSequence(tokens, "#ifdef defined(__cplusplus)\nextern \"C\" {\n#endif\n", "extern \"C\" {\n", false);
		replaceTokenSequence(tokens, "#ifdef defined __cplusplus\nextern \"C\" {\n#endif\n", "extern \"C\" {\n", false);
		replaceTokenSequence(tokens, "#ifdef __cplusplus\n}\n#endif\n", "}\n", false);

		for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; )
		{
			Token tok = *tokIt;

			switch(tok.text)
			{
			case "(":
				parenCount++;
				break;
			case ")":
				parenCount--; 
				break;
			case "[":
				brackCount++; 
				break;
			case "]":       
				brackCount--;
				break;
			case "{":
				braceCount++; 
				break;
			case "}":
				braceCount--;
				if(braceCount <= enumLevel)
					enumLevel = -1;
				break;

			case "enum":
				enumLevel = braceCount;
				break;
			case ";":
				enumLevel = -1;
				break;

			case "importlib":
				if(tokIt[1].text == "(" && tokIt[2].type == Token.String && tokIt[3].text == ")")
				{
					tokIt.text = "import";
					tokIt[1].text = "";
					tokIt[2].pretext = " ";
					tokIt[2].text = fixImport(tokIt[2].text);
					tokIt[3].text = "";
				}
				break;
			case "import":
				if(tokIt[1].type == Token.String)
				{
					tokIt.pretext ~= "public ";
					tokIt[1].text = fixImport(tokIt[1].text);
				}
				break;

			case "midl_pragma":
				comment_line(tokIt);
				continue;

			case "cpp_quote":
				//reinsert_cpp_quote(tokIt);
				if(handle_cpp_quote(tokIt, enumLevel >= 0))
					continue;
				break;

			case "version":
			case "align":
				if(tokIt[1].text != "(")
					tok.text = keywordPrefix ~ tok.text;
				break;

			case "unsigned":
			{
				string t;
				bool skipNext = true;
				switch(tokIt[1].text)
				{
				case "__int64": t = "ulong"; break;
				case "long":    t = "uint"; break;
				case "int":     t = "uint"; break;
				case "__int32": t = "uint"; break;
				case "__int3264": t = "uint"; break;
				case "short":   t = "ushort"; break;
				case "char":    t = "ubyte"; break;
				default:
					t = "uint"; 
					skipNext = false;
					break;
				}
				tok.text = t;
				if(skipNext)
					(tokIt + 1).erase();
				break;
			}
			case "signed":
			{
				string t;
				bool skipNext = true;
				switch(tokIt[1].text)
				{
				case "__int64": t = "long"; break;
				case "long":    t = "int"; break;
				case "int":     t = "int"; break;
				case "__int32": t = "int"; break;
				case "__int3264": t = "int"; break;
				case "short":   t = "short"; break;
				case "char":    t = "byte"; break;
				default:
					t = "int"; 
					skipNext = false;
					break;
				}
				tok.text = t;
				if(skipNext)
					(tokIt + 1).erase();
				break;
			}
			default:
				if(tok.type == Token.Macro && tok.text.startsWith("$"))
					tok.text = "_d_" ~ tok.text[1..$];
				else if(tok.type == Token.Number && (tok.text._endsWith("l") || tok.text._endsWith("L")))
					tok.text = tok.text[0..$-1];
				else if(tok.type == Token.Number && tok.text._endsWith("i64"))
					tok.text = tok.text[0..$-3] ~ "L";
				else if(tok.type == Token.String && tok.text.startsWith("L\""))
					tok.text = tok.text[1..$] ~ "w.ptr";
				else if(tok.type == Token.String && tok.text.startsWith("L\'"))
					tok.text = tok.text[1..$];
				else if(tok.text.startsWith("#"))
				{
					string txt = convertPP(tok.text, tok.lineno, enumLevel >= 0);
					reinsertTextTokens(tokIt, txt);
					continue;
				}
				else if(tok.text in disabled_defines)
					disable_macro(tokIt);
				else if(parenCount > 0)
				{
					// in function argument
					//if(tok.text == "const" || tok.text == "CONST")
					//	tok.text = "/*const*/";
					//else 
					if (tok.text.startsWith("REF") && tok.text != "REFSHOWFLAGS")
					{
						tokIt.insertBefore(createToken(tok.pretext, "ref", Token.Identifier, tokIt.lineno));
						tok.pretext = " ";
						tok.text = tok.text[3..$];
					}
				}
				else if(tok.type == Token.Identifier && enumLevel >= 0 && (tokIt[-1].text == "{" || tokIt[-1].text == ","))
					enums[tok.text] = true;
				break;
			}
			prevtext = tok.text;
			++tokIt;
		}

version(none) version(vsi)
{
		// wtypes.idl:
		replaceTokenSequence(tokens, "typedef ubyte           UCHAR;", "typedef ubyte           idl_UCHAR;",  true);
		replaceTokenSequence(tokens, "typedef short           SHORT;", "typedef short           idl_SHORT;",  true);
		replaceTokenSequence(tokens, "typedef ushort         USHORT;", "typedef ushort          idl_USHORT;", true);
		replaceTokenSequence(tokens, "typedef DWORD           ULONG;", "typedef DWORD           idl_ULONG;",  true);
		replaceTokenSequence(tokens, "typedef double         DOUBLE;", "typedef double          idl_DOUBLE;", true);
		replaceTokenSequence(tokens, "typedef char          OLECHAR;", "typedef char           idl_OLECHAR;", true);
		replaceTokenSequence(tokens, "typedef LPSTR        LPOLESTR;", "typedef LPSTR         idl_LPOLESTR;", true);
		replaceTokenSequence(tokens, "typedef LPCSTR      LPCOLESTR;", "typedef LPCSTR       idl_LPCOLESTR;", true);
		
		replaceTokenSequence(tokens, "WCHAR          OLECHAR;", "WCHAR           idl_OLECHAR;", true);
		replaceTokenSequence(tokens, "OLECHAR      *LPOLESTR;", "OLECHAR       *idl_LPOLESTR;", true);
		replaceTokenSequence(tokens, "const OLECHAR *LPCOLESTR;", "OLECHAR    *idl_LPCOLESTR;", true);

		replaceTokenSequence(tokens, "typedef LONG         SCODE;", "typedef LONG       vsi_SCODE;", true);
}

		//replaceTokenSequence(tokens, "interface IWinTypes { $data }", 
		//	"/+interface IWinTypes {+/\n$data\n/+ } /+IWinTypes+/ +/", true);

		// docobj.idl
		replaceTokenSequence(tokens, "OLECMDIDF_REFRESH_PROMPTIFOFFLINE = 0x2000, OLECMDIDF_REFRESH_THROUGHSCRIPT   = 0x4000,", "__XXX__", true);
		replaceTokenSequence(tokens, "OLECMDIDF_REFRESH_PROMPTIFOFFLINE = 0x2000, OLECMDIDF_REFRESH_THROUGHSCRIPT   = 0x4000", "", true);
		replaceTokenSequence(tokens, "OLECMDIDF_REFRESH_PROMPTIFOFFLINE = 0x2000", "", true);
		replaceTokenSequence(tokens, "__XXX__", "OLECMDIDF_REFRESH_PROMPTIFOFFLINE = 0x2000,\nOLECMDIDF_REFRESH_THROUGHSCRIPT   = 0x4000,", true);

		//vsshell.idl
		replaceTokenSequence(tokens, "typedef DWORD PFN_TSHELL_TMP;", "typedef PfnTshell PFN_TSHELL_TMP;", true);
		replaceTokenSequence(tokens, "MENUEDITOR_TRANSACTION_ALL,", "MENUEDITOR_TRANSACTION_ALL = 0,", true);
		replaceTokenSequence(tokens, "SCC_STATUS_INVALID = -1L,", "SCC_STATUS_INVALID = cast(DWORD)-1L,", true);

		replaceTokenSequence(tokens, "extern const __declspec(selectany)", "dconst", true);
		replaceTokenSequence(tokens, "EXTERN_C $args;", "/+EXTERN_C $args;+/", true);
		replaceTokenSequence(tokens, "SAFEARRAY($_ident)", "SAFEARRAY!($_ident)", true);

		replaceTokenSequence(tokens, "struct $_ident;", "/+ struct $_ident; +/", true);
		replaceTokenSequence(tokens, "class $_ident;", "/+ class $_ident; +/", true);
		replaceTokenSequence(tokens, "interface $_ident;", "/+ interface $_ident; +/", true);
		replaceTokenSequence(tokens, "dispinterface $_ident;", "/+ dispinterface $_ident; +/", true);
		replaceTokenSequence(tokens, "coclass $_ident;", "/+ coclass $_ident; +/", true);
		replaceTokenSequence(tokens, "library $_ident {", "version(all)\n{ /+ library $_ident +/", true);
		replaceTokenSequence(tokens, "importlib($expr);", "/+importlib($expr);+/", true);

version(remove_pp)
{
	string tsttxt = tokenListToString(tokens);
	
		while(replaceTokenSequence(tokens, "$_note else version(all) { $if } else { $else }", "$_note $if", true) > 0 ||
		      replaceTokenSequence(tokens, "$_note else version(all) { $if } $_not else", "$_note $if\n$_not", true) > 0 ||
		      replaceTokenSequence(tokens, "$_note else version(none) { $if } else { $else }", "$_note $else", true) > 0 ||
		      replaceTokenSequence(tokens, "$_note else version(none) { $if } $_not else", "$_note $_not", true) > 0 ||
		      replaceTokenSequence(tokens, "version(pp_if) { $if } else { $else }", "$else", true) > 0 ||
		      replaceTokenSequence(tokens, "version(pp_if) { $if } $_not else", "$_not", true) > 0 ||
		      replaceTokenSequence(tokens, "version(pp_ifndef) { $if } else { $else }", "$if", true) > 0 ||
		      replaceTokenSequence(tokens, "version(pp_ifndef) { $if } $_not else", "$if\n$_not", true) > 0) 
		{
			string rtsttxt = tokenListToString(tokens);
		}

	string ntsttxt = tokenListToString(tokens);
	
}

		while(replaceTokenSequence(tokens, "static if($expr) { } else { }", "", true) > 0 ||
		      replaceTokenSequence(tokens, "static if($expr) { } $_not else", "$_not", true) > 0 ||
		      replaceTokenSequence(tokens, "version($expr) { } else { }", "", true) > 0 ||
		      replaceTokenSequence(tokens, "version($expr) { } $_not else", "$_not", true) > 0) {}

		// move declaration at the top of the interface below the interface while keeping the order
		replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { $data }", 
					     "interface $_ident1 : $_identbase { $data\n} __eo_interface", true);
		while(replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { typedef $args; $data } $tail __eo_interface", 
						   "interface $_ident1 : $_identbase\n{ $data\n}\n$tail\ntypedef $args; __eo_interface", true) > 0
		   || replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { enum $args; $data } $tail __eo_interface", 
						   "interface $_ident1 : $_identbase\n{ $data\n}\n$tail\nenum $args; __eo_interface", true) > 0
		   || replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { dconst $_ident = $expr; $data } $tail __eo_interface", 
						   "interface $_ident1 : $_identbase\n{ $data\n}\n$tail\ndconst $_ident = $expr; __eo_interface", true) > 0
		   || replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { const $_identtype $_ident = $expr; $data } $tail __eo_interface", 
						   "interface $_ident1 : $_identbase\n{ $data\n}\n$tail\nconst $_identtype $_ident = $expr; __eo_interface", true) > 0
		   || replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { struct $args; $data } $tail __eo_interface", 
						   "interface $_ident1 : $_identbase\n{ $data\n}\n$tail\nstruct $args; __eo_interface", true) > 0
		   || replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { union $args; $data } $tail __eo_interface", 
						   "interface $_ident1 : $_identbase\n{ $data\n}\n$tail\nunion $args; __eo_interface", true) > 0
		   || replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { static if($expr) { $if } else { $else } $data } $tail __eo_interface", 
						   "interface $_ident1 : $_identbase\n{ $data\n}\n$tail\nstatic if($expr) {\n$if\n} else {\n$else\n} __eo_interface", true) > 0
		   || replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { version($expr) {/+ typedef $if } else { $else } $data } $tail __eo_interface", 
						   "interface $_ident1 : $_identbase\n{ $data\n}\n$tail\nversion($expr) {/+\ntypedef $if\n} else {\n$else\n} __eo_interface", true) > 0
			) {}
		replaceTokenSequence(tokens, "__eo_interface", "", true);

		replaceTokenSequence(tokens, "interface $_ident1 : $_identbase { $data const DISPID $constids }", 
			"interface $_ident1 : $_identbase { $data\n}\n\nconst DISPID $constids\n", true);
version(none)
{
		replaceTokenSequence(tokens, "typedef enum $_ident1 { $enums } $_ident2;", 
			"enum $_ident2\n{\n$enums\n}", true);
		replaceTokenSequence(tokens, "typedef enum { $enums } $_ident2;", 
			"enum $_ident2\n{\n$enums\n}", true);
		replaceTokenSequence(tokens, "typedef [$_ident3] enum $_ident1 { $enums } $_ident2;", 
			"enum $_ident2\n{\n$enums\n}", true);
		replaceTokenSequence(tokens, "enum $_ident1 { $enums }; typedef $_identbase $_ident2;", 
			"enum $_ident2 : $_identbase\n{\n$enums\n}", true);
} else {
		replaceTokenSequence(tokens, "typedef enum $_ident1 { $enums } $ident2;", 
			"enum /+$_ident1+/\n{\n$enums\n}\ntypedef int $ident2;", true);
		replaceTokenSequence(tokens, "typedef enum { $enums } $ident2;", 
			"enum\n{\n$enums\n}\ntypedef int $ident2;", true);
		replaceTokenSequence(tokens, "typedef [$info] enum $_ident1 { $enums } $ident2;", 
			"enum [$info] /+$_ident1+/\n{\n$enums\n}\ntypedef int $ident2;", true);
		replaceTokenSequence(tokens, "typedef [$info] enum { $enums } $ident2;", 
			"enum [$info]\n{\n$enums\n}\ntypedef int $ident2;", true);
		replaceTokenSequence(tokens, "enum $_ident1 { $enums }; typedef $_identbase $_ident2;", 
			"enum /+$_ident1+/ : $_identbase \n{\n$enums\n}\ntypedef $_identbase $_ident2;", true);
		replaceTokenSequence(tokens, "enum $_ident1 { $enums }; typedef [$info] $_identbase $_ident2;", 
			"enum /+$_ident1+/ : $_identbase \n{\n$enums\n}\ntypedef [$info] $_identbase $_ident2;", true);
		replaceTokenSequence(tokens, "enum $_ident1 { $enums };", 
			"enum /+$_ident1+/ : int \n{\n$enums\n}\ntypedef int $_ident1;", true);
		replaceTokenSequence(tokens, "typedef enum $_ident1 $_ident1;", "/+ typedef enum $_ident1 $_ident1; +/", true);
		replaceTokenSequence(tokens, "enum $_ident1 $_ident2", "$_ident1 $_ident2", true);
}

		replaceTokenSequence(tokens, "__struct_bcount($args)", "[__struct_bcount($args)]", true);
		replaceTokenSequence(tokens, "struct $_ident : $_opt public $_ident2 {", "struct $_ident { $_ident2 base;", true);

		replaceTokenSequence(tokens, "typedef struct { $data } $_ident2;", 
			"struct $_ident2\n{\n$data\n}", true);
		replaceTokenSequence(tokens, "typedef struct { $data } $_ident2, $expr;", 
			"struct $_ident2\n{\n$data\n}\ntypedef $_ident2 $expr;", true);
		replaceTokenSequence(tokens, "typedef struct $_ident1 { $data } $_ident2;", 
			"struct $_ident1\n{\n$data\n}\ntypedef $_ident1 $_ident2;", true);
		replaceTokenSequence(tokens, "typedef struct $_ident1 { $data } $expr;", 
			"struct $_ident1\n{\n$data\n}\ntypedef $_ident1 $expr;", true);
		replaceTokenSequence(tokens, "typedef [$props] struct $_ident1 { $data } $expr;", 
			"[$props] struct $_ident1\n{\n$data\n}\ntypedef $_ident1 $expr;", true);
		//replaceTokenSequence(tokens, "typedef struct $_ident1 { $data } *$_ident2;", 
		//	"struct $_ident1\n{\n$data\n}\ntypedef $_ident1 *$_ident2;", true);
		//replaceTokenSequence(tokens, "typedef [$props] struct $_ident1 { $data } *$_ident2;", 
		//	"[$props] struct $_ident1\n{\n$data\n}\ntypedef $_ident1 *$_ident2;", true);
		while(replaceTokenSequence(tokens, "struct { $data } $_ident2 $expr;", 
			"struct _ __ $_ident2 {\n$data\n} _ __ $_ident2 $_ident2 $expr;", true) > 0) {}

		replaceTokenSequence(tokens, "[$_expr1 uuid($_identIID) $_expr2] interface $_identClass : $_identBase {",
			"dconst GUID IID_ __ $_identClass = $_identClass.iid;\n\n" ~
			"interface $_identClass : $_identBase\n{\n    static dconst GUID iid = $_identIID;\n\n", true);
		replaceTokenSequence(tokens, "[$_expr1 uuid($IID) $_expr2] interface $_identClass : $_identBase {",
			"dconst GUID IID_ __ $_identClass = $_identClass.iid;\n\n" ~
			"interface $_identClass : $_identBase\n{\n    static dconst GUID iid = { $IID };\n\n", true);

		replaceTokenSequence(tokens, "[$_expr1 uuid($_identIID) $_expr2] coclass $_identClass {",
			"dconst GUID CLSID_ __ $_identClass = $_identClass.iid;\n\n" ~
			"class $_identClass\n{\n    static dconst GUID iid = $_identIID;\n\n", true);
		replaceTokenSequence(tokens, "[$_expr1 uuid($IID) $_expr2] coclass $_identClass {",
			"dconst GUID CLSID_ __ $_identClass = $_identClass.iid;\n\n" ~
			"interface $_identClass\n{\n    static dconst GUID iid = { $IID };\n\n", true);
		replaceTokenSequence(tokens, "coclass $_ident1 { $data }", "class $_ident1 { $data }", true);

		// replaceTokenSequence(tokens, "assert $expr;", "assert($expr);", true);

		replaceTokenSequence(tokens, "typedef union $_ident1 { $data } $_ident2 $expr;", 
			"union $_ident1\n{\n$data\n}\ntypedef $_ident1 $_ident2 $expr;", true);
		replaceTokenSequence(tokens, "typedef union $_ident1 switch($expr) $_ident2 { $data } $_ident3;",
			"union $_ident3 /+switch($expr) $_ident2 +/ { $data };", true);
		replaceTokenSequence(tokens, "typedef union switch($expr) { $data } $_ident3;",
			"union $_ident3 /+switch($expr) +/ { $data };", true);
		replaceTokenSequence(tokens, "union $_ident1 switch($expr) $_ident2 { $data };",
			"union $_ident1 /+switch($expr) $_ident2 +/ { $data };", true);
		replaceTokenSequence(tokens, "case $_ident1:", "[case $_ident1:]", true);
		replaceTokenSequence(tokens, "default:", "[default:]", true);
		replaceTokenSequence(tokens, "union { $data } $_ident2 $expr;", 
			"union _ __ $_ident2 {\n$data\n} _ __ $_ident2 $_ident2 $expr;", true);

		replaceTokenSequence(tokens, "typedef struct $_ident1 $expr;", "typedef $_ident1 $expr;", true);
		replaceTokenSequence(tokens, "typedef [$props] struct $_ident1 $expr;", "typedef [$props] $_ident1 $expr;", true);

		while (replaceTokenSequence(tokens, "typedef __nullterminated CONST $_identtype $_expr1, $args;", 
			"typedef __nullterminated CONST $_identtype $_expr1; typedef __nullterminated CONST $_identtype $args;", true) > 0) {}
		while (replaceTokenSequence(tokens, "typedef CONST $_identtype $_expr1, $args;", 
			"typedef CONST $_identtype $_expr1; typedef CONST $_identtype $args;", true) > 0) {}
		while (replaceTokenSequence(tokens, "typedef __nullterminated $_identtype $_expr1, $args;", 
			"typedef __nullterminated $_identtype $_expr1; typedef __nullterminated $_identtype $args;", true) > 0) {}
		while (replaceTokenSequence(tokens, "typedef [$info] $_identtype $_expr1, $args;", 
			"typedef [$info] $_identtype $_expr1; typedef [$info] $_identtype $args;", true) > 0) {}
		while (replaceTokenSequence(tokens, "typedef /+$info+/ $_identtype $_expr1, $args;", 
			"typedef /+$info+/ $_identtype $_expr1; typedef /+$info+/ $_identtype $args;", true) > 0) {}

		while (replaceTokenSequence(tokens, "typedef $_identtype $_expr1, $args;", 
			"typedef $_identtype $_expr1; typedef $_identtype $args;", true) > 0) {}
		while (replaceTokenSequence(tokens, "typedef void $_expr1, $args;", 
			"typedef void $_expr1; typedef void $args;", true) > 0) {};

		replaceTokenSequence(tokens, "typedef $_ident1 $_ident1;", "", true);
		replaceTokenSequence(tokens, "typedef interface $_ident1 $_ident1;", "", true);
		
		// Remote/Local version are made final to avoid placing them into the vtbl
		replaceTokenSequence(tokens, "[$pre call_as($arg) $post] $_not final", "[$pre call_as($arg) $post] final $_not", true);

		// Some properties use the same name as the type of the return value
		replaceTokenSequence(tokens, "$_identFun([$data] $_identFun $arg)", "$_identFun([$data] .$_identFun $arg)", true);

		// interface without base class is used as namespace
		replaceTokenSequence(tokens, "interface $_notIFace IUnknown { $_not static $data }", 
			"/+interface $_notIFace {+/ $_not $data /+} interface $_notIFace+/", true);
		replaceTokenSequence(tokens, "dispinterface $_ident1 { $data }", "interface $_ident1 { $data }", true);
		replaceTokenSequence(tokens, "module $_ident1 { $data }", "/+module $_ident1 {+/ $data /+}+/", true);
		replaceTokenSequence(tokens, "properties:", "/+properties:+/", true);
		replaceTokenSequence(tokens, "methods:", "/+methods:+/", true);
		replaceTokenSequence(tokens, "(void)", "()", true);
		replaceTokenSequence(tokens, "(VOID)", "()", true);
		replaceTokenSequence(tokens, "[in] ref $_ident", "in $_ident*", true); // in passes by value otherwise
		replaceTokenSequence(tokens, "[in]", "in", true);
		replaceTokenSequence(tokens, "[in,$_not out]", "[$_not] in", true);
		replaceTokenSequence(tokens, "[*]", "[0]", true);
		replaceTokenSequence(tokens, "[default]", "/+[default]+/", true);

		replaceExpressionTokens(tokens);

		replaceTokenSequence(tokens, "__success($args)", "/+__success($args)+/", true);
			
version(all) {
		replaceTokenSequence(tokens, "typedef const", "typedef CONST", true);
		replaceTokenSequence(tokens, "extern \"C\"", "extern(C)", true);
		replaceTokenSequence(tokens, "extern \"C++\"", "extern(C++)", true);
		replaceTokenSequence(tokens, "__bcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__bcount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__in_bcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__in_ecount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__in_xcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__in_bcount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__in_ecount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_bcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_xcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_bcount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_bcount_part($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_bcount_part_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_ecount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_ecount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_ecount_part($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_ecount_part_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_ecount_full($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_data_source($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_xcount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__out_has_type_adt_props($args)", "/+$*+/", true);
		
		replaceTokenSequence(tokens, "__inout_bcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__inout_ecount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__inout_xcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__inout_bcount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__inout_ecount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__inout_bcount_part($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__inout_ecount_part($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__inout_bcount_part_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__inout_ecount_part_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__deref_out_ecount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__deref_out_bcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__deref_out_xcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__deref_out_ecount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__deref_out_bcount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__deref_out_xcount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__deref_opt_out_bcount_full($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__deref_inout_ecount_z($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__field_bcount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__field_ecount($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__field_ecount_opt($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__in_range($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__declspec($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__in_range($args)", "/+$*+/", true);
		replaceTokenSequence(tokens, "__assume_bound($args);", "/+$*+/", true);
		replaceTokenSequence(tokens, "__asm{$args}", "assert(false, \"asm not translated\"); asm{naked; nop; /+$args+/}", true);
		replaceTokenSequence(tokens, "__asm $_not{$stmt}", "assert(false, \"asm not translated\"); asm{naked; nop; /+$_not$stmt+/} }", true);
		replaceTokenSequence(tokens, "sizeof($_ident)", "$_ident.sizeof", true);
		replaceTokenSequence(tokens, "sizeof($args)", "($args).sizeof", true);

		// bitfields:
		replaceTokenSequence(tokens, "$_identtype $_identname : $_num;",   "__bf $_identtype, __quote $_identname __quote, $_num __eobf", true);
		replaceTokenSequence(tokens, "$_identtype $_identname : $_ident;", "__bf $_identtype, __quote $_identname __quote, $_ident __eobf", true);
		replaceTokenSequence(tokens, "$_identtype : $_num;", "__bf $_identtype, __quote __quote, $_num __eobf", true);
		replaceTokenSequence(tokens, "__eobf __bf", ",\n\t", true);
		replaceTokenSequence(tokens, "__bf", "mixin(bitfields!(", true);
		replaceTokenSequence(tokens, "__eobf", "));", true);

		// remove version between identifiers, must be declaration
		while(replaceTokenSequence(tokens, "$_ident1 version(all)  { $if } else { $else } $_ident2", "$_ident1 $if $_ident2", true) > 0
		   || replaceTokenSequence(tokens, "$_ident1 version(all)  { $if } $_ident2", "$_ident1 $if $_ident2", true) > 0
		   || replaceTokenSequence(tokens, "$_ident1 version(none) { $if } else { $else } $_ident2", "$_ident1 $else $_ident2", true) > 0
		   || replaceTokenSequence(tokens, "$_ident1 version(none) { $if } $_ident2", "$_ident1 $_ident2", true) > 0) {}

		// __stdcall
	version(none)
	{
		replaceTokenSequence(tokens, "$_identtype NTAPI", "extern(Windows) $_identtype", true);
		replaceTokenSequence(tokens, "$_identtype (NTAPI", "extern(Windows) $_identtype (", true);
		replaceTokenSequence(tokens, "$_identtype WINAPI", "extern(Windows) $_identtype", true);
		replaceTokenSequence(tokens, "$_identtype (WINAPI", "extern(Windows) $_identtype (", true);
		replaceTokenSequence(tokens, "$_identtype (/+$_ident+/ WINAPI", "extern(Windows) $_identtype (", true);
		replaceTokenSequence(tokens, "$_identtype APIENTRY", "extern(Windows) $_identtype", true);
		replaceTokenSequence(tokens, "$_identtype (APIENTRY", "extern(Windows) $_identtype (", true);
		replaceTokenSequence(tokens, "$_identtype (CALLBACK", "extern(Windows) $_identtype (", true);
	} else {
		replaceTokenSequence(tokens, "NTAPI", "extern(Windows)", true);
		replaceTokenSequence(tokens, "WINAPI", "extern(Windows)", true);
		replaceTokenSequence(tokens, "APIENTRY", "extern(Windows)", true);
		replaceTokenSequence(tokens, "CALLBACK", "extern(Windows)", true);
	}

		replaceTokenSequence(tokens, "$_identtype extern(Windows)", "extern(Windows) $_identtype", true);
		replaceTokenSequence(tokens, "$_identtype* extern(Windows)", "extern(Windows) $_identtype*", true);
		replaceTokenSequence(tokens, "$_identtype (extern(Windows)", "extern(Windows) $_identtype (", true);
		replaceTokenSequence(tokens, "$_identtype* (extern(Windows)", "extern(Windows) $_identtype* (", true);
		replaceTokenSequence(tokens, "$_identtype (/+$_ident+/ extern(Windows)", "extern(Windows) $_identtype (", true);
	
		replaceTokenSequence(tokens, "DECLARE_HANDLE($_ident);", "typedef HANDLE $_ident;", true);
		replaceTokenSequence(tokens, "__inline $_identFun(", "inline int $_identFun(", true);
}
version(targetD2)
{
		replaceTokenSequence(tokens, "$_ident const*", "dconst($_ident)*", true);
		replaceTokenSequence(tokens, "const $_ident*", "dconst($_ident)*", true);
		replaceTokenSequence(tokens, "CONST $_ident*", "dconst($_ident)*", true);
}
else
{
		replaceTokenSequence(tokens, "const $_ident*", "/+const+/ $_ident*", true);
}
		replaceTokenSequence(tokens, "in const $_not(", "in $_not", false);
		

		if(currentModule == "prsht")
		{
			replaceTokenSequence(tokens, "alias _PROPSHEETPAGEA $_ident;", "alias $_ident _PROPSHEETPAGEA;", true);
			replaceTokenSequence(tokens, "alias _PROPSHEETPAGEW $_ident;", "alias $_ident _PROPSHEETPAGEW;", true);
		}
		//replaceTokenSequence(tokens, "[$args]", "\n\t\t/+[$args]+/", true);

		TokenIterator inAlias = tokens.end();
		for(TokenIterator tokIt = tokens.begin(); !tokIt.atEnd(); ++tokIt)
		{
			Token tok = *tokIt;
			//tok.pretext = tok.pretext.replace("//D", "");
			tok.text = translateToken(tok.text);
			if(tok.text == "[" && tokIt[1].text == "]")
			{
				if(tokIt[2].text == ";")
					tokIt[1].pretext ~= "0"; // in struct
				else if(tokIt[2].text == "," || tokIt[2].text == ")" && tokIt[-1].type == Token.Identifier)
				{
					tok.text = "";
					tokIt[1].text = "";
					tokIt[-1].pretext ~= "*"; // in function argument
				}
			}
			else if(tok.text == "[" && tokIt[1].text != "]")
			{
				if((tokIt.atBegin() || tokIt[-1].text != "{" || tokIt[-2].text != "=") && 
				   (tokIt[1].type != Token.Number || tokIt[2].text != "]") &&
				   (tokIt[2].text != "]" || tokIt[3].text != ";"))
				{
					TokenIterator bit = tokIt;
					//if(advanceToClosingBracket(bit) && bit.text != ";")
					{
						if(tokIt.atBegin || (tokIt[-1].text != "(" && tokIt[-1].text != "alias"))
							if (tok.pretext.indexOf('\n') < 0)
								tok.pretext ~= "\n\t\t";
						tok.text = "/+[";
					}
				}
			}
			else if(tok.text == "]" && tokIt[-1].text != "[")
			{
				TokenIterator openit = tokIt;
				if(retreatToOpeningBracket(openit) && 
				   (openit.atBegin || (openit-1).atBegin || openit[-1].text != "{" || openit[-2].text != "="))
					if((tokIt[-1].type != Token.Number || tokIt[-2].text != "[") &&
					   (tokIt[-2].text != "[" || tokIt[1].text != ";"))
						tok.text = "]+/";
			}
			else if(tok.text == "struct" && tokIt[1].type == Token.Identifier && tokIt[2].text != "{")
			{
				if(tokIt[1].text != "__" && tokIt[1].text != "_")
				{
					// forward reference to struct type
					tok.text = "";
					if(tokIt[1].text.startsWith("tag"))
						tokIt[1].text = tokIt[1].text[3..$];
				}
			}
			else if((tok.text == "GUID" || tok.text == "IID" || tok.text == "CLSID") && 
				tokIt[1].type == Token.Identifier && tokIt[2].text == "=" && tokIt[3].text == "{")
			{
				convertGUID(tokIt + 4);
			}
			else if(tok.text == "__quote")
			{
				tok.pretext = "";
				tok.text = "\"";
				tokIt[1].pretext = "";
			}
			else if(tok.text == "*" && !tokIt.atBegin() && isClassIdentifier(tokIt[-1].text))
				tok.text = "";
			else if(tok.type == Token.String && tok.text.length > 4 && tok.text[0] == '\'')
				tok.text = "\"" ~ tok.text[1 .. $-1] ~ "\"";

			else if(tok.text == "in" && (tokIt[1].text in classes))
				tok.text = "/+[in]+/";

			else if(tok.text == "alias")
				inAlias = tokIt;
			else if(tok.text == ";" && !inAlias.atEnd())
			{
				if(tokIt[-1].type == Token.Identifier)
				{
					if (string* s = tokIt[-1].text in aliases)
					{
						if(*s != currentFullModule)
						{
							inAlias.pretext ~= "/+";
							tok.text ~= "+/";
							if(!currentImports.contains(*s))
								addedImports.addunique(*s);
						}
					}
					else
						aliases[tokIt[-1].text] = currentFullModule;
				}
				inAlias = tokens.end();
			}
		}

		// vsshell.idl:
		replaceTokenSequence(tokens, "DEFINE_GUID($_ident,$_num1,$_num2,$_num3,$_num4,$_num5,$_num6,$_num7,$_num8,$_num9,$_numA,$_numB)",
			"const GUID $_ident = { $_num1,$_num2,$_num3, [ $_num4,$_num5,$_num6,$_num7,$_num8,$_num9,$_numA,$_numB ] }", true);
		replaceTokenSequence(tokens, "EXTERN_GUID($_ident,$_num1,$_num2,$_num3,$_num4,$_num5,$_num6,$_num7,$_num8,$_num9,$_numA,$_numB)",
			"const GUID $_ident = { $_num1,$_num2,$_num3, [ $_num4,$_num5,$_num6,$_num7,$_num8,$_num9,$_numA,$_numB ] }", true);
		string txt = tokenListToString(tokens, true);

		return txt;
	}

	string translateToken(string text)
	{
		switch(text)
		{
		case "dconst":    return "const";

		case "_stdcall":  return "/*_stdcall*/";
		case "_fastcall": return "/*_fastcall*/";
		case "__stdcall": return "/*__stdcall*/";
		case "__cdecl":   return "/*__cdecl*/";
		case "__gdi_entry": return "/*__gdi_entry*/";
	
		//case "const":     return "/*const*/";
		case "inline":    return "/*inline*/";
		case "__int64":   return "long";
		case "__int32":   return "int";
		case "__int3264": return "int";
		case "long":      return "int";
		case "typedef":   return "alias";
		case "bool":      return "idl_bool";
		case "GUID_NULL": return "const_GUID_NULL";
		case "NULL":      return "null";

		// winbase annotations
		case "__in":      return "/*__in*/";
		case "__in_opt":  return "/*__in_opt*/";
		case "__in_z_opt":  return "/*__in_z_opt*/";
		case "__in_bound":  return "/*__in_bound*/";
			
		case "__allocator":     return "/*__allocator*/";
		case "__out":     return "/*__out*/";
		case "__out_opt": return "/*__out_opt*/";
		case "__inout":   return "/*__inout*/";
		case "__deref":   return "/*__deref*/";
		case "__deref_inout_opt": return "/*__deref_inout_opt*/";
		case "__deref_out_opt": return "/*__deref_out_opt*/";
		case "__deref_inout": return "/*__deref_inout*/";
		case "__inout_opt":   return "/*__inout_opt*/";
		case "__deref_out":   return "/*__deref_out*/";
		case "__deref_opt_out":   return "/*__deref_opt_out*/";
		case "__deref_opt_out_opt":   return "/*__deref_opt_out_opt*/";
		case "__callback":  return "/*__callback*/";
		case "__format_string": return "/*__format_string*/";
		case "__reserved":  return "/*__reserved*/";
		case "__notnull": return "/*__notnull*/";
		case "__nullterminated": return "/*__nullterminated*/";
		case "__nullnullterminated": return "/*__nullnullterminated*/";
		case "__checkReturn": return "/*__checkReturn*/";
		case "volatile":  return "/*volatile*/";
		case "__inline":  return "/*__inline*/";
		case "__forceinline":  return "/*__forceinline*/";
		case "IN":        return "/*IN*/";
		case "OUT":       return "/*OUT*/";
		case "NEAR":      return "/*NEAR*/";
		case "FAR":       return "/*FAR*/";
		case "HUGEP":     return "/*HUGEP*/";
		case "OPTIONAL":  return "/*OPTIONAL*/";
		case "DECLSPEC_NORETURN": return "/*DECLSPEC_NORETURN*/";
		case "CONST":     return "/*CONST*/";
		case "VOID":      return "void";
		case "wchar_t":   return "wchar";
		case "->":        return ".";

		// vslangproj.d
		case "prjBuildActionCustom": return "prjBuildActionEmbeddedResource";

		default:
			if(string* ps = text in tokImports)
				text = *ps ~ "." ~ text;
			break;
		}
		return text;
	}

	void addSource(string file)
	{
		string base = basename(file);
		if(excludefiles.contains(base))
			return;
		
		if(!srcfiles.contains(file))
			srcfiles ~= file;
	}

	void addSourceByPattern(string file)
	{
		SpanMode mode = SpanMode.shallow;
		if (file[0] == '+')
		{
			mode = SpanMode.depth;
			file = file[1..$];
		}
		string path = dirname(file);
		string pattern = basename(file);
		foreach (string name; dirEntries(path, mode))
			if (fnmatch(basename(name), pattern))
				addSource(name);
	}

	void addSources(string file)
	{
		if (indexOf(file, '*') >= 0 || indexOf(file, '?') >= 0)
			addSourceByPattern("+" ~ file);
		else
			addSource(file);
	}

	string fileToModule(string file)
	{
		int len = file.startsWith(win_d_path) ? win_d_path.length : vsi_d_path.length;

		file = file[len .. $];
		if (_endsWith(file,".d"))
			file = file[0 .. $-2];
		file = replace(file, "/", ".");
		file = replace(file, "\\", ".");
		return file;
	}

	string makehdr(string file, string d_file)
	{
		string pkg  = d_file.startsWith(win_d_path) ? packageWin : packageVSI;
		string name = fileToModule(d_file);
		string hdr;
		hdr ~= "// File generated by idl2d from\n";
		hdr ~= "//   " ~ file ~ "\n";
		hdr ~= "module " ~ pkg ~ name ~ ";\n\n";
		//hdr ~= "import std.c.windows.windows;\n";
		//hdr ~= "import std.c.windows.com;\n";
		//hdr ~= "import idl.pp_util;\n";
		if(pkg == packageVSI)
			hdr ~= "import " ~ packageNF ~ "vsi;\n";
		else
			hdr ~= "import " ~ packageNF ~ "base;\n";
		hdr ~= "\n";

		foreach(imp; addedImports)
			hdr ~= "import " ~ imp ~ ";\n";

		if(currentModule == "vsshlids")
			hdr ~= "import " ~ packageVSI ~ "oleipc;\n";
		else if(currentModule == "debugger80")
			hdr ~= "import " ~ packageVSI ~ "dte80a;\n";
		else if(currentModule == "xmldomdid")
			hdr ~= "import " ~ packageWin ~ "idispids;\n";
		else if(currentModule == "xmldso")
			hdr ~= "import " ~ packageWin ~ "xmldom;\n";
		else if(currentModule == "ocidl")
			hdr ~= "import " ~ packageWin ~ "wingdi;\n";
		else if(currentModule == "commctrl")
			hdr ~= "import " ~ packageWin ~ "objidl;\n";
		hdr ~= "\n";

version(static_if_to_version)
{
version(remove_pp) {} else
		hdr ~= "version = pp_ifndef;\n\n";
}

		return hdr;
	}

	void setCurrentFile(string file)
	{
		currentFile = file;
		
		currentFullModule = fixImport(file);
		int p = lastIndexOf(currentFullModule, '.');
		if(p >= 0)
			currentModule = currentFullModule[p+1 .. $];
		else
			currentModule = currentFullModule;

		addedImports = addedImports.init;
		currentImports = currentImports.init;

		string[string] reinit;
		tokImports = reinit; // tokImports.init; dmd bugzilla #3491
	}

	int main(string[] argv)
	{
		getopt(argv, 
			"vsi", &vsi_base_path,
			"dte", &dte_path,
			"win", &win_path,
			"sdk", &sdk_d_path,
			"prefix", &keywordPrefix,
			"verbose", &verbose,
			"define", &defines,
			"undefine", &undefines);

		if(!_endsWith(dte_path, "\\"))
			dte_path ~= "\\";
		if(!_endsWith(win_path, "\\"))
			win_path ~= "\\";
		if(!_endsWith(sdk_d_path, "\\"))
			sdk_d_path ~= "\\";

		vsi_path  = vsi_base_path ~ r"\VisualStudioIntegration\Common\IDL\";
		vsi_hpath = vsi_base_path ~ r"\VisualStudioIntegration\Common\Inc\";

		vsi_d_path = sdk_d_path ~ r"vsi\";
		win_d_path = sdk_d_path ~ r"win32\";

		initFiles();
		
		// GC.disable();

		disabled_defines["__VARIANT_NAME_1"] = 1;
		disabled_defines["__VARIANT_NAME_2"] = 1;
		disabled_defines["__VARIANT_NAME_3"] = 1;
		disabled_defines["__VARIANT_NAME_4"] = 1;
		disabled_defines["uuid_constant"] = 1;

		// declared twice
		disabled_defines["VBProjectProperties2"] = 1; 
		disabled_defines["VBProjectConfigProperties2"] = 1; // declared twice
		disabled_defines["IID_ProjectProperties2"] = 1;
		disabled_defines["IID_ProjectConfigurationProperties2"] = 1;
		// bad init
		disabled_defines["DOCDATAEXISTING_UNKNOWN"] = 1;
		disabled_defines["HIERARCHY_DONTCHANGE"] = 1;
		disabled_defines["SELCONTAINER_DONTCHANGE"] = 1;
		disabled_defines["HIERARCHY_DONTPROPAGATE"] = 1;
		disabled_defines["SELCONTAINER_DONTPROPAGATE"] = 1;
		disabled_defines["ME_UNKNOWN_MENU_ITEM"] = 1;
		disabled_defines["ME_FIRST_MENU_ITEM"] = 1;
		
		// win sdk
		disabled_defines["pascal"] = 1;
		disabled_defines["WINBASEAPI"] = 1;
		disabled_defines["WINADVAPI"] = 1;
		disabled_defines["FORCEINLINE"] = 1;
		disabled_defines["POINTER_64"] = 1;
		disabled_defines["UNALIGNED"] = 1;
		disabled_defines["RESTRICTED_POINTER"] = 1;
		disabled_defines["RTL_CONST_CAST"] = 1;
		disabled_defines["RTL_RUN_ONCE_INIT"] = 1;
		disabled_defines["RTL_SRWLOCK_INIT"] = 1;
		disabled_defines["RTL_CONDITION_VARIABLE_INIT"] = 1;

		// commctrl.h
		disabled_defines["HDM_TRANSLATEACCELERATOR"] = 1;
		
		foreach(string file; argv[1..$])
			addSources(file);

		writeln("Searching files...");
		foreach(pat; win_idl_files)
			addSources(win_path ~ pat);
		foreach(pat; vsi_idl_files)
			addSources(vsi_path ~ pat);
		foreach(pat; vsi_h_files)
			addSources(vsi_hpath ~ pat);
		foreach(pat; dte_idl_files)
			addSources(dte_path ~ pat);

		writeln("Scanning files...");
		Source[] srcs;
		foreach(string file; srcfiles)
		{
			Source src = new Source;
			src.filename = file;
			src.text = fromMBSz (cast(immutable(char)*)(cast(char[]) read(file) ~ "\0").ptr);
			src.tokens = scanText(src.text, 1, true);
			collectClasses(src.tokens);
			srcs ~= src;
		}
		classes["IUnknown"] = true;
		classes["IServiceProvider"] = true;

		writeln("Converting files...");
		string sources = "SRC = \\\n";
		foreach(Source src; srcs)
		{
			writeln(src.filename);

			string d_file;
			d_file = replace(src.filename, win_path, win_d_path);
			d_file = replace(d_file, vsi_path, vsi_d_path);
			d_file = replace(d_file, vsi_hpath, vsi_d_path);
			d_file = replace(d_file, dte_path, vsi_d_path);
			d_file = tolower(d_file);
			if(d_file._endsWith(".idl") || d_file._endsWith(".idh"))
				d_file = d_file[0 .. $-3] ~ "d";
			if(d_file.endsWith(".h"))
				d_file = d_file[0 .. $-1] ~ "d";
			d_file = translateFilename(d_file);
			setCurrentFile(d_file);

			string text = convertText(src.tokens);
			text = removeDuplicateEmptyLines(text);

			string hdr = makehdr(src.filename, d_file);
			std.file.write(d_file, toUTF8(hdr ~ text));
			sources ~= "\t" ~ d_file[sdk_d_path.length .. $] ~ " \\\n";
		}
		sources ~= "\n";
		version(vsi) 
			string srcfile = sdk_d_path ~ "\\vsi_sources";
		else
			string srcfile = sdk_d_path ~ "\\sources";
		std.file.write(srcfile, sources);

		return 0;
	}

	bool verbose;
	bool simple = true;

	string[string] defines;
	string[] undefines;

	string[] srcfiles;
	string[] excludefiles;
	string currentFile;
	string currentModule;
	string currentFullModule;
}

int main(string[] argv)
{
	idl2d inst = new idl2d;
	return inst.main(argv);
}


///////////////////////////////////////////////////////////////////////
void testConvert(string txt, string exptxt, string mod = "")
{
	txt = replace(txt, "\r", "");
	exptxt = replace(exptxt, "\r", "");

	idl2d inst = new idl2d;
	inst.currentModule = mod;
	TokenList tokens = scanText(txt, 1, true);
	string ntxt = inst.convertText(tokens);
	assert(ntxt == exptxt);
}

unittest
{
	string txt = q{
cpp_quote("//;end_internal")
cpp_quote("typedef struct tagELEMDESC {")
cpp_quote("    TYPEDESC tdesc;             /* the type of the element */")
cpp_quote("    union {")
cpp_quote("        IDLDESC idldesc;        /* info for remoting the element */")
cpp_quote("        PARAMDESC paramdesc;    /* info about the parameter */")
cpp_quote("    };")
cpp_quote("} ELEMDESC, * LPELEMDESC;")
};

	string exptxt = q{
//;end_internal
struct tagELEMDESC
{
TYPEDESC tdesc;             /* the type of the element */
union {
IDLDESC idldesc;        /* info for remoting the element */
PARAMDESC paramdesc;    /* info about the parameter */
};
}
alias tagELEMDESC ELEMDESC; alias tagELEMDESC * LPELEMDESC;
};

	testConvert(txt, exptxt);
}

///////////////////////////////////////////////////////////////////////
unittest
{
	string txt = q{
	int x;
cpp_quote("#ifndef WIN16")
typedef struct tagSIZE
{
    LONG        cx;
    LONG        cy;
} SIZE, *PSIZE, *LPSIZE;
cpp_quote("#else // WIN16")
cpp_quote("typedef struct tagSIZE")
cpp_quote("{")
cpp_quote("    INT cx;")
cpp_quote("    INT cy;")
cpp_quote("} SIZE, *PSIZE, *LPSIZE;")
cpp_quote("#endif // WIN16")
};

version(remove_pp)
	string exptxt = q{
	int x;
struct tagSIZE
{
    LONG        cx;
    LONG        cy;
}
alias tagSIZE SIZE; alias tagSIZE *PSIZE; alias tagSIZE *LPSIZE; 
 // WIN16
};
else // !remove_pp
	string exptxt = q{
	int x;
version(all) /* #ifndef WIN16 */ {
struct tagSIZE
{
    LONG        cx;
    LONG        cy;
}
alias tagSIZE SIZE; alias tagSIZE *PSIZE; alias tagSIZE *LPSIZE;
} else { // #else // WIN16
struct tagSIZE
{
INT cx;
INT cy;
}
alias tagSIZE SIZE; alias tagSIZE *PSIZE; alias tagSIZE *LPSIZE;
} // #endif // WIN16
};
	testConvert(txt, exptxt);
}

///////////////////////////////////////////////////////////////////////
unittest
{
	string txt = "
	int x;
#if defined(MIDL_PASS)
typedef struct _LARGE_INTEGER {
#else // MIDL_PASS
typedef union _LARGE_INTEGER {
    struct { };
#endif //MIDL_PASS
    LONGLONG QuadPart;
} LARGE_INTEGER;
";
	string exptxt = "
	int x;
union _LARGE_INTEGER
{
    struct { };    LONGLONG QuadPart;
}
alias _LARGE_INTEGER LARGE_INTEGER;
";
	testConvert(txt, exptxt, "winnt");
}

///////////////////////////////////////////////////////////////////////
unittest
{
	string txt = "
#define convert() \\
	hello
#define noconvert(n,m) \\
	hallo1 |\\
	hallo2
";
	string exptxt = "
int convert() { return  
	hello; }
// #define noconvert(n,m) \\
//	hallo1 |\\
//	hallo2
";
	version(macro2template) exptxt = replace(exptxt, "int", "auto");
	testConvert(txt, exptxt);
}


unittest
{
	string txt = "
#define CONTEXT_i386 0x00010000L    // this assumes that i386 and
#define CONTEXT_CONTROL (CONTEXT_i386 | 0x00000001L) // SS:SP, CS:IP, FLAGS, BP
";
	string exptxt = "
const CONTEXT_i386 = 0x00010000;    // this assumes that i386 and
const CONTEXT_CONTROL = (CONTEXT_i386 | 0x00000001); // SS:SP, CS:IP, FLAGS, BP
";
	testConvert(txt, exptxt);
}

unittest
{
	string txt = "
#define NtCurrentTeb() ((struct _TEB *)_rdtebex())
";
	string exptxt = "
_TEB* NtCurrentTeb() { return    ( cast( _TEB*)_rdtebex()); }
";
	version(macro2template) exptxt = replace(exptxt, "_TEB* ", "auto ");
	testConvert(txt, exptxt);
}

unittest
{
	string txt = "
enum { prjBuildActionNone }
cpp_quote(\"#define prjBuildActionMin  prjBuildActionNone\")
cpp_quote(\"#define prjBuildActionMax  prjBuildActionCustom\")
";
	string exptxt = "
enum { prjBuildActionNone }
const prjBuildActionMin =  prjBuildActionNone;
alias prjBuildActionEmbeddedResource  prjBuildActionMax;
";
	testConvert(txt, exptxt);
}

unittest
{
	string txt = "
#define _INTEGRAL_MAX_BITS 64
#if (!defined (_MAC) && (!defined(MIDL_PASS) || defined(__midl)) && (!defined(_M_IX86) || (defined(_INTEGRAL_MAX_BITS) && _INTEGRAL_MAX_BITS >= 64)))
typedef __int64 LONGLONG;
#endif
";
	string exptxt = "
alias long LONGLONG;
";
//	testConvert(txt, exptxt);
}

unittest
{
	string txt = "
#define KEY_READ                ((STANDARD_RIGHTS_READ       |\\
                                 KEY_QUERY_VALUE)\\
                                  &  (~SYNCHRONIZE))
";
	string exptxt = "
const KEY_READ =                ((STANDARD_RIGHTS_READ       |
                                 KEY_QUERY_VALUE)
                                  &  (~SYNCHRONIZE));
";
	testConvert(txt, exptxt);
}

unittest
{
	string txt = "
#if _WIN32_WINNT >= 0x0600
#define  _PROPSHEETPAGEA_V3 _PROPSHEETPAGEA
#elif (_WIN32_IE >= 0x0400)
#define  _PROPSHEETPAGEA_V2 _PROPSHEETPAGEA
#else
#define  _PROPSHEETPAGEA_V1 _PROPSHEETPAGEA
#endif
";
	string exptxt = "
version(all) /* #if _WIN32_WINNT >= 0x0600 */ {
alias _PROPSHEETPAGEA_V3 _PROPSHEETPAGEA;
} else version(all) /* #elif (_WIN32_IE >= 0x0400) */ {
alias _PROPSHEETPAGEA_V2 _PROPSHEETPAGEA;
} else {

alias _PROPSHEETPAGEA_V1 _PROPSHEETPAGEA;
} 

";
	testConvert(txt, exptxt, "prsht");
}

