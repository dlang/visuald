module j2d;

import tokenizer;
import tokutil;

import std.string;
import std.file;
import std.path;
import std.stdio;
import std.ctype;
import std.algorithm;
import std.getopt;

string final_replacement = "const"; // "invariant" for D2?

// TODO
// - fix invalid utf8 chars
// + adjust import statements (parser.*)
// + foreach with complex type
// + do not add cast for "if(a) b;"
// + comment out list of exceptions after "throws"
// - use '~' for string concatenation
// - convert List<?:Type>
// + import static
// + complex cast/instanceof expressions
// + var.class -> typeid with complex var
// + {} declaration blocks -> static this() {}
// - outer in inline defined class
class j2d
{
	string[string] tokImports;

	void fixImport(TokenIterator tokIt)
	{
		// tokIt on import
		TokenIterator it = tokIt;
		it.advance();
		if(it.text == "static")
		{
			it.erase(); //text = ""; it.advance;
		}
		string imp;
		while(!it.atEnd() && it.text != ";")
		{
			if(it.text == "*")
			{
				//it[-1].text = "";
				if(imp.endsWith("/TOK")) // imp.startsWith("/descent") && 
				{
					it[-1].text = "";
					it[-1].pretext = "";
					it.pretext = "";
					it.text = "pkg"; // concat to TOKpkg
				}
				else
					it.text = "pkg";
				return;
			}
			if(it.text.length && it.text != ".")
				imp ~= "/" ~ translateToken(it.text);
			it.advance();
		}

		//if(imp.endsWith("/Map/Entry"))
		//	tokIt.pretext ~= "//";
		//else 
		if(!isSourceFile(imp))
		{
			tokImports[it[-1].text] = it[-3].text;
			it[-2].pretext ~= "/*";
			it.pretext = "*/" ~ it.pretext;
		}
		tokIt.pretext ~= "private ";
	}

	void fixDescentClass(TokenIterator tokIt)
	{
		string ident = tokIt.text; // sits on "descent"
		tokIt.advance();
		while(!tokIt.atEnd() && tokIt.text == ".")
		{
			tokIt.advance();
			if(tokIt.type != Token.Identifier)
				return;
			ident ~= "/" ~ tokIt.text;
			tokIt.advance();
		}

		string javafile = java_path ~ ident ~ ".java";
		if (std.file.exists(javafile))
		{
			tokIt.insertBefore(createToken("", ".", Token.Dot, tokIt.lineno));
			tokIt.insertBefore(createToken(tokIt[-2]));
		}
	}

	void fixInstanceOf(TokenIterator tokIt)
	{
		bool isTerminatingInstanceofType(int type)
		{
			return type == Token.EOF || type == Token.Semicolon ||
			       type == Token.AmpAmpersand || type == Token.OrOr ||
			       type == Token.Assign || type == Token.Question ||
			       type == Token.Colon;
		}
		// tokIt on instanceof
		TokenIterator before = tokIt;
		int beforetype = before.atBegin() ? Token.EOF : before[-1].type;
		while(beforetype != Token.EOF && beforetype != Token.Return && !isTerminatingInstanceofType(beforetype) &&
		      !isOpeningBracket(beforetype))
		{
			before.retreat();
			if(isClosingBracket(before.type))
				retreatToOpeningBracket(before);
			beforetype = before.atBegin() ? Token.EOF : before[-1].type;
		}
		
		TokenIterator after = tokIt + 1;
		while(!after.atEnd() && !isTerminatingInstanceofType(after.type) && !isClosingBracket(after.type))
		{
			if(isOpeningBracket(after.type))
				advanceToClosingBracket(after);
			else
				after.advance();
		}
		
		// do not invalidate tokIt!
		TokenList beforelist = before.eraseUntil(tokIt);
		tokIt.text = "__cast";
		tokIt.insertAfter(createToken("", "(", Token.ParenL, tokIt.lineno));
		
		after.insertBefore(createToken("", ")", Token.ParenR, tokIt.lineno));
		after.insertListBefore(beforelist);
	}

	void fixCast(TokenIterator tokIt)
	{
		// tokIt on ")"
		if(tokIt[1].type != Token.Identifier && tokIt[1].type != Token.Number && tokIt[1].type != Token.ParenL)
			return;
		if(tokIt[1].text == "throws" || tokIt[1].text == "/* throws" || tokIt[1].text == "const")
			return;
		
		if(!retreatToOpeningBracket(tokIt))
			return;

		tokIt.retreat();
		if(tokIt.text == "if" || tokIt.text == "while" || tokIt.text == "for" || tokIt.text == "new" || tokIt.text == "class" || 
		   tokIt.text == "__cast")
			return;

		tokIt.insertAfter(createToken(" ", "__cast", Token.Identifier, tokIt.lineno));
	}

	void fixEmptyStatement(TokenIterator tokIt)
	{
		// tokIt on ";"
		TokenIterator it = tokIt;
		tokIt.advance();
		if(tokIt.atEnd())
			return;
		if(tokIt.text != "else")
			return;
		tokIt.retreat();
		tokIt.retreat();
		if(tokIt.text != ")")
			return;
		
		if(!retreatToOpeningBracket(tokIt))
			return;
		if(tokIt[-1].text != "if")
			return;

		it.text = "{}";
	}

	bool isExtends(string text)
	{
		return text == "extends" || text == "implements" || text == ":";
	}

	enum ClassType
	{
		kNone,
		kClass,
		kInterface,
		kClassEnum,
	}

	void fixBadIdentifers(TokenList tokens)
	{
		for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; ++tokIt)
		{
			Token tok = *tokIt;
			if(tok.text.length > 20 && tok.text[0..20] == "VoidDoesNotHaveADefa")
			{
				tok.text = "VoidDoesNotHaveADefaultInitializer";
				assert(tokIt[1].text.length && tokIt[1].text[0] == 0xf1);
				assert(tokIt[2].text == "tInitializer");
				(tokIt + 1).erase();
				(tokIt + 1).erase();
			}
		}
	}

	void fixIdenticalMethodsAndFields(TokenList tokens, int[string] methods, int[string] fields)
	{
		// translate "ident" to "_ident" if ident is also a method
		for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; ++tokIt)
		{
			if(tokIt.type == Token.Identifier)
				if ((tokIt.text in methods) && (tokIt.text in fields))
					if(tokIt[1].type != Token.ParenL)
						tokIt.text = "_" ~ tokIt.text;
		}
	}

	string convertText(string text)
	{
		TokenList tokens = scanText(text);

		tokImports = tokImports.init;

		string currentClass;
		string[] classStack;
		int[] classBraceLevel;
		ClassType[] classTypes;

		string prevtext;

		int braceCount;
		int parenCount;
		int brackCount;
		string convertEnum;
		bool inthrows;
		bool inArrayInit;
		ClassType beginClass = ClassType.kNone;

		string[string] vartypes;
		int[string] methods;
		int[string] fields;

		bool static_decl = 0; // true: static read since last ';'
		TokenIterator static_decl_asgn; // iterator of assignment operator '='
		int close_static_decl = -1;

		string protection;
		string[string] subclasses;

		void pushclass(string clss)
		{
			if(protection == "public" && classStack.length && braceCount == 1 && close_static_decl < 0)
			{
				string s = currentClass;
				foreach_reverse(c; classStack[1..$])
					s = translateToken(c) ~ '.' ~ s;
				subclasses[translateToken(clss)] = s;
			}
			classStack ~= currentClass;
			classBraceLevel ~= braceCount;
			classTypes ~= beginClass;
			currentClass = clss;
		}
		void popclass()
		{
			currentClass = classStack[$-1];
			classStack = classStack[0 .. $-1];
			classBraceLevel = classBraceLevel[0 .. $-1];
			classTypes = classTypes[0 .. $-1];
		}
		void checkpopclass()
		{
			while(classBraceLevel.length > 0 && classBraceLevel[$-1] >= braceCount)
			    popclass();
		}
		void checkStaticDecl()
		{
			if(static_decl && static_decl_asgn.valid() && (classTypes.length == 0 || classTypes[$-1] != ClassType.kInterface))
			{
				// remove const/final from declaration
				for(TokenIterator it = static_decl_asgn; !it.atBegin() && indexOf(";{}", it.text) < 0; it.retreat())
					if(it.text == "final" || it.text == final_replacement)
						it.text = "/*final*/";
				// replace direct assignment with assignment in static this()
				static_decl_asgn.pretext = "; static this() { " ~ static_decl_asgn[-1].text ~ static_decl_asgn.pretext;
				static_decl = false;
				close_static_decl = braceCount;
			}
		}
		void storeType(TokenIterator tokIt, TokenIterator brackIt)
		{
			string s;
			while(tokIt != brackIt)
			{
				s ~= tokIt.text;
				tokIt.advance();
			}
			vartypes[brackIt.text] = s;
		}
		bool isArrayType(TokenIterator it)
		{
			if(it.type == Token.String)
				return true;
			if(string *ps = it.text in vartypes)
				return *ps == "String" || *ps == "string" || (*ps).endsWith("[]");
			return false;
		}

		//replaceTokenSequence(tokens, "enum Kind { $enums ;",   "class Kind { /+ $enums; +/", false);

		fixBadIdentifers(tokens);
		replaceTokenSequence(tokens, "new $_dotident() {", "new class $_dotident {", false);
		replaceTokenSequence(tokens, "new $_dotident($args) {", "new class($args) $_dotident {", true);
		replaceTokenSequence(tokens, "new $_dotident<$args>() {", "new class $_dotident<$args> {", true);
		while (replaceTokenSequence(tokens, "new $_expr[] { $init }", "[ $init ]", true) > 0) {} // do it again, in case it has to be applied on $init
		replaceTokenSequence(tokens, "new $_dotident($args).", "(new $_dotident($args)).", true);

		for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; ++tokIt)
		{
			Token tok = *tokIt;

			if(beginClass != ClassType.kNone && parenCount == 0 && tok.type == Token.Identifier)
			{
				pushclass(tok.text);
				beginClass = ClassType.kNone;
			}
			
			if(inthrows)
			{
				if (tok.text == "{" || tok.text == ";")
				{
					tok.pretext = " */" ~ tok.pretext;
					inthrows = false;
				}
			}

			if(convertEnum.length > 0)
			{
				if(tok.type == Token.Identifier && parenCount == 0 && 
				   (tokIt[1].type == Token.ParenL || tokIt[1].type == Token.Comma || tokIt[1].type == Token.Semicolon))
				{
					tok.pretext ~= "static " ~ /* final_replacement ~ " " ~ */ convertEnum ~ " ";
					tokIt[1].pretext ~= "; static this() { _values ~= " ~ tok.text ~ " = new " ~ convertEnum;
				}
				else if(tok.type == Token.Comma && parenCount == 0)
					tok.text = "; }";
				else if(tok.type == Token.Semicolon || tok.type == Token.BraceR)
				{
					string txt;
					if(tokIt[-1].type != Token.Comma) // ; following ,
					    txt ~= "; }";
					txt ~= "\n\t\tstatic " ~ convertEnum ~ "[] _values;";
					txt ~= "\n\t\tstatic " ~ convertEnum ~ "[] values() { return _values; }";
					tok.pretext ~= txt;
					if(tok.type == Token.Semicolon)
						tok.text = "";
					convertEnum = "";
				}
			}

			switch(tok.text)
			{
			case "(":
				if(convertEnum.length == 0)
					if(classBraceLevel.length > 0 && classBraceLevel[$-1] + 1 == braceCount)
						if(!tokIt.atBegin() && tokIt[-1].type == Token.Identifier)
						{
							methods[tokIt[-1].text] = 0;
							checkStaticDecl();
						}
				parenCount++;
				break;
			case ")":
				fixCast(tokIt);
				parenCount--; 
				break;
			case "[":       brackCount++; break;
			case "]":       
				brackCount--;
				if(tokIt[-1].text == ",")  // fix trailing ',' in array initializer
					tokIt[-1].text = "";
				 break;
			case "{":
				static_decl = false;
				if(prevtext == "=")
					inArrayInit = true;
				else if(classBraceLevel.length > 0 && braceCount == classBraceLevel[$-1] + 1 && 
				   (tokIt[-1].type == Token.Semicolon || tokIt[-1].type == Token.BraceL || tokIt[-1].type == Token.BraceR))
					tokIt.pretext ~= "static this() ";
				braceCount++; 
				if(inArrayInit)
					tok.text = "[";
				break;
			case "}":
				if(inArrayInit)
					tok.text = "]";
				braceCount--;
				protection = "";
				checkpopclass();
				break;

			case ";":
				fixEmptyStatement(tokIt);
				if(close_static_decl == braceCount)
				{
					tok.text ~= " }";
					close_static_decl = -1;
				}
				inArrayInit = false;
				protection = "";
				static_decl = false;
				static_decl_asgn = static_decl_asgn.init;
				goto case ",";
				// fall through
			case "=":
				if(static_decl)
					static_decl_asgn = tokIt;
				goto case ",";
			case ",":
				if(parenCount == 0 && classBraceLevel.length > 0 && classBraceLevel[$-1] + 1 == braceCount)
					if(!tokIt.atBegin() && tokIt[-1].type == Token.Identifier)
						fields[tokIt[-1].text] = 0;
				break;

			case "+":
				if(isArrayType(tokIt - 1) || isArrayType(tokIt + 1))
					tok.text = "~";
				break;

			case "private":
			case "public":
			case "protected":
				protection = tok.text;
				goto default;

			case "new":
				checkStaticDecl();
				goto default;

			case "static":
				static_decl = true;
				goto default;

			case "implements":
			case "extends": 
				tok.text = ":";
				for(TokenIterator it = tokIt + 2; !it.atEnd() && isExtends(it.text); ++it, ++it)
					it.text = ",";
				break;

			case "package":  
				tok.text = "private import";
				for(TokenIterator it = tokIt + 1; !it.atEnd(); ++it)
					if(it.text == ";")
					{
						it.pretext ~= ".pkg";
						break;
					}
				break;

			case "@":        tok.text = "// @"; break;
			case "throws":   tok.text = "/* throws"; inthrows = true; break;
			case "final":
				if(parenCount) 
					tok.text = "/*final*/"; 
				else
				{
					for(TokenIterator it = tokIt + 1; !it.atEnd(); ++it)
						if(it.text == "(" || it.text == "{")
							break;
						else if(it.text == ";" || it.text == "=")
						{
							tok.text = final_replacement;
							break;
						}
				}
				break;

			case "instanceof":
				fixInstanceOf(tokIt);
				break;

			case "class":
				if (prevtext != ".")
					beginClass = ClassType.kClass;
				break;
			case "interface":
				if (prevtext != ".")
					beginClass = ClassType.kInterface;
				break;

			case "this":
				if(classStack.length > 0 && tokIt[-1].text == ".")
				{
					if (tokIt[-2].text == currentClass)
					{
						tokIt[-2].text = ""; 
						tokIt[-1].text = "";
					}
					else
					{
						string txt = "outer";
						for(int s = 1; s < classStack.length; s++)
							if(tokIt[-2].text == classStack[$-s])
							{
								tokIt[-2].text = "/*" ~ tokIt[-2].text ~ "*/"; 
								tokIt[-1].text = "";
								tokIt.text = txt;
								break;
							}
							else
								txt ~= ".outer";
					}
				}
				break;

			case "String":
			case "boolean":
			case "bool":
			case "int":
			case "char":
			case "Object":
				TokenIterator brackIt = tokIt;
				while(brackIt[1].text == "[" && brackIt[2].text == "]")
					brackIt += 2;
				if(classTypes.length > 0 && classTypes[$-1] == ClassType.kInterface && parenCount == 0 &&
				   classBraceLevel[$-1] == braceCount - 1 && 
				   (prevtext == ";" || prevtext == "{" || prevtext == "}" || 
				    prevtext == "public" || prevtext == "private" || prevtext == "protected"))
				{
					// in interfaces, convert "int X = n;" to "static final int X = n;"
					if(brackIt[1].type == Token.Identifier && brackIt[2].type == Token.Assign)
						tokIt.pretext ~= "static " ~ final_replacement ~ " ";
				}
				if(brackIt[1].type == Token.Identifier)
					storeType(tokIt, brackIt);
				break;

			case "enum":
				if(tokIt[1].type == Token.Identifier && (tokIt[2].text == "{" || isExtends(tokIt[2].text)))
				{
					int spos = (tokIt[2].text == "{" ? 3 : 5);
					bool needsConvert = false;
					for(TokenIterator it = tokIt + spos; !it.atEnd() && it.text != "}"; ++it)
						if(it.type != Token.Identifier && it.type != Token.Comma)
						{
							needsConvert = true;
							break;
						}
					if(needsConvert)
					{
						convertEnum = tokIt[1].text;
						tok.text = "class";
						beginClass = ClassType.kClassEnum;
					}
				}
				break;

			case "import":
				fixImport(tokIt);
				break;

			case "length":
				if(tokIt[1].text == "(" && tokIt[2].text != ")")
				    tokIt[1].text = tokIt[2].text = "";
				goto default;

			case "descent":
				if(tokIt[-1].text != "import" && tokIt[-1].text != "module")
					fixDescentClass(tokIt);
				break;
			
			default:
				if(currentClass.length && tok.text == currentClass && 
				   tokIt[-1].text != "new" && tokIt[1].text == "(" && braceCount == classBraceLevel[$-1] + 1)
					tok.text = "this";
				if(tok.type == Token.Macro && tok.text.startsWith("$"))
					tok.text = "_d_" ~ tok.text[1..$];
				if(tok.type == Token.Number && tok.text.endsWith("l"))
					tok.text = tok.text[0..$-1] ~ "L";
				break;
			}
			prevtext = tok.text;
		}

		//replaceTokenSequence(tokens, "($_dotident1)$_ident2",   "cast($_dotident1)$_ident2", false);
		//replaceTokenSequence(tokens, "($_dotident1[])$_ident2", "cast($_dotident1[])$_ident2", false);
		//replaceTokenSequence(tokens, "($_dotident1)(",          "cast($_dotident1)(", false);

		//replaceTokenSequence(tokens, "$_dotident1 instanceof $_dotident2", "cast($_dotident2)$_dotident1", false);
		//replaceTokenSequence(tokens, "$_dotident1($arg) instanceof $_dotident2", "cast($_dotident2)$_dotident1($arg)", true);
		//replaceTokenSequence(tokens, "if cast",                 "if", false);

		replaceTokenSequence(tokens, "$_ident1.$_ident2.class", "typeid($_ident1.$_ident2)", false);
		replaceTokenSequence(tokens, "$_ident1.class", "typeid($_ident1)", false);

		replaceTokenSequence(tokens, "$_dotident1<$_dotident2,$_dotident3<$args>>", "$_dotident1!($_dotident2,$_dotident3!($args))", false);
		replaceTokenSequence(tokens, "$_dotident1<$_dotident2<$args>>", "$_dotident1!($_dotident2!($args))", false);
		replaceTokenSequence(tokens, "$_dotident1<$_dotident2<$args> >", "$_dotident1!($_dotident2!($args))", false);
		replaceTokenSequence(tokens, "$_dotident1<$_dotident2,$_dotident3>", "$_dotident1!($_dotident2,$_dotident3)", false);
		replaceTokenSequence(tokens, "$_dotident1<$_dotident2>", "$_dotident1!($_dotident2)", false);
		replaceTokenSequence(tokens, "$_dotident1<$_dotident2[]>", "$_dotident1!($_dotident2[])", false);
		replaceTokenSequence(tokens, "public class $_ident1!(", "public class $_ident1(", false);

		replaceTokenSequence(tokens, "this($_dotident_templ<? : $_dotident_type>", "this($_dotident_templ!(T)", false);
		replaceTokenSequence(tokens, "($_dotident_templ<? : $_dotident_type>", "(U:$_dotident_type)($_dotident_templ!(U)", false);
		replaceTokenSequence(tokens, "public <$_ident_T : $_ident_base>$_ident_rettype $_ident_func($_dotident_templ<? super $_dotident_super>",
		                             "public $_ident_rettype $_ident_func($_ident_T)($_dotident_templ!(T)", false);

		replaceTokenSequence(tokens, "for($_expr_var : $collection)", "foreach($_expr_var; $collection)", true);

		replaceTokenSequence(tokens, "static {", "static this() {", false);
		replaceTokenSequence(tokens, "assert $expr;", "assert($expr);", true);

		fixIdenticalMethodsAndFields(tokens, methods, fields);

		for(TokenIterator tokIt = tokens.begin(); tokIt != tokens.end; ++tokIt)
		{
			Token tok = *tokIt;
			tok.pretext = tok.pretext.replace("//D", "");
			tok.text = translateToken(tok.text);
		}
		string txt = tokenListToString(tokens);

		if(subclasses.length > 0)
		{
			txt ~= "\n";
			foreach(s, clss; subclasses)
				txt ~= "alias " ~ clss ~ "." ~ s ~ " " ~ s ~ ";\n";
		}
		return txt;
	}

	string translateToken(string text)
	{
		switch(text)
		{
		case "template": text = "j_template"; break;
		case "debug":    text = "j_debug"; break;
		case "version":  text = "j_version"; break;
		case "alias":    text = "j_alias"; break;
		case "mixin":    text = "j_mixin"; break;
		case "typeof":   text = "j_typeof"; break;
		case "module":   text = "j_module"; break;
		case "scope":    text = "j_scope"; break;
		case "body":     text = "j_body"; break;
		case "align":    text = "j_align"; break;
		case "is":       text = "j_is"; break;
		case "in":       text = "j_in"; break;
		case "out":      text = "j_out"; break;
		case "function": text = "j_function"; break;
		case "pragma":   text = "j_pragma"; break;
		case "typedef":  text = "j_typedef"; break;
		case "delete":   text = "j_delete"; break;
		case "struct":   text = "j_struct"; break;
		case "lazy":     text = "j_lazy"; break;
		case "cast":     text = "j_cast"; break;
		case "invariant":text = "j_invariant"; break;
		case "unittest": text = "j_unittest"; break;
		case "with":     text = "j_with"; break;
		case "ref":      text = "j_ref"; break;
		case "bool":     text = "j_bool"; break;
		case "alignof":  text = "j_alignof"; break;
		case "mangleof": text = "j_mangleof"; break;
		case "property": text = "j_property"; break;
		case "protected":text = "public"; break; // protected handling still in work

		case "TypeInfo": text = "j_TypeInfo"; break;

		case "boolean":  text = "bool"; break;
		case "4d":       text = "4.0"; break;
		case "...":      text = "[]"; break; // assume arguments used as array
		
		case "__cast":   text = "cast"; break;
		default:
			if(string* ps = text in tokImports)
				text = *ps ~ "." ~ text;
			break;
		}
		return text;
	}

	void addSource(string file)
	{
		string base = baseName(file);
		foreach(excl; excludefiles)
			if(excl == base)
				return;

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
		string path = dirName(file);
		string pattern = baseName(file);
		foreach (string name; dirEntries(path, mode))
			if (globMatch(baseName(name), pattern))
				addSource(name);
	}

	bool implementationFileExists(string d_file)
	{
		if (std.file.exists(d_file))
			return true;
		int pos = lastIndexOf(d_file, '\\');
		if(pos > 0)
			if (std.file.exists(d_file[0 .. pos] ~ ".d"))
				return true;
		return false;
	}

	bool isSourceFile(string imp)
	{
		if(imp.startsWith("/descent"))
		{
			string javafile = java_path ~ imp[1..$] ~ ".java";
			return (std.file.exists(javafile));
		}
		else
		{
			string d_file = d_path ~ imp[1..$] ~ ".d";
			d_file = replace(d_file, "/", "\\");
			if (!implementationFileExists(d_file))
			{
				int pos = lastIndexOf(imp, '/');
				bool isInterface = imp[pos + 1] == 'I' && isupper(imp[pos + 2]);
				string txt = "module " ~ replace(imp[1 .. $], "/", ".") ~ ";\n\n";
				txt ~= (isInterface ? "interface" : "class") ~ " " ~ imp[pos + 1 .. $] ~ "\n";
				txt ~= "{\n}\n";

				string path = dirName(d_file);
				if(!exists(path))
					std.file.mkdirRecurse(path);
				std.file.write(d_file, txt);
			}
			return std.file.exists(d_file);
		}
	}

	string[string] packages;

	string fileToModule(string file, string d_path)
	{
		file = file[d_path.length .. $];
		file = replace(file, ".d", "");
		file = replace(file, "/", ".");
		file = replace(file, "\\", ".");
		return file;
	}

	void addPackageFile(string file, string d_path)
	{
		int fpos = lastIndexOf(file, '/');
		int bpos = lastIndexOf(file, '\\');
		int pos = max(fpos, bpos);
		if(pos < 0)
			return;
		string pkgpath = file[0..pos + 1];
		string pkgfile = pkgpath ~ "pkg.d";

		if(!(pkgfile in packages))
			packages[pkgfile] = "module " ~ fileToModule(pkgfile, d_path) ~ ";\n\n";

		packages[pkgfile] ~= "public import " ~ fileToModule(file, d_path) ~ ";\n";
	}

	void writePackageFiles()
	{
		foreach(file, text; packages)
			std.file.write(file, text);
	}

	string makehdr(string file, string d_path)
	{
		file = fileToModule(file, d_path);
		string hdr = "module " ~ file ~ ";\n\n";
		hdr ~= "private import descent_j2d;\n\n";
		return hdr;
	}

	int main(string[] argv)
	{
		getopt(argv, 
			"verbose|v", &verbose,
			"simple|s", &simple,
			"define|D", &defines,
			"undefine|U", &undefines);

		foreach(string file; argv[1..$])
		{
			if (indexOf(file, '*') >= 0 || indexOf(file, '?') >= 0)
 				addSourceByPattern(file);
			else
				addSource(file);
		}

		addSourceByPattern("+" ~ java_path ~ "*.java");

		string sources = "SRC = \\\n";
		foreach(string file; srcfiles)
		{
			string d_file = replace(file, java_path, d_path);
			d_file = replace(d_file, ".java", ".d");
			string text = cast(string) read(file);
			text = convertText(text);

			addPackageFile(d_file, d_path);
			string hdr = makehdr(d_file, d_path);
			std.file.write(d_file, hdr ~ text);
			sources ~= "\t" ~ d_file[d_path.length .. $] ~ " \\\n";
		}
		sources ~= "\n";
		std.file.write(d_path ~ "sources", sources);

		writePackageFiles();

		return 0;
	}

	string java_path = r"m:\s\d\descent\descent.core\src\";
	string d_path = r"m:\s\d\ddescent\";

	bool verbose;
	bool simple = true;

	string[string] defines;
	string[] undefines;

	string[] srcfiles;
	string[] excludefiles;
}

int main(string[] argv)
{
	j2d inst = new j2d;
	return inst.main(argv);
}

unittest
{
	j2d inst = new j2d;
	string newtext1 = inst.convertText("return (A) x;");
	assert(newtext1 == "return cast (A) x;");

	string newtext2 = inst.convertText("return (A.B) x;");
	assert(newtext2 == "return cast (A.B) x;");

	string newtext3 = inst.convertText("return A instanceof B;");
	assert(newtext3 == "return cast( B) A;");

	string newtext4 = inst.convertText("source.get(i) instanceof AsmStatement;");
	assert(newtext4 == " cast( AsmStatement)source.get(i);");

	string newtext5 = inst.convertText("type1.type2.class;");
	assert(newtext5 == "typeid(type1.type2);");

	string newtext6 = inst.convertText("void foo() throws A, B {};");
	assert(newtext6 == "void foo() /* throws A, B */ {};");

	string newtext7 = inst.convertText("return new char[][] { first, second, };");
	assert(newtext7 == "return [ first, second ];");
		
	string newtext8 = inst.convertText("class A { foo; { } };");
	assert(newtext8 == "class A { foo; static this() { } };");

version(none) {
	string newtext9 = inst.convertText("public enum TOK : ITerminalSymbols { TOKreserved, TOKlparen(TokenNameLPAREN); }");
	assert(newtext9 == "public class TOK : ITerminalSymbols { static " ~ /* final_replacement ~ " " ~ */ "TOK TOKreserved = new TOK;"
		" static " ~ /* final_replacement ~ " " ~ */ "TOK TOKlparen = new TOK(TokenNameLPAREN); }");
}
	string newtext10 = inst.convertText("class A { int foo() { new B(0) { A.this.x; } } }");
	assert(newtext10 == "class A { int foo() { new class(0) B { /*A*/outer.x; } } }");

	string newtext11 = inst.convertText("class A { int foo() { new B(0) { new C(1) { A.this.x; } } } }");
	assert(newtext11 == "class A { int foo() { new class(0) B { new class(1) C { /*A*/outer.outer.x; } } } }");
}
