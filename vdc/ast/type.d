// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module ast.type;

import util;
import simplelexer;
import semantic;
import interpret;

import ast.node;
import ast.expr;
import ast.misc;
import ast.aggr;
import ast.tmpl;
import ast.stmt;
import ast.decl;

import std.conv;

class Type : Node
{
	// semantic data
	TypeInfo typeinfo;
		
	mixin ForwardCtor!();

	abstract bool propertyNeedsParens() const;
	
	enum ConversionFlags
	{
		kAllowBaseClass          = 1 << 0,
		kAllowConstConversion    = 1 << 1,
		kAllowBaseTypeConversion = 1 << 2,
		
		// flags to clear on indirection
		kIndirectionClear = kAllowBaseClass | kAllowBaseTypeConversion,
	}
	
	bool convertableFrom(Type from, ConversionFlags flags)
	{
		if(from == this)
			return true;
		return true;
	}
	
	void semantic(Scope sc)
	{
		if(!typeinfo)
			typeSemantic(sc);
	}

	void typeSemantic(Scope sc)
	{
		super.semantic(sc);
	}
	
	Value createValue()
	{
		semanticError(text("cannot create value of type ", this));
		return new VoidValue;
	}
}

//BasicType only created for standard types associated with tokens
class BasicType : Type
{
	mixin ForwardCtor!();

	bool propertyNeedsParens() const { return false; }
	
	static TypeInfo getTypeInfo(int id)
	{
		switch(id)
		{
			case TOK_bool:    return typeid(bool);
			case TOK_byte:    return typeid(byte);
			case TOK_ubyte:   return typeid(ubyte);
			case TOK_short:   return typeid(short);
			case TOK_ushort:  return typeid(ushort);
			case TOK_int:     return typeid(int);
			case TOK_uint:    return typeid(uint);
			case TOK_long:    return typeid(long);
			case TOK_ulong:   return typeid(ulong);
			case TOK_char:    return typeid(char);
			case TOK_wchar:   return typeid(wchar);
			case TOK_dchar:   return typeid(dchar);
			case TOK_float:   return typeid(float);
			case TOK_double:  return typeid(double);
			case TOK_real:    return typeid(real);
			case TOK_ifloat:  return typeid(ifloat);
			case TOK_idouble: return typeid(idouble);
			case TOK_ireal:   return typeid(ireal);
			case TOK_cfloat:  return typeid(cfloat);
			case TOK_cdouble: return typeid(cdouble);
			case TOK_creal:   return typeid(creal);
			case TOK_void:    return typeid(void);
			default: return null;
		}
	}

	Value createValue()
	{
		switch(id)
		{
			case TOK_bool:    return new BoolValue;
			case TOK_byte:    return new ByteValue;
			case TOK_ubyte:   return new UByteValue;
			case TOK_short:   return new ShortValue;
			case TOK_ushort:  return new UShortValue;
			case TOK_int:     return new IntValue;
			case TOK_uint:    return new UIntValue;
			case TOK_long:    return new LongValue;
			case TOK_ulong:   return new ULongValue;
			case TOK_char:    return new CharValue;
			case TOK_wchar:   return new WCharValue;
			case TOK_dchar:   return new DCharValue;
			case TOK_float:   return new FloatValue;
			case TOK_double:  return new DoubleValue;
			case TOK_real:    return new RealValue;
			case TOK_ifloat:  return new IFloatValue;
			case TOK_idouble: return new IDoubleValue;
			case TOK_ireal:   return new IRealValue;
			case TOK_cfloat:  return new CFloatValue;
			case TOK_cdouble: return new CDoubleValue;
			case TOK_creal:   return new CRealValue;
			case TOK_void:    return new VoidValue;
			default: break;
		}
		semanticError(text("cannot create value of type ", this));
		return new VoidValue;
	}
	
	void typeSemantic(Scope sc)
	{
		assert(id != TOK_auto);
		typeinfo = getTypeInfo(id);
	}

	enum Category { kInteger, kFloat, kComplex, kVoid }
	
	static Category category(int id)
	{
		switch(id)
		{
			case TOK_bool:    return Category.kInteger;
			case TOK_byte:    return Category.kInteger;
			case TOK_ubyte:   return Category.kInteger;
			case TOK_short:   return Category.kInteger;
			case TOK_ushort:  return Category.kInteger;
			case TOK_int:     return Category.kInteger;
			case TOK_uint:    return Category.kInteger;
			case TOK_long:    return Category.kInteger;
			case TOK_ulong:   return Category.kInteger;
			case TOK_char:    return Category.kInteger;
			case TOK_wchar:   return Category.kInteger;
			case TOK_dchar:   return Category.kInteger;
			case TOK_float:   return Category.kFloat;
			case TOK_double:  return Category.kFloat;
			case TOK_real:    return Category.kFloat;
			case TOK_ifloat:  return Category.kFloat;
			case TOK_idouble: return Category.kFloat;
			case TOK_ireal:   return Category.kFloat;
			case TOK_cfloat:  return Category.kComplex;
			case TOK_cdouble: return Category.kComplex;
			case TOK_creal:   return Category.kComplex;
			case TOK_void:    return Category.kVoid;
			default: assert(false);
		}
	}
	
	bool convertableFrom(Type from, ConversionFlags flags)
	{
		if(super.convertableFrom(from, flags))
			return true;

		auto bt = cast(BasicType) from;
		if(!bt)
			return false;

		if(flags & ConversionFlags.kAllowBaseTypeConversion)
			return category(id) == category(bt.id);
		return id == bt.id;
	}
	
	void toD(CodeWriter writer)
	{
		assert(id != TOK_auto);
		writer(id);
	}
}

//AutoType:
//    auto added implicitely if there is no other type specified
class AutoType : Type
{
	mixin ForwardCtor!();

	bool propertyNeedsParens() const { return false; }
	
	void toD(CodeWriter writer)
	{
		if(id != TOK_auto) // only implicitely added?
			writer(id);
	}
}

//ModifiedType:
//    [Type]
class ModifiedType : Type
{
	mixin ForwardCtor!();

	bool propertyNeedsParens() const { return true; }
	
	Type getType() { return getMember!Type(0); }
	
	void typeSemantic(Scope sc)
	{
		TypeInfo_Const ti;
		switch(id)
		{
			case TOK_const:     ti = new TypeInfo_Const; break;
			case TOK_immutable: ti = new TypeInfo_Invariant; break;
			case TOK_inout:     ti = new TypeInfo_Inout;  break;
			case TOK_shared:    ti = new TypeInfo_Shared; break;
		}
		
		auto type = getType();
		type.semantic(sc);
		ti.next = type.typeinfo;
		
		typeinfo = ti;
	}
	
	bool convertableFrom(Type from, ConversionFlags flags)
	{
		if(super.convertableFrom(from, flags))
			return true;
		
		Type nextThis = getType();
		auto modfrom = cast(ModifiedType) from;
		if(modfrom)
		{
			Type nextFrom = modfrom.getType();
			if(id == modfrom.id)
				if(nextThis.convertableFrom(nextFrom, flags))
					return true;
		
			if(flags & ConversionFlags.kAllowConstConversion)
				if(id == TOK_const && modfrom.id == TOK_immutable)
					if(nextThis.convertableFrom(nextFrom, flags))
						return true;
		}
		if(flags & ConversionFlags.kAllowConstConversion)
			if(id == TOK_const)
				if(nextThis.convertableFrom(from, flags))
					return true;
		return false;
	}

	Value createValue()
	{
		return getType().createValue(); // ignore modifier
	}
	
	void toD(CodeWriter writer)
	{
		writer(id, "(", getMember(0), ")");
	}
}

//IdentifierType:
//    [IdentifierList]
class IdentifierType : Type
{
	mixin ForwardCtor!();

	bool propertyNeedsParens() const { return false; }
	
	IdentifierList getIdentifierList() { return getMember!IdentifierList(0); }
	
	void typeSemantic(Scope sc)
	{
		auto idlist = getIdentifierList();
		idlist.semantic(sc);
	}
	
	void toD(CodeWriter writer)
	{
		writer(getMember(0));
	}
}


//Typeof:
//    [Expression/Type_opt IdentifierList_opt]
class Typeof : Type
{
	mixin ForwardCtor!();

	bool propertyNeedsParens() const { return false; }
	
	bool isReturn() { return id == TOK_return; }
	
	IdentifierList getIdentifierList() { return getMember!IdentifierList(1); }
	
	void toD(CodeWriter writer)
	{
		if(isReturn())
			writer("typeof(return)");
		else
			writer("typeof(", getMember(0), ")");
		if(auto identifierList = getIdentifierList())
			writer(".", identifierList);
	}
}

// base class for types that have an indirection, i.e. pointer and arrays
class TypeIndirection : Type
{
	mixin ForwardCtor!();

	bool propertyNeedsParens() const { return true; }
	
	Type getType() { return getMember!Type(0); }
	
	bool convertableFrom(Type from, ConversionFlags flags)
	{
		if(super.convertableFrom(from, flags))
			return true;
		
		Type nextThis = getType();
		if(this.classinfo != from.classinfo)
			return false;
		auto ifrom = static_cast!TypeIndirection(from);
		assert(ifrom);
	
		// could allow A* -> const(B*) if class A derives from B
		// even better    -> head_const(B*)
		return nextThis.convertableFrom(ifrom.getType(), flags & ~ConversionFlags.kIndirectionClear);
	}
}

//TypePointer:
//    [Type]
class TypePointer : TypeIndirection
{
	mixin ForwardCtor!();

	void typeSemantic(Scope sc)
	{
		auto type = getType();
		type.semantic(sc);
		auto typeinfo_ptr = new TypeInfo_Pointer;
		typeinfo_ptr.m_next = type.typeinfo;
		typeinfo = typeinfo_ptr;
	}

	Value createValue()
	{
		return new PointerValue();
	}
	
	void toD(CodeWriter writer)
	{
		writer(getMember(0), "*");
	}
}

//TypeDynamicArray:
//    [Type]
class TypeDynamicArray : TypeIndirection
{
	mixin ForwardCtor!();

	void typeSemantic(Scope sc)
	{
		auto type = getType();
		type.semantic(sc);
		auto typeinfo_arr = new TypeInfo_Array;
		typeinfo_arr.value = type.typeinfo;
		typeinfo = typeinfo_arr;
	}
	
	bool convertableFrom(Type from, ConversionFlags flags)
	{
		if(super.convertableFrom(from, flags))
			return true;
		
		if(from.classinfo == typeid(TypeStaticArray))
		{
			Type nextThis = getType();
			auto arrfrom = static_cast!TypeStaticArray(from);
			assert(arrfrom);
	
			// should allow A[] -> const(B[]) if class A derives from B
			// even better      -> head_const(B[])
			if(nextThis.convertableFrom(arrfrom.getType(), flags & ~ConversionFlags.kIndirectionClear))
				return true;
		}
		return false;
	}
	
	void toD(CodeWriter writer)
	{
		writer(getMember(0), "[]");
	}
}

//SuffixDynamicArray:
//    []
class SuffixDynamicArray : Node
{
	mixin ForwardCtor!();

	void toD(CodeWriter writer)
	{
		writer("[]");
	}
}

//TypeStaticArray:
//    [Type Expression]
class TypeStaticArray : TypeIndirection
{
	mixin ForwardCtor!();

	Expression getDimension() { return getMember!Expression(1); }
	
	void typeSemantic(Scope sc)
	{
		auto type = getType();
		type.semantic(sc);
		auto typeinfo_arr = new TypeInfo_StaticArray;
		typeinfo_arr.value = type.typeinfo;
		typeinfo_arr.len = getDimension().interpret(sc).toInt();
		typeinfo = typeinfo_arr;
	}

	void toD(CodeWriter writer)
	{
		writer(getMember(0), "[", getMember(1), "]");
	}
}

//SuffixStaticArray:
//    [Expression]
class SuffixStaticArray : Node
{
	mixin ForwardCtor!();

	Expression getDimension() { return getMember!Expression(0); }
	
	void toD(CodeWriter writer)
	{
		writer("[", getMember(0), "]");
	}
}

//TypeAssocArray:
//    [Type Type]
class TypeAssocArray : TypeIndirection
{
	mixin ForwardCtor!();

	Type getKeyType() { return getMember!Type(1); }
	
	void typeSemantic(Scope sc)
	{
		auto vtype = getType();
		vtype.semantic(sc);
		auto ktype = getKeyType();
		ktype.semantic(sc);
		
		auto typeinfo_arr = new TypeInfo_AssociativeArray;
		typeinfo_arr.value = vtype.typeinfo;
		typeinfo_arr.key = ktype.typeinfo;
		typeinfo = typeinfo_arr;
	}

	bool convertableFrom(Type from, ConversionFlags flags)
	{
		if(super.convertableFrom(from, flags))
		{
			auto aafrom = static_cast!TypeAssocArray(from); // verified in super.convertableFrom
			if(getKeyType().convertableFrom(aafrom.getKeyType(), flags & ~ConversionFlags.kIndirectionClear))
				return true;
		}
		return false;
	}
	
	void toD(CodeWriter writer)
	{
		writer(getMember(0), "[", getMember(1), "]");
	}
}

//SuffixAssocArray:
//    [Type]
class SuffixAssocArray : Node
{
	mixin ForwardCtor!();

	Type getKeyType() { return getMember!Type(0); }
	
	void toD(CodeWriter writer)
	{
		writer("[", getMember(0), "]");
	}
}

//TypeArraySlice:
//    [Type Expression Expression]
class TypeArraySlice : Type
{
	mixin ForwardCtor!();

	bool propertyNeedsParens() const { return true; }
	
	Type getType() { return getMember!Type(0); }
	Expression getLower() { return getMember!Expression(1); }
	Expression getUpper() { return getMember!Expression(2); }

	void typeSemantic(Scope sc)
	{
		auto rtype = getType();
		if(auto tpl = cast(TypeInfo_Tuple) rtype.typeinfo)
		{
			int lo = getLower().interpret(sc).toInt();
			int up = getUpper().interpret(sc).toInt();
			if(lo > up || lo < 0 || up > tpl.elements.length)
			{
				semanticError("tuple slice out of bounds");
				typeinfo = tpl;
			}
			else
			{
				auto ntpl = new TypeInfo_Tuple;
				ntpl.elements = tpl.elements[lo..up];
				typeinfo = ntpl;
			}
		}
		else
		{
			semanticError("type is not a tuple");
			typeinfo = rtype.typeinfo;
		}
	}

	void toD(CodeWriter writer)
	{
		writer(getMember(0), "[", getLower(), " .. ", getUpper(), "]");
	}
}

//TypeDelegate:
//    [Type ParameterList]
class TypeDelegate : Type
{
	mixin ForwardCtor!();

	bool propertyNeedsParens() const { return true; }
	
	Type getReturnType() { return getMember!Type(0); }
	ParameterList getParameters() { return getMember!ParameterList(1); }
	
	void typeSemantic(Scope sc)
	{
		auto ti_dg = new TypeInfo_DelegateX;
			
		auto rtype = getReturnType();
		rtype.semantic(sc);
		auto params = getParameters();
		params.semantic(sc);
		
		ti_dg.next = rtype.typeinfo;
		ti_dg.parameters = new TypeInfo_Tuple;
		for(int p = 0; p < params.members.length; p++)
			ti_dg.parameters.elements ~= params.getParameter(p).getParameterDeclarator().getType().typeinfo;
		ti_dg.attributes = combineAttributes(attr, params.attr);
		// no context information when defining the type, only with an instance
		typeinfo = ti_dg;
	}

	void toD(CodeWriter writer)
	{
		writer(getReturnType(), " delegate", getParameters());
		writer.writeAttributes(attr, true);
	}
}

//TypeFunction:
//    [Type ParameterList]
class TypeFunction : Type
{
	mixin ForwardCtor!();

	bool propertyNeedsParens() const { return true; }
	
	Type getReturnType() { return getMember!Type(0); }
	ParameterList getParameters() { return getMember!ParameterList(1); }
	
	void typeSemantic(Scope sc)
	{
		auto ti_fn = new TypeInfo_FunctionX;
			
		auto rtype = getReturnType();
		rtype.semantic(sc);
		auto params = getParameters();
		params.semantic(sc);
		
		ti_fn.next = rtype.typeinfo;
		ti_fn.parameters = new TypeInfo_Tuple;
		for(int p = 0; p < params.members.length; p++)
			ti_fn.parameters.elements ~= params.getParameter(p).getParameterDeclarator().getType().typeinfo;
		ti_fn.attributes = combineAttributes(attr, params.attr);
		typeinfo = ti_fn;
	}

	void toD(CodeWriter writer)
	{
		writer(getReturnType(), " function", getParameters());
		writer.writeAttributes(attr, true);
	}
}

class TypeInfo_FunctionX : TypeInfo_Function
{
	TypeInfo_Tuple parameters;
	int attributes;
}

class TypeInfo_DelegateX : TypeInfo_Delegate
{
	TypeInfo_Tuple parameters;
	int attributes;
	TypeInfo context;
}

TypeDynamicArray createTypeString(ref const(TextSpan) span)
{
	auto arr = new TypeDynamicArray(span);
			
	BasicType ct = new BasicType(TOK_char, span);
	ModifiedType mt = new ModifiedType(TOK_immutable, span);
	mt.addMember(ct);
	arr.addMember(mt);
	return arr;
}
