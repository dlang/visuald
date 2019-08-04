module vdc.dmdserver.dmdinit;

import dmd.arraytypes;
import dmd.builtin;
import dmd.cond;
import dmd.ctfeexpr;
import dmd.dclass;
import dmd.declaration;
import dmd.dimport;
import dmd.dinterpret;
import dmd.dmodule;
import dmd.dstruct;
import dmd.dsymbol;
import dmd.dtemplate;
import dmd.expression;
import dmd.func;
import dmd.globals;
import dmd.id;
import dmd.mtype;
import dmd.objc;
import dmd.target;

import dmd.root.outbuffer;

////////////////////////////////////////////////////////////////
alias countersType = uint[uint]; // actually uint[Key]

enum string[2][] dmdStatics =
[
	["_D3dmd5clone12buildXtoHashFCQBa7dstruct17StructDeclarationPSQCg6dscope5ScopeZ8tftohashCQDh5mtype12TypeFunction", "TypeFunction"],
	["_D3dmd7dstruct15search_toStringRCQBfQBe17StructDeclarationZ10tftostringCQCs5mtype12TypeFunction", "TypeFunction"],
	["_D3dmd13expressionsem11loadStdMathFZ10impStdMathCQBv7dimport6Import", "Import"],
	["_D3dmd4func15FuncDeclaration8genCfuncRPSQBm4root5array__T5ArrayTCQCl5mtype9ParameterZQBcCQDjQy4TypeCQDu10identifier10IdentifiermZ2stCQFb7dsymbol12DsymbolTable", "DsymbolTable"],
	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeSQBr7globals3LocPSQCi6dscope5ScopeZ11visitAArrayMFCQDpQCn10TypeAArrayZ3feqCQEn4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeSQBr7globals3LocPSQCi6dscope5ScopeZ11visitAArrayMFCQDpQCn10TypeAArrayZ4fcmpCQEo4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeSQBr7globals3LocPSQCi6dscope5ScopeZ11visitAArrayMFCQDpQCn10TypeAArrayZ5fhashCQEp4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd7typesem6dotExpFCQv5mtype4TypePSQBk6dscope5ScopeCQCb10expression10ExpressionCQDdQBc8DotIdExpiZ11visitAArrayMFCQEkQDq10TypeAArrayZ8fd_aaLenCQFn4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd7typesem6dotExpFCQv5mtype4TypePSQBk6dscope5ScopeCQCb10expression10ExpressionCQDdQBc8DotIdExpiZ8noMemberMFQDlQDaQClCQEp10identifier10IdentifieriZ4nesti", "int"],
	["_D3dmd6dmacro5Macro6expandMFPSQBc4root9outbuffer9OutBufferkPkAxaZ4nesti", "int"], // x86
	["_D3dmd7dmodule6Module19runDeferredSemanticRZ6nestedi", "int"],
	["_D3dmd10dsymbolsem22DsymbolSemanticVisitor5visitMRCQBx9dtemplate13TemplateMixinZ4nesti", "int"],
	["_D3dmd9dtemplate16TemplateInstance16tryExpandMembersMFPSQCc6dscope5ScopeZ4nesti", "int"],
	["_D3dmd9dtemplate16TemplateInstance12trySemantic3MFPSQBy6dscope5ScopeZ4nesti", "int"],
	["_D3dmd13expressionsem25ExpressionSemanticVisitor5visitMRCQCd10expression7CallExpZ4nesti", "int"],
	["_D3dmd5lexer5Lexer12stringbufferSQBf4root9outbuffer9OutBuffer", "OutBuffer"],
	["_D3dmd10expression10IntegerExp__T7literalVii0ZQnRZ11theConstantCQCkQCjQCa", "IntegerExp"],
	["_D3dmd10expression10IntegerExp__T7literalVii1ZQnRZ11theConstantCQCkQCjQCa", "IntegerExp"],
	["_D3dmd10expression10IntegerExp__T7literalViN1ZQnRZ11theConstantCQCkQCjQCa", "IntegerExp"],
	["_D3dmd10identifier10Identifier17generateIdWithLocFNbAyaKxSQCe7globals3LocZ8countersHSQDfQDeQCvQCmFNbQBwKxQBwZ3Keyk", "countersType"],
	["_D3dmd10identifier10Identifier10generateIdRNbPxaZ1im", "int"],
	["_D3dmd5lexer5Lexer4scanMFNbPSQBb6tokens5TokenZ8initdoneb", "bool"],
];

string cmangled(string s)
{
	version (Win64)
		if (s ==   "_D3dmd6dmacro5Macro6expandMFPSQBc4root9outbuffer9OutBufferkPkAxaZ4nesti")
			return "_D3dmd6dmacro5Macro6expandMFPSQBc4root9outbuffer9OutBuffermPmAxaZ4nesti";
	return s;
}

string genDeclDmdStatics()
{
	string s;
	foreach (decl; dmdStatics)
		s ~= q{extern extern(C) __gshared } ~ decl[1] ~ " " ~ cmangled(decl[0]) ~ ";\n";
		return s;
}

string genInitDmdStatics()
{
	string s;
	foreach (decl; dmdStatics)
		s ~= cmangled(decl[0]) ~ " = " ~ decl[1] ~ ".init;\n";
	return s;
}

mixin(genDeclDmdStatics);

pragma(mangle, "_D3dmd12statementsem24StatementSemanticVisitor5visitMRCQCb9statement16ForeachStatementZ7fdapplyPCQDr4func15FuncDeclaration")
extern __gshared FuncDeclaration* statementsem_fdapply;
pragma(mangle, "_D3dmd12statementsem24StatementSemanticVisitor5visitMRCQCb9statement16ForeachStatementZ6fldeTyPCQDq5mtype12TypeDelegate")
extern __gshared TypeDelegate* statementsem_fldeTy;


void clearSemanticStatics()
{
	/*
	import core.demangle;
	static foreach(s; dmdStatics)
	pragma(msg, demangle(s[0]));
	*/
	mixin(genInitDmdStatics);

	// statementsem
	// static __gshared FuncDeclaration* fdapply = [null, null];
	// static __gshared TypeDelegate* fldeTy = [null, null];
	statementsem_fdapply[0] = statementsem_fdapply[1] = null;
	statementsem_fldeTy[0]  = statementsem_fldeTy[1] = null;

	// dmd.dtemplate
	emptyArrayElement = null;
	TemplateValueParameter.edummies = null;
	TemplateTypeParameter.tdummy = null;
	TemplateAliasParameter.sdummy = null;

	CtfeStatus.callDepth = 0;
	CtfeStatus.stackTraceCallsToSuppress = 0;
	CtfeStatus.maxCallDepth = 0;
	CtfeStatus.numAssignments = 0;

	VarDeclaration.nextSequenceNumber = 0;

	// Package.this.packageTag?
	// funcDeclarationSemantic.printedMain?
	/+
	Type.stringtable.reset();

	dinterpret_init();

	Scope.freelist = null;
	//Token.freelist = null;

	Identifier.initTable();
	+/
}

// initialization that are necessary once
void dmdInit()
{
	__gshared bool initialized;
	if (initialized)
		return;
	initialized = true;

	import dmd.root.longdouble;
	// Initialization
	version(CRuntime_Microsoft)
		initFPU();

	global.params.isWindows = true;
	global._init();
	//Token._init();
	Id.initialize();
	Expression._init();
	builtin_init();

	target._init(global.params); // needed by Type._init
	Type._init();

	dmdReinit(true);
}

// initialization that are necessary before restarting an analysis (which might run
// for another platform/architecture)
void dmdReinit(bool configChanged)
{
	if (configChanged)
	{
		target._init(global.params); // needed by Type._init
		Type._reinit();

		// assume object.d unmodified otherwis
		Module.moduleinfo = null;

		ClassDeclaration.object = null;
		ClassDeclaration.throwable = null;
		ClassDeclaration.exception = null;
		ClassDeclaration.errorException = null;
		ClassDeclaration.cpp_type_info_ptr = null;

		StructDeclaration.xerreq = null;
		StructDeclaration.xerrcmp = null;

		Type.dtypeinfo = null;
		Type.typeinfoclass = null;
		Type.typeinfointerface = null;
		Type.typeinfostruct = null;
		Type.typeinfopointer = null;
		Type.typeinfoarray = null;
		Type.typeinfostaticarray = null;
		Type.typeinfoassociativearray = null;
		Type.typeinfovector = null;
		Type.typeinfoenum = null;
		Type.typeinfofunction = null;
		Type.typeinfodelegate = null;
		Type.typeinfotypelist = null;
		Type.typeinfoconst = null;
		Type.typeinfoinvariant = null;
		Type.typeinfoshared = null;
		Type.typeinfowild = null;
		Type.rtinfo = null;
	}
	Objc._init();

	Module._init();
	Module.amodules = Module.amodules.init;
	Module.deferred = Dsymbols();    // deferred Dsymbol's needing semantic() run on them
	Module.deferred2 = Dsymbols();   // deferred Dsymbol's needing semantic2() run on them
	Module.deferred3 = Dsymbols();   // deferred Dsymbol's needing semantic3() run on them
	Module.dprogress = 0;      // progress resolving the deferred list

	dinterpret_init();

	clearSemanticStatics();
}

// plain copy of dmd.mars.addDefaultVersionIdentifiers
void addDefaultVersionIdentifiers(const ref Param params)
{
    VersionCondition.addPredefinedGlobalIdent("DigitalMars");
    if (params.isWindows)
    {
        VersionCondition.addPredefinedGlobalIdent("Windows");
        if (global.params.mscoff)
        {
            VersionCondition.addPredefinedGlobalIdent("CRuntime_Microsoft");
            VersionCondition.addPredefinedGlobalIdent("CppRuntime_Microsoft");
        }
        else
        {
            VersionCondition.addPredefinedGlobalIdent("CRuntime_DigitalMars");
            VersionCondition.addPredefinedGlobalIdent("CppRuntime_DigitalMars");
        }
    }
    else if (params.isLinux)
    {
        VersionCondition.addPredefinedGlobalIdent("Posix");
        VersionCondition.addPredefinedGlobalIdent("linux");
        VersionCondition.addPredefinedGlobalIdent("ELFv1");
        VersionCondition.addPredefinedGlobalIdent("CRuntime_Glibc");
        VersionCondition.addPredefinedGlobalIdent("CppRuntime_Gcc");
    }
    else if (params.isOSX)
    {
        VersionCondition.addPredefinedGlobalIdent("Posix");
        VersionCondition.addPredefinedGlobalIdent("OSX");
        VersionCondition.addPredefinedGlobalIdent("CppRuntime_Clang");
        // For legacy compatibility
        VersionCondition.addPredefinedGlobalIdent("darwin");
    }
    else if (params.isFreeBSD)
    {
        VersionCondition.addPredefinedGlobalIdent("Posix");
        VersionCondition.addPredefinedGlobalIdent("FreeBSD");
        VersionCondition.addPredefinedGlobalIdent("ELFv1");
        VersionCondition.addPredefinedGlobalIdent("CppRuntime_Clang");
    }
    else if (params.isOpenBSD)
    {
        VersionCondition.addPredefinedGlobalIdent("Posix");
        VersionCondition.addPredefinedGlobalIdent("OpenBSD");
        VersionCondition.addPredefinedGlobalIdent("ELFv1");
        VersionCondition.addPredefinedGlobalIdent("CppRuntime_Gcc");
    }
    else if (params.isDragonFlyBSD)
    {
        VersionCondition.addPredefinedGlobalIdent("Posix");
        VersionCondition.addPredefinedGlobalIdent("DragonFlyBSD");
        VersionCondition.addPredefinedGlobalIdent("ELFv1");
        VersionCondition.addPredefinedGlobalIdent("CppRuntime_Gcc");
    }
    else if (params.isSolaris)
    {
        VersionCondition.addPredefinedGlobalIdent("Posix");
        VersionCondition.addPredefinedGlobalIdent("Solaris");
        VersionCondition.addPredefinedGlobalIdent("ELFv1");
        VersionCondition.addPredefinedGlobalIdent("CppRuntime_Sun");
    }
    else
    {
        assert(0);
    }
    VersionCondition.addPredefinedGlobalIdent("LittleEndian");
    VersionCondition.addPredefinedGlobalIdent("D_Version2");
    VersionCondition.addPredefinedGlobalIdent("all");

    if (params.cpu >= CPU.sse2)
    {
        VersionCondition.addPredefinedGlobalIdent("D_SIMD");
        if (params.cpu >= CPU.avx)
            VersionCondition.addPredefinedGlobalIdent("D_AVX");
        if (params.cpu >= CPU.avx2)
            VersionCondition.addPredefinedGlobalIdent("D_AVX2");
    }

    if (params.is64bit)
    {
        VersionCondition.addPredefinedGlobalIdent("D_InlineAsm_X86_64");
        VersionCondition.addPredefinedGlobalIdent("X86_64");
        if (params.isWindows)
        {
            VersionCondition.addPredefinedGlobalIdent("Win64");
        }
    }
    else
    {
        VersionCondition.addPredefinedGlobalIdent("D_InlineAsm"); //legacy
        VersionCondition.addPredefinedGlobalIdent("D_InlineAsm_X86");
        VersionCondition.addPredefinedGlobalIdent("X86");
        if (params.isWindows)
        {
            VersionCondition.addPredefinedGlobalIdent("Win32");
        }
    }

    if (params.isLP64)
        VersionCondition.addPredefinedGlobalIdent("D_LP64");
    if (params.doDocComments)
        VersionCondition.addPredefinedGlobalIdent("D_Ddoc");
    if (params.cov)
        VersionCondition.addPredefinedGlobalIdent("D_Coverage");
    static if(__traits(compiles, PIC.fixed))
    {
        // dmd 2.088
        if (params.pic != PIC.fixed)
            VersionCondition.addPredefinedGlobalIdent(params.pic == PIC.pic ? "D_PIC" : "D_PIE");
    }
    else if (params.pic)
        VersionCondition.addPredefinedGlobalIdent("D_PIC");

    if (params.useUnitTests)
        VersionCondition.addPredefinedGlobalIdent("unittest");
    if (params.useAssert == CHECKENABLE.on)
        VersionCondition.addPredefinedGlobalIdent("assert");
    if (params.useArrayBounds == CHECKENABLE.off)
        VersionCondition.addPredefinedGlobalIdent("D_NoBoundsChecks");
    if (params.betterC)
    {
        VersionCondition.addPredefinedGlobalIdent("D_BetterC");
    }
    else
    {
        VersionCondition.addPredefinedGlobalIdent("D_ModuleInfo");
        VersionCondition.addPredefinedGlobalIdent("D_Exceptions");
        VersionCondition.addPredefinedGlobalIdent("D_TypeInfo");
    }

    VersionCondition.addPredefinedGlobalIdent("D_HardFloat");
}

