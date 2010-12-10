// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module simpleparser;

import std.exception;
import std.string;

import simplelexer;

version(MAIN)
{
import std.stdio;
debug = log;
}
else // !version(MAIN)
{
import sdk.vsi.sdk_shared;

import logutil;
//debug = log;
alias logCall writeln;
}

debug(log) import std.conv;

// very simple parser, just checking curly braces and statement/declaration boundaries
// we are mainly interested in finding the matching else to if, version and debug statements
/* Grammar:

Module:
	Statements

Statements:
	Statement
	Statement Statements

Statement:
	IfStatement
	VersionStatement
	DebugStatement
	ScopedStatement
	;
	OtherToken Statement

ScopedStatement:
	{ }
	{ Statements }

IfStatement:
	if(Expression) Statement
	if(Expression) Statement else Statement

VersionStatement:
	version(Expression) Statement
	version(Expression) Statement else Statement

DebugStatement:
	debug(Expression) Statement
	debug(Expression) Statement else Statement

Expression:
	BracedExpression
	BracedExpression Expression
	NonBraceToken Expression

BracedExpression:
	( Expression )
	[ Expression ]
	ScopedStatement

OtherToken:    anything but '{', ';', if, version, debug (might also exclude ')', ']', '}')
NonBraceToken: anything but '{', '(', '[' (might also exclude ')', ']', '}')
*/

struct ParserSpan
{
	int iStartIndex; // starting character index within the line (must be <= length of line)
	int iStartLine;  // starting line
	int iEndIndex;   // ending character index within the line (must be <= length of line)
	int iEndLine;    // ending line
}

struct ParserToken(S)
{
	S          text;
	int        type;
	int        id;
	ParserSpan span;
};

debug(log)
string logString(ref ParserSpan span)
{
	if(span.iStartLine == 0 && span.iEndLine == 0)
		return "[" ~ to!string(span.iStartIndex) ~ "," ~ to!string(span.iEndIndex) ~ "]";

	return "[" ~ to!string(span.iStartLine) ~ ":" ~ to!string(span.iStartIndex) 
		 ~ "," ~ to!string(span.iEndLine)   ~ ":" ~ to!string(span.iEndIndex) ~ "]";
}

// returns < 0 if adr1 < adr2
int compareTextAddress(int line1, int index1, int line2, int index2)
{
	int difflines = line1 - line2;
	if(difflines != 0)
		return difflines;
	return index1 - index2;
}

int compareStartAddress(ref const(ParserSpan) span, int line, int index)
{
	return compareTextAddress(span.iStartLine, span.iStartIndex, line, index);
}

int compareEndAddress(ref const(ParserSpan) span, int line, int index)
{
	return compareTextAddress(span.iEndLine, span.iEndIndex, line, index);
}

bool spanContains(ref const(ParserSpan) span, int line, int index)
{
	return compareStartAddress(span, line, index) <= 0 && compareEndAddress(span, line, index) > 0;
}

bool spanEmpty(ref const(ParserSpan) span)
{
	return span.iStartLine == span.iEndLine && span.iStartIndex == span.iEndIndex;
}

//////////////////////////////////////////////////////////////
class LocationBase(S)
{
	alias ParserBase!S Parser;
	alias LocationBase!S Location;
	
	Location parent;
	Location[] children;
	
	ParserSpan span;
	
	this(Location _parent, ParserSpan _span)
	{
		span.iStartLine  = span.iEndLine  = _span.iStartLine;
		span.iStartIndex = span.iEndIndex = _span.iStartIndex;
		parent = _parent;
	}
	
	mixin template ForwardConstructor()
	{
		this(Location _parent, ParserSpan _span)
		{
			super(_parent, _span);
		}
	}

	void extendSpan(ref ParserSpan _span)
	{
		span.iEndLine = _span.iEndLine;
		span.iEndIndex = _span.iEndIndex;
	}
	void limitSpan(ref ParserSpan _span)
	{
		span.iEndLine = _span.iEndLine;
		span.iEndIndex = _span.iEndIndex;
	}
	void clearSpan()
	{
		span.iEndLine = span.iStartLine;
		span.iEndIndex = span.iStartIndex;
	}
	
	// return true if token consumed
	abstract bool shift(Parser parser, ref ParserToken!S tok);
	
	// return true if reduce should not be called on parent 
	bool reduce(Parser parser, Location loc)
	{
		extendSpan(loc.span);
		return true;
	}
	
	bool isStatement()
	{
		return true;
	}
}

class Module(S) : LocationBase!S
{
	this()
	{
		ParserSpan _span;
		super(null, _span);
	}
	
	override bool shift(Parser parser, ref ParserToken!S tok)
	{
		Location loc;
		switch(tok.id)
		{
			case TOK_rparen:
			case TOK_rbracket:
			case TOK_rcurly: // mismatched brace - do not create statement, it will reduce on them, just eat away
				return true;
			case TOK_if:
				loc = new IfStatement!S(this, tok.span);
				break;
			case TOK_version:
				loc = new VersionStatement!S(this, tok.span);
				break;
			case TOK_debug:
				loc = new DebugStatement!S(this, tok.span);
				break;
			default:
				Statement!S stmt = new Statement!S(this, tok.span);
				parser.push(stmt);
				return false;
		}
		parser.push(loc);
		return false;
	}
}

// children are braced sub expressions, the last child might be a trailing statement as in
//  scope(exit) { foo() }
class Statement(S) : LocationBase!S
{
	mixin ForwardConstructor;

	override bool shift(Parser parser, ref ParserToken!S tok)
	{
		Location loc;
		switch(tok.id)
		{
			case TOK_if:
				loc = new IfStatement!S(this, tok.span);
				break;
			case TOK_version:
				loc = new VersionStatement!S(this, tok.span);
				break;
			case TOK_debug:
				loc = new DebugStatement!S(this, tok.span);
				break;
			case TOK_lcurly:
				loc = new CurlyBracedStatement!S(this, tok.span);
				break;
			case TOK_lbracket:
				loc = new SquareBracedExpression!S(this, tok.span);
				break;
			case TOK_lparen:
				loc = new RoundBracedExpression!S(this, tok.span);
				break;
			case TOK_rparen:
			case TOK_rbracket:
			case TOK_rcurly: // mismatched brace - bail out
				parser.reduce();
				return false;
			case TOK_semicolon:
				extendSpan(tok.span);
				parser.reduce();
				return true;
				
			default:
				extendSpan(tok.span);
				return true;
		}
		parser.push(loc);
		return false;
	}

	override bool reduce(Parser parser, Location loc)
	{
		super.reduce(parser, loc);
		return !loc.isStatement(); // statement always trails
	}
	
}

class BracedStatement(S, int openid, int closeid) : LocationBase!S
{
	mixin ForwardConstructor;

	override bool shift(Parser parser, ref ParserToken!S tok)
	{
		if(spanEmpty(span))
		{
			extendSpan(tok.span);
			assert(tok.id == openid);
			return true;
		}
		extendSpan(tok.span);
		if(tok.id == closeid)
		{
			parser.reduce();
			return true;
		}
		if(tok.id == TOK_rcurly || tok.id == TOK_rbracket || tok.id == TOK_rparen)
		{
			// mismatched brace - bail out
			parser.reduce();
			return false;
		}
		Statement!S stmt = new Statement!S(this, tok.span);
		parser.push(stmt);
		return false;
	}
}

class CurlyBracedStatement(S) : BracedStatement!(S, TOK_lcurly, TOK_rcurly)
{
	mixin ForwardConstructor;
}

class SquareBracedExpression(S) : BracedStatement!(S, TOK_lbracket, TOK_rbracket)
{
	mixin ForwardConstructor;

	bool isStatement()
	{
		return false;
	}
}

class RoundBracedExpression(S) : BracedStatement!(S, TOK_lparen, TOK_rparen)
{
	mixin ForwardConstructor;

	bool isStatement()
	{
		return false;
	}
}

class IfDebugVersionStatement(S, string keyword) : LocationBase!S
{
	mixin ForwardConstructor;

	override bool shift(Parser parser, ref ParserToken!S tok)
	{
		if(spanEmpty(span))
		{
			assert(tok.text == keyword);
			extendSpan(tok.span);
			return true;
		}
		
		if(children.length == 0)
		{
			if(tok.id != TOK_lparen)
			{
				if(keyword == "debug" && tok.id != TOK_assign)
				{
					ParserSpan sp = ParserSpan(tok.span.iStartIndex, tok.span.iStartLine, 
											   tok.span.iStartIndex, tok.span.iStartLine);
					children ~= new RoundBracedExpression!S(this, sp);
					goto then_statement;
				}
				// bail out, it's a standard statement
				parser.replace(new Statement!S(parent, span));
				return false;
			}
			extendSpan(tok.span);
			Location loc = new RoundBracedExpression!S(this, tok.span);
			parser.push(loc);
			return false;
		}
		if(children.length == 1)
		{
then_statement:
			extendSpan(tok.span);
			Statement!S stmt = new Statement!S(this, tok.span);
			parser.push(stmt);
			return false;
		}
		if(children.length == 2)
		{
			if(tok.id != TOK_else)
			{
				parser.reduce();
				return false;
			}
			extendSpan(tok.span);
			Statement!S stmt = new Statement!S(this, tok.span);
			parser.push(stmt);
			return true;
		}
		parser.reduce();
		return false;
	}

	bool reduce(Parser parser, Location loc)
	{
		super.reduce(parser, loc);
		return (children.length <= 2); // always continue reduce after else statement
	}
}

class IfStatement(S) : IfDebugVersionStatement!(S, "if")
{
	mixin ForwardConstructor;
}

class VersionStatement(S) : IfDebugVersionStatement!(S, "version")
{
	mixin ForwardConstructor;
}

class DebugStatement(S) : IfDebugVersionStatement!(S, "debug")
{
	mixin ForwardConstructor;
}

//////////////////////////////////////////////////////////////
class ParserBase(S = string)
{
	alias ParserBase!S Parser;
	alias LocationBase!S Location;
	
	Location[] stack;

	this()
	{
	}

	void shift(ref ParserToken!S tok)
	{
		if(stack.length == 0)
			stack ~= new Module!S;
		
		debug(log) writeln(repeat(" ", stack.length), "shift ", tok.text, " ", logString(tok.span));
		while(!stack[$-1].shift(this, tok)) {}
	}

	void reduce()
	{
		Location loc;
		do
		{
			loc = pop();
			enforce(loc.parent, "parser location has no parent");
		} while(!loc.parent.reduce(this, loc));
	}
	
	void push(Location loc)
	{
		debug(log) writeln(repeat(" ", stack.length), "push ", loc);
		assert(stack.length > 0);
		assert(loc.parent == stack[$-1]);
		stack[$-1].children ~= loc;
		stack ~= loc;
	}

	Location pop()
	{
		enforce(stack.length, "parser stack empty");
		Location loc = stack[$-1];
		stack = stack[0..$-1];
		debug(log) writeln(repeat(" ", stack.length), "pop ", loc, " ", logString(loc.span));
		return loc;
	}

	void replace(Location loc)
	{
		debug(log) writeln(repeat(" ", stack.length), "replace ", loc);
		Location prev = pop();
		assert(stack.length > 0);
		assert(stack[$-1].children.length > 0);
		assert(stack[$-1].children[$-1] == prev);
		stack[$-1].children = stack[$-1].children[0..$-1];
		push(loc);
	}
	
	// throw away anything that is later than the given address
	bool prune(ref int line, ref int index)
	{
		debug(log) writeln("prune at [", line, ":", index, "]");
		
		static void pruneLater(int line, int index, ref Location[] locations)
		{
			while(locations.length > 0)
			{
				Location loc = locations[$-1];
				if(compareStartAddress(loc.span, line, index) < 0)
					break;

				debug(log) writeln(" stack pruning ", loc, " at ", logString(loc.span));
				locations = locations[0..$-1];
			}
		}

		// remove stack entries that start later than the given address
		pruneLater(line, index, stack);
		
		while(stack.length > 0)
		{
			Location loc = stack[$-1];
			assert(compareStartAddress(loc.span, line, index) < 0);

			// remove children that start later than the given address
			pruneLater(line, index, loc.children);

			if(loc.children.length <= 0)
				break;

			// move child containing the the given address back on the stack
			Location child = loc.children[$-1];
			assert(compareStartAddress(child.span, line, index) < 0);
			if(compareEndAddress(child.span, line, index) < 0)
				break;
			
			debug(log) writeln(" child pruning ", child, " at ", logString(child.span));
//			loc.children = loc.children[0..$-1];
			stack ~= child;
		}
		
		// fix span of stack entries
		foreach(loc; stack)
		{
			if(loc.children.length)
				loc.limitSpan(loc.children[$-1].span);
			else
				loc.clearSpan();
		}
		if(stack.length > 0)
		{
			line = stack[$-1].span.iEndLine;
			index = stack[$-1].span.iEndIndex;
		}
		debug(log) writeln("prune returns [", line, ":", index, "]");
		return true;
	}

	void fixExtend()
	{
		// fix span of stack entries
		foreach_reverse(loc; stack)
		{
			if(loc.children.length)
				loc.extendSpan(loc.children[$-1].span);
		}
	}
	
	Location findLocation(int line, int index, bool lastLocOpen)
	{
		static Location findLocation(Location[] locations, int line, int index)
		{
			foreach(loc; locations)
			{
				if(spanContains(loc.span, line, index))
					return loc;
			}
			return null;
		}
		if(lastLocOpen && stack.length > 0 && compareEndAddress(stack[$-1].span, line, index) <= 0)
			return stack[$-1];
		
		if(Location loc = findLocation(stack, line, index))
		{
			Location child;
			while((child = findLocation(loc.children, line, index)) !is null)
				loc = child;
			return loc;
		}
		return null;
	}
	
	void writeTree(Location loc, int indent)
	{
		writeln(repeat(" ", indent), loc, " ", logString(loc.span));
		foreach(child; loc.children)
			writeTree(child, indent + 1);
	}
	
	void writeTree()
	{
		for(int i = 0; i < stack.length; i++)
		{
			writeln("Stack depth ", i);
			writeTree(stack[i], 1);
		}
	}
	
	void parseLine(ref int state, S line, int lno)
	{
		for(uint pos = 0; pos < line.length; )
		{
			ParserToken!S tok;
			tok.span.iStartLine = lno;
			tok.span.iStartIndex = pos;
			tok.type = cast(TokenColor) SimpleLexer.scan(state, line, pos, tok.id);
			tok.text = line[tok.span.iStartIndex .. pos];
			
			if(pos == line.length)
			{
				// join end of line and beginning of next line
				tok.span.iEndLine = lno + 1;
				tok.span.iEndIndex = 0;
			}
			else
			{
				tok.span.iEndLine = lno;
				tok.span.iEndIndex = pos;
			}
			if(!SimpleLexer.isCommentOrSpace(tok.type, line[tok.span.iStartIndex .. $]))
				shift(tok);
		}
	}

	void OnLinesChanged(int iStartLine, int iOldEndLine, int iNewEndLine)
	{
	}
}

version(MAIN)
{
import parser.engine;

int main(string[] argv)
{
	return 0;
}
}
else version(MAIN)
{
import dparser;

int main(string[] argv)
{
	genDParser();
	return 0;
}
}
else version(MAIN)
{
int main(string[] argv)
{
	string text = q{
		class A { 
			int x; 
			version(none)
				int fn()
				{
					test;
				}
			else 
				int bar();
			if(1)
				if(2)
					debug(3) a;
					else b;
			c;
		}
	};

	auto parser = new ParserBase!string;
	string[] lines = split(text, "\n");

	int state = 0;
	int[] states = new int[lines.length+1];
	states[0] = state;

	foreach(lno, line; lines)
	{
		parser.parseLine(state, line, lno);
		states[lno+1] = state;
	}
	
	parser.writeTree();
	assert(parser.stack.length == 1);
	
	int line = 7, index = 0;
	parser.prune(line, index);
	parser.writeTree();

	state = states[line];
	for(int i = line; i < lines.length; i++)
		parser.parseLine(state, lines[i], i);

	parser.writeTree();
	assert(parser.stack.length == 1);

	auto verloc = parser.findLocation(4, 6, true);
	assert(cast(VersionStatement!string) verloc);
	
	return 0;
}

}
