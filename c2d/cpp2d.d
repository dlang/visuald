// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module c2d.cpp2d;

import c2d.tokenizer;
import c2d.ast;
import c2d.dlist;
import c2d.pp;
import c2d.dgutil;
import c2d.tokutil;

import stdext.file;
import stdext.path;

import std.string;
import std.file;
import std.path;
import std.stdio;
import std.ascii;
import std.array;
import std.algorithm;
import std.conv;

alias std.string.indexOf indexOf;

//////////////////////////////////////////////////////////////////////////////

// TASKS:
// + move function implementation into struct/class definition
// + move initializer of static member into struct/class definition
// + merge default initializer to function definition
// + detect abstract member functions
// + remove forward declarations
// + convert constructor to "this", base class init to "super", destructor to "~this"
// + allow contracts
// for struct/class/union/enum:
// + typedef struct S { } T; -> struct S { } typedef S T;
// + typedef struct { } S; -> struct S { }
// + [static] struct { } s; -> struct S { } [static] S s;
// + remove unnecessary struct in variable declarations
// + select class/struct depending on derivation
// + add enum name to constants
// + convert casts
// + split declarations with modifiers
// + convert asm, add ';' to each instructin, add naked
// - convert pointer comparison to "is"
// + convert string prefix to postfix, check line splicing
// + remove "extern"
// - remove extern "C" { }
// + prototype "(void)" -> "()"
// ? add toPtr() to class allocations
// + convert class pointers to non-pointers
// + convert stack object class to new
// + "::", "->" -> "."
// + empty statement ";" -> "{}"
// - remove array delete[]
// + "{" -> "[" for array initializer
// + convert multi-dimensional initializers, if specified as one-dimensional list
// + convert "&" to "ref" for function arguments
// + add "d2d_" to keywords
// + convert basic types
// + convert sizeof(x) -> x.sizeof
// + convert number postfix
// + convert wide chars
// + remove unnecessary paranthesis (confuses dmd in sizeof, (i)++, (i).nn)
// + translate bitfields to mixin
// - add & to function pointers
// + convert const type -> const(type)
//
// PP handling
// + fix conditional code blocks to work with version/static if
//  - statement list
//  - expression list
//  - a part of a if/else-if/else series
// - convert simple #define to enum/alias
// - convert macros to mixins
// - move comment before conditional inside
// + fix linesplicing in expanded macros
//
// future:
// - convert named enum to unnamed enum + typedef
// - allow conditionals in enums, split into multiple enums then
// - allow conditionals in array initializers, use mixin then

///////////////////////////////////////////////////////////////////////

bool[string] keywordsMap;
string[string] tokenMap;
string[string] filenameMap;

struct PatchRule
{
	string filenamePattern;
	string[] searchTokens;
	string[] replaceTokens;
}

struct C2DIni
{
	int    inputType;           // 0: input files, 1: current document, 2: current selection
	string inputFiles;          // file and dir list
	string inputDir;
	string outputDir;
	string importAllFile;

	string packagePrefix;
	string codePrefix;
	string keywordPrefix;

	string versionDefines;      // PP identifiers to convert to versions
	string expandConditionals;  // PP identifiers to expand in conditionals
	string userValueTypes;      // with translation to basic D types?
	string userClassTypes;
	string replaceTokenPre;
	string replaceTokenPost;

	bool writeIntermediate;

	// syntax:
	// filepattern:: search => replace
	static bool parsePatchRule(ref PatchRule rule, string line)
	{
		int pos = std.string.indexOf(line, "::");
		if(pos >= 0)
		{
			rule.filenamePattern = std.string.strip(line[0..pos]);
			line = line[pos + 2 .. $];
		}
		else
			rule.filenamePattern = "";

		pos = std.string.indexOf(line, "=>");
		if(pos < 0)
			return false;
		string search = line[0 .. pos];
		string replac = line[pos+2 .. $];
		replac = replace(replac, "\\n", "\n");

		rule.searchTokens = rule.searchTokens.init;
		rule.replaceTokens = rule.replaceTokens.init;
		scanTextArray!(string)(rule.searchTokens, search);
		scanTextArray!(string)(rule.replaceTokens, replac);
		return rule.searchTokens.length > 0;
	}

	static PatchRule[] parseRules(string txt)
	{
		PatchRule[] rules;
		string[] lines = splitLines(txt);
		for(int n = 0; n < lines.length; )
		{
			string line = lines[n++];
			while(line.endsWith("\\") && !line.endsWith("\\\\"))
			{
				line = line[0..$-1];
				if(n < lines.length)
					line ~= lines[n++];
			}
			line = stripLeft(line);
			if(line.startsWith("//"))
				continue;

			PatchRule rule;
			if(parsePatchRule(rule, line))
				rules ~= rule;
		}
		return rules;
	}

	void readFromFile(string fname)
	{
		string txt = to!string(std.file.read(fname));
		readFromText(txt);
	}

	void writeToFile(string fname)
	{
		string s = writeToText();
		std.file.write(fname, s);
	}

	void readFromText(string txt)
	{
		string[string][string] ini = parseIniText(txt);

		if(auto set = "Settings" in ini)
		{
			if(auto p = "inputType" in *set)
				inputType = parse!int(*p);
			if(auto p = "writeIntermediate" in *set)
				writeIntermediate = parse!bool(*p);
			if(auto p = "outputDir" in *set)
				outputDir = *p;
			if(auto p = "inputDir" in *set)
				inputDir = *p;
			if(auto p = "keywordPrefix" in *set)
				keywordPrefix = *p;
			if(auto p = "packagePrefix" in *set)
				packagePrefix = *p;
		}

		if(auto set = "inputFiles" in ini)
			if(auto p = "" in *set)
				inputFiles = *p;
		if(auto set = "codePrefix" in ini)
			if(auto p = "" in *set)
				codePrefix = *p;
		if(auto set = "versionDefines" in ini)
			if(auto p = "" in *set)
				versionDefines = *p;
		if(auto set = "expandConditionals" in ini)
			if(auto p = "" in *set)
				expandConditionals = *p;
		if(auto set = "userValueTypes" in ini)
			if(auto p = "" in *set)
				userValueTypes = *p;
		if(auto set = "userClassTypes" in ini)
			if(auto p = "" in *set)
				userClassTypes = *p;
		if(auto set = "replaceTokenPre" in ini)
			if(auto p = "" in *set)
				replaceTokenPre = *p;
		if(auto set = "replaceTokenPost" in ini)
			if(auto p = "" in *set)
				replaceTokenPost = *p;
	}

	string writeToText()
	{
		string s = "[Settings]\n";
		s ~= "inputType=" ~ to!string(inputType) ~ "\n";
		s ~= "writeIntermediate=" ~ to!string(writeIntermediate) ~ "\n";
		s ~= "outputDir=" ~ outputDir ~ "\n";
		s ~= "inputDir=" ~ inputDir ~ "\n";
		s ~= "keywordPrefix=" ~ keywordPrefix ~ "\n";
		s ~= "packagePrefix=" ~ packagePrefix ~ "\n";

		s ~= "[inputFiles]\n"		  ~ inputFiles;			if(!s.endsWith("\n")) s ~= "\n";
		s ~= "[codePrefix]\n"		  ~ codePrefix;			if(!s.endsWith("\n")) s ~= "\n";
		s ~= "[versionDefines]\n"	  ~ versionDefines;		if(!s.endsWith("\n")) s ~= "\n";
		s ~= "[expandConditionals]\n" ~ expandConditionals; if(!s.endsWith("\n")) s ~= "\n";
		s ~= "[userValueTypes]\n"	  ~ userValueTypes;		if(!s.endsWith("\n")) s ~= "\n";
		s ~= "[userClassTypes]\n"	  ~ userClassTypes;		if(!s.endsWith("\n")) s ~= "\n";
		s ~= "[replaceTokenPre]\n"    ~ replaceTokenPre;	if(!s.endsWith("\n")) s ~= "\n";
		s ~= "[replaceTokenPost]\n"   ~ replaceTokenPost;	if(!s.endsWith("\n")) s ~= "\n";

		return s;
	}

	bool toC2DOptions(ref C2DOptions opt)
	{
		opt.enableDmdSpecifics = false;
		opt.writeIntermediate = writeIntermediate;
		opt.keywordsPrefix = keywordPrefix;
		opt.packagePrefix = packagePrefix;
		opt.codePrefix = codePrefix;
		opt.importAllFile = importAllFile;
		opt.inputDir = normalizeDir(inputDir);
		opt.outputDir = normalizeDir(outputDir);

		opt.userValueTypes = opt.userValueTypes.init;
		opt.userRefTypes = opt.userRefTypes.init;
		
		foreach(t; split(userValueTypes))
			opt.userValueTypes[t] = true;

		foreach(t; split(userClassTypes))
			opt.userRefTypes[t] = true;

		opt.preRules = parseRules(replaceTokenPre);
		opt.postRules = parseRules(replaceTokenPost);

		PP.versionDefines = PP.versionDefines.init;
		foreach(v; split(versionDefines))
			PP.versionDefines[v] = true;

		PP.expandConditionals = PP.expandConditionals.init;
		opt.expandDefines = opt.expandDefines.init;
		foreach(v; split(expandConditionals))
		{
			bool b = true;
			int pos = indexOf(v, '=');
			string def;
			if(pos > 0)
			{
				def = v[pos + 1 .. $];
				b = (def.length == 0 || indexOf("tTyY1", def[0]) >= 0);
				v = v[0..pos];
			}
			PP.expandConditionals[v] = b;
			TokenList toklist;
			if(def.length)
			{
				toklist = scanText(def);
				toklist.prepend(createToken(" ", v, Token.Identifier, 0));
				toklist.prepend(createToken("", "#define", Token.PPdefine, 0));
			}
			opt.expandDefines[v] = toklist;
		}
		return true;
	}
}

///////////////////////////////////////////////////////////////////////

struct C2DOptions
{
	bool enableDmdSpecifics = true;
	bool writeIntermediate;

	int indentSize = 4;
	int tabSize = 4;

	string keywordsPrefix;
	string packagePrefix;
	string codePrefix;
	
	string importAllFile;
	string inputDir;
	string outputDir;

	bool[string] userValueTypes;
	bool[string] userRefTypes;

	PatchRule[] preRules;
	PatchRule[] postRules;

	TokenList[string] expandDefines;

	void setup_dmd()
	{
		options.enableDmdSpecifics = true;

		keywordsPrefix = "dmd_";
		codePrefix = "import dmd.port;\nimport dmd.importall;\n\n";

		importAllFile = "dmd/importall.d";
		inputDir = "c:/tmp/d/";
		outputDir = "c:/tmp/d/dmdgen2/";

		preRules = preRules.init;
		postRules = postRules.init;

		foreach(t; [ "TOK", "MATCH", "dchar_t", "opflag_t", "regm_t", "targ_size_t",
					 "tym_t", "OPER", "TY" ])
			userValueTypes[t] = true;
	}
}

C2DOptions options;

static this()
{
	// bool says whether the C++ keyword exists and has the same meaning
	keywordsMap = [
		"this" : true,
		"super" : false,
		"assert" : true,
		"null" : false,
		"true" : true,
		"false" : true,
		"cast" : false,
		"new" : true,
		"delete" : true,
		"throw" : true,
		"module" : false,
		"pragma" : false,
		"typeof" : false,
		"typeid" : false,
		"template" : false,

		"void" : true,
		"byte" : false,
		"ubyte" : false,
		"short" : true,
		"ushort" : false,
		"int" : true,
		"uint" : false,
		"long" : true,
		"ulong" : false,
		"cent" : false,
		"ucent" : false,
		"float" : true,
		"double" : true,
		"real" : false,
		"bool" : true,
		"char" : true,
		"wchar" : false,
		"dchar" : false,
		"ifloat" : false,
		"idouble" : false,
		"ireal" : false,

		"cfloat" : false,
		"cdouble" : false,
		"creal" : false,

		"delegate" : false,
		"function" : false,

		"is" : false,
		"if" : true,
		"else" : true,
		"while" : true,
		"for" : true,
		"do" : true,
		"switch" : true,
		"case" : true,
		"default" : true,
		"break" : true,
		"continue" : true,
		"synchronized" : false,
		"return" : true,
		"goto" : true,
		"try" : true,
		"catch" : true,
		"finally" : true,
		"with" : false,
		"asm" : false,
		"foreach" : false,
		"foreach_reverse" : false,
		"scope" : false,

		"struct" : true,
		"class" : true,
		"interface" : true,
		"union" : true,
		"enum" : true,
		"import" : false,
		"mixin" : false,
		"static" : true,
		"final" : false,
		"const" : true,
		"typedef" : true,
		"alias" : false,
		"override" : false,
		"abstract" : false,
		"volatile" : true,
		"debug" : false,
		"deprecated" : false,
		"in" : false,
		"out" : false,
		"inout" : false,
		"lazy" : false,
		"auto" : false,

		"align" : false,
		"extern" : true,
		"private" : true,
		"package" : true,
		"protected" : true,
		"public" : true,
		"export" : false,

		"body" : false,
		"invariant" : false,
		"unittest" : false,
		"version" : false,
		//{	"manifest",	TOKmanifest	},

		// Added after 1.0
		"ref" : false,
		"macro" : false,
		"pure" : false,
		"nothrow" : true,
		"__gshared" : false,
		"__thread" : false,
		"__traits" : false,
		"__overloadset" : false,

		"__FILE__" : true,
		"__LINE__" : true,

		"shared" : false,
		"immutable" : false,

		"@disable" : false,
		"@property" : false,
		"@safe" : false,
		"@system" : false,
		"@trusted" : false,
	];

	/*
		// dmd specific?
	*/

	tokenMap = [
		"::" : ".",
		"->" : ".",

		"__try"     : "try",
		"NULL"      : "null",
		//"__except"          : "catch(Exception e) //", false);

		"__in"      : "in",
		"__out"     : "out",
		"__body"    : "body",
		"__real"    : "real",
		"typedef"   : "alias",

		// temporary renames
		"__super"   : "super",
		"__const"   : "const",
		"__static_if" : "static if",
		"__static_eval" : "static_eval!",
		"__version" : "version",
		"__cast"    : "cast",
		"__init"    : "init",
		"__string"  : "string",
		"__mixin"   : "mixin",
		"__auto"    : "auto",
		"__enum"    : "enum",
		"__bitfields" : "bitfields!",
		"__is"      : "is",
		"!__is"     : "!is",

		"__near"    : "",
		"__far"     : "",
		"_asm"      : "asm",
		"__asm"     : "asm",

		"__cdecl"   : "",
		"__stdcall" : "",
		"__pascal"  : "",
		"__inline"  : "",
		"inline"    : "",
		"register"  : "",
		"volatile"  : "/*volatile*/",
		"typename"  : "",
	];

	/*
	filenameMap = [
		"root"      : "dmd_root",
		"code"      : "dmd_code",
		"type"      : "dmd_type",
		"global"    : "dmd_global",
		"complex_t" : "dmd_complex_t",
		"mem"       : "dmd_mem",
	];
	*/
}

string createModuleName(string filename)
{
	filename = stripExtension(filename);
	filename = replace(filename, "\\", "/");
	string names[] = split(filename, "/");
	string modname = options.packagePrefix;
	foreach(n; names)
	{
		string safename;
		foreach(dchar ch; n)
			if(isAlphaNum(ch))
				safename ~= ch;
			else
				safename ~= '_';

		if(safename in keywordsMap)
			safename = options.keywordsPrefix ~ safename;
		if(string *ps = safename in filenameMap)
			safename = *ps;

		if(modname.length)
			modname ~= '.';
		modname ~= safename;
	}
	return modname;
}

string mapTokenText(Token tok)
{
	if(Token.isPPToken(tok.type))
		return fixPPToken(tok);
	if(tok.type == Token.String)
		return fixString(tok.text);
	if(tok.type == Token.Number)
		return fixNumber(tok.text);
	
	if(bool *pb = tok.text in keywordsMap)
		if(!*pb)
			return options.keywordsPrefix ~ tok.text;
	if(string *ps = tok.text in tokenMap)
		return *ps;
	return tok.text;
}

string createMappedTokenListText(TokenList tokList)
{
	string text;
	for(TokenIterator tokIt = tokList.begin(); !tokIt.atEnd(); ++tokIt)
	{
		Token tok = *tokIt;
		string mapped = mapTokenText(tok);
		text ~= tok.pretext ~ mapped;
	}
	return text;
}


string fixPPToken(Token tok)
{
	assume(tok.type != Token.PPinsert);
	if(tok.type == Token.PPinclude)
	{
		TokenList tokList = scanText(tok.text, 1, false);
		TokenIterator it = tokList.begin();
		assume(it.type == Token.PPinclude);
		it.advance();
		if(!it.atEnd() && it.type == Token.String)
		{
			string fname = it.text[1 .. $-1]; // remove quotes
			string modname = createModuleName(fname);
			it[-1].text = "import";
			it.text = modname ~ ";";
			return tokenListToString(tokList);
		}
	}
	if(tok.type == Token.PPdefine)
	{
		string enumtext = convertDefineToEnum(tok.text, &fixNumber);
		if(enumtext != tok.text)
			return enumtext;
	}
	string text = replace(tok.text, "\\\n", "\\\n//");
	return "// " ~ text;
}

string fixString(string s)
{
	s = replace(s, "\\n\\\n", "\n");
	s = replace(s, "\\\n", "\"\n\"");
	if(startsWith(s, "L"))
		s = s[1..$] ~ "w";
	return s;
}

string fixNumber(string num)
{
	if(endsWith(num, "LL"))
		return num[0..$-1];
	if(endsWith(num, "L"))
		return num[0..$-1];
	return num;
}

///////////////////////////////////////////////////////////////////////

bool wantsSpacePretext(string s)
{
	switch(s)
	{
	case "=":
		return true;
	default:
		return false;
	}
}

bool needSeparatingSpace(char prevch, char nextch)
{
	if(!isAlphaNum(prevch) && prevch != '_')
		return false;
	if(!isAlphaNum(nextch) && nextch != '_')
		return false;
	return true;
}

void clearTokenText(TokenIterator tokIt)
{
	char prevch = 0;
	if(tokIt.pretext.length)
		prevch = tokIt.pretext[$-1];
	else
		for(TokenIterator prevTok = tokIt; prevch == 0 && !prevTok.atBegin(); )
		{
			prevTok.retreat();
			if(prevTok.text.length)
				prevch = prevTok.text[$-1];
			else if(prevTok.pretext.length)
				prevch = prevTok.pretext[$-1];
		}

	tokIt.text = "";
	tokIt.advance();
	while(!tokIt.atEnd())
	{
		if(tokIt.pretext == " " && !wantsSpacePretext(tokIt.text))
			tokIt.pretext = "";
		if(tokIt.pretext != "" || tokIt.text != "")
			break;
		tokIt.advance();
	}

	if(!tokIt.atEnd())
	{
		char nextch = 0;
		if(tokIt.pretext.length)
			nextch = tokIt.pretext[0];
		else if(tokIt.text.length)
			nextch = tokIt.text[0];
		if(needSeparatingSpace(prevch, nextch))
			tokIt.pretext = " " ~ tokIt.pretext;
	}
}

void checkSeparatingSpace(TokenIterator tokIt)
{
	if(!tokIt.atEnd() && !tokIt.atBegin())
	{
		char nextch = 0;
		if(tokIt.pretext.length)
			nextch = tokIt.pretext[0];
		else if(tokIt.text.length)
			nextch = tokIt.text[0];
		
		TokenIterator prevIt = tokIt - 1;
		char prevch = 0;
		if(prevIt.text.length)
			prevch = prevIt.text[$-1];
		else if(prevIt.pretext.length)
			prevch = prevIt.pretext[$-1];
		if(needSeparatingSpace(prevch, nextch))
			tokIt.pretext = " " ~ tokIt.pretext;
	}
}

void patchBasicDeclType(AST ast)
{
	enum TF_BIT
	{
		VOID     = 0x0001,
		INT      = 0x0002,
		FLOAT    = 0x0004,
		COMPLEX  = 0x0008,
		SIZE8    = 0x0010,
		SIZE16   = 0x0020,
		SIZE32   = 0x0040,
		SIZE64   = 0x0080,
		SIZE80   = 0x0100,
		LONG     = 0x0200,
		SIGNED   = 0x0400,
		UNSIGNED = 0x0800,
		BOOL     = 0x1000,
		CHAR     = 0x2000,
		AUTO     = 0x4000,
		ENUM     = 0x8000,
	}

	int type = 0;
	TokenIterator typeTokIt;
	string basic;
	bool isConst = false;
	for(TokenIterator tokIt = ast.start; tokIt != ast.end; ++tokIt)
	{
		bool isBasic = true;
		switch(tokIt.text)
		{
		case "void":      type |= TF_BIT.VOID; break;
		case "__auto":    type |= TF_BIT.AUTO; break;
		case "__enum":    type |= TF_BIT.ENUM; break;
		case "bool":      type |= TF_BIT.BOOL; break;
		case "char":      type |= TF_BIT.INT | TF_BIT.SIZE8; break;
		case "int":       type |= TF_BIT.INT | TF_BIT.SIZE32; break;
		case "short":     type |= TF_BIT.INT | TF_BIT.SIZE16; break;
		case "signed":    type |= TF_BIT.INT | TF_BIT.SIGNED; break;
		case "unsigned":  type |= TF_BIT.INT | TF_BIT.UNSIGNED; break;
		case "float":     type |= TF_BIT.FLOAT | TF_BIT.SIZE32; break;
		case "double":    type |= TF_BIT.FLOAT; break;
		case "_Complex":  type |= TF_BIT.COMPLEX; break;
		case "__int64":   type |= TF_BIT.INT | TF_BIT.SIZE64; break;
		case "_int64":    type |= TF_BIT.INT | TF_BIT.SIZE64; break;
		case "__int32":   type |= TF_BIT.INT | TF_BIT.SIZE32; break;
		case "_int32":    type |= TF_BIT.INT | TF_BIT.SIZE32; break;
		case "INT32":     type |= TF_BIT.INT | TF_BIT.SIZE32; break;
		case "LONG":      type |= TF_BIT.INT | TF_BIT.SIZE32; break;
		case "UINT32":    type |= TF_BIT.INT | TF_BIT.SIZE32 | TF_BIT.UNSIGNED; break;
		case "DWORD":     type |= TF_BIT.INT | TF_BIT.SIZE32 | TF_BIT.UNSIGNED; break;
		case "wchar_t":   type |= TF_BIT.INT | TF_BIT.SIZE16 | TF_BIT.UNSIGNED | TF_BIT.CHAR; break;
		case "long":
			if(type & TF_BIT.LONG)
				type = type & ~TF_BIT.SIZE32 | TF_BIT.SIZE64;
			else
				type |= TF_BIT.LONG;
			break;
		case "const":
			isConst = true;
			goto default; // fall through
		default:
			isBasic = false;
		}
		if(isBasic)
			basic ~= " " ~ tokIt.text;
		if(isBasic && !typeTokIt.valid())
			typeTokIt = tokIt;

		if(!DeclType.isPersistentTypeModifier(tokIt.text) || tokIt.text == "const")
			clearTokenText(tokIt);
	}

	if((type & (TF_BIT.VOID | TF_BIT.BOOL | TF_BIT.INT | TF_BIT.FLOAT | TF_BIT.COMPLEX | TF_BIT.AUTO | TF_BIT.ENUM)) == 0)
		type |= TF_BIT.INT;
	if((type & TF_BIT.INT) != 0 && (type & TF_BIT.LONG) != 0)
		type &= ~TF_BIT.LONG;
	if((type & TF_BIT.INT) != 0 && (type & (TF_BIT.SIGNED | TF_BIT.UNSIGNED)) == 0)
		type |= TF_BIT.SIGNED;

	switch(type)
	{
	case 0:                                            basic = ""; break;
	case TF_BIT.AUTO:                                  basic = "__auto"; break;
	case TF_BIT.ENUM:                                  basic = "__enum"; break;
	case TF_BIT.VOID:                                  basic = "void"; break;
	case TF_BIT.BOOL:                                  basic = "bool"; break;
	case TF_BIT.INT | TF_BIT.SIZE8  | TF_BIT.UNSIGNED: basic = "ubyte"; break;
	case TF_BIT.INT | TF_BIT.SIZE8  | TF_BIT.SIGNED:   basic = "char"; break; // byte?
	case TF_BIT.INT | TF_BIT.SIZE16 | TF_BIT.UNSIGNED: basic = "ushort"; break;
	case TF_BIT.INT | TF_BIT.SIZE16 | TF_BIT.SIGNED:   basic = "short"; break;
	case TF_BIT.INT | TF_BIT.SIZE16 | TF_BIT.UNSIGNED | TF_BIT.CHAR:   basic = "wchar_t"; break;
	case TF_BIT.INT |                 TF_BIT.UNSIGNED:
	case TF_BIT.INT | TF_BIT.SIZE32 | TF_BIT.UNSIGNED: basic = "uint"; break;
	case TF_BIT.INT |                 TF_BIT.SIGNED:
	case TF_BIT.INT | TF_BIT.SIZE32 | TF_BIT.SIGNED:   basic = "int"; break;
	case TF_BIT.INT | TF_BIT.SIZE64 | TF_BIT.UNSIGNED: basic = "ulong"; break;
	case TF_BIT.INT | TF_BIT.SIZE64 | TF_BIT.SIGNED:   basic = "long"; break;

	case TF_BIT.FLOAT | TF_BIT.SIZE32:                 basic = "float"; break;
	case TF_BIT.FLOAT | TF_BIT.LONG:                   basic = "__real"; break;
	case TF_BIT.FLOAT:                                 basic = "double"; break;
	case TF_BIT.FLOAT | TF_BIT.COMPLEX:                basic = "cdouble"; break;
	case TF_BIT.FLOAT | TF_BIT.COMPLEX | TF_BIT.SIZE32:basic = "cfloat"; break;
	case TF_BIT.FLOAT | TF_BIT.COMPLEX | TF_BIT.LONG:  basic = "creal"; break;

	default: throwException("unsupported basic type combination" ~ basic);
	}

	if(isConst)
		basic = "const(" ~ basic ~ ")";

	if(typeTokIt.valid())
	{
		typeTokIt.text = basic;
		TokenIterator it = typeTokIt + 1;
		for( ; !it.atEnd(); ++it)
			if(it.pretext.length || it.text.length)
				break;
		if(!it.atEnd() && it.pretext.length == 0 && (isAlphaNum(it.text[0]) || it.text[0] == '*' || it.text[0] == '_'))
			it.pretext = " ";
	}
}

void patchDeclTypeModifier(AST ast)
{
	for(TokenIterator tokIt = ast.start; tokIt != ast.end; ++tokIt)
	{
		if(DeclType.isTypeModifier(tokIt.text))
			if(!DeclType.isPersistentTypeModifier(tokIt.text) &&
			   !DeclType.isMutabilityModifier(tokIt.text))
				clearTokenText(tokIt);
	}
}

bool patchVoidArg(DeclType dtype)
{
	if(dtype.start.text != "void")
		return false;
	if(dtype.start + 1 != dtype.end)
		return false;
	if(dtype._parent.children.count() > 2)
		return false;
	if(dtype._parent.children.count() == 2)
	{
		AST dvar = dtype._parent.children[1];
		if(dvar.start != dvar.end)
			return false; // non-empty DeclVar
	}
	if(!dtype.start.atBegin() && dtype.start[-1].type == Token.LessThan)
		return false;
	if(!dtype.end.atEnd() && dtype.end.type == Token.GreaterThan)
		return false;

	// no DeclVar follows, must be (void) arg
	clearTokenText(dtype.start);
	return true;
}

void patchOperatorName(Expression expr)
{
	if(expr._toktype == Token.Identifier)
	{
		string prefix;
		TokenIterator it = expr.start;
		if(it.type == Token.DoubleColon)
		{
			prefix = "glob_"; // replace "::operator new" -> ".glob_new"
			it.advance();
		}
		/*version(V2)*/ if(it.type == Token.Operator)
		{
			string op;
			switch(it[1].text)
			{
			case "new":    op = "new"; break;
			case "delete": op = "delete"; break;
			default: break;
			}
			if(op.length > 0)
			{
				clearTokenText(it);
				it[1].text = prefix ~ op;
				// if this is the declaration, remove return type
				AST parent = expr._parent;
				while(parent && (parent._type == AST.Type.UnaryExp || parent._type == AST.Type.PostExp))
					parent = parent._parent;
				if(parent && parent._type == AST.Type.VarDeclaration)
				{
					parent = parent._parent;
					assume(parent && parent._type == AST.Type.Declaration);
					for(TokenIterator declIt = parent.start; declIt != expr.start; ++declIt)
						clearTokenText(declIt);
				}
			}
		}
	}
}

void patchEnumName(Expression expr)
{
	// expr known to be PrimaryExp
	if(expr._toktype == Token.Identifier)
	{
		if(expr.start.type == Token.Identifier)
			if(string* ps = expr.start.text in AST.enumIdentifier)
			{
				// don't replace in declarations
				AST var = expr._parent;
				while(var && !cast(DeclVar)var)
					var = var._parent;
				if(!var || (cast(DeclVar)var)._ident != expr.start.text)
					expr.start.text = replace(*ps, "::", ".") ~ expr.start.text;
			}
	}
}

bool sizeofExpressionNeedsParenthesis(AST ast)
{
	if(Expression expr = cast(Expression)ast)
	{
		return expr._type != AST.Type.PrimaryExp && expr._type != AST.Type.PostExp;
	}
	if(Declaration decl = cast(Declaration)ast)
	{
		// single token?
		return decl.start + 1 != decl.end;
	}
	return true;
}

void patchSizeof(Expression expr)
{
	// expr known to be PrimaryExp
	if(expr._toktype == Token.Sizeof)
	{
		// extract argument
		assume(expr.children.count() == 1);
		AST nexpr = expr.children[0].clone();          // doesn't have parenthesis
		TokenList nexprList = nexpr.cloneTokens(true);
		if(sizeofExpressionNeedsParenthesis(nexpr))
		{
			TokenList parenList = new TokenList;
			Token tokL = createToken("", "(", Token.ParenL, expr.start.lineno);
			Token tokR = createToken("", ")", Token.ParenR, expr.start.lineno);
			parenList.append(tokR);
			Expression parenExpr = new Expression(AST.Type.PrimaryExp, Token.ParenL);
			parenExpr.start = parenList.begin();
			parenExpr.end = parenList.end();
			
			parenExpr.appendChild(nexpr, nexprList);
			parenList.prepend(tokL);
			parenExpr.start = parenList.begin();

			nexpr = parenExpr;
			nexprList = parenList;
		}

		// create post-part ".sizeof"
		Token tokSizeof = createToken(*expr.start);
		Token tokDot = createToken("", ".", Token.Dot, tokSizeof.lineno);
		nexpr.start.pretext = tokSizeof.pretext ~ nexpr.start.pretext;
		tokSizeof.pretext = "";

		Expression idexpr = new Expression(AST.Type.PrimaryExp, Token.Identifier);
		TokenList idlist = new TokenList;
		idlist.append(tokSizeof);
		idexpr.start = idlist.begin();
		idexpr.end = idlist.end();

		// combine to arg.sizeof
		TokenList tokList = new TokenList;
		Expression postexpr = new Expression(AST.Type.PostExp, Token.Identifier);
		postexpr.start = postexpr.end = tokList.end();
		postexpr.appendChild(nexpr, nexprList);
		postexpr.appendChild(idexpr, idlist);
		postexpr.insertTokenBefore(idexpr, tokDot);

		ASTIterator it = expr._parent.children.find(expr);
		expr._parent.insertChildBefore(it, postexpr, tokList);
		expr._parent.removeChild(expr);

		patchAST(postexpr);
	}
}

void patchPrimaryParen(Expression expr)
{
	if(expr._toktype == Token.ParenL)
	{
		if(Expression subExpr = cast(Expression) expr.children[0])
			if(subExpr._toktype == Token.Identifier)
			{
				TokenList subList = expr.removeChild(subExpr);
				subExpr.start.pretext = expr.start.pretext ~ subExpr.start.pretext;
				ASTIterator it = expr._parent.children.find(expr);
				expr._parent.insertChildBefore(it, subExpr, subList);
				expr._parent.removeChild(expr);
				checkSeparatingSpace(subExpr.start);
				patchAST(subExpr);
			}
	}
}

///////////////////////////////////////////////////////////////

void patchReferenceArg(Expression expr)
{
	// expr is unary expression
	if(expr._toktype != Token.Ampersand)
		return;
	AST parent = expr;
	while(cast(Expression) parent)
	{
		// '&' must be somewhere in the unary part of the expression (not args or initilializer)
		if(parent._parent.children[0] != parent)
			return;
		parent = parent._parent;
	}

	if(cast(DeclVar) parent)
		if(Declaration decl = cast(Declaration) parent._parent)
		{
			decl.start.pretext ~= "ref ";
			expr.start.text = " ";  // remove '&'
		}
}

///////////////////////////////////////////////////////////////

// dmd specific
void patchAssignArrayData(Expression expr)
{
	if(!options.enableDmdSpecifics)
		return;

	// expr is binary expression
	if(expr._toktype != Token.Assign)
		return;

	Expression e1 = cast(Expression)expr.children[0];
	Expression e2 = cast(Expression)expr.children[1];
	if(!e1 || !e2)
		return;

	// if there is a rhs cast, it's ok
	if(e2._type == AST.Type.CastExp)
		return;

	// check if lhs is xxx.data[nnn] 
	if(e1._type != AST.Type.PostExp || e1._toktype != Token.BracketL)
		return;
	Expression e3 = cast(Expression)e1.children[0];
	if(!e3 || e3._type != AST.Type.PostExp || (e3._toktype != Token.Dot && e3._toktype != Token.Deref))
		return;
	
	Expression e4 = cast(Expression)e3.children[1];
	if(!e4 || e4._type != AST.Type.PrimaryExp || e4._toktype != Token.Identifier)
		return;

	if(e4.start.text != "data")
		return;
	
	// insert cast(void*) to rhs
	e2.start.pretext ~= "cast(void*)";
}

// dmd specific
void patchAssignCast(Expression expr)
{
	if(!options.enableDmdSpecifics)
		return;

	// expr is binary expression
	if(expr._toktype != Token.Assign)
		return;

	Expression e1 = cast(Expression)expr.children[0];
	Expression e2 = cast(Expression)expr.children[1];
	if(!e1 || !e2)
		return;

	// if there is a rhs cast, it's ok
	if(e2._type == AST.Type.CastExp)
		return;

	if(e2._type == AST.Type.PrimaryExp && e2._toktype == Token.Number) // constants are probably correct, do not need cast
		return;

	string casttext;
	// check if lhs is xxx.sz
	if(e1._type == AST.Type.PostExp && (e1._toktype == Token.Dot || e1._toktype == Token.Deref))
	{
		string field = e1.children[1].start.text;
		switch(field)
		{
		case "sz":
			if(e2.start.text != "sz")
				casttext = "cast(ubyte)"; 
			break;
		default:
			return;
		}
	}
	else if (e1._type == AST.Type.PrimaryExp && e1._toktype == Token.Identifier)
	{
		string var = e1.start.text;
		switch(var)
		{
		case "offset":
			if(e2._type == AST.Type.BinaryExp && e2._toktype != Token.Ampersand)
				casttext = "cast(typeof(offset))";
			break;
		default:
			return;
		}
	}

	if(casttext.length == 0)
		return;

	if(e2._type == AST.Type.BinaryExp)
	{
		casttext ~= "(";
		e2.end.pretext = ")" ~ e2.end.pretext;
	}
	e2.start.pretext ~= casttext;
}

void patchPointerComparison(Expression expr)
{
	// expr is binary expression
	if(expr._toktype != Token.Equal && expr._toktype != Token.Unequal)
		return;

	Expression e1 = cast(Expression)expr.children[0];
	Expression e2 = cast(Expression)expr.children[1];
	if(!e1 || !e2)
		return;

	if(e1.start.text == "NULL" || e2.start.text == "NULL")
	{
		if(expr._toktype == Token.Equal)
			e1.end.text = "__is";
		else
			e1.end.text = "!__is";

		if(e1.end.pretext.length == 0)
			e1.end.pretext = " ";
		if(e2.start.pretext.length == 0)
			e2.start.pretext = " ";
	}
}

///////////////////////////////////////////////////////////////

// dmd specific
void patchCallArguments(Expression expr)
{
	if(!options.enableDmdSpecifics)
		return;

	// expr is postexp expression
	if(expr._toktype != Token.ParenL && expr._toktype != Token.Mixin)
		return; // not a call

	Expression obj;
	Expression e1 = cast(Expression)expr.children[0];
	if(e1 && e1._type == AST.Type.PostExp && (e1._toktype == Token.Dot || e1._toktype == Token.Deref))
	{
		obj = cast(Expression)e1.children[0];
		e1 = cast(Expression)e1.children[1];
	}
	if(!e1 || e1._type != AST.Type.PrimaryExp || e1._toktype != Token.Identifier)
		return;

	int argIdx;
	enum KindOfPatch { ZeroLoc, RemoveAddress, AddCastVoid, IsPrint, QuoteArgs } KindOfPatch patch;

	switch(e1.start.text)
	{
	case "checkNestedReference":
	                      argIdx = 1; patch = KindOfPatch.ZeroLoc; break;
	case "search":        argIdx = 0; patch = KindOfPatch.ZeroLoc; break;
	case "IdentifierExp": argIdx = 0; patch = KindOfPatch.ZeroLoc; break;
	case "push":          if(!obj || obj.start.text == "sc") return; // not on Scope
		goto case; // fall through
	case "shift":         argIdx = 0; patch = KindOfPatch.AddCastVoid; break;
	case "write":
	case "toCBuffer":
	case "toCBuffer2":    argIdx = 0; patch = KindOfPatch.RemoveAddress; break;
	case "isprint":       argIdx = 0; patch = KindOfPatch.IsPrint; break;
	case "__mixin":       argIdx = 0; patch = KindOfPatch.QuoteArgs; break;
	default:
		return;
	}

	if(expr.countChildren() <= 1 + argIdx)
		return;

	Expression arg = cast(Expression)expr.children[1 + argIdx];
	if(!arg)
	    return;

	switch(patch)
	{
	case KindOfPatch.ZeroLoc:
		if(arg._type == AST.Type.PrimaryExp && arg._toktype == Token.Number && arg.start.text == "0")
			arg.start.text = "Loc(0)";
		break;
	
	case KindOfPatch.RemoveAddress:
		if(arg._type == AST.Type.UnaryExp && arg._toktype == Token.Ampersand)
			arg.start.text = "";
		break;

	case KindOfPatch.AddCastVoid:
		if(arg._type != AST.Type.CastExp)
			arg.start.pretext ~= "cast(void*)";
		break;

	case KindOfPatch.IsPrint:
		if(arg.start.text == "v")
			arg.start.pretext ~= "cast(int)";
		break;
		
	default:
		break;
	}

}

// dmd specific
void patchCtorInitializer(AST ast)
{
	if(!options.enableDmdSpecifics)
		return;

	if(ast.start.text != "__super")
		return;
	if(!ast.children || ast.children.empty())
		return;

	Expression arg = cast(Expression)ast.children[0];
	if(arg && arg._type == AST.Type.PrimaryExp && arg._toktype == Token.Number && arg.start.text == "0")
		arg.start.text = "Loc(0)";
}

// dmd specific
void patchReturnExpressionType(Statement stmt)
{
	if(!options.enableDmdSpecifics)
		return;

	if(!stmt.children || stmt.children.empty())
		return;

	Expression expr = cast(Expression)stmt.children[0];
	if(!expr)
		return;

	// assume next parent that is a declaration is the function declaration
	AST ast = stmt._parent;
	while(ast && ast._type != AST.Type.Declaration)
		ast = ast._parent;
	if(!ast)
		return;

	// get type of return, just look at basic type, ignore indirections
	DeclType dtype = cast(DeclType)ast.children[0];
	if(!dtype)
		return;

	TokenIterator tokIt = dtype.mainTypeIterator();
	if(tokIt.atEnd())
		return;

	// now do some special type handling
	if(tokIt.text == "complex_t")
	{
	    if(expr.start.text == "0" || expr.start.text == "toReal")
		    expr.start.pretext ~= "cast(complex_t)";
	}
}

void patchQuoteCallArguments(Expression call)
{
	int cnt = call.countChildren();
	if(call._toktype != Token.ParenL || cnt < 2)
		return;

	for(ASTIterator it = call.children.begin() + 1; !it.atEnd(); ++it)
	{
		it.start.pretext ~= "\"";
		it.end.pretext = "\"" ~ it.end.pretext;
	}
}

void patchQuoteMixinArguments(Expression expr)
{
	// expr is postexp expression
	if(expr._toktype != Token.Mixin)
		return;

	if(!expr.children || expr.children.empty())
		return;

	Expression call = cast(Expression)expr.children[0];
	if(!call)
		return;

	patchQuoteCallArguments(call);
}

///////////////////////////////////////////////////////////////

void patchAsm(Statement stmt)
{
	TokenIterator tokIt = stmt.start;
	if(tokIt != stmt.end && tokIt.type == Token.__Asm)
		tokIt.advance();
	while(tokIt != stmt.end && tokIt.type == Token.Newline)
		tokIt.advance();
	if(tokIt != stmt.end && tokIt.type == Token.BraceL)
		tokIt.advance();

	int nonNewlines = 0;
	for( ; tokIt != stmt.end; ++tokIt)
	{
		if(tokIt.type == Token.Newline || tokIt.type == Token.BraceR)
		{
			if(nonNewlines && !startsWith(tokIt.pretext, ';'))
				tokIt.pretext = ";" ~ tokIt.pretext;
			nonNewlines = 0;
		}
		//else if(tokIt.type == Token.Colon)
		//	nonNewlines = 0;
		else
			nonNewlines++;
	}
}

void patchEmptyStatement(Statement stmt)
{
	// a label is part of the token sequence of the statement
	if(stmt._toktype == Token.Semicolon && stmt.start.type == Token.Semicolon) // ';' allowed after label':'?
	{
		if(Statement parent = cast(Statement) stmt._parent)
			if(parent._toktype == Token.For)
				if(stmt == parent.children[0] || stmt == parent.children[1])
					return;

		stmt.start.text = "{}";
	}
}

///////////////////////////////////////////////////////////////////////////////

DeclVar findDeclarationForward(AST ast, string ident)
{
	if(ast._type == AST.Type.Declaration && ast.children)
	{
		ASTIterator it = ast.children.begin();
		if(!it.atEnd())
			it.advance();
		for(; !it.atEnd(); ++it)
		{
			AST idast = findIdentifier(*it);
			if(idast && idast.start.type == Token.Identifier)
				if(idast.start.text == ident)
					return cast(DeclVar) *it;
		}
	}
	else if(ast._type == AST.Type.ConditionalDeclaration || ast._type == AST.Type.DeclarationGroup)
		if(ast.children)
			for(ASTIterator it = ast.children.begin(); !it.atEnd(); ++it)
				if(DeclVar v = findDeclarationForward(*it, ident))
					return v;
	return null;
}

DeclVar findDeclarationUp(AST ast, string ident)
{
	while(ast._parent)
	{
		ASTIterator it = ast._parent.children.find(ast);
		while(!it.atBegin())
		{
			it.retreat();
			if(DeclVar v = findDeclarationForward(*it, ident))
				return v;
		}
		ast = ast._parent;
	}
	return null;
}

///////////////////////////////////////////////////////////////////////////////

void nameUnnamedStruct(DeclType dtype)
{
	if(dtype._ident.length > 0)
		return;

	// create name for unnamed types
	TokenIterator tokIt = dtype.start;
	DeclType.skipModifiers(tokIt);
	
	// now on struct/union/enum
	nextToken(tokIt);
	assume(tokIt.type == Token.BraceL);

	if(tokIt.type != Token.Identifier)
	{
		string ident = format("unnamed_%d", tokIt.lineno);
		Token tok = createToken(" ", ident, Token.Identifier, tokIt.lineno);
		// no need to change AST, because there is no child between "struct" and "{"
		tokIt.insertBefore(tok);
		dtype._ident = ident;
	}
}

void extractStructDefinition(Declaration decl)
{
	if(!decl.children || decl.children.count() < 2)
		return;

	DeclType dtype = cast(DeclType) decl.children[0];
	if(dtype._dtype != DeclType.Enum && dtype._dtype != DeclType.Class)
		return;

	if(!dtype.children) // empty class has children list, but no children
		return;

	nameUnnamedStruct(dtype);

	// copy struct/enum declaration before var declaration
	DeclType ndtype = dtype.clone();
	TokenList ndlist = ndtype.cloneTokens(true);

	DeclType.skipModifiers(ndtype.start);

	TokenIterator begIt = ndlist.begin();
	if(begIt != ndtype.start)
	{
		if(indexOf(ndtype.start.pretext, "\n") < 0)
		{
			int pos = lastIndexOf(begIt.pretext, "\n");
			if(pos >= 0)
				ndtype.start.pretext = begIt.pretext[pos .. $] ~ strip(ndtype.start.pretext);
		}
		ndlist.remove(begIt, ndtype.start);
	}

	ASTIterator it = decl._parent.children.find(decl);
	Declaration ndecl = new Declaration(ndtype);
	ndecl.start = ndtype.start;
	ndecl.end = ndtype.end;
	decl._parent.insertChildBefore(it, ndecl, ndlist);

	// remove decl body from var declaration
	while(!dtype.children.empty())
		dtype.removeChild(dtype.children[0]);
	dtype.children = null;

	// remove tokens left over between { and }
	TokenIterator tokIt = dtype.start;
	while(tokIt != dtype.end && tokIt.type != Token.BraceL)
		tokIt.advance();

	while(tokIt != dtype.end)
	{
		int type = tokIt.type;
		TokenIterator nextIt = tokIt;
		nextIt.advance();

		dtype.removeToken(tokIt);
		if(type == Token.BraceR)
			break;

		tokIt = nextIt;
	}

	patchAST(ndtype);
}

bool removeForwardDeclaration(Declaration decl)
{
	if(!decl.children || decl.children.count() != 1)
		return false;

	DeclType dtype = cast(DeclType) decl.children[0];
	if(dtype._dtype != DeclType.Enum && dtype._dtype != DeclType.Class)
		return false;

	if(dtype.children) // empty class has children list, but no children
		return false;

	decl._parent.removeChild(decl);
	return true;
}

bool removeExternDeclaration(Declaration decl)
{
	if(!decl.children || decl.children.count() < 1)
		return false;

	DeclType dtype = cast(DeclType) decl.children[0];
	if(dtype.start.type != Token.Extern)
		return false;

	decl._parent.removeChild(decl);
	return true;
}

bool isSimpleVarDecl(DeclVar var)
{
	assume(var && var.children && !var.children.empty);
	Expression expr = cast(Expression)var.children[0];
	assume(expr);

	return expr._type == AST.Type.PrimaryExp && expr._toktype == Token.Identifier;
}

void patchClassVarInit(Statement stmt)
{
	if(!stmt.children || stmt.children.empty())
		return;
	Declaration decl = cast(Declaration) stmt.children[0];
	if(!decl)
		return;
	DeclClassification classify = classifyDeclaration(decl);
	if(classify != DeclClassification.VarDeclaration)
		return;

	if(decl.children.count() >= 2)
	{
		DeclType dtype = cast(DeclType) decl.children[0];
		DeclVar  dvar  = cast(DeclVar)  decl.children[1];

		assume(dtype && dvar && dvar.children);

		if(dtype._dtype == DeclType.Class && !dtype.isTypedef() && !isBasicUserType(dtype._ident))
		{
			AST id = dvar.children[0];
			bool hasArgs = (id._type == AST.Type.PostExp && expressionType(id) == Token.ParenL);
			bool isPOD = AST.isPOD(dtype._ident);
			if((!isPOD && isSimpleVarDecl(dvar)) || hasArgs)
			{
				AST ident = findIdentifier(dvar);
				assume(ident);
				string newtext = " = new ";
				if(isPOD)
					newtext = " = ";
				ident.end.pretext = newtext ~ dtype._ident ~ dvar.end.pretext;
			}
		}
	}
}

void splitNonSimpleVarList(Declaration decl)
{
	if(decl.children && decl.children.count() > 2)
	{
		ASTIterator it = decl.children.begin();
		DeclType dtype = cast(DeclType)*it;

		bool simple = true;
		int cntvar = 0;
		for(it.advance(); !it.atEnd(); ++it)
		{
			DeclVar dvar = cast(DeclVar)*it;
			if(dvar)
			{
				cntvar++;
				simple = simple && isSimpleVarDecl(dvar);
			}
		}
		// do nothing if function body follows
		if(!simple && cntvar > 1)
		{
			ASTIterator insIt = decl._parent.children.find(decl);
			insIt.advance();

			for(it = decl.children.begin() + 2; !it.atEnd(); it = decl.children.begin() + 2)
			{
				DeclType ndtype = dtype.clone();
				TokenList typeTokens = ndtype.cloneTokens(true);
				int pos = lastIndexOf(typeTokens.begin().pretext, "\n");
				if(pos > 0)
					typeTokens.begin().pretext = typeTokens.begin().pretext[pos .. $];

				DeclVar dvar = cast(DeclVar)*it;
				TokenList varTokens = decl.removeChild(dvar);

				Declaration ndecl = new Declaration(null);
				TokenList declList = new TokenList;
				declList.append(createToken("", ";", Token.Semicolon, 0));
				ndecl.start = declList.begin();
				ndecl.end = declList.end();

				if(varTokens.begin().pretext.length == 0)
					varTokens.begin().pretext = " ";
				ndecl.appendChild(dvar, varTokens);
				ndecl.prependChild(ndtype, typeTokens);

				decl._parent.insertChildBefore(insIt, ndecl, declList);
				patchAST(ndecl);
			}

			// remove commas that are left over
			DeclVar dvar = cast(DeclVar)decl.children[1];
			TokenIterator semiIt = decl.end - 1;
			TokenIterator commaIt = dvar.end;
			assume(commaIt.type == Token.Comma && semiIt.type == Token.Semicolon);

			AST.fixIteratorChildrenEnd(dvar, commaIt, semiIt);
			commaIt.eraseUntil(semiIt);
		}
	}
}

void patchAbstractMethods(Declaration decl)
{
	DeclClassification classify = classifyDeclaration(decl);
	if(classify != DeclClassification.AbstractFuncDeclaration)
		return;

	decl.start.pretext ~= "abstract "; // this should be the "virtual" token, that is cleared later

	DeclVar  dvar  = cast(DeclVar)  decl.children[1];
	assume(dvar.end[-2].text == "=");
	assume(dvar.end[-1].text == "0");

	if(strip(dvar.end[-2].pretext) == "")
		dvar.end[-2].pretext = "";
	clearTokenText(dvar.end - 2);
	clearTokenText(dvar.end - 1);
}

int getArrayDimension(Expression var)
{
	int dim = 0;
	while(var && var._type == AST.Type.UnaryExp) // skip pointer declarations
		var = cast(Expression) var.children[0];

	while(var && var._type == AST.Type.PostExp && var._toktype == Token.BracketL)
	{
		dim++;
		var = cast(Expression) var.children[0];
	}
	return dim;
}

void patchInitializer(Declaration decl)
{
	if(decl.countChildren() < 2)
		return;

	DeclType dtype = cast(DeclType) decl.children[0];
	if(dtype && dtype._dtype == DeclType.Template)
		return; // TODO
	DeclVar  dvar  = cast(DeclVar)  decl.children[1];

	assume(dtype && dvar);
	if(dvar.countChildren() < 2)
		return;

	Expression var  = cast(Expression) dvar.children[0];
	Expression init = cast(Expression) dvar.children[1];
	assume(var && init);
	
	int dim = getArrayDimension(var);
	if(dim >= 1)
	{
		bool isBasic = dtype._dtype == DeclType.Basic || isBasicUserType(dtype._ident);
		patchArrayInit(init, dim, isBasic);
	}
	else
	{
		if(var._type == AST.Type.PrimaryExp && var._toktype == Token.Identifier)
			if(var.start.text == "dim2")
				init.start.pretext ~= "cast(" ~ dtype._ident ~ ")";
	}
}

void patchArrayInit(Expression init, int dim, bool isBasic)
{
	if(init._type != AST.Type.PrimaryExp || init._toktype != Token.BraceL)
		return;

	if(init.start.type == Token.BraceL)
		init.start.text = "[";
	if(init.end[-1].type == Token.BraceR)
		init.end[-1].text = "]";

	if(!init.children || init.children.empty())
		return;

	Expression first = cast(Expression) *init.children.begin();
	bool isInit = (first && first._type == AST.Type.PrimaryExp && first._toktype == Token.BraceL);
	bool wantBrackets = dim > 1 || !isBasic;

	if(isInit && dim > 1)
	{
		for(ASTIterator it = init.children.begin(); !it.atEnd(); ++it)
			if(Expression ini = cast(Expression) *it)
				patchArrayInit(ini, dim - 1, isBasic);
	}
	else if(!isInit && wantBrackets)
	{
		string open  = !isBasic ? "{ " : "[ ";
		string close = !isBasic ? " }," : " ],";

		// struct/array initializer expected, but none found, so we assume one intializer per line
		bool isOpen = false;
		for(ASTIterator it = init.children.begin(); !it.atEnd(); ++it)
		{
			Token tok = *it.start;
			if(indexOf(tok.pretext, '\n') >= 0)
			{
				if(it != init.children.begin())
					tok.pretext = close ~ tok.pretext;
				tok.pretext ~= open;
				isOpen = true;
			}
		}
		if(isOpen)
			init.end[-1].pretext = close ~ init.end[-1].pretext;
	}
}

void patchStringDeclaration(Declaration decl)
{
	if(decl.countChildren() < 2)
		return;

	DeclType dtype = cast(DeclType) decl.children[0];
	if(dtype && dtype._dtype == DeclType.Template)
		return; // TODO
	DeclVar  dvar  = cast(DeclVar)  decl.children[1];

	assume(dtype && dvar);

	Expression var = cast(Expression) dvar.children[0];
	if(!var || var._type != AST.Type.PostExp || var._toktype != Token.BracketL || var.countChildren() != 1)
		return;

	Expression id = cast(Expression) var.children[0];
	if(!id || id._type != AST.Type.PrimaryExp || id._toktype != Token.Identifier)
		return;

	Token isCharType(DeclType dtype)
	{
		Token charTok;
		bool isNotChar = false;
		for(TokenIterator it = dtype.start; it != dtype.end; ++it)
			if(!DeclType.isTypeModifier(it.text))
			{
				if(it.text == "char")
					charTok = *it;
				else
					isNotChar = true;
			}
		return isNotChar ? null : charTok;
	}

	Token tok = isCharType(dtype);
	if(!tok)
		return;

	tok.text = "__string";
	dtype._dtype = DeclType.Class;
	dtype._ident = tok.text;

	assume(var.end[-2].type == Token.BracketL);
	assume(var.end[-1].type == Token.BracketR);
	
	clearTokenText(var.end - 2);
	clearTokenText(var.end - 1);
}

void patchPointerDeclaration(Declaration decl)
{
	if(decl.countChildren() < 2)
		return;

	DeclType dtype = cast(DeclType) decl.children[0];
	if(dtype && dtype._dtype == DeclType.Template)
		return; // TODO
	DeclVar  dvar  = cast(DeclVar)  decl.children[1];

	assume(dtype && dvar);

	if(dtype._dtype != DeclType.Class || !isClassType(dtype._ident))
		return;

	Expression expr = cast(Expression) dvar.children[0];
	if(!expr || expr._type != AST.Type.UnaryExp || (expr._toktype != Token.Ampersand && expr._toktype != Token.Asterisk))
		return;

	clearTokenText(expr.start);
}

void patchDeclType(DeclType dtype)
{
	TokenIterator startIt = dtype.start;
	DeclType.skipModifiers(startIt);

	if(dtype._dtype == DeclType.Basic)
	{
		if(!patchVoidArg(dtype))
			patchBasicDeclType(dtype);
	}
	else if(dtype._dtype == DeclType.Enum)
	{
		TokenIterator nextIt = startIt;
		nextToken(nextIt);
		if(startIt.type == Token.Enum && dtype._parent.children.count() > 1)
			clearTokenText(startIt);
		
		// add ":int" to workaround forward references
		version(dmd_2_43)
		for( ; nextIt != dtype.end; ++nextIt)
			if(nextIt.type == Token.BraceL)
			{
				nextIt.pretext = " : int" ~ nextIt.pretext;
				break;
			}

		patchDeclTypeModifier(dtype);
	}
	else if(dtype._dtype == DeclType.Class)
	{
		if(startIt.type == Token.Class || startIt.type == Token.Struct)
		{
			TokenIterator nextIt = startIt;
			nextToken(nextIt);
			if(nextIt.type == Token.Identifier)
			{
				if(dtype._parent.children.count() > 1)
					// variable declaration doesn't need struct keyword
					clearTokenText(startIt);
				else if(AST.isPOD(nextIt.text))
					startIt.text = "struct";
				else
					startIt.text = "class";
			}
		}
		if(startIt.type == Token.Union)
		{
			if(dtype._parent.children.count() > 1)
				// variable declaration doesn't need union keyword
				clearTokenText(startIt);
		}
		patchDeclTypeModifier(dtype);
	}
	else if(dtype._dtype == DeclType.CtorDtor)
	{
		if(DeclVar var = cast(DeclVar) dtype.nextSibling())
		{
			if(var.start.type == Token.Tilde)
				var.start[1].text = "this";
			else
			{
				string text = "this";
				if(AST.isPOD(var.start.text))
					if(var.start[1].type == Token.ParenL && var.start[2].type == Token.ParenR)
						text = "static " ~ var.start.text ~ " opCall"; // var.start[2].pretext = "def_ctor" ~ var.start[2].pretext;
				var.start.text = text;
			}
		}
	}
	else if(dtype._dtype == DeclType.Template)
	{
		if(dtype.start.text == "template")
		{
			// a declaration, move arguments to identifier
			Declaration decl = cast(Declaration)dtype._parent;
			assume(decl && decl.children.count() > 1);
			if(Declaration decl2 = cast(Declaration)decl.children[1])
			{
				bool isStruct = dtype.end.text == "struct" || dtype.end.text == "class";
				if(DeclType dtype2 = cast(DeclType)decl2.children[0])
				{
					TokenList tl = decl.removeChild(dtype);
					string pretext = dtype.start.pretext;
					dtype.removeToken(dtype.start); // throw away "template"
					
					for(TokenIterator it = tl.begin(); it != tl.end(); it.advance())
						if(it.text == "<")
							it.text = "(";
					if(dtype.end[-1].text == ">")
						dtype.end[-1].text = ")";

					if(isStruct)
					{
						TokenIterator insertPos = dtype2.start + 2; // after "struct Identifier"
						dtype2.insertChildBefore(dtype2.childrenBegin(), dtype, tl, &insertPos);
					}
					else if(auto dvar2 = cast(DeclVar)decl2.children[1])
					{
						// simply add arguments to identifier
						if(dvar2.start.type == Token.Identifier)
						{
							string argtext = createMappedTokenListText(tl);
							dvar2.start.text ~= argtext;
						}
						// bad insert position:
						//TokenIterator insertPos = dvar2.start + 1; // after "int Identifier"
						//dvar2.insertChildBefore(dvar2.childrenBegin(), dtype, tl, &insertPos);
					}
					decl.start.pretext = pretext ~ decl.start.pretext;
				}
			}
		}
		else
		{
			// an instance, just replace <> with !()
			TokenIterator stop = dtype.end;
			if(dtype.children && !dtype.children.empty())
				stop = dtype.children.begin().start;
			for(TokenIterator it = dtype.start; it != stop && it != dtype.end; it.advance())
				if(it.text == "<")
					it.text = "!(";
			if(dtype.end[-1].text == ">")
				dtype.end[-1].text = ")";
		}
	}
}

void patchCastExp(AST ast)
{
	if(ast.start.type == Token.ParenL)
		ast.start.pretext ~= "cast";
	else // static_cast, etc
	{
		TokenIterator it = ast.start;
		it.text = "__cast";
		nextToken(it);
		assume(it.type == Token.LessThan);
		it.text = "(";
		it = ast.children[0].end;
		assume(it.type == Token.GreaterThan);
		it.text = ")";
	}
}

///////////////////////////////////////////////////////////////

void patchAST(AST ast)
{
	if(ast._type == AST.Type.CastExp)
	{
		patchCastExp(ast);
	}
	if(ast._type == AST.Type.TypeDeclaration)
	{
		if(DeclType dtype = cast(DeclType)ast)
			patchDeclType(dtype);
	}
	if(ast._type == AST.Type.PrimaryExp)
	{
		if(Expression expr = cast(Expression) ast)
		{
			patchOperatorName(expr);
			patchEnumName(expr);
			patchSizeof(expr);
			patchPrimaryParen(expr);
			patchQuoteMixinArguments(expr);
		}
	}
	if(ast._type == AST.Type.PostExp)
	{
		if(Expression expr = cast(Expression) ast)
		{
			patchCallArguments(expr);
		}
	}
	if(ast._type == AST.Type.UnaryExp)
	{
		if(Expression expr = cast(Expression) ast)
		{
			patchReferenceArg(expr);
		}
	}
	if(ast._type == AST.Type.BinaryExp)
	{
		if(Expression expr = cast(Expression) ast)
		{
			patchAssignArrayData(expr);
			patchAssignCast(expr);
			patchPointerComparison(expr);
		}
	}
	if(ast._type == AST.Type.Statement)
	{
		if(Statement stmt = cast(Statement) ast)
		{
			patchEmptyStatement(stmt);

			if(stmt._toktype == Token.__Asm)
				patchAsm(stmt);
			if(stmt._toktype == Token.Return)
				patchReturnExpressionType(stmt);

			patchClassVarInit(stmt);
		}
	}
	if(ast._type == AST.Type.CtorInitializer)
			patchCtorInitializer(ast);

	if(ast._type == AST.Type.Declaration)
	{
		if(Declaration decl = cast(Declaration) ast)
		{
			if (removeForwardDeclaration(decl))
				return;
			if (removeExternDeclaration(decl))
				return;
			extractStructDefinition(decl);
			splitNonSimpleVarList(decl);
			patchAbstractMethods(decl);
			patchInitializer(decl);
			patchStringDeclaration(decl);
			patchPointerDeclaration(decl);
		}
	}

	if(ast._type == AST.Type.DeclarationGroup)
	{
		if(ast.start.type == Token.Extern)
			switch(ast.start[1].text)
			{
			case "\"C\"": ast.start[1].text = "(C)"; break;
			default:
			}
	}
	if(ast.children)
	{
		for(ASTIterator it = ast.children.begin(); !it.atEnd(); )
		{
			// some simple support to allow changing the current child without making the iterator invalid
			AST child = *it; 
			++it;
			patchAST(child);
		}
	}

	// process after children are processed
	if(ast._type == AST.Type.ConditionalDeclaration)
	{
		bool emptyDeclGroup(AST grp)
		{
			TokenIterator it = grp.start;
			if(it == grp.end)
				return true;
			if(it.type != Token.BraceL)
				return false;
			it.advance(); // not nextToken to detect pp-tokens
			return it.type == Token.BraceR;
		}

		int cnt = ast.countChildren();
		assume(cnt > 1);
		bool empty = emptyDeclGroup(ast.children[1]);
		if(empty && cnt > 2)
			empty = emptyDeclGroup(ast.children[2]);
		if(empty)
			ast._parent.removeChild(ast);
	}
}

///////////////////////////////////////////////////////////////

alias void function (TokenList) patch_fn;

struct translateInfo
{
	string inputFile;
	patch_fn prepatch;
	patch_fn postpatch;
};

bool isBasicUserType(string ident)
{
	switch(ident)
	{
	case "time_t":
	case "size_t":
	case "int8_t":
	case "uint8_t":
	case "int16_t":
	case "uint16_t":
	case "int32_t":
	case "uint32_t":
	case "int64_t":
	case "uint64_t":
	case "uinteger_t":
	case "va_list":
		return true;
	default:
		return (ident in options.userValueTypes) !is null;
	}
}

bool isClassType(string ident)
{
	if(ident in options.userRefTypes)
		return true;
	if(AST.isPOD(ident))
		return false;
	if(isBasicUserType(ident))
		return false;
	if(DeclType.isBasicType(ident))
		return false;

	return true;
}

///////////////////////////////////////////////////////////////

int firstPathSeparator(string path)
{
	int fslash = indexOf(path, '/');
	int bslash = indexOf(path, '\\');
	if(fslash < 0)
		return bslash;
	if(bslash < 0)
		return fslash;
	return min(fslash, bslash);
}

///////////////////////////////////////////////////////////////////////
void writeDirAndFile(string filename, string text)
{
	string path = dirName(filename);
	if(!exists(path))
		mkdirRecurse(path);
	std.file.write(filename, text);
}

///////////////////////////////////////////////////////////////

class Source
{
	this(Cpp2DConverter dg)
	{
		_dg = dg;
	}

	void init(string filename)
	{
		string absfile = makeFilenameAbsolute(filename, options.inputDir);
		init(filename, cast(string) read(absfile));
	}

	void init(string filename, string text)
	{
		_tokenList = new TokenList;
		_filename = filename;
		_text = text;
	}

	void scan()
	{
		_tokenList = scanText(_text);
	}

	void rescanPP()
	{
		.rescanPP(_tokenList);
	}

	int patchRules(PatchRule[] rules)
	{
		int cntReplace = 0;
		foreach(rule; rules)
			if(rule.filenamePattern.length == 0 || globMatch(_filename, rule.filenamePattern))
				cntReplace += replaceTokenSequence(_tokenList, rule.searchTokens, rule.replaceTokens, true);
		if(cntReplace > 0)
			rescanPP();
		return cntReplace;
	}

	//////////////////////////////////////////////////////////////////////////////
	void fixConditionalCompilation()
	{
		PP pp = new PP;
		pp.fixConditionalCompilation(_tokenList);
		pp.convertDefinesToEnums(_tokenList);
	}

	void createAST()
	{
		_ast = new AST(AST.Type.Module);
		TokenIterator tokIt = _tokenList.begin();
		_ast.parseModule(tokIt);
	}

	string createTokenListText(int pass)
	{
		string text;
		for(TokenIterator tokIt = _tokenList.begin(); !tokIt.atEnd(); ++tokIt)
		{
			Token tok = *tokIt;
			string mapped = pass > 0 ? tok.text : mapTokenText(tok);
			text ~= tok.pretext ~ mapped;
		}
		return text;
	}

	void writeTokenList(string outfilename, string hdr, int pass)
	{
		string text = createTokenListText(pass);
		writeDirAndFile(options.outputDir ~ outfilename, hdr ~ text);
	}

	Cpp2DConverter _dg;
	string _filename;
	patch_fn postpatch;

	string _text;

	AST _ast;
	TokenList _tokenList;
}

///////////////////////////////////////////////////////////////

class Cpp2DConverter
{
	///////////////////////////////////////////////////////////////////////
	AST[][string] functionDeclarations;
	AST[][string] functionDefinitions;
	AST[][string] varDefinitions;
	Source[] sources;
	Source currentSource;

	///////////////////////////////////////////////////////////////////////

	void writemsg(string s)
	{
		writeln(s);
	}

	Source findSource(AST ast)
	{
		AST root = ast.getRoot();
		foreach(src; sources)
			if(src._ast is root)
				return src;
		return null;
	}

	void writemsg(AST ast, string s)
	{
		string where = text("(", ast.start.lineno, "): ");
		if(auto src = findSource(ast))
		{
			string absfile = makeFilenameAbsolute(src._filename, options.inputDir);
			where = absfile ~ where;
		}
		writemsg(where ~ s);
	}

	void writeerror(Throwable e)
	{
		string msg = e.toString();
		//if(startsWith(msg, currentfile))
		//	throw e;
		string fname;
		if(currentSource)
			fname = makeFilenameAbsolute(currentSource._filename, options.inputDir);
		
		if(msg.indexOf("SyntaxException") > 0)
		{
			int pos = msg.indexOf("):");
			if(pos > 0)
				msg = strip(msg[pos + 2 .. $]);
			if(msg.startsWith("("))
				msg = fname ~ msg;
			else if(fname.length)
				msg = fname ~ ": " ~ msg;
		}
		else if(fname.length)
			msg = fname ~ ": " ~ msg;
		writemsg(msg);
	}

	///////////////////////////////////////////////////////////////////////

	void registerFunctionDefinition(Declaration decl)
	{
		DeclClassification type = classifyDeclaration(decl);
		if(type == DeclClassification.FuncDefinition)
		{
			ToStringData tsd;
			tsd.noIdentifierInPrototype = true;
			string ident = decl.toString(tsd);
			if(auto fdecl = ident in functionDefinitions)
			{
				writemsg(decl, "duplicate definition of " ~ ident);
				writemsg((*fdecl)[0], "  previous definition is here");
			}
			functionDefinitions[ident] ~= decl;
		}
		else if(type == DeclClassification.VarDeclaration || type == DeclClassification.VarDefinition)
		{
			ToStringData tsd;
			string ident = decl.toString(tsd);
			if(auto vdecl = ident in varDefinitions)
			{
				writemsg(decl, "duplicate definition of " ~ ident);
				writemsg((*vdecl)[0], "  previous definition is here");
			}
			varDefinitions[ident] ~= decl;
		}
	}

	///////////////////////////////////////////////////////////////////////
	Statement convertCtorInitializerToStatement(CtorInitializer ctorInit, ref TokenList tokList, bool callSuper)
	{
		TokenList stmtList = new TokenList;
		Statement stmt = new Statement(Token.Number);
		stmt.start = stmt.end = stmtList.begin();

		if(callSuper)
			tokList.begin().text = "__super";
		else
			tokList.begin()[1].text = " = ("; // was "("
		stmt.appendChild(ctorInit, tokList);
		stmt.insertTokenBefore(null, createToken("", ";", Token.Semicolon, 0)); // append

		tokList = stmtList;
		return stmt;
	}

	void moveCtorInitializers(Declaration decl)
	{
		if(DeclType dtype = isClassDefinition(decl))
		{
			++checkMethodLevel;
			scope(exit) --checkMethodLevel;

			iterateTopLevelDeclarations(dtype, &moveCtorInitializers);
			return;
		}

		ASTIterator initIt = decl.children.begin();
		for( ; !initIt.atEnd(); ++initIt)
			if(initIt._type == AST.Type.CtorInitializers)
				break;

		if(initIt.atEnd())
			return;

		ASTIterator bodyIt = initIt;
		for(++bodyIt; !bodyIt.atEnd(); ++bodyIt)
			if(bodyIt._type == AST.Type.Statement)
				break;

		// assume no contract for constructor
		if(bodyIt.atEnd() || !bodyIt.children || bodyIt.children.count() == 0)
			return;

		string className = decl.start.text;
		AST stmt = bodyIt.children[0];
		ASTIterator insertIt;
		if(stmt.children && !stmt.children.empty())
		{
			insertIt = stmt.children.begin();
		//	stmt = stmt.children[0];
		//	if(stmt.children && !stmt.children.empty())
		//		insertIt = stmt.children.begin();
		}
		
		int count = 0;
		while(initIt.children && !initIt.children.empty())
		{
			CtorInitializer initCtor = cast(CtorInitializer) *(initIt.children.begin());
			assume(initCtor);

			TokenList initList = initIt.removeChild(initCtor);

			string id = initList.begin().text;
			bool callSuper = AST.isBaseClass(id, className);
			Statement initStmt = convertCtorInitializerToStatement(initCtor, initList, callSuper);
			stmt.insertChildBefore(insertIt, initStmt, initList);
			insertIt = stmt.children.begin() + ++count;
		}

		initIt._parent.removeChild(*initIt);
	}

	///////////////////////////////////////////////////////////////////////
	void removeScopeFromIdentifier(AST impl)
	{
		assume(impl.children && impl.children.count() >= 2);
		DeclVar declvar = cast(DeclVar) impl.children[1];
		assume(declvar);

		AST ident = findIdentifier(declvar);
		AST cloneIdent = ident.clone();
		TokenList cloneList = cloneIdent.cloneTokens();

		TokenIterator tokIt = cloneIdent.end;
		while(tokIt != cloneIdent.start)
		{
			tokIt.retreat();
			if(tokIt.type == Token.DoubleColon)
			{
				tokIt[1].pretext = ident.start.pretext ~ tokIt[1].pretext;
				cloneIdent.start.eraseUntil(tokIt + 1);
    				
				ASTIterator idit = ident._parent.children.find(ident);
				ident._parent.insertChildBefore(idit, cloneIdent, cloneList);
				ident._parent.removeChild(ident);
				break;
			}
		}
	}

	void getConditionals(AST ast, ref AST[] cond)
	{
		while(ast._parent)
		{
			AST parent = ast._parent;
			if(parent._type == AST.Type.ConditionalDeclaration)
			{
				cond ~= parent;
			}
			ast = parent;
		}
	}

	bool compareASTs(ref AST[] cond, ref AST[] condOther)
	{
		if(cond.length != condOther.length)
			return false;
		for(int c = 0; c < cond.length; c++)
			if(cond[c] !is condOther[c])
				return false;
		return true;
	}

	AST cloneConditionalCode(AST impl, TokenList implList, ref AST[] cond, ref TokenList condList)
	{
		assume(cond.length > 0);
		assume(cond[0].children.count == 2); // expr + if, no else

		AST condImpl = cond[0].clone();
		condList = condImpl.cloneTokens(true);
		ASTIterator it = condImpl.children.begin() + 1;
		AST inscond = condImpl;

		if((*it).start.type == Token.BraceL)
		{
			inscond = *it;
			if(inscond.children)
				it = inscond.children.begin();
			else
				it = condImpl.children.end(); // just remember, we were at the end
		}
		inscond.insertChildBefore(it, impl, implList);
		if(!it.atEnd())
			inscond.removeChild(*it);

		return condImpl;
	}

	///////////////////////////////////////////////////////////////////////
	int checkMethodLevel;
	int countNoImplementations;
	AST[] declsToRemove;

	void moveMethods(Declaration decl)
	{
		if(DeclType dtype = isClassDefinition(decl))
		{
			++checkMethodLevel;
			scope(exit) --checkMethodLevel;

			iterateTopLevelDeclarations(dtype, &moveMethods);
		}
		else if(checkMethodLevel >= 0 && isFunctionDeclaration(decl))
		{
			ToStringData tsd;
			tsd.noIdentifierInPrototype = true;
			tsd.addScopeToIdentifier = true;
			string ident = decl.toString(tsd);

			if(ident in functionDeclarations)
			{
				writemsg(decl, "multiple declarations for " ~ ident);
			}
			functionDeclarations[ident] ~= decl;

			if(ident in functionDefinitions)
			{
				bool isStatic = decl.start.type == Token.Static;
				bool isExtern = decl.start.type == Token.Extern;
				if(!isExtern)
					replaceFunctionDeclarationWithDefinition(decl, functionDefinitions[ident], checkMethodLevel, isStatic);
			}
			else
			{
				writemsg(decl, "no implementation for " ~ ident);
				countNoImplementations++;
			}
		}
		else if(checkMethodLevel > 0 && isVarDeclaration(decl))
		{
			if(decl.start.text == "static")
			{
				ToStringData tsd;
				tsd.addScopeToIdentifier = true;
				string ident = decl.toString(tsd);

				if(ident in varDefinitions)
					replaceFunctionDeclarationWithDefinition(decl, varDefinitions[ident], checkMethodLevel, true);
				else
				{
					writemsg(decl, "no instantiation of " ~ ident);
					countNoImplementations++;
				}
			}
		}
	}

	void replaceFunctionDeclarationWithDefinition(Declaration decl, AST[] def, int indent, bool isStatic)
	{
		assume(def.length > 0);

		ASTIterator insertIt = decl._parent.children.find(decl);
		string pretext = decl.start.pretext;

		string mergePretext(string pre1, string pre2)
		{
			if(strip(pre1) == "")
				if(indexOf(pre2, '\n') >= 0)
					return pre2;
			return pre1 ~ pre2;
		}

		AST conditional;
		TokenList condList;
		bool sameConditional;
		if(def.length > 1)
		{
			// if we have multiple definitions of the method, check whether they are all in the same
			//  conditional branch (e.g. in a series of #if/#elif/#else)
			AST[] cond;
			getConditionals(def[0], cond);
			sameConditional = (cond.length > 0);
			for(int d1 = 1; d1 < def.length && sameConditional; d1++)
			{
				AST[] condOther;
				getConditionals(def[d1], condOther);
				if(!compareASTs(cond, condOther))
					sameConditional = false;
			}

			if(cond.length > 0)
			{
				conditional = cond[0].clone();
				condList = conditional.cloneTokens(true);
				conditional.start.pretext = mergePretext(pretext, conditional.start.pretext);
				pretext = "";
			}
		}
		for(int d = 0; d < def.length; d++)
		{
			AST[] condDef;
			getConditionals(def[d], condDef);

			AST impl = def[d];
			TokenList implList = impl._parent.removeChild(impl);
			if(isStatic && !implList.empty())
				implList.begin().pretext ~= "static ";

			// remove scope info from identifier
			removeScopeFromIdentifier(impl);

			copyDefaultArguments(decl, cast(Declaration) impl);

			if(indent > 0)
				reindentList(implList, indent * options.indentSize, options.tabSize);

			if(conditional && sameConditional)
			{
				ASTIterator it = conditional.children.begin() + d + 1;
				AST cond = conditional;

				if(!it.atEnd() && (*it).start.type == Token.BraceL)
				{
					cond = *it;
					if(cond.children)
						it = cond.children.begin();
				}
				if(it.atEnd())
					cond.appendChild(impl, implList);
				else
					cond.insertChildBefore(it, impl, implList);
				if(!it.atEnd())
					cond.removeChild(*it);
			}
			else if(conditional) // && def.length > 1)
			{
				AST condImpl = cloneConditionalCode(impl, implList, condDef, condList);
				if(!condList.empty())
					condList.begin().pretext = mergePretext(pretext, condList.begin().pretext);
				pretext = pretext.init;
				decl._parent.insertChildBefore(insertIt, condImpl, condList);
			}
			else
			{
				if(!implList.empty())
					implList.begin().pretext = mergePretext(pretext, implList.begin().pretext);
				decl._parent.insertChildBefore(insertIt, impl, implList);
			}
		}

		if(conditional && sameConditional)
			decl._parent.insertChildBefore(insertIt, conditional, condList);

		// cannot remove decl immediately, because iterators in iterateTopLevelDeclarations will become invalid
		declsToRemove ~= decl;
	}

	void moveAllMethods()
	{
		declsToRemove.length = 0;

		foreach(currentSource; sources)
		{
			currentSource._ast.verify();
			iterateTopLevelDeclarations(currentSource._ast, &moveMethods);
		}

		foreach(AST decl; declsToRemove)
			decl._parent.removeChild(decl, true);

		declsToRemove.length = 0;
	}

	///////////////////////////////////////////////////////////////////////
	void moveAllCtorInitializers()
	{
		foreach(currentSource; sources)
		{
			currentSource._ast.verify();
			iterateTopLevelDeclarations(currentSource._ast, &moveCtorInitializers);
		}
	}

	///////////////////////////////////////////////////////////////////////
	void patchAllAST()
	{
		foreach(currentSource; sources)
			patchAST(currentSource._ast);
	}

	void writeFiles(int pass)
	{
		if(pass == 0 && options.importAllFile.length)
		{
			string importAllFile = options.importAllFile;
			string importAll = createImportAll(importAllFile, false);
			writeDirAndFile(options.outputDir ~ importAllFile, importAll);
			
			string srcAll = createImportAll(importAllFile, true);
			writeDirAndFile(options.outputDir ~ "sources", srcAll);
		}

		foreach(currentSource; sources)
		{
			if(pass == 0 && currentSource.postpatch)
				currentSource.postpatch(currentSource._tokenList);
			if(pass == 0)
				currentSource.patchRules(options.postRules);

			string outfile = genOutFilename(currentSource._filename, pass);
			string hdr;
			if(pass == 0)
			{
				hdr = options.codePrefix;
				string modname = createModuleName(currentSource._filename);
				string modtext = replace(hdr, "MODULENAME", modname);
				if(modtext == hdr)
					hdr = "module " ~ modname ~ ";\n\n" ~ modtext;
				else
					hdr = modtext;
			}
			currentSource.writeTokenList(outfile, hdr, pass);
		}
	}

	string createImportAll(string filename, bool makefile)
	{
		string txt;
		if (makefile)
			txt = "SRC = \\\n";
		else
		{
			string modname = createModuleName(filename);
			txt = replace(options.codePrefix, "MODULENAME", modname);
			if(txt == options.codePrefix)
				txt = "module " ~ modname ~ ";\n\n" ~ txt;
		}

		foreach(currentSource; sources)
		{
			string file = genOutFilename(currentSource._filename, 0);
			string mod = createModuleName(file);

			if(makefile)
				mod = replace(mod, ".", "\\");

			if(makefile)
				txt ~= "\t" ~ mod ~ ".d \\\n";
			else
				txt ~= "public import " ~ mod ~ ";\n";
		}

		return txt;
	}

	string genOutFilename(string filename, int pass)
	{
		string ext = extension(filename);
		string modname = createModuleName(filename);
		string fname = replace(modname, ".", "/");
		if(pass == 0)
		{
			if (ext != ".h" && ext != "")
				fname ~= "_" ~ ext[1 .. $];
			fname ~= ".d";
		}
		else
		{
			fname ~= ext;
		}
		string genpath = (pass > 0 ? format("pass%d/", pass) : "");
		return genpath ~ fname;
	}

	///////////////////////////////////////////////////////////////////////
	void processSource(Source src, patch_fn prepatch, patch_fn postpatch)
	{
		src.scan();
		src.fixConditionalCompilation();
		src.rescanPP();
		if(prepatch)
		{
			prepatch(src._tokenList);
			src.rescanPP();
		}
		if(options.expandDefines.length)
		{
			expandPPdefines(src._tokenList, options.expandDefines, MixinMode.ExpandDefine);
			rescanPP(src._tokenList);
		}
		src.patchRules(options.preRules);

		src.postpatch = postpatch;

		if(src._filename.length && options.writeIntermediate)
		{
			string outfile = genOutFilename(src._filename, 1);
			src.writeTokenList(outfile, "", 1);
		}

		syntaxErrorMessages = "";
		src.createAST();
		if(syntaxErrorMessages.length)
		{
			string absfile = makeFilenameAbsolute(src._filename, options.inputDir);
			syntaxErrorMessages = replace(syntaxErrorMessages, "$FILENAME$", absfile);
			if(syntaxErrorMessages.endsWith("\n"))
				syntaxErrorMessages = syntaxErrorMessages[0..$-1];
			writemsg(syntaxErrorMessages);
		}

		src._ast.verify();

		iterateTopLevelDeclarations(src._ast, &registerFunctionDefinition);
	}

	///////////////////////////////////////////////////////////////////////
	int main_dmd(translateInfo[] srcfiles)
	{
		options.setup_dmd();

		syntaxErrors = 0;
		int parsed = 0;
		int failed = 0;
		string currentfile;
		foreach(ref translateInfo ti; srcfiles)
		{
			parsed++;
			try
			{
				currentfile = ti.inputFile;
				writemsg("parsing " ~ currentfile);

				currentSource = new Source(this);
				currentSource.init(currentfile);
				sources ~= currentSource;
				processSource(currentSource, ti.prepatch, ti.postpatch);
			}
			catch(Throwable e)
			{
				failed++;
				writeerror(e);
				//throw new Exception(msg);
			}
		}

		writemsg(text(failed, " of ", parsed, " files failed to parse"));
		if(failed > 0)
			return -1;

		try
		{
			moveAllMethods();
			moveAllCtorInitializers();
			if(options.writeIntermediate)
				writeFiles(2);

			patchAllAST();
			writeFiles(0);
		}
		catch(Throwable e)
		{
			writeerror(e);
			return 1;
		}
		writemsg(text("conversion of ", parsed, " files completed (", syntaxErrors, " syntax errors)"));
		return 0;
	}

	///////////////////////////////////////////////////////////////////////
	int main(string[] srcfiles)
	{
		int parsed = 0;
		int failed = 0;
		syntaxErrors = 0;

		foreach(string currentfile; srcfiles)
		{
			parsed++;
			try
			{
				writemsg(currentfile);

				currentSource = new Source(this);
				currentSource.init(currentfile);
				sources ~= currentSource;
				processSource(currentSource, null, null);
			}
			catch(Throwable e)
			{
				failed++;
				writeerror(e);
			}
		}

		if(failed > 0)
		{
			writemsg(text(failed, " of ", parsed, " files failed to parse, aborting"));
			return -1;
		}

		try
		{
			moveAllMethods();
			moveAllCtorInitializers();
			if(options.writeIntermediate)
				writeFiles(2);

			patchAllAST();
			writeFiles(0);
		}
		catch(Throwable e)
		{
			writeerror(e);
			return 1;
		}

		writemsg(text("conversion of ", parsed, " files completed (", syntaxErrors, " syntax errors)"));
		return 0;
	}

	///////////////////////////////////////////////////////////////////////
	string main(string text)
	{
		currentSource = new Source(this);
		try
		{
			currentSource.init("", text);
			sources ~= currentSource;
			processSource(currentSource, null, null);

			moveAllMethods();
			moveAllCtorInitializers();
			//writeFiles(2);

			patchAllAST();
			//writeFiles(0);

			currentSource.patchRules(options.postRules);

			string ntext = currentSource.createTokenListText(0);
			return ntext;
		}
		catch(Throwable e)
		{
			writeerror(e);
			return null;
		}
	}
}

///////////////////////////////////////////////////////////////////////

string testDmdGen(string txt, int countRemove = 1, int countNoImpl = 0, TokenList[string] defines = null)
{
	AST.clearStatic();

	TokenList tokenList = scanText(txt);

	if(defines)
	{
		expandPPdefines(tokenList, defines, MixinMode.ExpandDefine);
		rescanPP(tokenList);
	}

	PP pp = new PP;
	pp.fixConditionalCompilation(tokenList);
	pp.convertDefinesToEnums(tokenList);
	rescanPP(tokenList);
	debug string chk1 = tokenListToString(tokenList);

	AST ast = new AST(AST.Type.Module);
	TokenIterator tokIt = tokenList.begin();
	ast.parseModule(tokIt);
	ast.verify();
	debug string chk2 = tokenListToString(tokenList);

	Cpp2DConverter gen = new Cpp2DConverter;
	options.setup_dmd();
	iterateTopLevelDeclarations(ast, &gen.registerFunctionDefinition);
	iterateTopLevelDeclarations(ast, &gen.moveMethods);
	assume(gen.countNoImplementations == countNoImpl);
	debug string chk3 = tokenListToString(tokenList);

	assume(gen.declsToRemove.length == countRemove);
	foreach(decl; gen.declsToRemove)
		decl._parent.removeChild(decl, true);
	ast.verify();

	iterateTopLevelDeclarations(ast, &gen.moveCtorInitializers);
	debug string chk4 = tokenListToString(tokenList);
	ast.verify();

	patchAST(ast);
	debug string chk5 = tokenListToString(tokenList);
	ast.verify();

	string res;
	for(TokenIterator it = tokenList.begin(); !it.atEnd(); ++it)
		res ~= it.pretext ~ mapTokenText(*it);

	res = detab(res, options.tabSize);
	return res;
}

unittest
{
	// arrays copied by reference!
	int[] arr1 = [ 1, 2, 3 ];
	int[] arr2 = arr1;
	assert(arr2[2] == 3);
	arr2[1] = 4;
	assert(arr1[1] == 4);
}

unittest
{
	string txt = "class C { type_t foo(int a, int x = 1); }; type_t C::foo(int a, int y) {}";
	string exp = "struct C {  type_t foo(int a, int y = 1) {} };";
	string res = testDmdGen(txt);

	assert(res == exp);
}

unittest
{
	string txt = 
		"class C {\n"
		"    FuncDeclaration *overloadResolve(int flags = 0);\n"
		"};\n"
		"FuncDeclaration *C::overloadResolve(int flags) {}\n";
	string exp = 
		"struct C {\n"
		"    FuncDeclaration *overloadResolve(int flags = 0) {}\n"
		"};\n";
	string res = testDmdGen(txt, 1, 0);

	assert(res == exp);
}

unittest
{
	string txt = "class C { type_t foo(); }; type_t C::foo() {}";
	AST ast = testAST(txt);
	ast.verify();

	AST clss = ast.children[0].children[0];
	AST decl = clss.children[0];
	AST impl = ast.children[1];

	string exp = " type_t foo();";
	string res = tokenListToString(decl.start, decl.end);
	assert(exp == res);

	TokenList decllist = clss.removeChild(decl);
	ast.verify();
	decl.verify();

	string exp1 = " type_t foo();";
	string res1 = tokenListToString(decllist);
	assert(exp1 == res1);

	string exp2 = "class C { }; type_t C::foo() {}";
	string res2 = tokenListToString(ast.start, ast.end);
	assert(exp2 == res2);

	TokenList impllist = ast.removeChild(impl);
	ast.verify();
	impl.verify();

	string exp3 = " type_t C::foo() {}";
	string res3 = tokenListToString(impllist);
	assert(exp3 == res3);

	string exp4 = "class C { };";
	string res4 = tokenListToString(ast.start, ast.end);
	assert(exp4 == res4);

	clss.insertChildBefore(clss.children.begin(), impl, impllist);

	string exp5 = "class C { type_t C::foo() {} };";
	string res5 = tokenListToString(ast.start, ast.end);
	assert(exp5 == res5);

	ast.verify();
}

unittest
{
	string txt = 
	    "class C {\n"
	    "    type_t foo();\n"
	    "};\n"
	    "__static_if(1) {\n"
	    "type_t C::foo() { return 1; }\n"
	    "} else {\n"
	    "type_t C::foo() { return 2; }\n"
	    "}";
	string exp = 
	    "struct C {\n"
	    "static if(1) {\n"
	    "    type_t foo() { return 1; }\n"
	    "} else {\n"
	    "    type_t foo() { return 2; }\n"
	    "}\n"
	    "};"
//	    "\nstatic if(1) {\n"
//	    "} else {\n"
//	    "}"
	    ;

	string res = testDmdGen(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "class C {\n"
	    "    type_t foo();\n"
	    "};\n"
	    "__static_if(1) {\n"
	    "type_t C::foo() { return 1; }\n"
	    "}\n"
	    "__static_if(2) {\n"
	    "type_t C::foo() { return 2; }\n"
	    "}";
	string exp = 
	    "struct C {\n"
	    "static if(1) {\n"
	    "    type_t foo() { return 1; }\n"
	    "}\n"
	    "static if(2) {\n"
	    "    type_t foo() { return 2; }\n"
	    "}\n"
	    "};"
//	    "\nstatic if(1) {\n"
//	    "}\n"
//	    "static if(2) {\n"
//	    "}"
	    ;

	string res = testDmdGen(txt);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "class C {\n"
	    "    static int x;\n"
	    "    static int *y;\n"
	    "    static int z[NUM];\n"
	    "};\n"
	    "int C::x = 3;\n"
	    "int *C::y;\n"
	    "int C::z[NUM];\n";
	string exp = 
	    "struct C {\n"
	    "    static int x = 3;\n"
	    "    static int *y;\n"
	    "    static int z[NUM];\n"
	    "};\n";

	string res = testDmdGen(txt, 3);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "struct A : B\n"
	    "{\n"
	    "    A() : B(1) { }\n"
	    "    A(int x) : B(x) { }\n"
	    "};\n";
	string exp = 
	    "class A : B\n"
	    "{\n"
	    "    this() { super(1); }\n"
	    "    this(int x) { super(x); }\n"
	    "};\n";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}


unittest
{
	string txt = 
	    "int foo() {\n"
	    "    if(memchr((char *)stringbuffer)) x;\n"
	    "}";
	string exp =
	    "int foo() {\n"
	    "    if(memchr(cast(char *)stringbuffer)) x;\n"
	    "}";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "int a;\n"
	    "\n"
	    "    int x, *y = 0;\n";
	string exp =
	    "int a;\n"
	    "\n"
	    "    int x;\n"
	    "    int *y = 0;\n";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "int a = sizeof(void*);\n"
	    "int b = sizeof(wchar_t);\n";
	string exp =
	    "int a = (void *).sizeof;\n"
	    "int b = wchar_t.sizeof;\n";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "int foo() {\n"
	    "  __asm\n"
	    "  {\n"
	    "     mov eax,ebx  ; hi\n"
	    "; there\n"
	    "     mov ebx,eax  ; hi\n"
	    "  }\n"
	    "}";
	string exp =
	    "int foo() {\n"
	    "  asm\n"
	    "  {\n"
	    "     mov eax,ebx;  //; hi\n"
	    "//; there\n"
	    "     mov ebx,eax;  //; hi\n"
	    "  }\n"
	    "}";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "class A : B { };\n"
	    "int foo() {\n"
	    "  A a(3);\n"
	    "}";
	string exp =
	    "class A : B { };\n"
	    "int foo() {\n"
	    "  A a = new A(3);\n"
	    "}";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "class A : B {\n"
	    "    A();\n"
	    "    static A* bar();\n"
	    "    #define ABC 1\n"
	    "    virtual int foo();\n"
	    "    virtual void baz() = 0;\n"
	    "};\n"
	    "A::A() { }\n"
	    "int abc = ABC;\n"
	    "int A::foo() { return 0; }\n"
	    "A *A::bar() { halt; }\n";
	string exp =
	    "class A : B {\n"
	    "    this() { }\n"
	    "    static A bar() { halt; }\n"
	    "    enum ABC = 1;\n"
	    "    int foo() { return 0; }\n"
	    "    abstract void baz();\n"
	    "};\n"
	    "int abc = A.ABC;\n";

	string res = testDmdGen(txt, 3);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "class A : B {\n"
	    "    A();\n"
	    "};\n"
	    "A::A() : B(1) {\n"
	    "#if 1\n"
	    "    x = 0;\n"
	    "#endif\n"
	    "    y = 1;\n"
	    "}\n";
	string exp =
	    "class A : B {\n"
	    "    this() { super(1);\n"
	    "    static if(1) {\n"
	    //"    // #if 1\n"
	    "        x = 0;\n"
	    //"    // #endif\n"
	    "    }\n"
	    "        y = 1;\n"
	    "    }\n"
	    "};\n";

	string res = testDmdGen(txt, 1);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "int foo() {\n"
	    "#if DMDV1 /* multi\n"
	    "       * line comment */\n"
	    "    if(1)\n"
	    "        x = 0;\n"
	    "    else\n"
	    "#endif\n"
	    "        x = 1;\n"
	    "}\n";
	string exp =
	    "int foo() {\n"
	    "static if(!DMDV1) goto L_F2; /* multi\n"
	    "       * line comment */\n"
	    "    if(1)\n"
	    "        x = 0;\n"
	    "    else\n"
	    "L_F2:\n"
	    "        x = 1;\n"
	    "}\n";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "int foo(int *&x) {\n"
	    "    x = 1;\n"
	    "}\n";
	string exp =
	    "int foo(ref int * x) {\n"
	    "    x = 1;\n"
	    "}\n";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = 
	    "#define X(op) struct op##Exp : Exp {};\n"
	    "X(Add)";
	string exp =
	    "class AddExp : Exp {};";

	TokenList[string] defines = [ "X" : null ];

	string res = testDmdGen(txt, 0, 0, defines);
	assert(res == exp);
}

unittest
{
	string txt = "\n"
	    "struct S2 { int y; } s2;\n"
	    "struct P {\n"
	    "    struct { int x; } s;\n"
	    "    union { int u; };\n"
	    "};\n"
	    "typedef struct { int z; } T, *PS;";
	string exp = "\n"
	    "struct S2 { int y; }\n"
	    "S2 s2;\n"
	    "struct P {\n"
	    "    struct unnamed_4 { int x; }\n"
	    "    unnamed_4 s;\n"
	    "    union { int u; };\n"
	    "};\n"
	    "struct unnamed_7 { int z; }\n"
	    "alias unnamed_7 T;\n"
	    "alias unnamed_7 *PS;";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = "\n"
	    "typedef enum { e1, e2, e3 } ENUM;\n";
	string exp = "\n"
	    "enum unnamed_2 { e1, e2, e3 }\n"
	    "alias unnamed_2 ENUM;\n";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = "class CFile : CF {}; int foo() { CFile f(&g); }\n";
	string exp = "class CFile : CF {}; int foo() { CFile f = new CFile(&g); }\n";

	string res = testDmdGen(txt, 0);
	assert(res == exp);
}

unittest
{
	string txt = "extern \"C\" { bool foo(const real_t *); }\n";
	string exp = "extern (C) { bool foo(const real_t *); }\n";

	string res = testDmdGen(txt, 0, 1);
	assert(res == exp);
}

unittest
{
	string txt = "extern \"C\" bool foo;\n";
	string exp = "extern (C) bool foo;\n";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "#if 1\n"
	    "int x(), y();\n"
	    "#else\n"
	    "int a(), b();\n"
	    "#endif\n";
	string exp = "static if(1) {\n"
	    "int x();\n"
	    "int y();\n"
		"} else {\n"
	    "int a();\n"
	    "int b();\n"
		"}\n";

	string res = testDmdGen(txt, 0, 2); // x(), y() count as one non-implemented function
	assert(res == exp);
}

unittest
{
	string txt = "int foo(void);\n"
		 "int bar(void) { return x; }\n";
	string exp = "int foo();\n"
		 "int bar() { return x; }\n";

	string res = testDmdGen(txt, 0, 1);
	assert(res == exp);
}

unittest
{
	string txt = "int arr[] = { 0, 1, 2, 3 };\n";
	string exp = "int arr[] = [ 0, 1, 2, 3 ];\n";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "data arr[] = {\n"
		" 0, 1,\n"
		" 2, 3,\n"
		"};\n";
	string exp = "data arr[] = [\n"
		" { 0, 1, },\n"
		" { 2, 3, },\n"
		"];\n";
	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "int arr[][2] = {\n"
		" 0, 1,\n"
		" 2, 3,\n"
		"};\n";
	string exp = "int arr[][2] = [\n"
		" [ 0, 1, ],\n"
		" [ 2, 3, ],\n"
		"];\n";
	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "static char txt[] = \"hi\";\n";
	string exp = "static string txt = \"hi\";\n";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "class Type : Obj {\n"
		"    Type* tbit() { return 0; }\n"
		"};";
	string exp = "class Type : Obj {\n"
		"    Type tbit() { return 0; }\n"
		"};";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "enum ENUM { kEnum };\n"
		"int foo() {\n"
		"    Ident id = (op == kEnum) ? 0 : 1;\n"
		"}";
	string exp = "enum ENUM { kEnum };\n"
		"int foo() {\n"
		"    Ident id = (op == ENUM.kEnum) ? 0 : 1;\n"
		"}";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = 
		"int foo() {\n"
		"    search(0, 1);\n"
		"    search(loc, 1);\n"
		"    ad.search(0, 1);\n"
		"    Expression e = new IdentifierExp(0, id);\n"
		"}";
	string exp =
		"int foo() {\n"
		"    search(Loc(0), 1);\n"
		"    search(loc, 1);\n"
		"    ad.search(Loc(0), 1);\n"
		"    Expression e = new IdentifierExp(Loc(0), id);\n"
		"}";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "__mixin(X(b));\n";
	string exp = "mixin(X(\"b\"));\n";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "void foo() { int dim2 = 3; }";
	string exp = "void foo() { int dim2 = cast(int)3; }";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "typedef ArrayBase<struct File> Files;";
	string exp = "alias ArrayBase!(File) Files;";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "template<typename TYPE>struct ArrayBase : Array { };";
	string exp = "class ArrayBase( TYPE) : Array { };";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "struct S { S(int value_) : value(value_), negative(false) {} };";
	string exp = "struct S { this(int value_) { value = (value_); negative = (false);} };";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "struct S { static S foo(const T numbers[2]); }; S S::foo(const T numbers[2]) { }";
	string exp = "struct S {  static S foo(const T numbers[2]) { } };";

	string res = testDmdGen(txt, 1, 0);
	assert(res == exp);
}

unittest
{
	string txt = "typedef ArrayBase<void> Voids;";
	string exp = "alias ArrayBase!(void) Voids;";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "struct Keyword { const char *name; };";
	string exp = "struct Keyword { const(char) *name; };";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	string txt = "class C : B { }; typedef C D; D* c;";
	string exp = "class C : B { }; alias C D; D c;";

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

unittest
{
	// force failure
	string txt = "if(cond) fun(); else gun();";
	string exp = "if(cond) fun(); else gun();";

	string res = testDmdGen(txt, 0, 0);
	assert(res != exp);
}

unittest
{
	string txt = 
	    "#if EXP\n"
	    "int a;\n"
	    "#else\n"
	    "int b;\n"
	    "#endif\n"
	    ;
	string exp =
	    "// #if EXP\n"
	    "int a;\n"
		" \n"
	    "// #endif\n"
		;

	PP.expandConditionals["EXP"] = true;

	string res = testDmdGen(txt, 0, 0, null);
	assert(res == exp);

	exp =
	    "// not #if EXP\n"
	    " \n"
		"int b;\n"
	    "// #endif\n"
		;

	PP.expandConditionals["EXP"] = false;

	res = testDmdGen(txt, 0, 0, null);
	assert(res == exp);

	PP.expandConditionals = PP.expandConditionals.init;
}

unittest
{
	// force failure
	string txt = 
		"#define A 1\n"
		"#define B A\n"
		"#define C() B*B\n"
		"#define SQR(a) (a)*(a)\n"
		;
	string exp = 
		"enum A = 1;\n"
		"alias B A;\n"
		" auto C(  )() { return B*B; }\n"
		" auto SQR(  ARG1 )(ARG1 a) { return a*a; }\n"
		;

	string res = testDmdGen(txt, 0, 0);
	assert(res == exp);
}

version(MAIN)
void main() {}
