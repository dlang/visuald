// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.ast.type;

import vdc.util;
import vdc.lexer;
import vdc.semantic;
import vdc.interpret;

import vdc.ast.node;
import vdc.ast.expr;
import vdc.ast.misc;
import vdc.ast.aggr;
import vdc.ast.tmpl;
import vdc.ast.stmt;
import vdc.ast.decl;

import std.conv;

class BuiltinProperty(T) : Symbol
{
	Value value;
	
	this(T val)
	{
		value = Value.create(val);
	}
	
	override void toD(CodeWriter writer)
	{
		assert(false);
	}

	override Type calcType()
	{
		return value.getType();
	}
	override Value interpret(Context sc)
	{
		return value;
	}
}

Symbol newBuiltinProperty(T)(T val)
{
	return new BuiltinProperty!T(val);
}

class BuiltinType(T) : Node
{
}

Scope[int] builtInScopes;

Scope getBuiltinBasicTypeScope(int tokid)
{
	if(auto ps = tokid in builtInScopes)
		return *ps;
	
	Scope sc = new Scope;

	foreach(tok; BasicTypeTokens)
	{
		if (tokid == tok)
		{
			alias Token2BasicType!(tok) BT;
			
			sc.addSymbol("init",     newBuiltinProperty(BT.init));
			sc.addSymbol("sizeof",   newBuiltinProperty(BT.sizeof));
			sc.addSymbol("mangleof", newBuiltinProperty(BT.mangleof));
			sc.addSymbol("alignof",  newBuiltinProperty(BT.alignof));
			sc.addSymbol("stringof", newBuiltinProperty(BT.stringof));
			static if(__traits(compiles, BT.min))
				sc.addSymbol("min", newBuiltinProperty(BT.min));
			static if(__traits(compiles, BT.max))
				sc.addSymbol("max", newBuiltinProperty(BT.max));
		}
	}
	builtInScopes[tokid] = sc;
	return sc;
}

class Type : Node
{
	// semantic data
	TypeInfo typeinfo;
		
	mixin ForwardCtor!();

	abstract bool propertyNeedsParens() const;
	
	override Type clone()
	{
		Type n = static_cast!Type(super.clone());
		return n;
	}
	
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
	
	override void _semantic(Scope sc)
	{
		if(!typeinfo)
			typeSemantic(sc);
	}

	void typeSemantic(Scope sc)
	{
		super._semantic(sc);
	}

	override Type calcType()
	{
		return this;
	}

	override Value interpret(Context sc)
	{
		return new TypeValue(this);
	}
	
	Value getProperty(Value sv, string ident)
	{
		return null;
	}
	
	Value getProperty(Value sv, Declarator decl)
	{
		return null;
	}
	
	@disable final Value interpretProperty(Context ctx, string prop)
	{
		if(Value v = _interpretProperty(ctx, prop))
			return v;
		return semanticErrorValue("cannot calculate property ", prop, " of type ", this);
	}
	@disable Value _interpretProperty(Context ctx, string prop)
	{
		return null;
	}

	Value createValue(Context ctx, Value initValue)
	{
		return semanticErrorValue("cannot create value of type ", this);
	}

	Type opIndex(int v)
	{
		return semanticErrorType("cannot index a ", this);
	}
	
	Type opSlice(int b, int e)
	{
		return semanticErrorType("cannot slice a ", this);
	}
	
	Type opCall(Type args)
	{
		return semanticErrorType("cannot call a ", this);
	}
	
}

//BasicType only created for standard types associated with tokens
class BasicType : Type
{
	mixin ForwardCtor!();
	
	override bool propertyNeedsParens() const { return false; }
	
	static Type createType(int tokid)
	{
		BasicType type = new BasicType;
		type.id = tokid;
		return type;
	}
	
	static Type getType(int tokid)
	{
		static Type[] cachedTypes;
		if(tokid >= cachedTypes.length)
			cachedTypes.length = tokid + 1;
		if(!cachedTypes[tokid])
			cachedTypes[tokid] = createType(tokid);
		return cachedTypes[tokid];
	}

	static TypeInfo getTypeInfo(int id)
	{
		// TODO: convert foreach to table access for faster lookup
		foreach(tok; BasicTypeTokens)
		{
			if (id == tok)
				return typeid(Token2BasicType!(tok));
		}
		return null;
	}

	static size_t getSizeof(int id)
	{
		// TODO: convert foreach to table access for faster lookup
		foreach(tok; BasicTypeTokens)
		{
			if (id == tok)
				return Token2BasicType!(tok).sizeof;
		}
		assert(false);
	}

	static string getMangleof(int id)
	{
		// TODO: convert foreach to table access for faster lookup
		foreach(tok; BasicTypeTokens)
		{
			if (id == tok)
				return Token2BasicType!(tok).mangleof;
		}
		assert(false);
	}

	static size_t getAlignof(int id)
	{
		// TODO: convert foreach to table access for faster lookup
		foreach(tok; BasicTypeTokens)
		{
			if (id == tok)
				return Token2BasicType!(tok).alignof;
		}
		assert(false);
	}

	static string getStringof(int id)
	{
		// TODO: convert foreach to table access for faster lookup
		foreach(tok; BasicTypeTokens)
		{
			if (id == tok)
				return Token2BasicType!(tok).stringof;
		}
		assert(false);
	}

	static Value getMin(int id)
	{
		// TODO: convert foreach to table access for faster lookup
		foreach(tok; BasicTypeTokens)
		{
			static if(__traits(compiles, Token2BasicType!(tok).min))
				if (id == tok)
					return Value.create(Token2BasicType!(tok).min);
		}
		return .semanticErrorValue(tokenString(id), " has no min property");
	}

	static Value getMax(int id)
	{
		// TODO: convert foreach to table access for faster lookup
		foreach(tok; BasicTypeTokens)
		{
			static if(__traits(compiles, Token2BasicType!(tok).max))
				if (id == tok)
					return Value.create(Token2BasicType!(tok).max);
		}
		return .semanticErrorValue(tokenString(id), " has no max property");
	}

	override Value createValue(Context ctx, Value initValue)
	{
		// TODO: convert foreach to table access for faster lookup
		foreach(tok; BasicTypeTokens)
		{
			if (id == tok)
			{
				if(initValue)
					return createInitValue!(Token2ValueType!(tok))(ctx, initValue);
				return Value.create(Token2BasicType!(tok).init);
			}
		}
		return semanticErrorValue("cannot create value of type ", this);
	}
	
	override void typeSemantic(Scope sc)
	{
		assert(id != TOK_auto);
		typeinfo = getTypeInfo(id);
	}

	override Scope getScope()
	{
		if(!scop)
			scop = getBuiltinBasicTypeScope(id);
		return scop;
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
	
	@disable override Value _interpretProperty(Context ctx, string prop)
	{
		switch(prop)
		{
			// all types
			case "init":
				return createValue(nullContext, null);
			case "sizeof":
				return Value.create(getSizeof(id));
			case "alignof":
				return Value.create(getAlignof(id));
			case "mangleof":
				return Value.create(getMangleof(id));
			case "stringof":
				return Value.create(getStringof(id));
				
			// integer types
			case "min":
				return getMin(id);
			case "max":
				return getMax(id);
				
			// floating point types
			case "infinity":
			case "nan":
			case "dig":
			case "epsilon":
			case "mant_dig":
			case "max_10_exp":
			case "max_exp":
			case "min_10_exp":
			case "min_exp":
			case "min_normal":
			case "re":
			case "im":
			default:
				return super._interpretProperty(ctx, prop);
		}
	}
	
	override bool convertableFrom(Type from, ConversionFlags flags)
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
	
	override void toD(CodeWriter writer)
	{
		assert(id != TOK_auto);
		writer(id);
	}
}

class NullType : Type
{
	override bool propertyNeedsParens() const { return false; }
	
	override void toD(CodeWriter writer)
	{
		writer("Null");
	}
}

//AutoType:
//    auto added implicitely if there is no other type specified
class AutoType : Type
{
	mixin ForwardCtor!();

	override bool propertyNeedsParens() const { return false; }
	
	override void toD(CodeWriter writer)
	{
		if(id != TOK_auto) // only implicitely added?
			writer(id);
	}

	override Value createValue(Context ctx, Value initValue)
	{
		if(!initValue)
			return semanticErrorValue("no initializer in auto declaration");
		return initValue;
	}
}

//ModifiedType:
//    [Type]
class ModifiedType : Type
{
	mixin ForwardCtor!();

	override bool propertyNeedsParens() const { return true; }
	
	Type getType() { return getMember!Type(0); } // ignoring modifiers
	
	override void typeSemantic(Scope sc)
	{
		TypeInfo_Const ti;
		switch(id)
		{
			case TOK_const:     ti = new TypeInfo_Const; break;
			case TOK_immutable: ti = new TypeInfo_Invariant; break;
			case TOK_inout:     ti = new TypeInfo_Inout;  break;
			case TOK_shared:    ti = new TypeInfo_Shared; break;
			default: assert(false);
		}
		
		auto type = getType();
		type.semantic(sc);
		ti.next = type.typeinfo;
		
		typeinfo = ti;
	}
	
	override bool convertableFrom(Type from, ConversionFlags flags)
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

	override Value createValue(Context ctx, Value initValue)
	{
		return getType().createValue(ctx, initValue); // TODO: ignores modifier
	}
	
	override void toD(CodeWriter writer)
	{
		writer(id, "(", getMember(0), ")");
	}
}

//IdentifierType:
//    [IdentifierList]
class IdentifierType : Type
{
	mixin ForwardCtor!();

	override bool propertyNeedsParens() const { return false; }
	
	Node resolved;
	
	IdentifierList getIdentifierList() { return getMember!IdentifierList(0); }

	override void toD(CodeWriter writer)
	{
		writer(getMember(0));
	}

	override Type calcType()
	{
		auto idlist = getIdentifierList();
		idlist.semantic(getScope());
		if(idlist.resolved)
			return idlist.resolved.calcType();

		return semanticErrorType("cannot resolve type");
	}
	
	override Value interpret(Context sc)
	{
		// might also be called inside an alias, actually resolving to a value
		return new TypeValue(this);
	}
}


//Typeof:
//    [Expression/Type_opt IdentifierList_opt]
class Typeof : Type
{
	mixin ForwardCtor!();

	override bool propertyNeedsParens() const { return false; }
	
	bool isReturn() { return id == TOK_return; }
	
	IdentifierList getIdentifierList() { return getMember!IdentifierList(1); }
	
	override void toD(CodeWriter writer)
	{
		if(isReturn())
			writer("typeof(return)");
		else
			writer("typeof(", getMember(0), ")");
		if(auto identifierList = getIdentifierList())
			writer(".", identifierList);
	}
	
	override Value interpret(Context sc)
	{
		if(isReturn())
		{
			return semanticErrorValue("typeof(return) not implemented");
		}
		Node n = getMember(0);
		Type t = n.calcType();
		return new TypeValue(t);
	}
}

// base class for types that have an indirection, i.e. pointer and arrays
class TypeIndirection : Type
{
	mixin ForwardCtor!();

	override bool propertyNeedsParens() const { return true; }
	
	Type getType() { return getMember!Type(0); }
	
	override bool convertableFrom(Type from, ConversionFlags flags)
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

	override Type opIndex(int v)
	{
		return getType();
	}
	
	override Type opSlice(int b, int e)
	{
		return this;
	}
	
}

//TypePointer:
//    [Type]
class TypePointer : TypeIndirection
{
	mixin ForwardCtor!();

	override void typeSemantic(Scope sc)
	{
		auto type = getType();
		type.semantic(sc);
		auto typeinfo_ptr = new TypeInfo_Pointer;
		typeinfo_ptr.m_next = type.typeinfo;
		typeinfo = typeinfo_ptr;
	}

	override Value createValue(Context ctx, Value initValue)
	{
		auto v = PointerValue._create(this, null);
		if(initValue)
			v.opBin(ctx, TOK_assign, initValue);
		return v;
	}

	bool convertableTo(TypePointer t)
	{
		auto type = getType().calcType();
		return t.getType().calcType().compare(type);
	}

	override void toD(CodeWriter writer)
	{
		writer(getMember(0), "*");
	}
}

class LengthProperty : Symbol
{
	Type type;
	
	override Type calcType()
	{
		if(!type)
			type = BasicType.createType(TOK_uint);
		return type;
	}
		
	override Value interpret(Context sc)
	{
		if(auto ac = cast(AggrContext)sc)
		{
			if(auto dav = cast(DynArrayValue) ac.instance)
				return new SetLengthValue(dav);
			return semanticErrorValue("cannot calulate length of ", ac.instance);
		}
		return semanticErrorValue("no context to length of ", sc);
	}

	override void toD(CodeWriter writer)
	{
		writer("length");
	}
}

//TypeDynamicArray:
//    [Type]
class TypeDynamicArray : TypeIndirection
{
	mixin ForwardCtor!();

	static Scope cachedScope;
	
	override void typeSemantic(Scope sc)
	{
		auto type = getType();
		type.semantic(sc);
		auto typeinfo_arr = new TypeInfo_Array;
		typeinfo_arr.value = type.typeinfo;
		typeinfo = typeinfo_arr;
	}
	
	override bool convertableFrom(Type from, ConversionFlags flags)
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
	
	override void toD(CodeWriter writer)
	{
		writer(getMember(0), "[]");
	}

	override Scope getScope()
	{
		if(!scop)
		{
			scop = new Scope;
			scop.addSymbol("length", new LengthProperty);
		}
		return scop;
	}

	override Value createValue(Context ctx, Value initValue)
	{
		if(auto mtype = cast(ModifiedType) getType())
			if(mtype.id == TOK_immutable)
				if(auto btype = cast(BasicType) mtype.getType())
					if(btype.id == TOK_char)
						return createInitValue!StringValue(ctx, initValue);
		
		
		auto val = new DynArrayValue(this);
		// TODO: check types
		if(auto dav = cast(DynArrayValue)initValue)
			val.values = dav.values;
		return val;
	}
	
/+	Value deepCopy(Context sc, Value initValue)
	{
		auto val = new DynArrayValue(this);
		if(int dim = initValue ? initValue.interpretProperty(sc, "length").toInt() : 0)
		{
			auto type = getType();
			Value[] values;
			values.length = dim;
			IntValue idxval = new IntValue;
			for(int i = 0; i < dim; i++)
			{
				*(idxval.pval) = i;
				Value v = initValue ? initValue.opIndex(idxval) : null;
				values[i] = type.createValue(sc, v);
			}
			val.values = values;
		}
		return val;
	}
+/
}

//SuffixDynamicArray:
//    []
class SuffixDynamicArray : Node
{
	mixin ForwardCtor!();

	override void toD(CodeWriter writer)
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
	
	override void typeSemantic(Scope sc)
	{
		auto type = getType();
		type.semantic(sc);
		auto typeinfo_arr = new TypeInfo_StaticArray;
		typeinfo_arr.value = type.typeinfo;
		typeinfo_arr.len = getDimension().interpret(sc.ctx).toInt();
		typeinfo = typeinfo_arr;
	}

	override Scope getScope()
	{
		if(!scop)
		{
			Scope sc = parent.getScope();
			scop = new Scope;
			size_t len = getDimension().interpret(sc.ctx).toInt();
			scop.addSymbol("length", newBuiltinProperty(len));
		}
		return scop;
	}

	/+
	override Scope getScope()
	{
		if(!scop)
		{
			scop = createTypeScope();
			//scop.addSymbol("length", new BuiltinProperty!uint(BasicType.getType(TOK_uint), 0));
			scop.parent = super.getScope();
		}
		return scop;
	}
	+/

	override void toD(CodeWriter writer)
	{
		writer(getMember(0), "[", getMember(1), "]");
	}
	
	override Value createValue(Context ctx, Value initValue)
	{
		int dim = getDimension().interpret(ctx).toInt();
		auto val = new TupleValue;
		auto type = getType();
		Value[] values;
		values.length = dim;
		IntValue idxval = new IntValue;
		for(int i = 0; i < dim; i++)
		{
			*(idxval.pval) = i;
			Value v = initValue ? initValue.opIndex(idxval) : null;
			values[i] = type.createValue(ctx, v);
		}
		val.values = values;
		return val;
	}
	
	override Type opSlice(int b, int e)
	{
		auto da = new TypeDynamicArray;
		da.addMember(getType().clone());
		return da;
	}
	
}

//SuffixStaticArray:
//    [Expression]
class SuffixStaticArray : Node
{
	mixin ForwardCtor!();

	Expression getDimension() { return getMember!Expression(0); }
	
	override void toD(CodeWriter writer)
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
	
	override void typeSemantic(Scope sc)
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

	override bool convertableFrom(Type from, ConversionFlags flags)
	{
		if(super.convertableFrom(from, flags))
		{
			auto aafrom = static_cast!TypeAssocArray(from); // verified in super.convertableFrom
			if(getKeyType().convertableFrom(aafrom.getKeyType(), flags & ~ConversionFlags.kIndirectionClear))
				return true;
		}
		return false;
	}
	
	override void toD(CodeWriter writer)
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
	
	override void toD(CodeWriter writer)
	{
		writer("[", getMember(0), "]");
	}
}

//TypeArraySlice:
//    [Type Expression Expression]
class TypeArraySlice : Type
{
	mixin ForwardCtor!();

	override bool propertyNeedsParens() const { return true; }
	
	Type getType() { return getMember!Type(0); }
	Expression getLower() { return getMember!Expression(1); }
	Expression getUpper() { return getMember!Expression(2); }

	override void typeSemantic(Scope sc)
	{
		auto rtype = getType();
		if(auto tpl = cast(TypeInfo_Tuple) rtype.typeinfo)
		{
			int lo = getLower().interpret(sc.ctx).toInt();
			int up = getUpper().interpret(sc.ctx).toInt();
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

	override void toD(CodeWriter writer)
	{
		writer(getMember(0), "[", getLower(), " .. ", getUpper(), "]");
	}
}

//TypeFunction:
//    [Type ParameterList]
class TypeFunction : Type
{
	mixin ForwardCtor!();

	override bool propertyNeedsParens() const { return true; }
	
	Type getReturnType() { return getMember!Type(0); }
	ParameterList getParameters() { return getMember!ParameterList(1); }
	
	Declarator funcDecl; // the actual function pointer
	
	override void typeSemantic(Scope sc)
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

	override Value createValue(Context ctx, Value initValue)
	{
		auto fv = new FunctionValue;
		if(FunctionValue ifv = cast(FunctionValue) initValue)
		{
			// TODO: verfy types
			fv.functype = ifv.functype;
		}
		else if(initValue)
			return semanticErrorValue("cannot assign ", initValue, " to ", this);
		else
			fv.functype = this;
		return fv;
	}

	override Type opCall(Type args)
	{
		return getReturnType().calcType();
	}
	
	override void toD(CodeWriter writer)
	{
		writer(getReturnType(), " function", getParameters());
		writer.writeAttributes(attr, true);
	}
}

//TypeDelegate:
//    [Type ParameterList]
class TypeDelegate : TypeFunction
{
	mixin ForwardCtor!();

	override void typeSemantic(Scope sc)
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

	override Value createValue(Context ctx, Value initValue)
	{
		auto fv = new DelegateValue;
		if(DelegateValue ifv = cast(DelegateValue) initValue)
		{
			// TODO: verfy types
			fv.functype = ifv.functype;
			fv.context = ifv.context;
		}
		else if(initValue)
			return semanticErrorValue("cannot assign ", initValue, " to ", this);
		else
		{
			fv.functype = this;
			fv.context = ctx;
		}
		return fv;
	}
	
	override void toD(CodeWriter writer)
	{
		writer(getReturnType(), " delegate", getParameters());
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

class TypeString : TypeDynamicArray
{
	mixin ForwardCtor!();

	override Value createValue(Context ctx, Value initValue)
	{
		return createInitValue!StringValue(ctx, initValue);
	}
	
}

TypeDynamicArray createTypeString()
{
	TextSpan span;
	return createTypeString(span);
}

TypeDynamicArray createTypeString(ref const(TextSpan) span)
{
	auto arr = new TypeString(span);
			
	BasicType ct = new BasicType(TOK_char, span);
	ModifiedType mt = new ModifiedType(TOK_immutable, span);
	mt.addMember(ct);
	arr.addMember(mt);
	return arr;
}

TypeDynamicArray getTypeString()
{
	static TypeDynamicArray cachedTypedString;
	if(!cachedTypedString)
	{
		TextSpan span;
		cachedTypedString = createTypeString(span);
	}
	return cachedTypedString;
}

