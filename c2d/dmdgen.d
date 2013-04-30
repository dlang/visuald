module dmdgen;

import tokenizer;
import ast;
import dlist;
import pp;
import dgutil;
import tokutil;

import std.string;
import std.file;
import std.path;
import std.stdio;
import std.ctype;
import std.algorithm;

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
// + conveert class pointers to non-pointers
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
// + remove unnecessary paranthesis (confuses parser in sizeof, (i)++, (i).nn)
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

string[string] tokenMap;
string[string] filenameMap;

static this()
{
	tokenMap = [
		"::" : ".",
		"->" : ".",

		"version"   : "d_version",
		"ref"       : "d_ref",
		"align"     : "d_align",
		"dchar"     : "dmd_dchar",
		"body"      : "d_body",
		"module"    : "d_module",
		"scope"     : "d_scope",
		"pragma"    : "d_pragma",
		"wchar"     : "d_wchar",
		"real"      : "d_real",
		"byte"      : "d_byte",
		"cast"      : "d_cast",
		"delegate"  : "d_delegate",
		"alias"     : "d_alias",
		"is"        : "d_is",
		"in"        : "d_in",
		"out"       : "d_out",
		"invariant" : "d_invariant",
		"final"     : "d_final",
		"inout"     : "d_inout",
		"override"  : "d_override",
		"alignof"   : "d_alignof",
		"mangleof"  : "d_mangleof",
		"init"      : "d_init",

		"Object"    : "d_Object",
		"TypeInfo"  : "d_TypeInfo",
		"toString"  : "d_toString",
		"main"      : "d_main",
		"string"    : "d_string",

		"param_t"   : "PARAM",
		"hash_t"    : "d_hash_t",
		"File"      : "d_File",
		"STATIC"    : "private",
		"CEXTERN"   : "extern",
		"__try"     : "try",
		"NULL"      : "null",
		//"__except"          : "catch(Exception e) //", false);

		"__in"      : "in",
		"__out"     : "out",
		"__body"    : "body",
		"__real"    : "real",
		"typedef"   : "alias",

		"static_if" : "static if",
		"__static_eval" : "static_eval!",
		"__version" : "version",
		"__cast"    : "cast",
		"__init"    : "init",
		"__string"  : "string",
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
		"volatile"  : "/*volatile*/"
	];

	filenameMap = [
		"version"   : "dmd_version",
		"macro"     : "dmd_macro",
		"enum"      : "dmd_enum",
		"template"  : "dmd_template",
		"module"    : "dmd_module",
		"import"    : "dmd_import",
		"scope"     : "dmd_scope",
		"root"      : "dmd_root",
		"code"      : "dmd_code",
		"global"    : "dmd_global",
		"mem"       : "dmd_mem",
		"d-gcc-real": "d_gcc_real",
		"d-gcc-complex_t" : "d_gcc_complex_t",
		"d-dmd-gcc" : "d_dmd_gcc",
		"dchar"     : "dmd_dchar",
		"frontend.net.pragma" : "frontend.net.dmd_pragma"
	];
}

string mapTokenText(Token tok)
{
	if(Token.isPPToken(tok.type))
		return fixPPToken(tok);
	if(tok.type == Token.String)
		return fixString(tok.text);
	if(tok.type == Token.Number)
		return fixNumber(tok.text);
	
	if(string *ps = tok.text in tokenMap)
		return *ps;
	return tok.text;
}

string fixPPToken(Token tok)
{
	assert(tok.type != Token.PPinsert);
	if(tok.type == Token.PPinclude)
	{
		TokenList tokList = scanText(tok.text, 1, false);
		TokenIterator it = tokList.begin();
		assert(it.type == Token.PPinclude);
		it.advance();
		if(!it.atEnd() && it.type == Token.String)
		{
			string fname = it.text[1 .. $-1]; // remove quotes
			fname = replace(fname, ".h", "");
			fname = replace(fname, "/", ".");
			if(string* ps = fname in filenameMap)
				fname = *ps;
			it[-1].text = "import";
			it.text = fname ~ ";";
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
	if(!isalnum(prevch) && prevch != '_')
		return false;
	if(!isalnum(nextch) && nextch != '_')
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
		case "INT32":     type |= TF_BIT.INT | TF_BIT.SIZE32; break;
		case "UINT32":    type |= TF_BIT.INT | TF_BIT.SIZE32 | TF_BIT.UNSIGNED; break;
		case "wchar_t":   type |= TF_BIT.INT | TF_BIT.SIZE16 | TF_BIT.UNSIGNED; break;
		case "long":
			if(type & TF_BIT.LONG)
				type = TF_BIT.INT | TF_BIT.SIZE64;
			else
				type |= TF_BIT.LONG;
			break;
		case "const":
			isConst = true; // fall through
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

	if((type & (TF_BIT.VOID | TF_BIT.BOOL | TF_BIT.INT | TF_BIT.FLOAT | TF_BIT.COMPLEX)) == 0)
		type |= TF_BIT.INT;
	if((type & TF_BIT.INT) != 0 && (type & TF_BIT.LONG) != 0)
		type &= ~TF_BIT.LONG;
	if((type & TF_BIT.INT) != 0 && (type & (TF_BIT.SIGNED | TF_BIT.UNSIGNED)) == 0)
		type |= TF_BIT.SIGNED;

	switch(type)
	{
	case 0:                                            basic = ""; break;
	case TF_BIT.VOID:                                  basic = "void"; break;
	case TF_BIT.BOOL:                                  basic = "bool"; break;
	case TF_BIT.INT | TF_BIT.SIZE8  | TF_BIT.UNSIGNED: basic = "ubyte"; break;
	case TF_BIT.INT | TF_BIT.SIZE8  | TF_BIT.SIGNED:   basic = "char"; break; // byte?
	case TF_BIT.INT | TF_BIT.SIZE16 | TF_BIT.UNSIGNED: basic = "ushort"; break;
	case TF_BIT.INT | TF_BIT.SIZE16 | TF_BIT.SIGNED:   basic = "short"; break;
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
		if(!it.atEnd() && it.pretext.length == 0 && (isalnum(it.text[0]) || it.text[0] == '*' || it.text[0] == '_'))
			it.pretext = " ";
	}
}

void patchDeclTypeModifier(AST ast)
{
	for(TokenIterator tokIt = ast.start; tokIt != ast.end; ++tokIt)
	{
		if(DeclType.isTypeModifier(tokIt.text))
			if(!DeclType.isPersistentTypeModifier(tokIt.text))
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
		if(it.type == Token.Operator)
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

				// if this is the declaration, reomve return type
				AST parent = expr._parent;
				while(parent && (parent._type == AST.Type.UnaryExp || parent._type == AST.Type.PostExp))
					parent = parent._parent;
				if(parent && parent._type == AST.Type.VarDeclaration)
				{
					parent = parent._parent;
					assert(parent && parent._type == AST.Type.Declaration);
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
			    expr.start.text = replace(*ps, "::", ".") ~ expr.start.text;
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
		assert(expr.children.count() == 1);
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
				ASTIterator it = expr._parent.children.find(expr);
				expr._parent.insertChildBefore(it, subExpr, subList);
				expr._parent.removeChild(expr);
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
			expr.start.text = "";  // remove '&'
		}
}

///////////////////////////////////////////////////////////////

void patchAssignArrayData(Expression expr)
{
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

void patchAssignCast(Expression expr)
{
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

void patchCallArguments(Expression expr)
{
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
	case "shift":         argIdx = 0; patch = KindOfPatch.AddCastVoid; break;
	case "write":
	case "toCBuffer":
	case "toCBuffer2":    argIdx = 0; patch = KindOfPatch.RemoveAddress; break;
	case "isprint":       argIdx = 0; patch = KindOfPatch.IsPrint; break;
	case "mixin":         argIdx = 0; patch = KindOfPatch.QuoteArgs; break;
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
	}

}

void patchCtorInitializer(AST ast)
{
	if(ast.start.text != "super")
		return;
	if(!ast.children || ast.children.empty())
		return;

	Expression arg = cast(Expression)ast.children[0];
	if(arg && arg._type == AST.Type.PrimaryExp && arg._toktype == Token.Number && arg.start.text == "0")
		arg.start.text = "Loc(0)";
}

void patchReturnExpressionType(Statement stmt)
{
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
	assert(tokIt.type == Token.BraceL);

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
	assert(var && var.children && !var.children.empty);
	Expression expr = cast(Expression)var.children[0];
	assert(expr);

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

		assert(dtype && dvar && dvar.children);

		if(dtype._dtype == DeclType.Class && !dtype.isTypedef() && !isBasicUserType(dtype._ident))
		{
			AST id = dvar.children[0];
			bool hasArgs = (id._type == AST.Type.PostExp && expressionType(id) == Token.ParenL);
			bool isPOD = AST.isPOD(dtype._ident);
			if((!isPOD && isSimpleVarDecl(dvar)) || hasArgs)
			{
				AST ident = findIdentifier(dvar);
				assert(ident);
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
			assert(commaIt.type == Token.Comma && semiIt.type == Token.Semicolon);

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
	assert(dvar.end[-2].text == "=");
	assert(dvar.end[-1].text == "0");

	if(strip(dvar.end[-2].pretext) == "")
		dvar.end[-2].pretext = "";
	clearTokenText(dvar.end - 2);
	clearTokenText(dvar.end - 1);
}

int getArrayDimension(Expression var)
{
	int dim = 0;
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
	DeclVar  dvar  = cast(DeclVar)  decl.children[1];

	assert(dtype && dvar);
	if(dvar.countChildren() < 2)
		return;

	Expression var  = cast(Expression) dvar.children[0];
	Expression init = cast(Expression) dvar.children[1];
	assert(var && init);
	
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
		for(ASTIterator it = init.children.begin(); !it.atEnd(); ++it)
		{
			Token tok = *it.start;
			if(indexOf(tok.pretext, '\n') >= 0)
			{
				if(it != init.children.begin())
					tok.pretext = close ~ tok.pretext;
				tok.pretext ~= open;
			}
		}
		init.end[-1].pretext = close ~ init.end[-1].pretext;
	}
}

void patchStringDeclaration(Declaration decl)
{
	if(decl.countChildren() < 2)
		return;

	DeclType dtype = cast(DeclType) decl.children[0];
	DeclVar  dvar  = cast(DeclVar)  decl.children[1];

	assert(dtype && dvar);

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
				if(it.text == "char")
					charTok = *it;
				else
					isNotChar = true;
		return isNotChar ? null : charTok;
	}

	Token tok = isCharType(dtype);
	if(!tok)
		return;

	tok.text = "__string";
	dtype._dtype = DeclType.Class;
	dtype._ident = tok.text;

	assert(var.end[-2].type == Token.BracketL);
	assert(var.end[-1].type == Token.BracketR);
	
	clearTokenText(var.end - 2);
	clearTokenText(var.end - 1);
}

void patchPointerDeclaration(Declaration decl)
{
	if(decl.countChildren() < 2)
		return;

	DeclType dtype = cast(DeclType) decl.children[0];
	DeclVar  dvar  = cast(DeclVar)  decl.children[1];

	assert(dtype && dvar);

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
				if(dtype._parent.children.count() > 1)
					// variable declaration doesn't need struct keyword
					clearTokenText(startIt);
				else if(AST.isPOD(nextIt.text))
					startIt.text = "struct";
				else
					startIt.text = "class";
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
		assert(it.type == Token.LessThan);
		it.text = "(";
		it = ast.children[0].end;
		assert(it.type == Token.GreaterThan);
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
		for(ASTIterator it = ast.children.begin(); !it.atEnd(); )
		{
			// some simple support to allow changing the current child without making the iterator invalid
			AST child = *it; 
			++it;
			patchAST(child);
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
		assert(cnt > 1);
		bool empty = emptyDeclGroup(ast.children[1]);
		if(empty && cnt > 2)
			empty = emptyDeclGroup(ast.children[2]);
		if(empty)
			ast._parent.removeChild(ast);
	}
}

///////////////////////////////////////////////////////////////////////

void patch_dmdv2(TokenList srctokens)
{
	replaceTokenSequence(srctokens, ["__version", "(", "DMDV2", ")", "{", "$1", ",", "}" ], [ "$1", "," ], true);
}

void patch_disable_conditional(TokenList srctokens, string condition)
{
	replaceTokenSequence(srctokens, [ "static_if", "(", condition, ")", "{", "$1", "}", "else", "{", "$2", "}" ], [ "$2" ], true);
	replaceTokenSequence(srctokens, [ "static_if", "(", condition, ")", "{", "$1", "}" ], [ ], true);
}

void patch_enable_conditional(TokenList srctokens, string condition)
{
	replaceTokenSequence(srctokens, [ "static_if", "(", condition, ")", "{", "$1", "}", "else", "{", "$2", "}" ], [ "$1" ], true);
	replaceTokenSequence(srctokens, [ "static_if", "(", condition, ")", "{", "$1", "}" ], [ "$1" ], true);
}

void patch_declspec(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "__declspec", "(", "naked", ")" ], [ "__naked" ], true);
}

void patch_virtual_dtor(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "virtual", "~" ], [ "~" ], true);
}

void patch_contracts(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "static_if", "(", "__DMC__", ")", "{", "__in", "$1", "__body", "}" ],
	                                [ "__in", "$1", "__body" ], true);
	replaceTokenSequence(srctokens, [ "static_if", "(", "__DMC__", ")", "{", "__out", "$1", "__body", "}" ],
	                                [ "__out", "$1", "__body" ], true);
}

void patch_T68000_T80x86(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "T68000", "(", "$1", ")" ], [ "" ], true);
	replaceTokenSequence(srctokens, [ "T80x86", "(", "$1", ")" ], [ "$1" ], true);
}

void patch_va_arg(TokenList srctokens)
{
	// va_arg mixes values and types, so we cannot parse it -> invoke mixin instead
	//TokenList[string] mixins = [ "va_arg" : new TokenList ];
	//expandPPdefines(srctokens, mixins, MixinMode.ExpressionMixin);
	replaceTokenSequence(srctokens, "va_arg($1,void *)", "va_arg($1,voidp)", true);
}

void patch_foreach(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "foreach", "(", "$i", ",", "$n", ",", "$vec", ")" ], 
	                                [ "for (", "$i", " = first_bit(", "$vec", "); ", "$i", " < ", "$n", "; ", 
	                                           "$i", " = next_bit(", "$vec", ", ", "$i", "))" ], true);
}

// frontend
void patch_expression_h(TokenList srctokens)
{
	// members in source, but not in header
	replaceTokenSequence(srctokens, "struct VarExp : SymbolExp { $decl };",
	                                "struct VarExp : SymbolExp { $decl\n"
	                                "#if DMDV1\n"
	                                "    elem *toElem(IRState *irs);\n"
	                                "#endif\n"
	                                "};", true);
	replaceTokenSequence(srctokens, "struct SymOffExp : SymbolExp { $decl };",
	                                "struct SymOffExp : SymbolExp { $decl\n"
	                                "#if 0\n"
	                                "    elem *toElem(IRState *irs);\n"
	                                "#endif\n"
					"};", true);
	replaceTokenSequence(srctokens, "struct StringExp : Expression { $decl };",
	                                "struct StringExp : Expression { $decl\n"
	                                "#if 0\n"
	                                "    Expression *syntaxCopy();\n"
	                                "#endif\n"
					"};", true);
 
	TokenList[string] defines = [ "X" : null, "ASSIGNEXP" : null ];
	expandPPdefines(srctokens, defines, MixinMode.ExpandDefine);
}

void patch_expression_c(TokenList srctokens)
{
	// move return before conditionals
	replaceTokenSequence(srctokens, "__static_eval(1, false)(return", "return\n    __static_eval(1, false)(", true);
	replaceTokenSequence(srctokens, "__static_eval(!$args)(return", "__static_eval(!$args)(", true);

	// loc assignment also in contructor body
	replaceTokenSequence(srctokens, "Expression::Expression($arg) : loc(loc)", "Expression::Expression($arg)", true);
}

void patch_cast_c(TokenList srctokens)
{
	TokenList[string] defines = [ "X" : null ];
	expandPPdefines(srctokens, defines, MixinMode.ExpressionMixin);
}

void patch_mtype_h(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "struct TypeTuple : Type { $decl };",
	                                "struct TypeTuple : Type { $decl\n"
	                                "#if 0\n"
	                                "    Type *makeConst();\n"
	                                "#endif\n"
	                                "};", true);
	replaceTokenSequence(srctokens, "int isZeroInit(Loc loc = 0)",
	                                "int isZeroInit(Loc loc = Loc(0))\n", true);

	string[string] defines = [ "^t.*$" : "static Type* $id() { return $text; }" ];
	regexReplacePPdefines(srctokens, defines);
}

void patch_doc_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "unsigned char ddoc_default", "char ddoc_default", true);
}

void patch_mars_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "written", "=", "$std", "static_if", "(", "TARGET_NET", ")", "{", "$net", "}" ],
	                                [ "\nstatic_if(TARGET_NET) {\n    written = ", "$std", "$net", 
					  "\n} else {\n    written = ", "$std", ";\n}" ], true);
	patch_disable_conditional(srctokens, "WINDOWS_SEH");
}

void patch_template_c(TokenList srctokens)
{
	patch_disable_conditional(srctokens, "WINDOWS_SEH");
}

void patch_lexer_c(TokenList srctokens)
{
	patch_contracts(srctokens);
	patch_dmdv2(srctokens);

	TokenList[string] mixins = [ "SINGLE" : null, "DOUBLE" : null ];
	expandPPdefines(srctokens, mixins, MixinMode.ExpandDefine); // StatementMixin);

	replaceTokenSequence(srctokens, "TOK value;",
	                                "TOK value = TOK.__init;", true);
	replaceTokenSequence(srctokens, "sv->ptrvalue = (void *) new Identifier",
	                                "sv->ptrvalue = new Identifier", true);
	replaceTokenSequence(srctokens, "linnum = tok.uns64value - 1",
	                                "linnum = (int) (tok.uns64value - 1)", true);

	replaceTokenSequence(srctokens, "isoctal (unsigned char c)", "isoctal (unsigned int c)", true);
	replaceTokenSequence(srctokens, "ishex   (unsigned char c)", "ishex   (unsigned int c)", true);
	replaceTokenSequence(srctokens, "isidchar(unsigned char c)", "isidchar(unsigned int c)", true);

	replaceTokenSequence(srctokens, "switch(flags) { case 0:", "switch (flags)\n    {\n\tcase (FLAGS) 0:", true);

	replaceTokenSequence(srctokens, "TOK Lexer::wysiwygStringConstant($args){$body}", 
	                                "TOK Lexer::wysiwygStringConstant($args)\n{$body\n    assert(false);\n}", true);
	replaceTokenSequence(srctokens, "TOK Lexer::hexStringConstant($args){$body}", 
	                                "TOK Lexer::hexStringConstant($args)\n{$body\n    assert(false);\n}", true);
	replaceTokenSequence(srctokens, "TOK Lexer::escapeStringConstant($args){$body}", 
	                                "TOK Lexer::escapeStringConstant($args)\n{$body\n    assert(false);\n}", true);
}

TokenList[string] lexer_h_mixins;

void patch_lexer_h(TokenList srctokens)
{
	patch_dmdv2(srctokens);

	// just capture CASE_BASIC_TYPES_X for parse.c
	lexer_h_mixins = [ "CASE_BASIC_TYPES_X" : null, "CASE_BASIC_TYPES" : null ];
	expandPPdefines(srctokens, lexer_h_mixins, MixinMode.LabelMixin);
}

void patch_parse_c(TokenList srctokens)
{
	expandPPdefines(srctokens, lexer_h_mixins, MixinMode.LabelMixin);
}

void patch_module_c(TokenList srctokens)
{
	// we don't handle different protoypes for the same function
	replaceTokenSequence(srctokens, [ "static_if", "(", "IN_GCC", ")", "{", "void", "Module", "::", "parse", "$if", 
	                                  "}", "else", "{", "$else", "}" ], 
					[ "void Module::parse", "$if" ], true);
}

void patch_module_h(TokenList srctokens)
{
	// we don't handle different protoypes for the same function
	replaceTokenSequence(srctokens, [ "static_if", "(", "IN_GCC", ")", "{", "void", "parse", "$if", 
	                                  "}", "else", "{", "$else", "}" ], 
					[ "void parse", "$if" ], true);
}

void patch_statement_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "char fntab[9][3]", "const char *fntab[9]", true);
}

void patch_toir_c(TokenList srctokens)
{
	// we don't handle different protoypes for the same function
	replaceTokenSequence(srctokens, [ "static", "const", "char", "*", "namearray", "[", "]", "=", "{",
	                                  "__version", "(", "DMDV1", ")", "{", "$v1", 
					  "}", "else", "$x", "__version", "(", "DMDV2", ")", "{", "$v2", "}", "}", ";" ],
					[ "\n__version(DMDV1) {\n    static const char *namearray[] =\n",
					  "    {\n", "$v1", "\n    };\n", "} else ",
					  "__version(DMDV2) {\n    static const char *namearray[] =\n",
					  "    {\n", "$v2", "\n    };\n", "}" ], true);
}

void patch_interpret_c(TokenList srctokens)
{
	TokenList[string] mixins = [ "START" : null, "UNA_INTERPRET" : null, 
	                             "BIN_INTERPRET" : null, "BIN_INTERPRET2" : null,
				     "BIN_ASSIGN_INTERPRET" : null ];
	expandPPdefines(srctokens, mixins, MixinMode.ExpandDefine); // StatementMixin

	replaceTokenSequence(srctokens, "fp_t fp", "Expression *(*fp)(Type *, Expression *, Expression *)", true);
	replaceTokenSequence(srctokens, "fp2_t fp", "Expression *(*fp)(enum TOK, Type *, Expression *, Expression *)", true);
}

void patch_traits_c(TokenList srctokens)
{
	TokenList[string] mixins = [ "ISTYPE" : null, "ISDSYMBOL" : null ];
	expandPPdefines(srctokens, mixins, MixinMode.StatementMixin);
}

void patch_access_c(TokenList srctokens)
{
    replaceTokenSequence(srctokens, [ "error" ], [ "mars::error" ], true);
}

void patch_arrayop_c(TokenList srctokens)
{
	// TODO: mixins defined multiple times, needs disambiguation
	TokenList[string] mixins = [ "X" : null ];
	expandPPdefines(srctokens, mixins, MixinMode.ExpandDefine); // StatementMixin
}

void patch_iasm_c(TokenList srctokens)
{
	// we don't handle different protoypes for the same function
	replaceTokenSequence(srctokens, [ "asm_make_modrm_byte", "(", "__version", "(", "DEBUG", ")", "{", "$args", "}" ],
	                                [ "asm_make_modrm_byte(", "$args" ], true);
	replaceTokenSequence(srctokens, "unsigned rm  : 3; unsigned reg : 3; unsigned mod : 2;",
	                                "mixin(__bitfields(uint, \"rm\", 3,\n"
					"                  uint, \"reg\", 3,\n"
					"                  uint, \"mod\", 2));", true);
	replaceTokenSequence(srctokens, "unsigned base : 3; unsigned index : 3; unsigned ss : 2;",
	                                "mixin(__bitfields(uint, \"base\", 3,\n"
					"                  uint, \"index\", 3,\n"
					"                  uint, \"ss\", 2));", true);
}

void patch_clone_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "static_if", "(", "STRUCTTHISREF", ")", "{", "$1", ",", "}", "else", "{", "$2", ",", "}" ], 
					[ "__static_evalif(STRUCTTHISREF)(", "$1", ", ", "$2", ")", "," ], true);
	replaceTokenSequence(srctokens, [ "static_if", "(", "STRUCTTHISREF", ")", "{", "$1", "}", "else", "{", "$2", "}" ], 
					[ "__static_evalif(STRUCTTHISREF)(", "$1", ", ", "$2", ")" ], true);
}

void patch_class_c(TokenList srctokens)
{
	// defineRef never declared in class
	replaceTokenSequence(srctokens, [ "ClassDeclaration", "::", "defineRef" ], [ "ClassDeclaration__defineRef" ], true);
}

void patch_async_c(TokenList srctokens)
{
	patch_disable_conditional(srctokens, "_WIN32");
}

void patch_array_c(TokenList srctokens)
{
	patch_disable_conditional(srctokens, "_WIN32");
}

void patch_tocsym_c(TokenList srctokens)
{
	patch_contracts(srctokens);
	replaceTokenSequence(srctokens, "Dsymbol::toSymbolX($args, type", "Dsymbol::toSymbolX($args, TYPE", true);
}

void patch_e2ir_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "Type *tn; static_if(!0) goto $label; if($ifexpr) $label2: $stmt tb2->nextOf();",
	                                "Type *tn;\n"
					"    $stmt tb2->nextOf();\n"
					"static_if(0)\n"
					"    if($ifexpr)\n"
					"        goto $label; else goto L_never; else $label:", true);
	replaceTokenSequence(srctokens, "else static_if(0) {", "static_if(0) { L_never:", true);
}

// root/tk
void patch_port_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "std", "::", "numeric_limits", "$1", "infinity", "(", ")" ], [ "INFINITY" ], true);
}

void patch_root_c(TokenList srctokens)
{
	patch_disable_conditional(srctokens, "_MSC_VER");
}

void patch_root_h(TokenList srctokens)
{
	patch_virtual_dtor(srctokens);
	replaceTokenSequence(srctokens, [ "unsigned", "short" ], [ "wchar_t" ], true);
}

void patch_lstring_h(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "dchar string[];", "dchar string[0];", true);
}

void patch_lstring_c(TokenList srctokens)
{
	patch_enable_conditional(srctokens, "_MSC_VER");
}

void patch_dchar_c(TokenList srctokens)
{
	patch_declspec(srctokens);
}

void patch_stringtable_h(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "void *ptrvalue;", "Object *ptrvalue;", true);
}


void patch_newman_c(TokenList srctokens)
{
	patch_enable_conditional(srctokens, "__cplusplus");
}

void patch_list_h(TokenList srctokens)
{
	patch_disable_conditional(srctokens, "MEM_DEBUG");
}

void patch_list_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "static_if", "(", "!", "assert", ")", "{", "$1", "}" ], [ ], true);
	patch_declspec(srctokens);

	replaceTokenSequence(srctokens, [ "static_if", "(", "!", "list_freelist", ")", "{", "$1", "}" ], [ "$1" ], true);
	replaceTokenSequence(srctokens, [ "static_if", "(", "!", "list_new", ")", "{", "$1", "}" ], [ "$1" ], true);

	patch_disable_conditional(srctokens, "MEM_DEBUG");
	patch_disable_conditional(srctokens, "__DMC__");
	patch_enable_conditional(srctokens, "__cplusplus");
	patch_va_arg(srctokens);
}

void patch_filespec_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "static_if", "(", "!", "assert", ")", "{", "$1", "}" ], [ ], true);
}

void patch_vec_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "static_if", "(", "!", "assert", ")", "{", "$1", "}" ], [ ], true);
	replaceTokenSequence(srctokens, ", static_if(__INTSIZE == 4) { $1 }", ", $1", true);
	replaceTokenSequence(srctokens, "static_if(__SC__ <= 0x610) { $1 }", "", true);
	patch_declspec(srctokens);
	replaceTokenSequence(srctokens, "_asm { static_if($COND1) { $asm1 } else static_if($COND2) { $asm2 } else { $asm3 } }",
	                                "static_if($COND1) {\n"
	                                "    _asm { $asm1 }\n"
	                                "} else static_if($COND2) {\n"
	                                "    _asm { $asm2 }\n"
	                                "} else {\n"
	                                "    _asm { $asm3 }\n"
	                                "}\n", true);
}

// backend
void patch_gdag_c(TokenList srctokens)
{
	patch_foreach(srctokens);
}

void patch_gother_c(TokenList srctokens)
{
	patch_foreach(srctokens);
	replaceTokenSequence(srctokens, "assnod = (elem **) static_if(TX86) { $1 } else { $2 }",
	                                "\nstatic_if(TX86) {\n\t\t\tassnod = (elem **) $1\n"
	                                "} else {\n\t\t\tassnod = (elem **) $2\n}\n", true);
}

void patch_gloop_c(TokenList srctokens)
{
	patch_foreach(srctokens);
	patch_T68000_T80x86(srctokens);

	replaceTokenSequence(srctokens, "&& tyuns(flty)))", "&& tyuns(flty))", true);
	replaceTokenSequence(srctokens, "Xzero())) ))", "Xzero()))", true);
	replaceTokenSequence(srctokens, "countrefs2(e1)))", "countrefs2(e1))", true);
	
	
}

void patch_el_c(TokenList srctokens)
{
	patch_declspec(srctokens);
	patch_disable_conditional(srctokens, "DOS386");
}

///////////////////////////////////////////////////////////////

typedef void (*patch_fn)(TokenList);

struct translateInfo
{
	string inputFile;
	patch_fn patch;
};

translateInfo srcfiles[] = [
	{ "dmd/lexer.h", &patch_lexer_h },
	{ "dmd/lexer.c", &patch_lexer_c },

	{ "dmd/expression.h", &patch_expression_h },
	{ "dmd/expression.c", &patch_expression_c },
	{ "dmd/doc.c", &patch_doc_c },
	{ "dmd/doc.h", },
	{ "dmd/mars.h", &patch_dmdv2 },
	{ "dmd/arraytypes.h", },
	{ "dmd/macro.h", },
	{ "dmd/template.h", },
	{ "dmd/aggregate.h", },
	{ "dmd/declaration.h", },
	{ "dmd/dsymbol.h", },
	{ "dmd/mtype.h", &patch_mtype_h },
	{ "dmd/identifier.h", },
	{ "dmd/enum.h", },
	{ "dmd/id.h", },
	{ "dmd/module.h", &patch_module_h },
	{ "dmd/scope.h", },
	{ "dmd/hdrgen.h", },
	{ "dmd/mars.c", &patch_mars_c },
	{ "dmd/cond.h", },
	{ "dmd/lib.h", },
	{ "dmd/enum.c", },
	{ "dmd/struct.c", },
	{ "dmd/statement.h", },
	{ "dmd/dsymbol.c", },
	{ "dmd/init.h", },
	{ "dmd/import.h", },
	{ "dmd/attrib.h", },
	{ "dmd/import.c", },
	{ "dmd/id.c", },
	{ "dmd/staticassert.c", },
	{ "dmd/staticassert.h", },
	{ "dmd/identifier.c", },
	{ "dmd/mtype.c", },
	{ "dmd/utf.h", },
	{ "dmd/parse.h", },
	{ "dmd/optimize.c", },
	{ "dmd/template.c", &patch_template_c },
	{ "dmd/declaration.c", },
	{ "dmd/cast.c", &patch_cast_c },
	{ "dmd/init.c", },
	{ "dmd/func.c", },
	{ "dmd/utf.c", },
	{ "dmd/unialpha.c", },
	{ "dmd/parse.c", &patch_parse_c },
	{ "dmd/version.h", },
	{ "dmd/aliasthis.h", },
	{ "dmd/statement.c", &patch_statement_c },
	{ "dmd/constfold.c", },
	{ "dmd/version.c", },
	{ "dmd/inifile.c", },
	{ "dmd/typinf.c", },
	{ "dmd/irstate.h", },
	{ "dmd/module.c", &patch_module_c },
	{ "dmd/scope.c", },
	{ "dmd/dump.c", },
	{ "dmd/cond.c", &patch_dmdv2 },
	{ "dmd/inline.c", },
	{ "dmd/opover.c", },
	{ "dmd/entity.c", },
	{ "dmd/class.c", &patch_class_c },
	{ "dmd/mangle.c", &patch_contracts },
	{ "dmd/attrib.c", },
	{ "dmd/impcnvtab.c", },
	{ "dmd/link.c", },
	{ "dmd/access.c", &patch_access_c },
	{ "dmd/macro.c", },
	{ "dmd/hdrgen.c", },
	{ "dmd/delegatize.c", },
	{ "dmd/traits.c", &patch_traits_c },
	{ "dmd/aliasthis.c", },
	{ "dmd/builtin.c", },
	{ "dmd/libomf.c", },
	{ "dmd/arrayop.c", &patch_arrayop_c },
	{ "dmd/irstate.c", },
	{ "dmd/glue.c", },
	{ "dmd/msc.c", },
	// { "dmd/tk.c", },

/*
	{ "dmd/s2ir.c", },
	{ "dmd/todt.c", },
	{ "dmd/e2ir.c", &patch_e2ir_c },
	{ "dmd/toir.h", },
	{ "dmd/tocsym.c", &patch_tocsym_c },
	{ "dmd/toobj.c", },
	{ "dmd/toctype.c", },
	{ "dmd/tocvdebug.c", },
	{ "dmd/toir.c", &patch_toir_c },
*/
	{ "dmd/util.c", },
	{ "dmd/bit.c", },
	{ "dmd/eh.c", },

//	{ "dmd/elxxx.c", },
//	{ "dmd/fltables.c", },
//	{ "dmd/cdxxx.c", },
//	{ "dmd/tytab.c", },
//	{ "dmd/optab.c", },
//	{ "dmd/iasm.c", &patch_iasm_c },

	{ "dmd/clone.c", &patch_clone_c },
	{ "dmd/interpret.c", &patch_interpret_c },
	// { "dmd/ph.c", },

	// { "dmd/root/async.h", }, // defined more precisely in async.c
	{ "dmd/root/async.c", &patch_async_c },
	{ "dmd/root/lstring.c", &patch_lstring_c },
	{ "dmd/root/array.c", &patch_array_c },
	{ "dmd/root/gnuc.c", },
	{ "dmd/root/man.c", },
	//{ "dmd/root/rmem.c", },
	//{ "dmd/root/rmem.h", },
	// { "dmd/root/port.h", },
	// { "dmd/root/port.c", &patch_port_c },
	{ "dmd/root/root.c", &patch_root_c },
	{ "dmd/root/response.c", },
	{ "dmd/root/stringtable.c", },
	{ "dmd/root/stringtable.h", &patch_stringtable_h },

	{ "dmd/root/root.h", &patch_root_h },
	{ "dmd/root/lstring.h", &patch_lstring_h },
	//{ "dmd/root/dchar.c", &patch_dchar_c },
	//{ "dmd/root/dchar.h", },

	{ "dmd/tk/list.h", &patch_list_h },
	{ "dmd/tk/vec.h", },
	{ "dmd/tk/filespec.c", &patch_filespec_c },
	{ "dmd/tk/filespec.h", },
	{ "dmd/tk/list.c", &patch_list_c },
	{ "dmd/tk/vec.c", &patch_vec_c },
	//{ "dmd/tk/mem.h", },
	//{ "dmd/tk/mem.c", },

/+
	{ "dmd/backend/go.c", },
	{ "dmd/backend/gdag.c", &patch_gdag_c },
	{ "dmd/backend/gother.c", &patch_gother_c },
	{ "dmd/backend/gflow.c", },
	{ "dmd/backend/gloop.c", &patch_gloop_c },
	{ "dmd/backend/var.c", },
	{ "dmd/backend/el.c", &patch_el_c },
	{ "dmd/backend/newman.c", &patch_newman_c },
	{ "dmd/backend/glocal.c", },
	{ "dmd/backend/os.c", },
	{ "dmd/backend/nteh.c", },
	{ "dmd/backend/evalu8.c", },
	{ "dmd/backend/cgcs.c", },
	{ "dmd/backend/rtlsym.c", },
	{ "dmd/backend/html.c", },
	{ "dmd/backend/cgelem.c", },
	{ "dmd/backend/cgen.c", &patch_declspec },
	{ "dmd/backend/cgreg.c", },
	{ "dmd/backend/out.c", },
	{ "dmd/backend/blockopt.c", &patch_T68000_T80x86 },
	{ "dmd/backend/cg.c", },
	{ "dmd/backend/cgcv.c", },
	{ "dmd/backend/type.c", },
	{ "dmd/backend/dt.c", },
	{ "dmd/backend/debug.c", },
	{ "dmd/backend/code.c", &patch_declspec },
	{ "dmd/backend/cg87.c", },
	{ "dmd/backend/cgsched.c", },
	{ "dmd/backend/ee.c", },
	{ "dmd/backend/symbol.c", },
	{ "dmd/backend/cgcod.c", },
	{ "dmd/backend/cod1.c", },
	{ "dmd/backend/cod2.c", },
	{ "dmd/backend/cod3.c", },
	{ "dmd/backend/cod4.c", },
	{ "dmd/backend/cod5.c", },
	{ "dmd/backend/outbuf.c", },
	{ "dmd/backend/bcomplex.c", },
	{ "dmd/backend/ptrntab.c", },
	{ "dmd/backend/aa.c", },
	{ "dmd/backend/ti_achar.c", },
	// { "dmd/backend/md5.c", }, // old style prototypes
	{ "dmd/backend/cgobj.c", &patch_declspec },

	{ "dmd/backend/cc.h", },
	{ "dmd/backend/cdef.h", },
	{ "dmd/backend/bcomplex.h", },
	{ "dmd/backend/ty.h", },
	{ "dmd/backend/token.h", },
	{ "dmd/backend/rtlsym.h", },
	{ "dmd/backend/global.h", },
	{ "dmd/backend/el.h", },
	{ "dmd/backend/oper.h", },
	{ "dmd/backend/code.h", },
	{ "dmd/backend/type.h", },
	{ "dmd/backend/dt.h", },
	{ "dmd/backend/cgcv.h", },
	{ "dmd/backend/outbuf.h", },
	{ "dmd/backend/html.h", },
	{ "dmd/backend/parser.h", },
	{ "dmd/backend/tassert.h", },
	{ "dmd/backend/cv4.h", },
	{ "dmd/backend/go.h", },
	{ "dmd/backend/cpp.h", },
	{ "dmd/backend/exh.h", },
	{ "dmd/backend/iasm.h", },
+/
];

void setupVariables()
{
	PP.versionDefines ~= "DEBUG",
	PP.versionDefines ~= "DMDV1";
	PP.versionDefines ~= "DMDV2"; // allow early evaluation
	PP.versionDefines ~= "_DH";   // identifier ambiguous, also used by iasm_c
	PP.versionDefines ~= "LOG";
	PP.versionDefines ~= "LOGSEMANTIC";
}

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
	case "TOK":
	case "MATCH":
	case "dchar_t":
	case "opflag_t":
	case "regm_t":
	case "targ_size_t":
	case "tym_t":
	case "OPER":
	case "TY":
		return true;
	default:
		return false;
	}
}

bool isClassType(string ident)
{
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

string createImportAll(string filename, bool makefile)
{
	string path = dirName(filename);
	string ext = extension(filename)[1 .. $];
	string bname = filename[path.length + 1..$-ext.length-1];
	
	string txt;
	if (makefile)
		txt = "SRC = \\\n";
	else
	{
		txt = "module " ~ bname ~ ";\n\n";
		txt ~= "public import dmdport;\n\n";
	}

	foreach(ti; srcfiles)
	{
		string file = genOutFilename(ti.inputFile, 0);
		int pdot = lastIndexOf(file, '.');
		int pslash;
		if(makefile)
			pslash = firstPathSeparator(file);
		else
			pslash = max(lastIndexOf(file, '/'), lastIndexOf(file, '\\'));

		string mod = file[pslash+1 .. pdot];
		if(string *ps = mod in filenameMap)
			mod = *ps;

		if(!makefile)
		{
			mod = replace(mod, "/", ".");
			mod = replace(mod, "\\", ".");
		}

		if(makefile)
			txt ~= "\tdmdgen/" ~ mod ~ ".d \\\n";
		else
			txt ~= "public import " ~ mod ~ ";\n";
	}

	return txt;
}

string genOutFilename(string filename, int pass)
{
	string path = dirName(filename);
	string gendir = pass == 0 ? "dmdgen" : "gen" ~ format("%d", pass);
	string genpath = replace(path, "dmd", gendir);
	if(!exists(genpath))
		mkdirRecurse(genpath);

	string ext = extension(filename)[1 .. $];
	string bname = filename[path.length + 1..$-ext.length-1];

	if(pass == 0)
	{
		if(string *ps = bname in filenameMap)
			bname = *ps;

		if (ext != "h")
			bname ~= "_" ~ ext;
		bname ~= ".d";
	}
	else
	{
		bname = bname ~ "." ~ ext;
	}
	return genpath ~ sep ~ bname;
}

///////////////////////////////////////////////////////////////

class Source
{
	this(DmdGen dg, string filename)
	{
		this(dg, filename, cast(string) read(filename));
	}

	this(DmdGen dg, string filename, string text)
	{
		_tokenList = new TokenList;
		_dg = dg;
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

	void writeTokenList(string outfilename, string hdr, int pass)
	{
		string text;
		for(TokenIterator tokIt = _tokenList.begin(); !tokIt.atEnd(); ++tokIt)
		{
			Token tok = *tokIt;
			string mapped = pass > 0 ? tok.text : mapTokenText(tok);
			text ~= tok.pretext ~ mapped;
		}
		std.file.write(outfilename, hdr ~ text);
	}

	DmdGen _dg;
	string _filename;

	string _text;

	AST _ast;
	TokenList _tokenList;
}

///////////////////////////////////////////////////////////////

class DmdGen
{
	///////////////////////////////////////////////////////////////////////
	AST[][string] functionDeclarations;
	AST[][string] functionDefinitions;
	AST[][string] varDefinitions;
	Source[] sources;

	void registerFunctionDefinition(Declaration decl)
	{
		DeclClassification type = classifyDeclaration(decl);
		if(type == DeclClassification.FuncDefinition)
		{
			ToStringData tsd;
			tsd.noIdentifierInPrototype = true;
			string ident = decl.toString(tsd);
			if(ident in functionDefinitions)
				writefln("duplicate definition of " ~ ident);
			functionDefinitions[ident] ~= decl;
		}
		else if(type == DeclClassification.VarDeclaration || type == DeclClassification.VarDefinition)
		{
			ToStringData tsd;
			string ident = decl.toString(tsd);
			if(ident in varDefinitions)
				writefln("duplicate definition of " ~ ident);
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
			tokList.begin().text = "super";
		stmt.appendChild(ctorInit, tokList);
		stmt.end.insertBefore(createToken("", ";", Token.Semicolon, 0));

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
		
		while(initIt.children && !initIt.children.empty())
		{
			CtorInitializer initCtor = cast(CtorInitializer) *(initIt.children.begin());
			assert(initCtor);

			TokenList initList = initIt.removeChild(initCtor);

			string id = initList.begin().text;
			bool callSuper = AST.isBaseClass(id, className);
			Statement initStmt = convertCtorInitializerToStatement(initCtor, initList, callSuper);
			stmt.insertChildBefore(insertIt, initStmt, initList);
		}

		initIt._parent.removeChild(*initIt);
	}

	///////////////////////////////////////////////////////////////////////
	void removeScopeFromIdentifier(AST impl)
	{
		assert(impl.children && impl.children.count() >= 2);
		DeclVar declvar = cast(DeclVar) impl.children[1];
		assert(declvar);

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
		assert(cond.length > 0);
		assert(cond[0].children.count == 2); // expr + if, no else

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
				writefln("mutiple declarations for " ~ ident);
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
				writefln("no implementation for " ~ ident);
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
					writefln("no instantiation of " ~ ident);
					countNoImplementations++;
				}
			}
		}
	}

	void replaceFunctionDeclarationWithDefinition(Declaration decl, AST[] def, int indent, bool isStatic)
	{
		assert(def.length > 0);

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
			sameConditional = true;
			AST[] cond;
			getConditionals(def[0], cond);
			for(int d1 = 1; d1 < def.length; d1++)
			{
				AST[] condOther;
				getConditionals(def[d1], condOther);
				if(!compareASTs(cond, condOther))
					sameConditional = false;
			}

			if(sameConditional)
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
				reindentList(implList, 4 * indent, 8);

			if(conditional && sameConditional)
			{
				ASTIterator it = conditional.children.begin() + d + 1;
				AST cond = conditional;

				if((*it).start.type == Token.BraceL)
				{
					cond = *it;
					if(cond.children)
						it = cond.children.begin();
				}
				cond.insertChildBefore(it, impl, implList);
				if(!it.atEnd())
					cond.removeChild(*it);
			}
			else if(def.length > 1)
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

		foreach(Source src; sources)
		{
			src._ast.verify();
			iterateTopLevelDeclarations(src._ast, &moveMethods);
		}

		foreach(AST decl; declsToRemove)
			decl._parent.removeChild(decl, true);

		declsToRemove.length = 0;
	}

	///////////////////////////////////////////////////////////////////////
	void moveAllCtorInitializers()
	{
		foreach(Source src; sources)
		{
			src._ast.verify();
			iterateTopLevelDeclarations(src._ast, &moveCtorInitializers);
		}
	}

	///////////////////////////////////////////////////////////////////////
	void patchAllAST()
	{
		foreach(Source src; sources)
			patchAST(src._ast);
	}

	///////////////////////////////////////////////////////////////////////
	void writeFiles(int pass)
	{
		string hdr;
		if(pass == 0)
		{
			string importAllFile = "dmdgen/importall.d";
			string importAll = createImportAll(importAllFile, false);
			std.file.write(importAllFile, importAll);
			
			string srcAll = createImportAll(importAllFile, true);
			std.file.write("dmdgen/sources", srcAll);

			// hdr = "import importall;\n";
			hdr = "import dmdport;\n";
			hdr ~= "import importall;\n";
		}

		foreach(Source src; sources)
		{
			string outfile = genOutFilename(src._filename, pass);
			src.writeTokenList(outfile, hdr, pass);
		}
	}

	///////////////////////////////////////////////////////////////////////
	Source createSource(string currentfile, patch_fn patch)
	{
		Source src = new Source(this, currentfile);
		src.scan();
		src.fixConditionalCompilation();
		src.rescanPP();
		if(patch)
		{
			patch(src._tokenList);
			src.rescanPP();
		}

		if(currentfile.length)
		{
			string outfile = genOutFilename(currentfile, 1);
			src.writeTokenList(outfile, "", 1);
		}

		src.createAST();
		src._ast.verify();

		iterateTopLevelDeclarations(src._ast, &registerFunctionDefinition);
		return src;
	}

	///////////////////////////////////////////////////////////////////////
	int main(string[] argv)
	{
		int parsed = 0;
		int failed = 0;
		string currentfile;
		foreach(ref translateInfo ti; srcfiles)
		{
			parsed++;
			try
			{
				currentfile = ti.inputFile;
				writefln(currentfile);

				Source src = createSource(currentfile, ti.patch);
				sources ~= src;
			}
			catch(Exception e)
			{
				failed++;
				string msg = e.toString();
				if(startsWith(msg, currentfile))
					throw e;
				msg = currentfile ~ ": " ~ msg;
				writefln(msg);
				//throw new Exception(msg);
			}
		}

		writefln("%d of %d files failed to parse", failed, parsed);
		if(failed > 0)
		    return -1;

		moveAllMethods();
		moveAllCtorInitializers();
		writeFiles(2);

		patchAllAST();
		writeFiles(0);

		return 0;
	}
}

int main(string[] argv)
{
	try
	{
		setupVariables();
		AST.clearStatic();

		DmdGen dg = new DmdGen;
		return dg.main(argv);
	}
	catch(Exception e)
	{
		string msg = e.toString();
		writefln(msg);
	}
	catch(Error e)
	{
		string msg = e.toString();
		writefln(msg);
	}
	return -1;
}

///////////////////////////////////////////////////////////////////////

string testDmdGen(string txt, int countRemove = 1, int countNoImpl = 0, TokenList[string] defines = null)
{
	AST.clearStatic();

	TokenList tokenList = scanText(txt);

	PP pp = new PP;
	pp.fixConditionalCompilation(tokenList);
	pp.convertDefinesToEnums(tokenList);
	rescanPP(tokenList);

	if(defines)
	{
		expandPPdefines(tokenList, defines, MixinMode.ExpandDefine);
		rescanPP(tokenList);
	}

	AST ast = new AST(AST.Type.Module);
	TokenIterator tokIt = tokenList.begin();
	ast.parseModule(tokIt);
	ast.verify();

	DmdGen gen = new DmdGen;
	iterateTopLevelDeclarations(ast, &gen.registerFunctionDefinition);
	iterateTopLevelDeclarations(ast, &gen.moveMethods);
	assert(gen.countNoImplementations == countNoImpl);

	assert(gen.declsToRemove.length == countRemove);
	foreach(decl; gen.declsToRemove)
		decl._parent.removeChild(decl, true);
	ast.verify();

	iterateTopLevelDeclarations(ast, &gen.moveCtorInitializers);
	ast.verify();

	patchAST(ast);
	ast.verify();

	string res;
	for(TokenIterator it = tokenList.begin(); !it.atEnd(); ++it)
		res ~= it.pretext ~ mapTokenText(*it);

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
	    "static_if(1) {\n"
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
	    "static_if(1) {\n"
	    "type_t C::foo() { return 1; }\n"
	    "}\n"
	    "static_if(2) {\n"
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
	    "int b = ushort.sizeof;\n";

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
	    "    enum : int { ABC = 1 };\n"
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
	    "#if 0\n"
	    "    x = 0;\n"
	    "#endif\n"
	    "    y = 1;\n"
	    "}\n";
	string exp =
	    "class A : B {\n"
	    "    this() { super(1);\n"
	    "    static if(0) {\n"
	    "\tx = 0;\n"
	    "    }\n"
	    "\ty = 1;\n"
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
	    "int foo(ref int *x) {\n"
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
	    "enum unnamed_2 : int { e1, e2, e3 }\n"
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

	string res = testDmdGen(txt, 0, 2);
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
	string exp = "enum ENUM : int { kEnum };\n"
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
	string txt = "mixin(X(b));\n";
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
