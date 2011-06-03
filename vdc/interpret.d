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
import vdc.logger;

import vdc.ast.decl;
import vdc.ast.type;

import std.variant;
import std.conv;
import std.typetuple;
import std.string;

template Singleton(T, ARGS...)
{
	T get()
	{
		static T instance;
		if(!instance)
			instance = new T(ARGS);
		return instance;
	}
}

class ErrorType : Type
{
	mixin ForwardCtor!();
	
	override bool propertyNeedsParens() const { return false; }
	override void toD(CodeWriter writer) { writer("_errortype_"); }
}

class Value
{
	bool mutable = true;
	debug string sval;
	
	static T _create(T, V)(V val)
	{
		T v = new T;
		*v.pval = val;
		debug v.sval = v.toStr();
		return v;
	}
	
	static Value create(bool    v) { return _create!BoolValue   (v); }
	static Value create(byte    v) { return _create!ByteValue   (v); }
	static Value create(ubyte   v) { return _create!UByteValue  (v); }
	static Value create(short   v) { return _create!ShortValue  (v); }
	static Value create(ushort  v) { return _create!UShortValue (v); }
	static Value create(int     v) { return _create!IntValue    (v); }
	static Value create(uint    v) { return _create!UIntValue   (v); }
	static Value create(long    v) { return _create!LongValue   (v); }
	static Value create(ulong   v) { return _create!ULongValue  (v); }
	static Value create(char    v) { return _create!CharValue   (v); }
	static Value create(wchar   v) { return _create!WCharValue  (v); }
	static Value create(dchar   v) { return _create!DCharValue  (v); }
	static Value create(float   v) { return _create!FloatValue  (v); }
	static Value create(double  v) { return _create!DoubleValue (v); }
	static Value create(real    v) { return _create!RealValue   (v); }
	static Value create(ifloat  v) { return _create!IFloatValue (v); }
	static Value create(idouble v) { return _create!IDoubleValue(v); }
	static Value create(ireal   v) { return _create!IRealValue  (v); }
	static Value create(cfloat  v) { return _create!CFloatValue (v); }
	static Value create(cdouble v) { return _create!CDoubleValue(v); }
	static Value create(creal   v) { return _create!CRealValue  (v); }
	
	static Value create(string  v) { return StringValue._create (v); }
	
	Type getType()
	{
		return semanticErrorType(text("cannot get type of ", this));
	}
	
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
	override string toString()
	{
		return text(getType(), ":", toStr());
	}
	
	version(all)
	Value opBin(int tokid, Value v)
	{
		return semanticErrorValue(text("binary operator ", tokenString(tokid), " on ", this, " not implemented"));
	}

	Value opUn(int tokid)
	{
		switch(tokid)
		{
			case TOK_and:        return opRefPointer();
			case TOK_mul:        return opDerefPointer();
			default: break;
		}
		return semanticErrorValue(text("unary operator ", tokenString(tokid), " on ", this, " not implemented"));
	}

	Value opRefPointer()
	{
		return PointerValue._create(this);
	}
	Value opDerefPointer()
	{
		return semanticErrorValue(text("cannot dereference a ", this));
	}

	Value getProperty(string ident)
	{
		return getType().interpretProperty(ident);
	}
	
	Value opIndex(Value v)
	{
		return semanticErrorValue(text("cannot index a ", this));
	}
	
	Value opSlice(Value b, Value e)
	{
		return semanticErrorValue(text("cannot slice a ", this));
	}
	
	Value opCall(Scope sc, Value args)
	{
		return semanticErrorValue(text("cannot call a ", this));
	}
	
	//mixin template operators()
	version(none)
		Value opassign(string op)(Value v)
		{
			TypeInfo ti1 = this.classinfo;
			TypeInfo ti2 = v.classinfo;
			foreach(iv1; BasicTypeValues)
			{
				if(ti1 is typeid(iv1))
				{
					foreach(iv2; BasicTypeValues)
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
										return semanticErrorValue("division by zero");
								mixin("(cast(iv1) this).val " ~ op ~ "v2;");
								return this;
							}
					}
				}
			}
			return semanticErrorValue(text("cannot execute ", op, " on a ", v, " with a ", this));
		}
		
	version(none)
		Value opBinOp(string op)(Value v)
		{
			TypeInfo ti1 = this.classinfo;
			TypeInfo ti2 = v.classinfo;
			foreach(iv1; BasicTypeValues)
			{
				if(ti1 is typeid(iv1))
				{
					foreach(iv2; BasicTypeValues)
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
										return semanticErrorValue("division by zero");
								mixin("auto z = v1 " ~ op ~ "v2;");
								return create(z);
							}
							else
							{
								return semanticErrorValue(text("cannot calculate ", op, " on a ", this, " and a ", v));
							}
						}
					}
				}
			}
			return semanticErrorValue(text("cannot calculate ", op, " on a ", this, " and a ", v));
		}

	version(none)
		Value opUnOp(string op)()
		{
			TypeInfo ti1 = this.classinfo;
			foreach(iv1; BasicTypeValues)
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
			return semanticErrorValue(text("cannot calculate ", op, " on a ", this));
		}

	////////////////////////////////////////////////////////////
	mixin template mixinBinaryOp1(string op, iv2)
	{
		Value binOp1(Value v)
		{
			iv2.ValType v2 = *(cast(iv2) v).pval;
			static if(op == "/" || op == "%")
				if(v2 == 0)
					return semanticErrorValue("division by zero");
			mixin("auto z = *pval " ~ op ~ "v2;");
			return create(z);
		}
	}
	
	mixin template mixinBinaryOp(string op, Types...)
	{
		Value binOp(Value v)
		{
			TypeInfo ti = v.classinfo;
			foreach(iv2; Types)
			{
				if(ti is typeid(iv2))
				{
					static if (__traits(compiles, { 
						iv2.ValType y;
						mixin("auto z = (*pval) " ~ op ~ "y;");
					}))
					{
						iv2.ValType v2 = *(cast(iv2) v).pval;
						static if(op == "/" || op == "%")
							if(v2 == 0)
								return semanticErrorValue("division by zero");
						mixin("auto z = (*pval) " ~ op ~ "v2;");
						return create(z);
					}
					else
						break;
				}
			}
			return semanticErrorValue(text("cannot calculate ", op, " on a ", this, " and a ", v));
		}
	}

	mixin template mixinAssignOp(string op, Types...)
	{
		Value assOp(Value v)
		{
			if(!mutable)
				return semanticErrorValue(text(this, " value is not mutable"));
				
			TypeInfo ti = v.classinfo;
			foreach(iv2; Types)
			{
				if(ti is typeid(iv2))
					static if (__traits(compiles, {
						iv2.ValType y;
						mixin("*pval " ~ op ~ "y;");
					}))
					{
						iv2.ValType v2 = *(cast(iv2) v).pval;
						static if(op == "/=" || op == "%=")
							if(v2 == 0)
								return semanticErrorValue("division by zero");
						mixin("*pval " ~ op ~ "v2;");

						logInfo("value changed by " ~ op ~ " to " ~ toStr());
						debug sval = toStr();
						return this;
					}
			}
			return semanticErrorValue(text("cannot assign ", op, " a ", v, " to a ", this));
		}
	}
}

T createInitValue(T)(Value initValue)
{
	T v = new T;
	if(initValue)
		v.opBin(TOK_assign, initValue);
	return v;
}

alias TypeTuple!(bool, byte, ubyte, short, ushort, int, uint, long, ulong, 
				 char, wchar, dchar, float, double, real, 
				 ifloat, idouble, ireal, cfloat, cdouble, creal) BasicTypes;

alias TypeTuple!(BoolValue, ByteValue, UByteValue, ShortValue, UShortValue,
				 IntValue, UIntValue, LongValue, ULongValue,
				 CharValue, WCharValue, DCharValue, 
				 FloatValue, DoubleValue, RealValue,
				 IFloatValue, IDoubleValue, IRealValue,
				 CFloatValue, CDoubleValue, CRealValue) BasicTypeValues;

alias TypeTuple!(TOK_bool, TOK_byte, TOK_ubyte, TOK_short, TOK_ushort, TOK_int, 
				 TOK_uint, TOK_long, TOK_ulong, TOK_char, TOK_wchar, TOK_dchar,
				 TOK_float, TOK_double, TOK_real, TOK_ifloat, TOK_idouble, TOK_ireal, 
				 TOK_cfloat, TOK_cdouble, TOK_creal) BasicTypeTokens;

int BasicType2Token(T)() { return BasicTypeTokens[staticIndexOf!(T, BasicTypes)]; }

template Token2BasicType(int tok)
{
	alias BasicTypes[staticIndexOf!(tok, BasicTypeTokens)] Token2BasicType;
}

template Token2ValueType(int tok)
{
	alias BasicTypeValues[staticIndexOf!(tok, BasicTypeTokens)] Token2ValueType;
}

class ValueT(T) : Value
{
	alias T ValType;
	
	ValType* pval;
	
	this()
	{
		pval = new ValType;
	}
	
	static int getTypeIndex() { return staticIndexOf!(ValType, BasicTypes); }
	
	override Type getType()
	{
		static Type instance;
		if(!instance)
			instance = BasicType.createType(BasicTypeTokens[getTypeIndex()]);
		return instance;
	}
	
	override string toStr()
	{
		return to!string(*pval);
	}
	
//	pragma(msg, ValType);
//	pragma(msg, text(" compiles?", __traits(compiles, val ? true : false )));
	
	// pragma(msg, "toBool " ~ ValType.stringof ~ (__traits(compiles, *pval ? true : false) ? " compiles" : " fails"));
	static if(__traits(compiles, *pval ? true : false))
		override bool toBool()
		{
			return *pval ? true : false;
		}

	// pragma(msg, "toLong " ~ ValType.stringof ~ (__traits(compiles, function long () { ValType v; return v; }) ? " compiles" : " fails"));
	static if(__traits(compiles, function long () { ValType v; return v; } ))
		override long toLong()
		{
			return *pval;
		}
	
	////////////////////////////////////////////////////////////
	static string genMixinBinOpAll()
	{
		string s;
		for(int i = TOK_binaryOperatorFirst; i <= TOK_binaryOperatorLast; i++)
			if(i >= TOK_assignOperatorFirst && i <= TOK_assignOperatorLast)
				s ~= text("mixin mixinAssignOp!(\"", tokenString(i), "\", BasicTypeValues) ass_", operatorName(i), ";\n");
			else
				s ~= text("mixin mixinBinaryOp!(\"", tokenString(i), "\", BasicTypeValues) bin_", operatorName(i), ";\n");
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
	
	override Value opBin(int tokid, Value v)
	{
		switch(tokid)
		{
			mixin(genBinOpCases());
			default: break;
		}
		
		return semanticErrorValue(text("cannot calculate ", tokenString(tokid), " on a ", this, " and a ", v));
	}

	////////////////////////////////////////////////////////////
	mixin template mixinUnaryOp(string op)
	{
		Value unOp()
		{
			static if (__traits(compiles, { mixin("auto z = " ~ op ~ "(*pval);"); }))
			{
				mixin("auto z = " ~ op ~ "(*pval);");
				return create(z);
			}
			else
			{
				return semanticErrorValue(text("cannot calculate ", op, " on a ", this));
			}
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
	
	override Value opUn(int tokid)
	{
		switch(tokid)
		{
			case TOK_and:        return opRefPointer();
			case TOK_mul:        return opDerefPointer();
			mixin(genUnOpCases());
			default: break;
		}
		return semanticErrorValue(text("cannot calculate ", tokenString(tokid), " on a ", this));
	}

}

class VoidValue : Value
{
	override string toStr()
	{
		return "void";
	}
}

VoidValue _theVoidValue;

VoidValue theVoidValue()
{
	if(!_theVoidValue)
	{
		_theVoidValue = new VoidValue;
		_theVoidValue.mutable = false;
	}
	return _theVoidValue;
}

class ErrorValue : Value
{
	override string toStr()
	{
		return "_error_";
	}
	
	override Type getType()
	{
		return Singleton!ErrorType.get();
	}
}

class NullValue : Value
{
	override string toStr()
	{
		return "null";
	}

	override Type getType()
	{
		return Singleton!NullType.get();
	}
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

class FloatValue : ValueT!float
{
}

class DoubleValue : ValueT!double
{
}

class RealValue : ValueT!real
{
}

class IFloatValue : ValueT!ifloat
{
}

class IDoubleValue : ValueT!idouble
{
}

class IRealValue : ValueT!ireal
{
}

class CFloatValue : ValueT!cfloat
{
}

class CDoubleValue : ValueT!cdouble
{
}

class CRealValue : ValueT!creal
{
}

alias TypeTuple!(CharValue, WCharValue, DCharValue, StringValue) StringTypeValues;

class DynArrayValue : Value
{
	Type type;
	Value[] values;

	this(Type t)
	{
		type = t;
	}
}

class StringValue : Value
{
	alias string ValType;
	
	ValType* pval;

	this()
	{
		pval = (new string[1]).ptr;
	}
	
	this(string s)
	{
		pval = (new string[1]).ptr;
		*pval = s;
	}
	
	static StringValue _create(string s)
	{
		StringValue sv = new StringValue(s);
		return sv;
	}
	
	override Type getType()
	{
		return createTypeString();
	}
	
	override string toStr()
	{
		return *pval;
	}

	override bool toBool()
	{
		return *pval !is null;
	}

	mixin mixinAssignOp!("=",  StringTypeValues) ass_assign;
	mixin mixinAssignOp!("~=", StringTypeValues) ass_catass;
	mixin mixinBinaryOp!("~",  StringTypeValues) bin_tilde;
	mixin mixinBinaryOp1!("<",  StringValue) bin_lt;
	mixin mixinBinaryOp1!(">",  StringValue) bin_gt;
	mixin mixinBinaryOp1!("<=", StringValue) bin_le;
	mixin mixinBinaryOp1!(">=", StringValue) bin_ge;
	mixin mixinBinaryOp1!("==", StringValue) bin_equal;
	mixin mixinBinaryOp1!("!=", StringValue) bin_notequal;
	
	override Value opBin(int tokid, Value v)
	{
		switch(tokid)
		{
			case TOK_assign:   return ass_assign.assOp(v);
			case TOK_tilde:    return bin_tilde.binOp(v);
			case TOK_catass:   return ass_catass.assOp(v);
			case TOK_lt:       return bin_lt.binOp1(v);
			case TOK_gt:       return bin_gt.binOp1(v);
			case TOK_le:       return bin_le.binOp1(v);
			case TOK_ge:       return bin_ge.binOp1(v);
			case TOK_equal:    return bin_equal.binOp1(v);
			case TOK_notequal: return bin_notequal.binOp1(v);
			default:           return super.opBin(tokid, v);
		}
	}

	override Value opIndex(Value v)
	{
		int idx = v.toInt();
		if(idx < 0 || idx >= (*pval).length)
			return semanticErrorValue(text("index ", idx, " out of bounds on ", *pval));
		return create((*pval)[idx]);
	}
}

class StructValue : Value
{
	Type type;
	alias void[] ValType;
	
	ValType* pval;

	this(Type t)
	{
		type = t;
	}
}

class ClassValue : Value
{
	Type type;
	alias void[] ValType;
	
	ValType* pval;

	this(Type t)
	{
		type = t;
	}
}

class PointerValue : Value
{
	alias Value ValType; 
	
	ValType pval; // Value is a class type, so its a reference, i.e. a pointer to the value

	static PointerValue _create(Value v)
	{
		PointerValue pv = new PointerValue;
		pv.pval = v;
		return pv;
	}
	
	override bool toBool()
	{
		return pval !is null;
	}
	
	override Value opDerefPointer()
	{
		if(!pval)
			return semanticErrorValue("dereferencing a null pointer");
		return pval;
	}
}

class TypeValue : Value
{
	Type type;
	
	this(Type t)
	{
		type = t;
	}

	override Type getType()
	{
		return type;
	}

	override string toStr()
	{
		return writeD(type);
	}
}

class TupleValue : Value
{
	Value[] values;

	override Value opIndex(Value v)
	{
		int idx = v.toInt();
		if(idx < 0 || idx >= values.length)
			return semanticErrorValue(text("index ", idx, " out of bounds on value tuple"));
		return values[idx];
	}

	override Value opBin(int tokid, Value v)
	{
		switch(tokid)
		{
			case TOK_assign:
			case TOK_tilde:
			case TOK_catass:
			default:           return super.opBin(tokid, v);
		}
	}

	override Value getProperty(string ident)
	{
		switch(ident)
		{
			case "length":
				return create(values.length);
			default:
				return super.getProperty(ident);
		}
	}
}

class FunctionValue : Value
{
	TypeFunction functype;
	
	override Value opCall(Scope sc, Value vargs)
	{
		if(!functype.mInit)
			return semanticErrorValue("calling null reference");

		auto args = static_cast!TupleValue(vargs);
		ParameterList params = functype.getParameters();
		if(args.values.length != params.members.length)
			return semanticErrorValue("incorrect number of arguments");

		Value[] prevValues;
		prevValues.length = params.members.length;
		for(int p = 0; p < params.members.length; p++)
		{
			auto decl = params.getParameter(p).getParameterDeclarator().getDeclarator();
			prevValues[p] = decl.interpret(sc);
			Value v = args.values[p];
			Type t = prevValues[p].getType();
			if(!t.compare(v.getType()))
				v = t.createValue(v);
			decl.value = v;
		}
		Value retVal = functype.mInit.interpretCall(sc);
		for(int p = 0; p < params.members.length; p++)
		{
			auto decl = params.getParameter(p).getParameterDeclarator().getDeclarator();
			decl.value = prevValues[p];
		}
		return retVal ? retVal : theVoidValue;
	}
}

class DelegateValue : Value
{
	Scope context;
	FunctionValue func;
}

// program control
class ProgramControlValue : Value
{
	string ident;
}

class BreakValue : ProgramControlValue
{
	this(string s)
	{
		ident = s;
	}
}

class ContinueValue : ProgramControlValue 
{
	this(string s)
	{
		ident = s;
	}
}

class GotoValue : ProgramControlValue 
{
	this(string s)
	{
		ident = s;
	}
}

class GotoCaseValue : ProgramControlValue 
{
	this(string s)
	{
		ident = s;
	}
}
