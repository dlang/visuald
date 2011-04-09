// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.interpret;

import vdc.util;
import vdc.semantic;
import vdc.lexer;

import vdc.ast.decl;
import vdc.ast.type;

import std.variant;
import std.conv;
import std.typetuple;
import std.string;

class ErrorType : Type
{
	mixin ForwardCtor!();
	
	override bool propertyNeedsParens() const { return false; }
}

int basicTypeToken(bool)    { return TOK_bool; }
int basicTypeToken(byte)    { return TOK_byte; }
int basicTypeToken(ubyte)   { return TOK_ubyte; }
int basicTypeToken(short)   { return TOK_short; }
int basicTypeToken(ushort)  { return TOK_ushort; }
int basicTypeToken(int)     { return TOK_int; }
int basicTypeToken(uint)    { return TOK_uint; }
int basicTypeToken(long)    { return TOK_long; }
int basicTypeToken(ulong)   { return TOK_ulong; }
int basicTypeToken(char)    { return TOK_char; }
int basicTypeToken(wchar)   { return TOK_wchar; }
int basicTypeToken(dchar)   { return TOK_dchar; }
int basicTypeToken(float)   { return TOK_float; }
int basicTypeToken(double)  { return TOK_double; }
int basicTypeToken(real)    { return TOK_real; }
int basicTypeToken(ifloat)  { return TOK_ifloat; }
int basicTypeToken(idouble) { return TOK_idouble; }
int basicTypeToken(ireal)   { return TOK_ireal; }
int basicTypeToken(cfloat)  { return TOK_cfloat; }
int basicTypeToken(cdouble) { return TOK_cdouble; }
int basicTypeToken(creal)   { return TOK_creal; }

class Value
{
	static T _create(T, V)(V val)
	{
		T v = new T;
		v.val = cast(T.ValType) val;
		return v;
	}
	
	static Value create(bool   v) { return _create!BoolValue  (v); }
	static Value create(byte   v) { return _create!ByteValue  (v); }
	static Value create(ubyte  v) { return _create!UByteValue (v); }
	static Value create(short  v) { return _create!ShortValue (v); }
	static Value create(ushort v) { return _create!UShortValue(v); }
	static Value create(int    v) { return _create!IntValue   (v); }
	static Value create(uint   v) { return _create!UIntValue  (v); }
	static Value create(long   v) { return _create!IntValue   (v); }
	static Value create(ulong  v) { return _create!ULongValue (v); }
	static Value create(char   v) { return _create!CharValue  (v); }
	static Value create(wchar  v) { return _create!WCharValue (v); }
	static Value create(dchar  v) { return _create!DCharValue (v); }
	static Value create(string v) { return _create!StringValue(v); }
	
	bool toBool()
	{
		semanticError(text("cannot convert ", this, " to bool"));
		return false;
	}

	int toInt()
	{
		long lng = toLong();
		return cast(int) lng;
	}
	
	long toLong()
	{
		semanticError(text("cannot convert ", this, " to integer"));
		return 0;
	}

	void setLong(long lng)
	{
		semanticError(text("cannot convert long to ", this));
	}

	string toStr()
	{
		semanticError(text("cannot convert ", this, " to string"));
		return "";
	}

	version(all)
	Value opBin(int tokid, Value v)
	{
		semanticError(text("binary operator ", tokenString(tokid), " on ", this, " not implemented"));
		return this;
	}

	Value opUn(int tokid)
	{
		switch(tokid)
		{
			case TOK_and:        return opRefPointer();
			case TOK_mul:        return opDerefPointer();
			default: break;
		}
		semanticError(text("unary operator ", tokenString(tokid), " on ", this, " not implemented"));
		return this;
	}

	
	//mixin template operators()
	version(none)
		Value opassign(string op)(Value v)
		{
			TypeInfo ti1 = this.classinfo;
			TypeInfo ti2 = v.classinfo;
			foreach(iv1; IntegerValues)
			{
				if(ti1 is typeid(iv1))
				{
					foreach(iv2; IntegerValues)
					{
						if(ti2 is typeid(iv2))
							static if (__traits(compiles, {
								iv1.ValType x;
								iv2.ValType y;
								mixin("x " ~ op ~ "y;");
							}))
							{
								iv2.ValType v2 = (cast(iv2) v).val;
								static if(op == "/=" || op == "%=")
									if(v2 == 0)
									{
										semanticError("division by zero");
										v2 = 1;
									}
								mixin("(cast(iv1) this).val " ~ op ~ "v2;");
								return this;
							}
					}
				}
			}
			semanticError(text("cannot execute ", op, " on a ", v, " with a ", this));
			return this;
		}
		
	version(none)
		Value opBinOp(string op)(Value v)
		{
			TypeInfo ti1 = this.classinfo;
			TypeInfo ti2 = v.classinfo;
			foreach(iv1; IntegerValues)
			{
				if(ti1 is typeid(iv1))
				{
					foreach(iv2; IntegerValues)
					{
						if(ti2 is typeid(iv2))
						{
							static if (__traits(compiles, {
								iv1.ValType x;
								iv2.ValType y;
								mixin("auto z = x " ~ op ~ "y;");
							}))
							{
								iv1.ValType v1 = (cast(iv1) this).val;
								iv2.ValType v2 = (cast(iv2) v).val;
								static if(op == "/" || op == "%")
									if(v2 == 0)
									{
										semanticError("division by zero");
										v2 = 1;
									}
								mixin("auto z = v1 " ~ op ~ "v2;");
								return create(z);
							}
							else
							{
								semanticError(text("cannot calculate ", op, " on a ", this, " and a ", v));
							}
						}
					}
				}
			}
			semanticError(text("cannot calculate ", op, " on a ", this, " and a ", v));
			return this;
		}

	version(none)
		Value opUnOp(string op)()
		{
			TypeInfo ti1 = this.classinfo;
			foreach(iv1; IntegerValues)
			{
				if(ti1 is typeid(iv1))
				{
					static if (__traits(compiles, {
						iv1.ValType x;
						mixin("auto z = " ~ op ~ "x;");
					}))
					{
						mixin("auto z = " ~ op ~ "(cast(iv1) this).val;");
						return create(z);
					}
				}
			}
			semanticError(text("cannot calculate ", op, " on a ", this));
			return this;
		}

	Value opRefPointer()
	{
		return _create!(PointerValue)(this);
	}
	Value opDerefPointer()
	{
		semanticError(text("cannot dereference a ", this));
		return this;
	}
}

alias TypeTuple!(bool, byte, ubyte, short, ushort, int, uint, long, ulong, 
				 char, wchar, dchar) IntegerTypes;

alias TypeTuple!(BoolValue, ByteValue, UByteValue, ShortValue, UShortValue,
				 IntValue, UIntValue, LongValue, ULongValue,
				 CharValue, WCharValue, DCharValue) IntegerValues;

class ValueT(T) : Value
{
	alias T ValType;
	
	ValType val;
	
	int getTypeIndex() { return staticIndexOf!(ValType, IntegerTypes); }
	
//	pragma(msg, ValType);
//	pragma(msg, text(" compiles?", __traits(compiles, val ? true : false )));
	
	static if(__traits(compiles, val ? true : false))
		bool toBool()
		{
			return val ? true : false;
		}

	static if(__traits(compiles, (){ long lng = val; }))
		long toLong()
		{
			return val;
		}
	
	////////////////////////////////////////////////////////////
	mixin template mixinBinaryOp(string op)
	{
		Value binOp(Value v)
		{
			TypeInfo ti = v.classinfo;
			foreach(iv2; IntegerValues)
			{
				if(ti is typeid(iv2))
				{
					static if (__traits(compiles, { 
						iv2.ValType y;
						mixin("auto z = val " ~ op ~ "y;");
					}))
					{
						iv2.ValType v2 = (cast(iv2) v).val;
						static if(op == "/" || op == "%")
							if(v2 == 0)
							{
								semanticError("division by zero");
								v2 = 1;
							}
						mixin("auto z = val " ~ op ~ "v2;");
						return create(z);
					}
					else
						break;
				}
			}
			semanticError(text("cannot calculate ", op, " on a ", this, " and a ", v));
			return this;
		}
	}

	mixin template mixinAssignOp(string op)
	{
		Value assOp(Value v)
		{
			TypeInfo ti = v.classinfo;
			foreach(iv2; IntegerValues)
			{
				if(ti is typeid(iv2))
					static if (__traits(compiles, {
						iv2.ValType y;
						mixin("val " ~ op ~ "y;");
					}))
					{
						iv2.ValType v2 = (cast(iv2) v).val;
						static if(op == "/=" || op == "%=")
							if(v2 == 0)
							{
								semanticError("division by zero");
								v2 = 1;
							}
						mixin("val " ~ op ~ "v2;");
						return this;
					}
			}
			semanticError(text("cannot assign ", op, " a ", v, " to a ", this));
			return this;
		}
	}
	
	static string genMixinBinOpAll()
	{
		string s;
		for(int i = TOK_binaryOperatorFirst; i <= TOK_binaryOperatorLast; i++)
			if(i >= TOK_assignOperatorFirst && i <= TOK_assignOperatorLast)
				s ~= text("mixin mixinAssignOp!(\"", tokenString(i), "\") ass_", operatorName(i), ";\n");
			else
				s ~= text("mixin mixinBinaryOp!(\"", tokenString(i), "\") bin_", operatorName(i), ";\n");
		return s;
	}
	
	mixin(genMixinBinOpAll());
	
	static string genBinOpCases()
	{
		string s;
		for(int i = TOK_binaryOperatorFirst; i <= TOK_binaryOperatorLast; i++)
			if(i >= TOK_assignOperatorFirst && i <= TOK_assignOperatorLast)
				s ~= text("case ", i, ": return ass_", operatorName(i), ".assOp(v);\n");
			else
				s ~= text("case ", i, ": return bin_", operatorName(i), ".binOp(v);\n");
		return s;
	}
	
	Value opBin(int tokid, Value v)
	{
		switch(tokid)
		{
			mixin(genBinOpCases());
			default: break;
		}
		
		semanticError(text("cannot calculate ", tokenString(tokid), " on a ", this, " and a ", v));
		return this;
	}

	////////////////////////////////////////////////////////////
	mixin template mixinUnaryOp(string op)
	{
		Value unOp()
		{
			static if (__traits(compiles, { mixin("auto z = " ~ op ~ "val;"); }))
			{
				mixin("auto z = " ~ op ~ "val;");
				return create(z);
			}
			semanticError(text("cannot calculate ", op, " on a ", this));
			return this;
		}
	}
	
	static const int unOps[] = [ TOK_plusplus, TOK_minusminus, TOK_min, TOK_add, TOK_not, TOK_tilde ];
	
	static string genMixinUnOpAll()
	{
		string s;
		foreach(id; unOps)
			s ~= text("mixin mixinUnaryOp!(\"", tokenString(id), "\") un_", operatorName(id), ";\n");
		return s;
	}
	
	mixin(genMixinUnOpAll());
	
	static string genUnOpCases()
	{
		string s;
		foreach(id; unOps)
			s ~= text("case ", id, ": return un_", operatorName(id), ".unOp();\n");
		return s;
	}
	
	Value opUn(int tokid)
	{
		switch(tokid)
		{
			case TOK_and:        return opRefPointer();
			case TOK_mul:        return opDerefPointer();
			mixin(genUnOpCases());
			default: break;
		}
		semanticError(text("cannot calculate ", tokenString(tokid), " on a ", this));
		return this;
	}

}


class VoidValue : Value
{
}

class BoolValue : ValueT!bool
{
}

class ByteValue : ValueT!byte
{
}

class UByteValue : ValueT!ubyte
{
}

class ShortValue : ValueT!short
{
}

class UShortValue : ValueT!ushort
{
}

class IntValue : ValueT!int
{
}

class UIntValue : ValueT!uint
{
}

class LongValue : ValueT!long
{
}

class ULongValue : ValueT!ulong
{
}

class CharValue : ValueT!char
{
}

class WCharValue : ValueT!wchar
{
}

class DCharValue : ValueT!dchar
{
}

class FloatValue : Value
{
	alias float ValType;
	
	ValType val;

	bool toBool()
	{
		return val != 0;
	}

	long toLong()
	{
		return cast(int) val;
	}
}

class DoubleValue : Value
{
	alias double ValType;
	
	ValType val;

	bool toBool()
	{
		return val != 0;
	}

	long toLong()
	{
		return cast(int) val;
	}
}

class RealValue : Value
{
	alias real ValType;
	
	ValType val;

	bool toBool()
	{
		return val != 0;
	}

	long toLong()
	{
		return cast(int) val;
	}
}

class IFloatValue : Value
{
	alias ifloat ValType;
	
	ValType val;

	bool toBool()
	{
		return val != 0;
	}

	long toLong()
	{
		return cast(int) val;
	}
}

class IDoubleValue : Value
{
	alias idouble ValType;
	
	ValType val;

	bool toBool()
	{
		return val != 0;
	}

	long toLong()
	{
		return cast(int) val;
	}
}

class IRealValue : Value
{
	alias ireal ValType;
	
	ValType val;

	bool toBool()
	{
		return val != 0;
	}

	long toLong()
	{
		return cast(int) val;
	}
}

class CFloatValue : Value
{
	alias cfloat ValType;
	
	ValType val;

	bool toBool()
	{
		return val != 0;
	}

	long toLong()
	{
		return cast(int) val;
	}
}

class CDoubleValue : Value
{
	alias cdouble ValType;
	
	ValType val;

	bool toBool()
	{
		return val != 0;
	}

	long toLong()
	{
		return cast(int) val;
	}
}

class CRealValue : Value
{
	alias creal ValType;
	
	ValType val;

	bool toBool()
	{
		return val != 0;
	}

	long toLong()
	{
		return cast(int) val;
	}
}

class StringValue : Value
{
	alias string ValType;
	
	ValType val;

	bool toBool()
	{
		return val !is null;
	}
}

class StructValue : Value
{
	Type type;
	alias void[] ValType;
	
	ValType val;

	this(Type t)
	{
		type = t;
	}
}

class ClassValue : Value
{
	Type type;
	alias void[] ValType;
	
	ValType val;

	this(Type t)
	{
		type = t;
	}
}

class PointerValue : Value
{
	alias Value ValType;
	
	ValType val;

	bool toBool()
	{
		return val !is null;
	}
	
	Value opDerefPointer()
	{
		return val;
	}
}
