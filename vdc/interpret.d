// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details
//
// Interpretation passes around a context, holding the current variable stack
// class Context { Scope sc; Value[Node] vars; Context parent; }
//
// static shared values are not looked up in the context
// thread local static values are looked up in a global thread context
// non-static values are looked up in the current context
//
// member/field lookup in aggregates uses an instance specific Context
//
// when entering a scope, a new Context is created with the current 
//  Context as parent
// when leaving a scope, the context is destroyed together with scoped values
//  created within the lifetime of the context
// a delegate value saves the current context to be used when calling the delegate
//
// local functions are called with the context of the enclosing function
// member functions are called with the context of the instance
// static or global functions are called with the thread context
//
module vdc.interpret;

import vdc.util;
import vdc.semantic;
import vdc.lexer;
import vdc.logger;

import vdc.ast.decl;
import vdc.ast.type;
import vdc.ast.aggr;
import vdc.ast.expr;

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
	debug string ident;
	
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
		semanticError("cannot get type of ", this);
		return Singleton!(ErrorType).get();
	}
	
	bool toBool()
	{
		semanticError("cannot convert ", this, " to bool");
		return false;
	}

	int toInt()
	{
		long lng = toLong();
		return cast(int) lng;
	}
	
	long toLong()
	{
		semanticError("cannot convert ", this, " to integer");
		return 0;
	}

	void setLong(long lng)
	{
		semanticError("cannot convert long to ", this);
	}

	string toStr()
	{
		semanticError("cannot convert ", this, " to string");
		return "";
	}

	string toMixin()
	{
		semanticError("cannot convert ", this, " to mixin");
		return "";
	}
	//override string toString()
	//{
	//    return text(getType(), ":", toStr());
	//}
	
	version(all)
	Value opBin(Context ctx, int tokid, Value v)
	{
		return semanticErrorValue("cannot calculate ", this, " ", tokenString(tokid), " ", v);
		//return semanticErrorValue("binary operator ", tokenString(tokid), " on ", this, " not implemented");
	}

	Value opUn(Context ctx, int tokid)
	{
		switch(tokid)
		{
			case TOK_and:        return opRefPointer();
			case TOK_mul:        return opDerefPointer();
			default: break;
		}
		return semanticErrorValue("unary operator ", tokenString(tokid), " on ", this, " not implemented");
	}

	Value opRefPointer()
	{
		auto tp = new TypePointer();
		tp.addMember(getType());
		return PointerValue._create(tp, this);
	}
	Value opDerefPointer()
	{
		return semanticErrorValue("cannot dereference a ", this);
	}

	Value interpretProperty(Context ctx, string prop)
	{
		return getType().interpretProperty(ctx, prop);
	}
	
	Value opIndex(Value v)
	{
		return semanticErrorValue("cannot index a ", this);
	}
	
	Value opSlice(Value b, Value e)
	{
		return semanticErrorValue("cannot slice a ", this);
	}
	
	Value opCall(Context sc, Value args)
	{
		return semanticErrorValue("cannot call a ", this);
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
			return semanticErrorValue("cannot execute ", op, " on a ", v, " with a ", this);
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
								return semanticErrorValue("cannot calculate ", op, " on a ", this, " and a ", v);
							}
						}
					}
				}
			}
			return semanticErrorValue("cannot calculate ", op, " on a ", this, " and a ", v);
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
			return semanticErrorValue("cannot calculate ", op, " on a ", this);
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
			return semanticErrorValue("cannot calculate ", op, " on a ", this, " and a ", v);
		}
	}

	mixin template mixinAssignOp(string op, Types...)
	{
		Value assOp(Value v)
		{
			if(!mutable)
				return semanticErrorValue(this, " value is not mutable");
				
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

						debug logInfo("value %s changed by " ~ op ~ " to %s", ident, toStr());
						debug sval = toStr();
						return this;
					}
			}
			return semanticErrorValue("cannot assign ", op, " a ", v, " to a ", this);
		}
	}
}

T createInitValue(T)(Context ctx, Value initValue)
{
	T v = new T;
	if(initValue)
		v.opBin(ctx, TOK_assign, initValue);
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
	
	override Value opBin(Context ctx, int tokid, Value v)
	{
		switch(tokid)
		{
			mixin(genBinOpCases());
			default: break;
		}
		
		return semanticErrorValue("cannot calculate ", tokenString(tokid), " on a ", this, " and a ", v);
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
				return semanticErrorValue("cannot calculate ", op, " on a ", this);
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
	
	override Value opUn(Context ctx, int tokid)
	{
		switch(tokid)
		{
			case TOK_and:        return opRefPointer();
			case TOK_mul:        return opDerefPointer();
			mixin(genUnOpCases());
			default: break;
		}
		return semanticErrorValue("cannot calculate ", tokenString(tokid), " on a ", this);
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

class DynArrayValue : TupleValue
{
	Type type;

	this(Type t)
	{
		type = t;
	}

	override string toStr()
	{
		return _toStr("[", "]");
	}
	
	override Value interpretProperty(Context ctx, string prop)
	{
		switch(prop)
		{
			case "length":
				return new SetLengthValue(this);
			default:
				return super.interpretProperty(ctx, prop);
		}
	}
}

class SetLengthValue : UIntValue
{
	DynArrayValue array;
	
	this(DynArrayValue a)
	{
		array = a;
	}

	override string toStr()
	{
		return array.toStr() ~ ".length";
	}

	override Value opBin(Context ctx, int tokid, Value v)
	{
		switch(tokid)
		{
			case TOK_assign:
				int len = v.toInt();
				int oldlen = array._values.length;
				array._values.length = len;
				if(TypeDynamicArray tda = cast(TypeDynamicArray) array.type)
					while(oldlen < len)
						array._values[oldlen++] = tda.getType().createValue(ctx, null);
				return this;
			default:
				return super.opBin(ctx, tokid, v);
		}
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
		return '"' ~ *pval ~ '"';
	}

	override string toMixin()
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
	
	override Value opBin(Context ctx, int tokid, Value v)
	{
		switch(tokid)
		{
			case TOK_assign:   
				auto rv = ass_assign.assOp(v); 
				debug sval = toStr();
				return rv;
			case TOK_catass:
				auto rv = ass_catass.assOp(v);
				debug sval = toStr();
				return rv;
			case TOK_tilde:    return bin_tilde.binOp(v);
			case TOK_lt:       return bin_lt.binOp1(v);
			case TOK_gt:       return bin_gt.binOp1(v);
			case TOK_le:       return bin_le.binOp1(v);
			case TOK_ge:       return bin_ge.binOp1(v);
			case TOK_equal:    return bin_equal.binOp1(v);
			case TOK_notequal: return bin_notequal.binOp1(v);
			default:           return super.opBin(ctx, tokid, v);
		}
	}

	override Value opIndex(Value v)
	{
		int idx = v.toInt();
		if(idx < 0 || idx >= (*pval).length)
			return semanticErrorValue("index ", idx, " out of bounds on ", *pval);
		return create((*pval)[idx]);
	}
}

class PointerValue : Value
{
	TypePointer type;  // type of pointer
	Value pval; // Value is a class type, so its a reference, i.e. a pointer to the value

	override string toStr()
	{
		return "&" ~ pval.toStr();
	}

	static PointerValue _create(TypePointer type, Value v)
	{
		PointerValue pv = new PointerValue;
		pv.type = type;
		pv.pval = v;
		return pv;
	}
	
	override Type getType()
	{
		return type;
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

	override Value opBin(Context ctx, int tokid, Value v)
	{
		switch(tokid)
		{
			case TOK_assign:
				auto pv = cast(PointerValue)v;
				if(!v)
					pval = null;
				else if(!pv)
					return semanticErrorValue("cannot convert value ", v, " to pointer of type ", type);
				else if(pv.type.convertableTo(type))
					pval = pv.pval;
				else
					return semanticErrorValue("cannot convert pointer type ", pv.type, " to ", type);
				debug sval = toStr();
				return this;
			case TOK_equal:
			case TOK_notequal:
				auto pv = cast(PointerValue)v;
				if(!pv || (!pv.type.convertableTo(type) && !type.convertableTo(pv.type)))
					return semanticErrorValue("cannot compare types ", pv.type, " and ", type);
				if(tokid == TOK_equal)
					return Value.create(pv.pval is pval);
				else
					return Value.create(pv.pval !is pval);
			default:
				return super.opBin(ctx, tokid, v);
		}
	}

	override Value interpretProperty(Context ctx, string prop)
	{
		switch(prop)
		{
			case "init":
				return _create(type, null);
			default:
				if(!pval)
					return semanticErrorValue("dereferencing null pointer");
				return pval.interpretProperty(ctx, prop);
		}
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
	
	override Value opCall(Context sc, Value vargs)
	{
		return type.createValue(sc, vargs);
	}
}

class AliasValue : Value
{
	IdentifierList id;
	
	this(IdentifierList _id)
	{
		id = _id;
	}

	override Type getType()
	{
		return id.calcType();
	}

	override string toStr()
	{
		return writeD(id);
	}
}

class TupleValue : Value
{
private:
	Value[] _values;
public:
	@property Value[] values() 
	{ 
		return _values; 
	}
	@property void values(Value[] v)
	{
		_values = v;
		debug sval = toStr();
	}
	void addValue(Value v)
	{
		_values ~= v;
		debug sval = toStr();
	}
	
	override string toStr()
	{
		return _toStr("(", ")");
	}

	string _toStr(string open, string close)
	{
		string s = open;
		foreach(i, v; values)
		{
			if(i > 0)
				s ~= ",";
			s ~= v.toStr();
		}
		s ~= close;
		return s;
	}
	
	override Value opIndex(Value v)
	{
		int idx = v.toInt();
		if(idx < 0 || idx >= values.length)
			return semanticErrorValue("index ", idx, " out of bounds on value tuple");
		return values[idx];
	}

	override Value opBin(Context ctx, int tokid, Value v)
	{
		switch(tokid)
		{
			case TOK_equal:
				if(auto tv = cast(TupleValue) v)
				{
					if(tv.values.length != values.length)
						return Value.create(false);
					for(int i = 0; i < values.length; i++)
						if(!values[i].opBin(ctx, TOK_equal, tv.values[i]).toBool())
							return Value.create(false);
					return Value.create(true);
				}
				return semanticErrorValue("cannot compare ", v, " to ", this);
			case TOK_notequal:
				return Value.create(!opBin(ctx, TOK_equal, v).toBool());
			case TOK_assign:
				if(auto tv = cast(TupleValue) v)
					values = tv.values;
				else
					return semanticErrorValue("cannot assign ", v, " to ", this);
				debug sval = toStr();
				return this;
			case TOK_tilde:
			case TOK_catass:
			default:
				return super.opBin(ctx, tokid, v);
		}
	}

	override Value interpretProperty(Context ctx, string prop)
	{
		switch(prop)
		{
			case "length":
				return create(values.length);
			default:
				return super.interpretProperty(ctx, prop);
		}
	}
}

class FunctionValue : Value
{
	TypeFunction functype;
	bool adr;
	
	override string toStr()
	{
		if(!functype.funcDecl)
			return "null";
		if(!functype.funcDecl.ident)
			return "_funcliteral_";
		return "&" ~ functype.funcDecl.ident;
	}

	Value doCall(Context sc, Value vargs)
	{
		if(!functype.funcDecl)
			return semanticErrorValue("calling null reference");

		auto ctx = new Context(sc);

		auto args = static_cast!TupleValue(vargs);
		ParameterList params = functype.getParameters();
		int numparams = params.members.length;
		if(params.anonymous_varargs)
		{
			if(args.values.length < numparams)
				return semanticErrorValue("too few arguments");
			// TODO: add _arguments and _argptr variables
		}
		else if(params.varargs)
		{
			if(args.values.length < numparams - 1)
				return semanticErrorValue("too few arguments");
			// TODO: pack remaining arguments into tuple
			numparams--;
		}
		else if(args.values.length != numparams)
			return semanticErrorValue("incorrect number of arguments");

		for(int p = 0; p < numparams; p++)
		{
			auto decl = params.getParameter(p).getParameterDeclarator().getDeclarator();
			Value v = args.values[p];
			Type t = v.getType();
			if(!decl.isRef)
				v = t.createValue(sc, v); // if not ref, always create copy
			else if(!t.compare(v.getType()))
				v = semanticErrorValue("cannot create reference of incompatible type");
			ctx.setValue(decl, v);
		}
		Value retVal = functype.funcDecl.interpretCall(ctx);
		return retVal ? retVal : theVoidValue;
	}

	override Value opCall(Context sc, Value vargs)
	{
		return doCall(threadContext, vargs);
	}

	override Value opBin(Context ctx, int tokid, Value v)
	{
		FunctionValue dg = cast(FunctionValue) v;
		if(!dg)
			return semanticErrorValue("cannot assign ", v, " to function");
		//! TODO: verify compatibility of types
		switch(tokid)
		{
			case TOK_assign:
				functype = dg.functype;
				debug sval = toStr();
				return Value;
			case TOK_equal:
				return Value.create(functype.compare(dg.functype));
			case TOK_notequal:
				return Value.create(!functype.compare(dg.functype));
			default:
				return super.opBin(ctx, tokid, v);
		}
	}

	override Type getType()
	{
		return functype;
	}

	override Value opRefPointer()
	{
		adr = true;
		return this;
	}
}

class DelegateValue : FunctionValue
{
	Context context;
	
	override Value opCall(Context sc, Value vargs)
	{
		return doCall(context, vargs);
	}

	override Value opBin(Context ctx, int tokid, Value v)
	{
		DelegateValue dg = cast(DelegateValue) v;
		if(!dg)
			return semanticErrorValue("cannot assign ", v, " to delegate");
		//! TODO: verify compatibility of types
		switch(tokid)
		{
			case TOK_assign:
				context = dg.context;
				functype = dg.functype;
				debug sval = toStr();
				return Value;
			case TOK_equal:
				return Value.create((context is dg.context) && functype.compare(dg.functype));
			case TOK_notequal:
				return Value.create((context !is dg.context) || !functype.compare(dg.functype));
			default:
				return super.opBin(ctx, tokid, v);
		}
	}
}

class AggrValue : TupleValue
{
	Value outer;

	abstract override Aggregate getType();

	override string toStr()
	{
		return getType().ident ~ _toStr("{", "}");
	}

	override Value interpretProperty(Context ctx, string prop)
	{
		auto type = getType();
		if(Value v = type.getProperty(ctx, this, prop))
			return v;
		if(Value v = type.getStaticProperty(prop))
			return v;
		if(outer) // TODO: outer checked after super?
			if(Value v = outer.interpretProperty(ctx, prop))
				return v;
		return super.interpretProperty(ctx, prop);
	}

	override Value opBin(Context ctx, int tokid, Value v)
	{
		switch(tokid)
		{
			case TOK_equal:
				if(Value fv = getType().getProperty(ctx, this, "opEqual"))
				{
					auto tctx = new AggrContext(ctx, this);
					auto tv = new TupleValue;
					tv.addValue(v);
					return fv.opCall(tctx, tv);
				}
				return super.opBin(ctx, tokid, v);
			case TOK_is:
				return Value.create(v is this);
			case TOK_notidentity:
				return Value.create(v !is this);
			default:
				return super.opBin(ctx, tokid, v);
		}
	}
}

class AggrValueT(T) : AggrValue
{
	T type;

	this(T t)
	{
		type = t;
	}

	override Aggregate getType()
	{
		return type;
	}
}
	
class StructValue : AggrValueT!Struct
{
	this(Struct t)
	{
		super(t);
	}
}

class UnionValue : AggrValueT!Union
{
	this(Union t)
	{
		super(t);
	}
}

class ClassInstanceValue : AggrValueT!Class
{
	this(Class t)
	{
		super(t);
	}
}

class ReferenceValue : Value
{
	ClassInstanceValue instance;

	override string toStr()
	{
		if(!instance)
			return "null";
		return instance.toStr();
	}
	
	override Value opBin(Context ctx, int tokid, Value v)
	{
		auto cv = cast(ReferenceValue) v;
		if(!cv)
			return super.opBin(ctx, tokid, v);
		
		switch(tokid)
		{
			case TOK_assign:
				instance = cv.instance;
				debug sval = toStr();
				return this;
			case TOK_equal:
				if(instance is cv.instance)
					return Value.create(true);
				if(!instance || !cv.instance)
					return Value.create(false);
				return instance.opBin(ctx, TOK_equal, cv.instance);
			case TOK_is:
				return Value.create(instance is cv.instance);
			case TOK_notidentity:
				return Value.create(instance !is cv.instance);
			default:
				return super.opBin(ctx, tokid, v);
		}
	}
}

class ReferenceValueT(T) : ReferenceValue
{
	T type;

	this(T t)
	{
		type = t;
	}

	override T getType()
	{
		return type;
	}

	override Value interpretProperty(Context ctx, string prop)
	{
		if(instance)
			return instance.interpretProperty(ctx, prop);
		if(Value v = type.getStaticProperty(prop))
			return v;
		return super.interpretProperty(ctx, prop);
	}
}

class ClassValue : ReferenceValueT!Class
{
	this(Class t, ClassInstanceValue inst = null)
	{
		super(t);
		instance = inst;
	}
}

class InterfaceValue : ReferenceValueT!Intrface
{
	this(Intrface t)
	{
		super(t);
	}
}

class AnonymousClassInstanceValue : AggrValueT!AnonymousClass
{
	this(AnonymousClass t)
	{
		super(t);
	}
}

class AnonymousClassValue : ReferenceValueT!AnonymousClass
{
	this(AnonymousClass t)
	{
		super(t);
	}
}

////////////////////////////////////////////////////////////////////////
// program control
class ProgramControlValue : Value
{
	string label;
}

class BreakValue : ProgramControlValue
{
	this(string s)
	{
		label = s;
	}
}

class ContinueValue : ProgramControlValue 
{
	this(string s)
	{
		label = s;
	}
}

class GotoValue : ProgramControlValue 
{
	this(string s)
	{
		label = s;
	}
}

class GotoCaseValue : ProgramControlValue 
{
	this(string s)
	{
		label = s;
	}
}
