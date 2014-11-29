module stdext.ddocmacros;

import std.traits;
import std.range;
import std.ascii;
import std.string;

// version = LOG;

version(LOG) import std.stdio;

C[][] ddocArgs(C,S)(ref S src)
{
	C[][] args;
	C[] arg;

	if(!src.empty && src.front.isWhite)
		src.popFront;

	int parens = 0;
	while(!src.empty)
	{
		auto c = src.front;
		src.popFront;

		switch(c)
		{
			case ')':
				if(parens == 0)
				{
					args ~= arg;
					return args;
				}
				parens--;
				goto default;
			case '(':
				parens++;
				goto default;

			case ',':
				if(parens == 0)
				{
					args ~= arg;
					arg = arg.init;
					if(!src.empty && src.front.isWhite)
						src.popFront;
					break;
				}
				goto default;
			default:
				arg ~= c;
				break;
		}
	}
	version(LOG) writeln("ddocArgs = ", args);
	return args;
}

K ddocIdent(K, S)(ref S src)
{
	alias C = ElementEncodingType!S;
	K id;
	while(!src.empty)
	{
		C c = src.front;
		if(isAlpha(c) || c == '_' || isDigit(c))
		{
			id ~= c;
			src.popFront;
		}
		else
			break;
	}
	version(LOG) writeln("ddocIdent = ", id);
	return id;
}

C[] joinArgs(C)(C[][] args, size_t first)
{
	C[] s; // use joiner?
	if(args.length > first)
	{
		s = args[first];
		foreach(a; args[first + 1 .. $])
		{
			s ~= ',';
			s ~= a;
		}
	}
	return s;
}

struct RangeStack(R)
{
	alias E = ElementType!R;
	alias C = ElementEncodingType!R;

	R[] stack;
	C[][][] arguments;

	@property bool empty() const { return stack.empty; }
	@property E front() const { return stack[$-1].front; }
	@property void popFront() 
	{
		stack[$-1].popFront; 
		if(stack[$-1].empty)
		{
			stack.length--;
			arguments.length--;
		}
	}
	void push(ref R r, C[][] args)
	{
		version(LOG) writeln("push = ", r);
		if(!r.empty)
		{
			stack ~= r.save;
			arguments ~= args;
		}
	}
	R getArg(dchar n)
	{
		if(arguments.empty)
			return null;

		if(n == '0')
			return joinArgs(arguments[$-1], 0);
		if(n == '+')
			return joinArgs(arguments[$-1], 1);
		size_t a = n - '0';
		if(a <= arguments[$-1].length)
			return arguments[$-1][a - 1];
		return null;
	}
}

S ddocExpand(S,AA)(S s, AA defs, bool keepUnknown) if(isInputRange!S)
{
	alias C = ElementEncodingType!S;
	alias K = KeyType!AA;
	alias V = ValueType!AA;

	RangeStack!S src;
	src.push(s, null);

	S res;
	while(!src.empty)
	{
		auto c = src.front;
		src.popFront;

		switch(c)
		{
			case '$':
				auto d = src.front;
				if(d == '(')
				{
					src.popFront;
					auto id = ddocIdent!(K)(src);
					auto args = ddocArgs!C(src);
					if(auto p = id in defs)
					{
						src.push(*p, args);
					}
					else if(keepUnknown)
					{
						res ~= c;
						res ~= d;
						res ~= id;
						string keepArgs = " $0)";
						src.push(keepArgs, args);
					}
					break;
				}
				else if(isAlpha(d))
				{
					auto id = ddocIdent!(K)(src);
					if(auto p = id in defs)
					{
						src.push(*p, null);
					}
					else if(keepUnknown)
					{
						res ~= c;
						res ~= id;
					}
					break;
				}
				else if(isDigit(d) || d == '+')
				{
					auto arg = src.getArg(d);
					src.popFront;
					src.push(arg, null);
					break;
				}
				goto default;
			default:
				res ~= c;
				break;
		}
	}
	return res;
}

string phobosDdocExpand(string txt)
{
	string[string] macros =
	[ 
		"D" : "`$0`",
		"LINK" : "$0",
		"LINK2" : "$2",
		"XREF" : "$2",
		"UL" : "\n$0",
		"LI" : "\n* $0",
	];
	return ddocExpand(txt, macros, true);
}

unittest
{
	import std.stdio;

	string txt = "$(D d-code)";
	string[string] macros = [ "D" : "$0", "LINK" : `<a href="$1">$+</a>` ];
	string res = ddocExpand(txt, macros, true);
	version(LOG) writeln(res);
	assert(strip(res) == "d-code");

	res = ddocExpand("link = $(LINK 1,2, 3,4)", macros, true);
	version(LOG) writeln(res);
	assert(strip(res) == `link = <a href="1">2,3,4</a>`);
}

//version(unittest) {}
//void main() {}
