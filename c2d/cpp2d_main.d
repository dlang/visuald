// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module c2d.cpp2d_main;

import c2d.cpp2d;
import c2d.ast;
import c2d.pp;
import c2d.tokutil;

import stdext.path;
import stdext.file;
import stdext.string;

import std.stdio;
import std.file;
import std.getopt;

///////////////////////////////////////////////////////////////////////

void patch_dmdv2(TokenList srctokens)
{
	replaceTokenSequence(srctokens, ["__version", "(", "DMDV2", ")", "{", "$1", ",", "}" ], [ "$1", "," ], true);
}

void patch_dmdv1(TokenList srctokens)
{
	replaceTokenSequence(srctokens, ["__version", "(", "DMDV1", ")", "{", "$1", "}" ], [ ], true);
}

void patch_disable_conditional(TokenList srctokens, string condition)
{
	replaceTokenSequence(srctokens, [ "__static_if", "(", condition, ")", "{", "$1", "}", "else", "{", "$2", "}" ], [ "$2" ], true);
	replaceTokenSequence(srctokens, [ "__static_if", "(", condition, ")", "{", "$1", "}" ], [ ], true);
}

void patch_enable_conditional(TokenList srctokens, string condition)
{
	replaceTokenSequence(srctokens, [ "__static_if", "(", condition, ")", "{", "$1", "}", "else", "{", "$2", "}" ], [ "$1" ], true);
	replaceTokenSequence(srctokens, [ "__static_if", "(", condition, ")", "{", "$1", "}" ], [ "$1" ], true);
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
	replaceTokenSequence(srctokens, [ "__static_if", "(", "__DMC__", ")", "{", "__in", "$1", "__body", "}" ],
	                                [ "__in", "$1", "__body" ], true);
	replaceTokenSequence(srctokens, [ "__static_if", "(", "__DMC__", ")", "{", "__out", "$1", "__body", "}" ],
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
	TokenList[string] defines2 = [ "DUMP" : null  ];
	expandPPdefines(srctokens, defines2, MixinMode.ExpandDefine);
}

void patch_mtype_h(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "struct TypeTuple : Type { $decl };",
	                                "struct TypeTuple : Type { $decl\n"
	                                "#if 0\n"
	                                "    Type *makeConst();\n"
	                                "#endif\n"
	                                "};", true);
	replaceTokenSequence(srctokens, "(Loc loc = 0)",
	                                "(Loc loc = Loc(0))\n", true);
	replaceTokenSequence(srctokens, "typedef union tree_node TYPE;", "", true);

	string[string] defines = [ "^t.*$" : "static Type* $id() { return $text; }" ];
	regexReplacePPdefines(srctokens, defines);
}

void patch_doc_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "unsigned char ddoc_default", "char ddoc_default", true);
	patch_dmdv1(srctokens);
}

void patch_mars_h(TokenList srctokens)
{
	patch_dmdv2(srctokens);
	replaceTokenSequence(srctokens, "template <typename TYPE> struct ArrayBase;", "", true);
}

void patch_mars_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "written", "=", "$std", "__static_if", "(", "TARGET_NET", ")", "{", "$net", "}" ],
	                                [ "\n__static_if(TARGET_NET) {\n    written = ", "$std", "$net", 
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

void patch_intrange_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "__static_if(PERFORM_UNITTEST) { $1 }", "", true);
	patch_operators(srctokens);
}

void patch_intrange_h(TokenList srctokens)
{
	patch_operators(srctokens);
}

void patch_module_c(TokenList srctokens)
{
	// we don't handle different protoypes for the same function
	replaceTokenSequence(srctokens, [ "__static_if", "(", "IN_GCC", ")", "{", "void", "Module", "::", "parse", "$if", 
	                                  "}", "else", "{", "$else", "}" ], 
					[ "void Module::parse", "$if" ], true);
}

void patch_module_h(TokenList srctokens)
{
	// we don't handle different protoypes for the same function
	replaceTokenSequence(srctokens, [ "__static_if", "(", "IN_GCC", ")", "{", "void", "parse", "$if", 
	                                  "}", "else", "{", "$else", "}" ], 
					[ "void parse", "$if" ], true);
}

void patch_statement_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "char fntab[9][3]", "const char *fntab[9]", true);
}

void patch_inifile_c(TokenList srctokens)
{
	// missing statement after label
	replaceTokenSequence(srctokens, "Letc:", "Letc:;", true);
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
	replaceTokenSequence(srctokens, [ "__static_if", "(", "STRUCTTHISREF", ")", "{", "$1", ",", "}", "else", "{", "$2", ",", "}" ], 
					[ "__static_evalif(STRUCTTHISREF)(", "$1", ", ", "$2", ")", "," ], true);
	replaceTokenSequence(srctokens, [ "__static_if", "(", "STRUCTTHISREF", ")", "{", "$1", "}", "else", "{", "$2", "}" ], 
					[ "__static_evalif(STRUCTTHISREF)(", "$1", ", ", "$2", ")" ], true);
}

void postpatch_entity_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "static NameId* namesTable[] = { $data }",
						 "NameId[][] namesTable; static this() { namesTable = [ $data ]; }", true);
}

void patch_class_c(TokenList srctokens)
{
	// defineRef never declared in class
	replaceTokenSequence(srctokens, [ "ClassDeclaration", "::", "defineRef" ], [ "ClassDeclaration__defineRef" ], true);
}

void patch_async_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "__static_if", "(", "_WIN32", ")", "{", "$1", "}", "else", 
									  "__static_if", "(", "linux",  ")", "{", "$2", "}", "else", "{", "$3", "}" ], [ "$3" ], true);
	//patch_disable_conditional(srctokens, "_WIN32");
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
	replaceTokenSequence(srctokens, "Type *tn; __static_if(!0) goto $label; if($ifexpr) $label2: $stmt tb2->nextOf();",
	                                "Type *tn;\n"
					"    $stmt tb2->nextOf();\n"
					"__static_if(0)\n"
					"    if($ifexpr)\n"
					"        goto $label; else goto L_never; else $label:", true);
	replaceTokenSequence(srctokens, "else __static_if(0) {", "__static_if(0) { L_never:", true);
}

// root/tk
void patch_port_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "std", "::", "numeric_limits", "$1", "infinity", "(", ")" ], [ "INFINITY" ], true);
}

void patch_root_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "return this - obj;", "return (char*)this - (char*)obj;", true);
	patch_disable_conditional(srctokens, "_MSC_VER");
}

void patch_root_h(TokenList srctokens)
{
	patch_virtual_dtor(srctokens);
	replaceTokenSequence(srctokens, [ "unsigned", "short" ], [ "wchar_t" ], true);
	replaceTokenSequence(srctokens, "operator[]", "opIndex", true);
	// remove forward reference
	replaceTokenSequence(srctokens, "template <typename TYPE> struct ArrayBase;", "", true);
}

void patch_operators(TokenList srctokens)
{
	replaceTokenSequence(srctokens, "operator[]", "opIndex", true);
	replaceTokenSequence(srctokens, "operator==", "opEquals", true);
	replaceTokenSequence(srctokens, "operator!=", "opNotEquals", true);
	replaceTokenSequence(srctokens, "operator<", "opLess", true);
	replaceTokenSequence(srctokens, "operator>", "opGreater", true);
	replaceTokenSequence(srctokens, "operator<=", "opLessEqual", true);
	replaceTokenSequence(srctokens, "operator>=", "opGreaterEqual", true);
	replaceTokenSequence(srctokens, "operator-()", "opNeg()", true);
	replaceTokenSequence(srctokens, "operator+", "opAdd", true);
	replaceTokenSequence(srctokens, "operator-", "opSub", true);
	replaceTokenSequence(srctokens, "operator*", "opMul", true);
	replaceTokenSequence(srctokens, "operator/", "opDiv", true);
	replaceTokenSequence(srctokens, "operator%", "opMod", true);
	replaceTokenSequence(srctokens, "operator++()", "opPostInc()", true);
	replaceTokenSequence(srctokens, "operator<<", "opShl", true);
	replaceTokenSequence(srctokens, "operator>>", "opShr", true);
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
	replaceTokenSequence(srctokens, [ "__static_if", "(", "!", "assert", ")", "{", "$1", "}" ], [ ], true);
	patch_declspec(srctokens);

	replaceTokenSequence(srctokens, [ "__static_if", "(", "!", "list_freelist", ")", "{", "$1", "}" ], [ "$1" ], true);
	replaceTokenSequence(srctokens, [ "__static_if", "(", "!", "list_new", ")", "{", "$1", "}" ], [ "$1" ], true);

	patch_disable_conditional(srctokens, "MEM_DEBUG");
	patch_disable_conditional(srctokens, "__DMC__");
	patch_enable_conditional(srctokens, "__cplusplus");
	patch_va_arg(srctokens);
}

void patch_filespec_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "__static_if", "(", "!", "assert", ")", "{", "$1", "}" ], [ ], true);
}

void patch_vec_c(TokenList srctokens)
{
	replaceTokenSequence(srctokens, [ "__static_if", "(", "!", "assert", ")", "{", "$1", "}" ], [ ], true);
	replaceTokenSequence(srctokens, ", __static_if(__INTSIZE == 4) { $1 }", ", $1", true);
	replaceTokenSequence(srctokens, "__static_if(__SC__ <= 0x610) { $1 }", "", true);
	patch_declspec(srctokens);
	replaceTokenSequence(srctokens, "_asm { __static_if($COND1) { $asm1 } else __static_if($COND2) { $asm2 } else { $asm3 } }",
	                                "__static_if($COND1) {\n"
	                                "    _asm { $asm1 }\n"
	                                "} else __static_if($COND2) {\n"
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
	replaceTokenSequence(srctokens, "assnod = (elem **) __static_if(TX86) { $1 } else { $2 }",
	                                "\n__static_if(TX86) {\n\t\t\tassnod = (elem **) $1\n"
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

translateInfo srcfiles[] =
[
	{ "dmd/lexer.h", &patch_lexer_h },
	{ "dmd/lexer.c", &patch_lexer_c },

	{ "dmd/expression.h", &patch_expression_h },
	{ "dmd/expression.c", &patch_expression_c },
	{ "dmd/doc.c", &patch_doc_c },
	{ "dmd/doc.h", },
	{ "dmd/mars.h", &patch_mars_h },
	{ "dmd/arraytypes.h", },
	{ "dmd/macro.h", },
	{ "dmd/template.h", },
	{ "dmd/aggregate.h", },
	{ "dmd/declaration.h", },
	{ "dmd/dsymbol.h", },
	{ "dmd/mtype.h", &patch_mtype_h },
	{ "dmd/identifier.h", },
	{ "dmd/intrange.h", &patch_intrange_h },
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
	{ "dmd/inifile.c", &patch_inifile_c },
	{ "dmd/typinf.c", },
	{ "dmd/irstate.h", },
	{ "dmd/module.c", &patch_module_c },
	{ "dmd/scope.c", },
	{ "dmd/dump.c", },
	{ "dmd/cond.c", &patch_dmdv2 },
	{ "dmd/inline.c", },
	{ "dmd/intrange.c", &patch_intrange_c },
	{ "dmd/opover.c", },
	{ "dmd/entity.c", null, &postpatch_entity_c },
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
	// { "dmd/msc.c", },
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
//	{ "dmd/bit.c", },
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
	//{ "dmd/root/lstring.c", &patch_lstring_c },
	{ "dmd/root/array.c", &patch_array_c },
	{ "dmd/root/gnuc.h", },
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
	//{ "dmd/root/lstring.h", &patch_lstring_h },
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

///////////////////////////////////////////////////////////////
// dmd specific setup
void setupDmd()
{
	if("param_t" in tokenMap)
		return; // don't need to do it twice

	tokenMap["param_t"]	 = "PARAM";
	tokenMap["STATIC"]	 = "private";
	tokenMap["CEXTERN"]	 = "extern";
	tokenMap["finally"]	 = "dmd_finally";
	tokenMap["Object"]	 = "dmd_Object";
	tokenMap["TypeInfo"] = "dmd_TypeInfo";
	tokenMap["toString"] = "dmd_toString";
	tokenMap["main"]	 = "dmd_main";
	tokenMap["string"]	 = "dmd_string";
	tokenMap["hash_t"]	 = "dmd_hash_t";
	tokenMap["File"]	 = "dmd_File";

	PP.versionDefines["DEBUG"] = true;
	PP.versionDefines["DMDV1"] = true;
	PP.versionDefines["DMDV2"] = true; // allow early evaluation
	PP.versionDefines["_DH"] = true;   // identifier ambiguous, also used by iasm_c
	PP.versionDefines["LOG"] = true;
	PP.versionDefines["LOGSEMANTIC"] = true;
	PP.versionDefines["IN_GCC"] = true;

	PP.expandConditionals["0"] = false;
	PP.expandConditionals["1"] = true;
	PP.expandConditionals["DMDV1"] = false;
	PP.expandConditionals["DMDV2"] = true;
	PP.expandConditionals["_DH"]   = false;
	PP.expandConditionals["IN_GCC"] = true;
}

///////////////////////////////////////////////////////////////
class StdIo_Cpp2DConverter : Cpp2DConverter
{
	override void writemsg(string s)
	{
		writeln(s);
	}
}

///////////////////////////////////////////////////////////////
int main(string[] argv)
{
	bool dmd;
	string cfg_path;

	getopt(argv, 
		   "dmd", &dmd,
		   "config", &cfg_path);

	Cpp2DConverter dg = new StdIo_Cpp2DConverter;
	if(dmd)
	{
		setupDmd();
		AST.clearStatic();
		return dg.main_dmd(srcfiles);
	}


	C2DIni ini;
	if(cfg_path.length)
	{
		ini.readFromFile(cfg_path);
		ini.toC2DOptions(/*c2d.cpp2d.*/options);
	}
	else if(argv.length <= 1)
	{
		writeln("usage: ", argv[0], " [-dmd|-config file.ini] [files...]");
		return -1;
	}
	string[] filespecs;
	string workdir;
	if(argv.length > 1)
	{
		filespecs = argv[1..$];
		workdir = normalizeDir(getcwd());
	}
	else
	{
		filespecs = tokenizeArgs(ini.inputFiles);
		workdir = ini.inputDir;
	}
	string[] files = expandFileList(filespecs, workdir);
	if(files.length)
		return dg.main(files);
	writeln("no input files.");
	return -1;
}

///////////////////////////////////////////////////////////////
extern(C) void D3c2d5cpp2d12__unittest48FZv();
extern extern(C) __gshared ModuleInfo D3c2d5cpp2d12__ModuleInfoZ;

unittest
{
	ModuleInfo* info = &D3c2d5cpp2d12__ModuleInfoZ;
	if(auto test = info.unitTest())
		test();
	void* p = cast(void*) &D3c2d5cpp2d12__unittest48FZv;
}

///////////////////////////////////////////////////////////////
extern extern(C) __gshared ModuleInfo D4core3sys7windows10stacktrace12__ModuleInfoZ;

void disableStacktrace()
{
	ModuleInfo* info = &D4core3sys7windows10stacktrace12__ModuleInfoZ;
	if (info.isNew)
	{
		enum
		{
			MItlsctor    = 8,
			MItlsdtor    = 0x10,
			MIctor       = 0x20,
			MIdtor       = 0x40,
			MIxgetMembers = 0x80,
		}
		if (info.n.flags & MIctor)
		{
			size_t off = info.New.sizeof;
			if (info.n.flags & MItlsctor)
				off += info.o.tlsctor.sizeof;
			if (info.n.flags & MItlsdtor)
				off += info.o.tlsdtor.sizeof;
			if (info.n.flags & MIxgetMembers)
				off += info.o.xgetMembers.sizeof;
			*cast(typeof(info.o.ctor)*)(cast(void*)info + off) = null;
		}
	}
	else
		info.o.ctor = null;
}

shared static this() 
{
	disableStacktrace();
}

