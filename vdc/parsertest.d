// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.parsertest;

version(MAIN)
{

import vdc.util;
import vdc.semantic;
import vdc.lexer;
import vdc.logger;
import vdc.parser.engine;
import vdc.parser.mod;

import ast = vdc.ast.all;

import std.exception;
import std.stdio;
import std.string;
import std.conv;
import std.file;
import std.path;

import core.runtime;

version = semantic;
//version = cpp;
version = run;

////////////////////////////////////////////////////////////////

ast.Node parse(TokenId[ ] tokens)
{
	Parser p = new Parser;
	p.pushState(&Module.enter);
	
	foreach(tok; tokens)
	{
		p.lexerTok.id = tok;
		p.shift(p.lexerTok);
	}
	
	if(!p.shiftEOF())
		return null;
	
	return p.popNode();
}

version(none)
unittest
{
	TokenId[] tokens = [ TOK_Identifier, TOK_assign, TOK_null ];
	Node n = parse(tokens);
	assert(n);
	n.print(0);

	tokens = [ TOK_Identifier, TOK_assign, TOK_null, TOK_addass, TOK_this ];
	n = parse(tokens);
	assert(n);
	n.print(0);
	
	tokens = [ TOK_Identifier, TOK_min,  TOK_null, TOK_add,      TOK_this ];
	n = parse(tokens);
	assert(n);
	n.print(0);
}

void testParse(string txt, string filename = "")
{
	Parser p = new Parser;
	ast.Node n;
	try
	{
		p.filename = filename;
		n = p.parseModule(txt);
	}
	catch(ParseException e)
	{
		writeln(e.msg);
		return;
	}

	debug
	{
	string app;
	DCodeWriter writer = new DCodeWriter(getStringSink(app));
	writer(n);

	version(log)
	{
		writeln("########################################");
		writeln(app);
		writeln(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>");
	}

	if(filename.length)
	{
		string ofile1 = "c:/tmp/d/a1/" ~ basename(filename);
		std.file.write(ofile1, app);
	}
	
	p.filename = filename ~ "_D";
	ast.Node n2 = p.parseModule(app);

version(all)
{	
	bool eq = n.compare(n2);
	assert(eq);
}
else
{
	string app2;
	DCodeWriter writer2 = new DCodeWriter(getStringSink(app2));
	writer2(n2);
	
	if(filename.length)
	{
		string ofile2 = "c:/tmp/d/a2/" ~ basename(filename);
		std.file.write(ofile2, app2);
	}
	
	for(int i = 0; i < app.length && i < app2.length; i++)
		if(app[i] != app2[i])
		{
			string a1 = app[i..$];
			string a2 = app2[i..$];
			assert(a1 == a2);
		}
	assert(app == app2);
	}
}

	string app3;
	CCodeWriter writer3 = new CCodeWriter(getStringSink(app3));
	writer3.writeNode(n);

	if(filename.length)
	{
		string ofile3 = "c:/tmp/d/c1/" ~ basename(filename);
		writeln(ofile3);
		std.file.write(ofile3, app3);
	}
}

void testSemantic(string txt, string filename = "")
{
	logInfo("### testSemantic " ~ filename ~ " ###");
	
	Project prj = new Project;
	auto mod = prj.addText(filename, txt);
	assert(mod);
	prj.semantic();
	assert(prj.countErrors + semanticErrors == 0);
}

version(all) unittest
{
	//Node n = p.parseModule("a = b + c * 4 - 6");
	//n.print(0);
	//p.parseModule("a, b, c = (1 ? 2 : 3 || d && 5 ^ *x)[3 .. 5]").print(0);

	string txt = q{
void fn()
{
		auto bar()(int x)
		{
			return 5 + x;
		}
		
	typeof(x)();
	extern (C) int Foo1;
	
		(x, y){ return x; };
	assert(!__traits(compiles, immutable(S43)(3, &i)));
	assert(ti.tsize==(void*).sizeof);
}

private static extern (C)
{
	shared char* function () uloc_getDefault;
}
		C14 c = new class C14 { };
		mixin typeof(c).m d;
		typeof(s).Foo j;

		size_t vsize = void.sizeof;

const const(int)* ptr() { return a.ptr; }

		mixin Foo!(uint);
		
		import id = std.imp;

		myint foo(myint x = myint.max)
		{}
		
		int[] x = 0.0 + (4 - 5);
		pure:
			synchronized
			{
				void y;
			}
		mixin(test);
		
		enum ENUM { a = 1, b = 2 }
		
		const(int) i = 4;
		const int j = 4;
	};
	testParse(txt, "unittest1");
}

unittest
{
	string txt = q{
		int y;
		int x;
	};
	testParse(txt, "unittest2");
}

unittest
{
	string txt = q{
		void main(string[] argv)
		{
			return;
			return 1;
			
			break;
			break wusel;
			while(1)
				mixin(argv[0]);
		}
	};
	testParse(txt, "unittest3");
}

unittest
{
	string txt = q{
		class A : public B, private C, D
		{
			int x;
			int[] y;
		}
	};
	testParse(txt, "unittest4");
}

unittest
{
	string txt = q{
		public alias uint AReserved;
		private typedef uint TReserved;
	};
	testParse(txt, "unittest5");
}

unittest
{
	string txt = q{
		void foo() {
			if(a * b * 2) {}
		}
	};
	testParse(txt, "unittest6");
}

unittest
{
	string txt = q{
		version(all)
		{
		version(v1):
		version(v2):
		}
		static if(true):
		pragma(msg,"static if(true)");

		static if(false):
		pragma(msg,"static if(false)");
	};
	testParse(txt, "unittest7");
}

///////////////////////////////////////////////////////////////////////
int[] ctfeLexer(string s)
{
	Lexer lex;
	int state;
	uint pos;
	
	int[] ids;
	while(pos < s.length)
	{
		uint prevpos = pos;
		int id;
		int type = lex.scan(state, s, pos, id);
		assert(prevpos < pos);
		if(!Lexer.isCommentOrSpace(type, s[prevpos .. pos]))
			ids ~= id;
	}
	return ids;
}

unittest
{
	static assert(ctfeLexer(q{int /* comment to skip */ a;}) == [ TOK_int, TOK_Identifier, TOK_semicolon ]);
}
///////////////////////////////////////////////////////////////////////
unittest
{
	string txt = q{
		class Adapter
		{
			int func() { return 73; }
		}
		class Foo46
		{
			class AnonAdapter : Adapter {}

			void func()
			{
				Adapter a = new AnonAdapter();
				return a.func();
			}
		}
		static assert((new Foo46).func() == 73);
	};
	testSemantic(txt, "adapter");
}

unittest
{
	string txt = q{
		int foo(alias a)(){ return a; }
		int x = 3;
		static assert(foo!(x)() == 3);
	};
	testSemantic(txt, "template_func");
}

unittest
{
	string txt = q{
		static assert((5^15) == 10);
		static assert(5 < 7);
		static assert(15 > 7);
		static assert(5 <= 7);
		static assert(15 >= 7);
		static assert(7 == 7);
		static assert(5 != 7);
		static assert(5 << 2 == 20);
		static assert(5 >> 1 == 2);
		static assert(5 >>> 1 == 2);
		static assert(5 + 2 == 7);
		static assert(5 - 2 == 3);
		static assert(5 * 2 == 10);
		static assert(5 / 2 == 2);
		static assert(5 % 2 == 1);
		static assert(3^^3 == 27);
		static assert(-3^^2 == -9);
		static assert((5 & 3) == 1);
		static assert((5 | 3) == 7);
		static assert((5 && 0) == false);
		static assert((0 || 5) == true);
		static assert(~0 == -1);
		static assert(!false == true);
		static assert((1 == 2 ? 5 : 3) == 3);

		static assert(1 + 2 == 3);
		static assert(1.0 + 2.5 == 3.5);
		static assert(1 + 2.5 == 3.5);
		// static assert(1 ~ 2 == 12);
		static assert("1" ~ "2" == "12");
		static assert("1" ~ '2' == "12");
	};
	testSemantic(txt, "ctfe_operators");
}

unittest
{
	string txt = q{
		static assert(x == 3);
		mixin(mix);
		string mix = "int x = 3;";

		int y = foo() + mixin("3");

		int foo()
		{
			mixin("return 4;");
		}
		static assert(y == 7);
	};
	testSemantic(txt, "forward_mixin");
}

unittest
{
	string txt = q{
		float fac(float x)
		{
			if(x <= 1)
				return x;
			float y = x - 1;
			return x * fac(y);
		}

		static assert(fac(3) == 6);
	};
	testSemantic(txt, "ctfe_fac");
}
	
unittest
{
	string txt = q{
		static if(int.sizeof == 4)
		{
			alias int ssize_t;
		}
		else
		{
			alias long ssize_t;
		}

		static assert(ssize_t.stringof == "int");
	};
	testSemantic(txt, "static_if");
}
	
unittest
{
	string txt = q{
		string foo()
		{
			string s = "";
			char i = 'A';
			while(true)
			{
				s ~= i;
				++i;
				if(i > 'K')
					break;
			}
			return s;
		}

		static assert(foo() == "ABCDEFGHIJK");
	};
	testSemantic(txt, "while");
}
	
unittest
{
	string txt = q{
		struct Abc9
		{
			int bar(int x)
			{
				Abc9 *foo() { return &this; }

				Abc9 *p = foo();
				assert(p == &this);
				return 4 + x;
			}
		}
		static assert(Abc9().bar(3) == 7);
	};
	testSemantic(txt, "nested");
}
		
unittest
{
	string txt = q{
		int bar2(int a)
		{
			static int c = 4;
			int foo(int b) { return b + c + 1; }
			return foo(a);
		}
		static assert(bar2(3) == 8);
	};
	testSemantic(txt, "static");
}
	//alias 4 test;
	//uint[test] arr;
	//pragma(msg,arr.sizeof);

///////////////////////////////////////////////////////////////////////

import core.exception;
import std.file;
	
int main(string[] argv)
{
	Runtime.traceHandler = null;
	
	Project prj = new Project;

	foreach(file; argv[1..$])
	{
		if(indexOf(file, '*') >= 0 || indexOf(file, '?') >= 0)
		{
			string path = dirname(file);
			string pattern = basename(file);
			foreach(string name; dirEntries(path, SpanMode.depth))
				if(fnmatch(basename(name), pattern))
					prj.addFile(name);
		}
		else
		{
			prj.addFile(file);
		}
	}
	version(semantic)
		prj.semantic();
	
	version(cpp)
	{
		prj.writeCpp("c:/tmp/d/cproject.cpp");
	}
	version(run)
	{
		prj.run();
	}
	writeln(prj.countErrors + semanticErrors, " errors");
	return prj.countErrors + semanticErrors > 0 ? 1 : 0;
}
}

