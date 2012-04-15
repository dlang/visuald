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
// pp4d - convert IDL or header files to D
//
///////////////////////////////////////////////////////////////////////
//
// what it does:
// - read input files and #included/imported files
// - tokenize input files
// - expand preprocessor conditionals, removing any disabled source code
// - converting #define into
//   - comment if expansion text cannot be parsed as a C++ expression
//   - template if there are parenthesis () 
//   - alias if expansion is a simple identifier
//   - enum 
// - expand definitions that are not converted to template/alias/enum
// - apply user replacements
// - apply standard replacements
// - 

module c2d.pp4d;

import c2d.tokenizer;
import c2d.tokutil;
import c2d.dgutil;
import c2d.ast;
import c2d.patchast;

import std.string;
import std.file;
import std.path;
import std.stdio;
import std.ascii;
import std.algorithm;
import std.getopt;
import std.utf;
import std.conv;
import std.array;
import std.windows.charset;

///////////////////////////////////////////////////////
class Source
{
	string filename;
	string d_file;
	string text;
	TokenList tokens;
	AST ast;
	
	int[] alignment;
}

class Define
{
	string ident;
	string[] args;
	TokenList tokens;
	string file;
	int lineno;
	int invocations;
	int invocationLevel = int.max;
	bool undefined;
	bool isExpr;
	bool hasArgs; // even if 0 args
}

class TokenReplace
{
	string name;
	string[] find;
	string[] replace;
}

// endsWith does not work reliable and crashes on page end
bool _endsWith(string s, string e)
{
	return (s.length >= e.length && s[$-e.length .. $] == e);
}

alias std.string.indexOf indexOf;

///////////////////////////////////////////////////////
class pp4d
{
	///////////////////////////////////////////////////////
	// configuration
	string keywordPrefix = "pp_";
	string[string] inc_path;
	string packageNF = "pp"; // package for includes that were not found
	
	void initFiles()
	{
//		inc_path[r"c:\Program Files\Microsoft SDKs\Windows\v7.1\Include\"] = r"pp\win32\";
		inc_path[r"c:\Programme\Microsoft SDKs\Windows\v6.0A\Include\"] = r"pp\win32\";
	}

	void warning(int lineno, string msg)
	{
		writeln(currentFile ~ "(" ~ to!string(lineno) ~ "): " ~ msg);
	}
	
	///////////////////////////////////////////////////////

	ubyte[] pp_enable_stack; // 0: disabled, waiting for #elif to become true, 1: enabled, 2: disabled, was enabled
	string[] elif_braces_stack;
	
	bool convert_next_cpp_quote = true;
	bool cpp_quote_in_comment = false;

	string[string] tokImports;
	string[] currentImports;
	string[] addedImports;

	TokenReplace[] replacements;
	
	bool verbose;
	bool simple = true;

	Source[] srcs;
	Define[string] defines;
	int defineLevel;
	
	ConvProject project;
	string[] srcfiles;
	string[] excludefiles;

	Source currentSource;

	string currentFile;
	string currentModule;
	string currentFullModule;
	
	//////////////////////////////////////////////////////////////
	// replace sequence of cpp_quote lines with the tokenized version of the contained strings
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
			text ~= cpp_string(strip(it[2].text[1..$-1]));
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

	// replace tokIt with the tokenized version of text
	void reinsertTextTokens(ref TokenIterator tokIt, string text)
	{
		TokenList tokens = scanText(text, tokIt.lineno, false);
		reinsertTextTokens(tokIt, tokens);
	}

	// replace tokIt with the token list
	void reinsertTextTokens(ref TokenIterator tokIt, TokenList tokens)
	{
		string pretext;
		if(!tokIt.atEnd())
		{
			pretext = tokIt.pretext;
			tokIt.erase();
		}
		tokIt = insertTokenList(tokIt, tokens);
		tokIt.pretext = pretext ~ tokIt.pretext;
	}

	//////////////////////////////////////////////////////////////
	void expandDefines(ref TokenIterator tokIt, TokenIterator lastIt, bool nonExprOnly)
	{
		for(TokenIterator it = tokIt; !it.atEnd() && it != lastIt; )
		{
			if(it.type == Token.Identifier)
			{
				bool atStart = tokIt == it;
				if(it.text == "defined")
				{
					string pretext = it.pretext;
					string ident;
					if(it[1].type == Token.ParenL && it[2].type == Token.Identifier && it[3].type == Token.ParenR)
					{
						ident = it[2].text;
						it.erase();
						it.erase();
					}
					else if(it[1].type == Token.Identifier)
						ident = it[1].text;
					else
						throwException("identifier expected after defined, with or without paranthesis");
					
					it.erase();
					it.type = Token.Number;
					it.pretext = pretext;
					it.text = (ident in defines) ? "1" : "0";
					if(atStart)
						tokIt = it;
				}
				else if(Define* def = it.text in defines)
				{
					if(def.invocationLevel >= defineLevel && def.tokens && (!nonExprOnly || !def.isExpr))
					{
						def.invocationLevel = defineLevel;
						scope(exit) def.invocationLevel = int.max;
							
						TokenIterator afterIns = expandDefine(it, def.tokens, &expandArgDefines);
						if(atStart)
							tokIt = it;
						it = afterIns;
						continue;
					}
				}
			}
			it.advance();
		}
	}

	void expandArgDefines(bool arg, TokenList tokens)
	{
		if(!arg)
			defineLevel++;
		scope(exit) if(!arg)
			defineLevel--;

		TokenIterator tokIt = tokens.begin();
		expandDefines(tokIt, tokens.end(), false);
	}
	
	Expression parseExpression(TokenIterator tokIt)
	{
		Expression expr = Expression.parseFullExpression(tokIt);
		checkToken(tokIt, Token.EOF);
		return expr;
	}
	
	bool evalCondition(TokenIterator tokIt, TokenIterator lastIt)
	{
		debug string txt = tokenListToString(tokIt, lastIt, true);
		expandDefines(tokIt, lastIt, false);
		debug string exptxt = tokenListToString(tokIt, lastIt, true);
		
		Expression expr = parseExpression(tokIt);
		long val = expr.evaluate();
		
		return val != 0;
	}

	//////////////////////////////////////////////////////////////
	bool inDisabledPPBranch()
	{
		return pp_enable_stack.length > 0 && pp_enable_stack[$-1] != 1;
	}

	bool convertPP(ref TokenIterator refIt)
	{
		TokenList tokens = scanText(refIt.text, refIt.lineno, false);
		TokenIterator tokIt = tokens.begin();
		TokenIterator lastIt = tokens.end() - 1;
		if(lastIt.type == Token.EOF)
			--lastIt;

		bool wasDisabled = inDisabledPPBranch();
		
		switch(tokIt.type)
		{
		case Token.PPinclude:
			if(inDisabledPPBranch())
				break;
			// tokIt.text = "public import";
			string incfile;
			if(tokIt[1].type == Token.String)
				incfile = tokIt[1].text[1..$-1];
			else if(tokIt[1].text == "<")
			{
				TokenIterator it = tokIt + 2;
				for( ; !it.atEnd() && it.text != ">"; it.erase())
					incfile ~= it.pretext ~ it.text;
			}
			reinsertTextTokens(refIt, "import \"" ~ incfile ~ "\";\n");
			return true;

		case Token.PPif:
			pp_enable_stack ~= inDisabledPPBranch() ? 2 : evalCondition(tokIt + 1, lastIt + 1) ? 1 : 0;
			break;
		case Token.PPifndef:
			if(tokIt[1].type != Token.Identifier)
				throwException("identifier expected after #ifdef");
			pp_enable_stack ~= inDisabledPPBranch() ? 2 : (tokIt[1].text in defines) ? 0 : 1;
			break;
		case Token.PPifdef:
			if(tokIt[1].type != Token.Identifier)
				throwException("identifier expected after #ifdef");
			pp_enable_stack ~= inDisabledPPBranch() ? 2 : (tokIt[1].text in defines) ? 1 : 0;
			break;
			
		case Token.PPendif:
			if(pp_enable_stack.length == 0)
				throwException("unbalanced #endif");
			pp_enable_stack = pp_enable_stack[0 .. $-1];
			break;
			
		case Token.PPelse:
			if(pp_enable_stack.length == 0)
				throwException("unbalanced #else");
			pp_enable_stack[$-1] = (pp_enable_stack[$-1] == 0 ? 1 : 2);
			break;
			
		case Token.PPelif:
			if(pp_enable_stack.length == 0)
				throwException("unbalanced #elif");
			
			if(pp_enable_stack[$-1] == 0)
			{
				if(evalCondition(tokIt + 1, lastIt + 1))
					pp_enable_stack[$-1] = 1;
			}
			else
				pp_enable_stack[$-1] = 2;
			break;
			
		case Token.PPdefine:
			if(!inDisabledPPBranch())
			{
				string text;
				if(convertDefine(tokIt, text))
				{
					reinsertTextTokens(refIt, text);
					return false;
				}
//				else
//					refIt.text = commentPP(refIt.text);
			}
			break;
		case Token.PPundef:
			if(!inDisabledPPBranch())
			{
				if(tokIt[1].type != Token.Identifier)
					throwException("identifier expected after #undef");
				if(Define* def = tokIt[1].text in defines)
					def.undefined = true;
			}
			break;
		default:
			if(tokIt.text == "#pragma")
				handlePragma(tokIt);
			refIt.pretext ~= "// ";
			return false;
		}
		
		//refIt.pretext ~= "// ";
		string pretext = refIt.pretext;
		reinsertTextTokens(refIt, new TokenList); // to keep pretext of tokIt
		if(false && !wasDisabled)
		{
			int pos = lastIndexOf(pretext, '\n');
			if(pos >= 0)
				pretext = pretext[0..pos];
			refIt.pretext = pretext;
		}
		//refIt.erase();
		return true;
	}

	string commentPP(string text)
	{
		int pos = indexOf(text, '\n');
		if(pos < 0 || pos >= text.length - 1)
			return "// " ~ text;
		
		string s;
		bool insertSlashes = true;
		foreach(dchar c; text)
		{
			if(insertSlashes)
				s ~= "// ";
			insertSlashes = (c == '\n');
			s ~= c;
		}
		return s;
	}
	
	bool wantsCheckExpression(TokenIterator it, TokenIterator endIt)
	{
		if(it.atEnd() || it == endIt)
			return false;
		if(endIt == it + 1 && Tokenizer.identifierToKeyword(it.text) != Token.Identifier)
			return false;
		return true;
	}
	
	bool convertDefine(ref TokenIterator tokIt, ref string repltext)
	{
		TokenIterator it = tokIt + 1;
		if(it.type != Token.Identifier)
			throwException("identifier expected after #define");
		
		TokenIterator endIt = tokIt._list.end();
		if(endIt[-1].type == Token.EOF)
			--endIt;
		
		Define def = new Define;
		def.ident = it.text;
		def.file = currentFile;
		def.lineno = tokIt.lineno;
		def.hasArgs = false;
		++it;
		if(it.text == "(" && it.pretext.length == 0)
		{
			def.hasArgs = true;
			++it;
			if(it.text != ")")
			{
				for( ; ; )
				{
					if(it.type != Token.Identifier)
						throwException("identifier expected as argument to #define " ~ def.ident);
					def.args ~= it.text;
					++it;
					if(it.text == ")")
						break;
					if(it.text != ",")
						throwException("',' of ')' expected in argument list to #define " ~ def.ident);
					++it;
				}
			}
			++it;
		}

		if(Define* pdef = def.ident in defines)
		{
			if(!pdef.undefined)
			{
				if(pdef.args != def.args)
					warning(tokIt.lineno, "different arguments in redefinition of " ~ def.ident 
					                    ~ " at " ~ pdef.file ~ "(" ~ to!string(pdef.lineno) ~ ")");
				else if(!compareTokenList (tokIt, endIt, pdef.tokens.begin(), pdef.tokens.end()))
					warning(tokIt.lineno, "different expansion in redefinition of " ~ def.ident
					               ~ " at " ~ pdef.file ~ "(" ~ to!string(pdef.lineno) ~ ")");
				return false;
			}
		}
		def.tokens = copyTokenList(tokIt, endIt);
		def.isExpr = false;
		if(wantsCheckExpression(it, endIt))
		{
			try
			{
				TokenList list = copyTokenList(it, endIt);
				list.append(createToken("", "", Token.EOF, tokIt.lineno));
				TokenIterator exprIt = list.begin();
				expandDefines(exprIt, list.end(), true);
				if(!exprIt.atEnd() && exprIt.type != Token.EOF)
				{
					parseExpression(exprIt); // throws if fails to parse
					def.isExpr = true;

					if(def.hasArgs)
					{
						repltext = "auto " ~ def.ident ~ "(";
						foreach(i, a; def.args)
							repltext ~= (i == 0 ? "t_" : ", t_") ~ a;
						repltext ~= ")(";
						foreach(i, a; def.args)
							repltext ~= (i == 0 ? "t_" : ", t_") ~ a ~ " " ~ a;
						repltext ~= ") { return ";
						repltext ~= tokenListToString(list);
						repltext ~= "; }\n";
						repltext = replace(repltext, "\\\n", "\n");
					}
					else if(exprIt.type == Token.Identifier && ((exprIt + 1).atEnd() || exprIt[1].type == Token.EOF))
					{
						repltext = "typedef " ~ exprIt.text ~ " " ~ def.ident ~ ";\n";
					}
					else
					{
						repltext = "enum " ~ def.ident ~ " = " ~ tokenListToString(list) ~ ";\n";
					}
				}
			}
			catch(Exception)
			{
			}
		}
		
		defines[def.ident] = def;
		
		return def.isExpr;
	}

	bool handlePragma(TokenIterator tokIt)
	{
		if(tokIt[1].text != "regex" || tokIt[2].type != Token.ParenL)
			return false;
		tokIt += 3;
		
		string name;
		if(tokIt.type == Token.Identifier && tokIt[1].text == ":")
		{
			name = tokIt.text;
			tokIt += 2;
			if(tokIt.text == "delete")
			{
				if(tokIt[1].type != Token.ParenR)
					throwException("no closing ')' in #pragma regex");
				
				for(int i = 0; i < replacements.length; )
					if(name == replacements[i].name)
						replacements = replacements[0..i] ~ replacements[i+1..$];
					else
						i++;
				return true;
			}
		}
		if(tokIt.type != Token.String)
			throwException("search string expected in #pragma regex");
		
		string find = cpp_string(tokIt.text[1..$-1]);
		string replace;
		if(tokIt[1].type == Token.Comma && tokIt[2].type == Token.String)
		{
			tokIt += 2;
			replace = cpp_string(tokIt.text[1..$-1]);
		}
		if(tokIt[1].type != Token.ParenR)
			throwException("no closing ')' in #pragma regex");
		
		TokenReplace repl = new TokenReplace;
		repl.name = name;
		scanTextArray!(string)(repl.find, find);
		scanTextArray!(string)(repl.replace, replace);
		replacements ~= repl;
		
		return true;
	}
	
	//////////////////////////////////////////////////////////////
	string translateModuleName(string name)
	{
		name = toLower(name);
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

		string dir = dirName(fname);
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

		string file = searchFile(text);
		string mod = genDFilename(file);
		if(endsWith(mod, ".d"))
			mod = mod[0..$-2];
		return replace(mod, "\\", ".");
	}

	string fixImport(string text)
	{
		string imp = _fixImport(text);
		currentImports.addunique(imp);
		return imp;
	}

	//////////////////////////////////////////////////////////////
	bool preprocessToken(ref TokenIterator tokIt)
	{
		Token tok = *tokIt;
		switch(tok.text)
		{
		// idl support
		case "importlib":
			if(tokIt[1].text == "(" && tokIt[2].type == Token.String && tokIt[3].text == ")")
			{
				/+
				tokIt.text = "import";
				tokIt[1].text = "";
				tokIt[2].pretext = " ";
				tokIt[2].text = fixImport(tokIt[2].text);
				tokIt[3].text = "";
				+/
			}
			break;
		case "import":
			if(tokIt[1].type == Token.String)
			{
				string incfile = tokIt[1].text[1..$-1];
				searchAndProcessFile(incfile);

				tokIt.pretext ~= "public ";
				tokIt[1].text = fixImport(tokIt[1].text);
			}
			break;

		case "midl_pragma":
			comment_line(tokIt);
			return true;

		case "cpp_quote":
			reinsert_cpp_quote(tokIt);
			return true;

		default:
			if(tokIt.type == Token.Identifier)
				if(Define* def = tokIt.text in defines)
				{
					if(def.invocationLevel >= defineLevel && def.tokens && !def.isExpr)
					{
						def.invocationLevel = defineLevel;
						scope(exit) {
							def.invocationLevel = int.max;
						}
							
						tokIt = expandDefine(tokIt, def.tokens, &expandArgDefines);
						return true;
					}
				}
			break;
		}
		return false;
	}

	void preprocessText(TokenList tokens)
	{
		for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; )
		{
			Token tok = *tokIt;
			try
			{
				if(tok.text.startsWith("#"))
				{
					if(convertPP(tokIt))
						continue;
				}
				else if(!inDisabledPPBranch())
				{
					if(preprocessToken(tokIt))
						continue;
				}
			}
			catch(Exception e)
			{
				writeln(currentFile ~ "(" ~ to!string(tok.lineno) ~ "): " ~ e.toString());
			}
			if (inDisabledPPBranch())
				tokIt.erase();
			else
				++tokIt;
		}
	}
	
	//////////////////////////////////////////////////////////////
	bool convertToken(ref TokenIterator tokIt)
	{
		Token tok = *tokIt;
		switch(tok.text)
		{
		case "unsigned":
		case "signed":
		{
			string t;
			bool skipNext = true;
			switch(tokIt[1].text)
			{
			case "__int64":   t = "ulong"; break;
			case "long":      t = "uint"; break;
			case "int":       t = "uint"; break;
			case "__int32":   t = "uint"; break;
			case "__int3264": t = "uint"; break;
			case "short":     t = "ushort"; break;
			case "char":      t = "ubyte"; break;
			default:
				t = "uint"; 
				skipNext = false;
				break;
			}
			if(tok.text == "signed")
				t = t[1..$];
			tokIt.text = t;
			if(skipNext)
				(tokIt + 1).erase();
			break;
		}
			
		default:
			if(tok.type == Token.Number && (tok.text._endsWith("l") || tok.text._endsWith("L")))
				tok.text = tok.text[0..$-1];
			else if(tok.type == Token.Number && tok.text._endsWith("i64"))
				tok.text = tok.text[0..$-3] ~ "L";
			else if(tok.type == Token.String && tok.text.startsWith("L\""))
				tok.text = tok.text[1..$] ~ "w.ptr";
			else if(tok.type == Token.String && tok.text.startsWith("L\'"))
				tok.text = tok.text[1..$];
			
			break;
		}
		return false;
	}

	void convertText(TokenList tokens)
	{
		for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; )
		{
			Token tok = *tokIt;

			try
			{
				if(convertToken(tokIt))
					continue;
			}
			catch(Exception e)
			{
				writeln(currentFile ~ "(" ~ to!string(tok.lineno) ~ "): " ~ e.toString());
			}
			++tokIt;
		}

		for(int i = 0; i < replacements.length; i++)
			replaceTokenSequence(tokens, replacements[i].find, replacements[i].replace, true);
		
		replaceCastExpressions(tokens);
		removeForwardDeclarations(tokens);
		moveInterfaceSubTypes(tokens);
		convertEnumDeclarations(tokens);
		convertStructDeclarations(tokens);
		convertUnionDeclarations(tokens);
		convertTypedefDeclarations(tokens);
		convertAsmStatements(tokens);
		convertSizeof(tokens);
		convertBitfields(tokens);
		convertExternDeclarations(tokens);
		
		for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; )
		{
			Token tok = *tokIt;
			tok.text = translateToken(tok.text);
			tokIt.advance();
		}
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
		case "volatile":  return "/*volatile*/";

		case "__int64":   return "long";
		case "__int32":   return "int";
		case "long":      return "int";
		case "typedef":   return "alias";
		//case "bool":      return "idl_bool";
		case "GUID_NULL": return "const_GUID_NULL";
		case "NULL":      return "null";

		case "wchar_t":   return "wchar";
		case "->":        return ".";

		// vslangproj.d
//		case "prjBuildActionCustom": return "prjBuildActionEmbeddedResource";

		default:
			if(string* ps = text in tokImports)
				text = *ps ~ "." ~ text;
			break;
		}
		return text;
	}

	void replaceCastExpressions(TokenList tokens)
	{
		version(all)
		{
			for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; )
			{
				Token tok = *tokIt;
				if(tok.type == Token.ParenL && 
					(tokIt.atBegin() || tokIt[-1].type != Token.Identifier || tokIt[-1].text == "return"))
				{
					TokenIterator it = tokIt;
					if(advanceToClosingBracket(it) && !it.atEnd())
					{
						bool isCast = false;
						isCast = isCast || (it.type == Token.Identifier);
						isCast = isCast || (it.type == Token.Number);
						isCast = isCast || (it.type == Token.Tilde);
						isCast = isCast || (it.type == Token.ParenL);
						isCast = isCast || (it.type != Token.Semicolon && it[-2].type == Token.Asterisk);
						isCast = isCast || (it.type == Token.Minus && it[-2].type == Token.Identifier && it == tokIt + 3);
						if(isCast && it.type == Token.BraceL)
							isCast = false;
						if(isCast)
						{
							Token castTok = createToken(tok.pretext, "cast", Token.Identifier, tokIt.lineno);
							tok.pretext = "";
							tokIt.insertBefore(castTok);
							tokIt = it;
							continue;
						}
					}
				}
				else if(tok.text == "reinterpret_cast" || tok.text == "static_cast" || tok.text == "const_cast")
				{
					if(tokIt[1].text == "<")
					{
						TokenIterator it = tokIt + 2;
						while(!it.atEnd() && it.text != ">") // TODO: template types not supported
							it.advance();
						if(!it.atEnd())
						{
							tok.text = "cast";
							tokIt[1].text = "(";
							tokIt[1].type = Token.ParenL;
							it.text = ")";
							it.type = Token.ParenR;
							tokIt = it;
						}
					}
				}
				tokIt.advance();
			}
		}
		else
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
		replaceTokenSequence(tokens, "$_ident cast", "$_ident", true);
		replaceTokenSequence(tokens, "!cast", "!", true);
		replaceTokenSequence(tokens, "reinterpret_cast<$_ident>", "cast($_ident)", true);
		replaceTokenSequence(tokens, "reinterpret_cast<$_ident*>", "cast($_ident*)", true);
		replaceTokenSequence(tokens, "const_cast<$_ident*>", "cast($_ident*)", true);
		}
	}

	void removeForwardDeclarations(TokenList tokens)
	{
		replaceTokenSequence(tokens, "enum $_ident;", "/+ enum $_ident; +/", true);
		replaceTokenSequence(tokens, "struct $_ident;", "/+ struct $_ident; +/", true);
		replaceTokenSequence(tokens, "class $_ident;", "/+ class $_ident; +/", true);
		replaceTokenSequence(tokens, "interface $_ident;", "/+ interface $_ident; +/", true);
		replaceTokenSequence(tokens, "dispinterface $_ident;", "/+ dispinterface $_ident; +/", true);
		replaceTokenSequence(tokens, "coclass $_ident;", "/+ coclass $_ident; +/", true);
		replaceTokenSequence(tokens, "library $_ident {", "version(all)\n{ /+ library $_ident +/", true);
		replaceTokenSequence(tokens, "importlib($expr);", "/+importlib($expr);+/", true);
	}

	void moveInterfaceSubTypes(TokenList tokens)
	{
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

		// convert UUID
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
	}
	
	void convertEnumDeclarations(TokenList tokens)
	{
		replaceTokenSequence(tokens, "typedef enum $_ident1 { $enums } $_ident1;", 
			"enum /+$_ident1+/\n{\n$enums\n}\ntypedef int $_ident1;", true);
		replaceTokenSequence(tokens, "typedef enum $_ident1 { $enums } $ident2;", 
			"enum /+$_ident1+/\n{\n$enums\n}\ntypedef int $_ident1;\ntypedef int $ident2;", true);
		replaceTokenSequence(tokens, "typedef enum { $enums } $ident2;", 
			"enum\n{\n$enums\n}\ntypedef int $ident2;", true);
		replaceTokenSequence(tokens, "typedef [$info] enum $_ident1 { $enums } $_ident1;", 
			"enum [$info] /+$_ident1+/\n{\n$enums\n}\ntypedef int $_ident1;", true);
		replaceTokenSequence(tokens, "typedef [$info] enum $_ident1 { $enums } $ident2;", 
			"enum [$info] /+$_ident1+/\n{\n$enums\n}\ntypedef int $_ident1;\ntypedef int $ident2;", true);
		replaceTokenSequence(tokens, "typedef [$info] enum { $enums } $ident2;", 
			"enum [$info]\n{\n$enums\n}\ntypedef int $ident2;", true);
		replaceTokenSequence(tokens, "enum $_ident1 { $enums }; typedef $_identbase $_ident2;", 
			"enum /+$_ident1+/ : $_identbase \n{\n$enums\n}\ntypedef $_identbase $_ident1;\ntypedef $_identbase $_ident2;", true);
		replaceTokenSequence(tokens, "enum $_ident1 { $enums }; typedef [$info] $_identbase $_ident2;", 
			"enum /+$_ident1+/ : $_identbase \n{\n$enums\n}\ntypedef [$info] $_identbase $_ident2;", true);
		replaceTokenSequence(tokens, "enum $_ident1 { $enums };", 
			"enum /+$_ident1+/ : int \n{\n$enums\n}\ntypedef int $_ident1;", true);
		replaceTokenSequence(tokens, "typedef enum $_ident1 $_ident1;", "/+ typedef enum $_ident1 $_ident1; +/", true);
		replaceTokenSequence(tokens, "enum $_ident1 $_ident2", "$_ident1 $_ident2", true);
	}
	
	void convertStructDeclarations(TokenList tokens)
	{
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

		replaceTokenSequence(tokens, "typedef struct $_ident1 $expr;", "typedef $_ident1 $expr;", true);
		replaceTokenSequence(tokens, "typedef [$props] struct $_ident1 $expr;", "typedef [$props] $_ident1 $expr;", true);
		replaceTokenSequence(tokens, "struct $_ident1 *", "$_ident1 *", true);
		//replaceTokenSequence(tokens, "struct $_ident1 $_ident2", "$_ident1 $_ident2", true);
	}

	void convertUnionDeclarations(TokenList tokens)
	{
		replaceTokenSequence(tokens, "typedef union $_ident1 { $data } $_ident2 $expr;", 
			"union $_ident1\n{\n$data\n}\ntypedef $_ident1 $_ident2 $expr;", true);
		replaceTokenSequence(tokens, "typedef union $_ident1 switch($expr) $_ident2 { $data } $_ident3;",
			"union $_ident3 /+switch($expr) $_ident2 +/ { $data };", true);
		replaceTokenSequence(tokens, "typedef union switch($expr) { $data } $_ident3;",
			"union $_ident3 /+switch($expr) +/ { $data };", true);
		replaceTokenSequence(tokens, "union $_ident1 switch($expr) $_ident2 { $data };",
			"union $_ident1 /+switch($expr) $_ident2 +/ { $data };", true);
		replaceTokenSequence(tokens, "union $_ident1 switch($expr) $_ident2 { $data }",
			"union $_ident1 /+switch($expr) $_ident2 +/ { $data }", true);
		replaceTokenSequence(tokens, "case $_ident1:", "[case $_ident1:]", true);
		replaceTokenSequence(tokens, "default:", "[default:]", true);
		replaceTokenSequence(tokens, "union { $data } $_ident2 $expr;", 
			"union _ __ $_ident2 {\n$data\n} _ __ $_ident2 $_ident2 $expr;", true);
	}

	void convertTypedefDeclarations(TokenList tokens)
	{
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
	}

	void convertAsmStatements(TokenList tokens)
	{
		replaceTokenSequence(tokens, "__asm{$args}", "assert(false, \"asm not translated\"); asm{naked; nop; /+$args+/}", true);
		replaceTokenSequence(tokens, "__asm $_not{$stmt}", "assert(false, \"asm not translated\"); asm{naked; nop; /+$_not$stmt+/} }", true);
	}

	void convertSizeof(TokenList tokens)
	{
		replaceTokenSequence(tokens, "sizeof($_ident)", "$_ident.sizeof", true);
		replaceTokenSequence(tokens, "sizeof($args)", "($args).sizeof", true);
	}
	
	void convertBitfields(TokenList tokens)
	{
		// bitfields:
		replaceTokenSequence(tokens, "$_identtype $_identname : $_num;",   "__bf $_identtype, __quote $_identname __quote, $_num __eobf", true);
		replaceTokenSequence(tokens, "$_identtype $_identname : $_ident;", "__bf $_identtype, __quote $_identname __quote, $_ident __eobf", true);
		replaceTokenSequence(tokens, "$_identtype : $_num;", "__bf $_identtype, __quote __quote, $_num __eobf", true);
		replaceTokenSequence(tokens, "__eobf __bf", ",\n\t", true);
		replaceTokenSequence(tokens, "__bf", "mixin(bitfields!(", true);
		replaceTokenSequence(tokens, "__eobf", "));", true);
	}
	
	void convertExternDeclarations(TokenList tokens)
	{
		replaceTokenSequence(tokens, "extern \"C\"", "extern(C)", true);
		replaceTokenSequence(tokens, "extern \"C++\"", "extern(C++)", true);
	}

	//////////////////////////////////////////////////////////////
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
		int len = 0;
		foreach(inc, pkg; inc_path)
			if(file.startsWith(inc))
				len = inc.length;

		file = file[len .. $];
		if (_endsWith(file,".d"))
			file = file[0 .. $-2];
		file = replace(file, "/", ".");
		file = replace(file, "\\", ".");
		return file;
	}

	/+
	string makehdr(string file, string d_file)
	{
		string pkg  = d_file.startsWith(win_d_path) ? packageWin : packageVSI;
		string name = fileToModule(d_file);
		string hdr;
		hdr ~= "// File generated by pp4d from\n";
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

		if(currentModule == "vsshell")
			hdr ~= "import " ~ packageWin ~ "commctrl;\n";
		if(currentModule == "vsshlids")
			hdr ~= "import " ~ packageVSI ~ "oleipc;\n";
		else if(currentModule == "debugger80")
			hdr ~= "import " ~ packageWin ~ "oaidl;\n"
				~  "import " ~ packageVSI ~ "dte80a;\n";
		else if(currentModule == "xmldomdid")
			hdr ~= "import " ~ packageWin ~ "idispids;\n";
		else if(currentModule == "xmldso")
			hdr ~= "import " ~ packageWin ~ "xmldom;\n";
		else if(currentModule == "commctrl")
			hdr ~= "import " ~ packageWin ~ "objidl;\n";
		else if(currentModule == "shellapi")
			hdr ~= "import " ~ packageWin ~ "iphlpapi;\n";
		else if(currentModule == "ifmib")
			hdr ~= "import " ~ packageWin ~ "iprtrmib;\n";
		else if(currentModule == "ipmib")
			hdr ~= "import " ~ packageWin ~ "iprtrmib;\n";
		else if(currentModule == "tcpmib")
			hdr ~= "import " ~ packageWin ~ "iprtrmib;\n";
		else if(currentModule == "udpmib")
			hdr ~= "import " ~ packageWin ~ "iprtrmib;\n";
		
		hdr ~= "\n";

		return hdr;
	}
+/
	
	void setCurrentSource(Source src)
	{
		currentSource = src;
		if(!src)
			return;
		
		currentFile = src.filename;
		
		currentFullModule = fixImport(currentFile);
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

	string genDFilename(string filename)
	{
		string d_file = packageNF ~ "\\" ~ filename;
		foreach(inc, pkg; inc_path)
			if(filename.startsWith(inc))
			{
				d_file = pkg ~ filename[inc.length..$];
				break;
			}
		
		d_file = toLower(d_file);
		if(d_file._endsWith(".idl") || d_file._endsWith(".idh"))
			d_file = d_file[0 .. $-3] ~ "d";
		if(d_file.endsWith(".h"))
			d_file = d_file[0 .. $-1] ~ "d";
		d_file = translateFilename(d_file);
		return d_file;
	}
	

	string mapTokenList(TokenList tokenList)
	{
		int pass = 0;
		string text;
		for(TokenIterator tokIt = tokenList.begin(); !tokIt.atEnd(); ++tokIt)
		{
			Token tok = *tokIt;
			string mapped = pass > 0 ? tok.text : mapTokenText(tok);
			text ~= tok.pretext ~ mapped;
		}
		return text;
	}

	void processFile(string file)
	{
		foreach(Source s; srcs)
			if(s.filename == file)
				return;
		
		writeln("processing " ~ file ~ "...");
		
		Source src = new Source;
		src.filename = file;
		src.text = fromMBSz (cast(immutable(char)*)(cast(char[]) read(file) ~ "\0").ptr);
		src.tokens = scanText(src.text, 1, true);
		src.d_file = genDFilename(src.filename);
		srcs ~= src;

		Source prevSource = currentSource;
		setCurrentSource(src);

		preprocessText(src.tokens);
		identifierToKeywords(src.tokens);

//		convertText(src.tokens);
		
		setCurrentSource(prevSource);
	}

	void parseSource(Source src)
	{
		Source prevSource = currentSource;
		setCurrentSource(src);
		
		int cntExceptions = SyntaxException.count;
		try
		{
			src.ast = new AST(AST.Type.Module);
			TokenIterator tokIt = src.tokens.begin();
			src.ast.parseModule(tokIt);
			src.ast.verify();
		}
		catch
		{
		}
		cntExceptions = SyntaxException.count - cntExceptions;
		if(cntExceptions > 0)
			writeln(src.filename ~ ": " ~ to!string(cntExceptions) ~ " syntax errors");
	
		setCurrentSource(prevSource);
	}
	
	string processText(string text)
	{
		Source src = new Source;
		src.filename = "text";
		src.text = text;
		src.tokens = scanText(src.text, 1, true);
		src.d_file = "test.d";

		setCurrentSource(src);
		preprocessText(src.tokens);
		convertText(src.tokens);
		string ntext = tokenListToString(src.tokens, true);
		ntext = removeDuplicateEmptyLines(ntext);

		setCurrentSource(null);
		return ntext;
	}
	
	string searchFile(string file)
	{
		if(!std.file.exists(file))
		{
			foreach(inc, pkg; inc_path)
				if(std.file.exists(inc ~ file))
				{
					file = inc ~ file;
					break;
				}
		}
		return file;
	}

	void writeFile(Source src)
	{
version(none)
		string text = tokenListToString(src.tokens, true);
else
		string text = mapTokenList(src.tokens);
		
		text = removeDuplicateEmptyLines(text);
		
		string hdr = ""; // makehdr(src.filename, d_file);
		std.file.write(src.d_file, toUTF8(hdr ~ text));
	}
	
	bool searchAndProcessFile(string file)
	{
		file = searchFile(file);
		if(!std.file.exists(file))
			return false;
		
		processFile(file);
		return true;
	}
	
	int main(string[] argv)
	{
		getopt(argv, 
			"inc", &inc_path,
			"prefix", &keywordPrefix,
			"verbose", &verbose);

		initFiles();
		Tokenizer.ppOnly = true;
		
		try
		{
			string[] inputFiles = argv[1..$];
			foreach(string file; inputFiles)
				processFile(file);

			foreach(Source src; srcs)
				writeFile(src);

			foreach(Source src; srcs)
				parseSource(src);

			project = new ConvProject;
			foreach(Source src; srcs)
				project.registerAST(src.ast);
			
			project.processAll();
			
			foreach(Source src; srcs)
				writeFile(src);
		}
		catch(Throwable e)
		{
			writeln("fatal error: " ~ currentFile ~ " " ~ e.msg);
			e = e;
			throw e;
		}
		
		return 0;
	}
}

int main(string[] argv)
{
	pp4d inst = new pp4d;
	return inst.main(argv);
}

///////////////////////////////////////////////////////////////
void testProcess(string txt, string exp)
{
	pp4d inst = new pp4d;
	string res = inst.processText(txt);
	res = replace(res, "\n", "\r\n"); // for better disaply in debugger
	exp = replace(exp, "\n", "\r\n");
	assume(res == exp);
}

unittest
{
	string txt = 
		"#define X(a) a X\n" ~
		"X(2)\n";
	string exp = 
		"2 X\n";

	testProcess(txt, exp);
}

unittest
{
	string txt = 
		"#define RASCONNW struct tagRASCONNW\n" ~
		"RASCONNW\n" ~
		"{ };\n";
	string exp = 
		"struct tagRASCONNW\n" ~
		"{ };\n";

	testProcess(txt, exp);
}

unittest
{
	string txt = 
		"#define __forceinline\n" ~
		"#define FORCEINLINE __forceinline\n" ~
		"foo;\n" ~
		"#if 1\n" ~
		"FORCEINLINE bar;\n" ~
		"#endif\n";
	string exp = 
		"foo;\n" ~
		" bar;\n";
	
	testProcess(txt, exp);
}
