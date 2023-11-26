// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2019 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.dmdserver.dmdinit;

import dmd.arraytypes;
import dmd.builtin;
import dmd.cond;
import dmd.compiler;
import dmd.ctfeexpr;
import dmd.dclass;
import dmd.declaration;
import dmd.dimport;
import dmd.dinterpret;
import dmd.dmdparams;
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

import dmd.common.outbuffer;
import dmd.root.ctfloat;

import std.string;
import core.stdc.string;

////////////////////////////////////////////////////////////////
alias countersType = uint[uint]; // actually uint[Key]

enum string[2][] dmdStatics =
[
	["_D3dmd5clone12buildXtoHashFCQBa7dstruct17StructDeclarationPSQCg6dscope5ScopeZ8tftohashCQDh5mtype12TypeFunction", "TypeFunction"],
	["_D3dmd7dstruct15search_toStringRCQBfQBe17StructDeclarationZ10tftostringCQCs5mtype12TypeFunction", "TypeFunction"],
	// 2.103
	["_D3dmd7dmodule6Module11loadStdMathFZ8std_mathCQBsQBrQBm", "Module"],
	["_D3dmd7dmodule6Module14loadCoreAtomicFZ11core_atomicCQBzQByQBt", "Module"],
	
	["_D3dmd4func15FuncDeclaration8genCfuncRPSQBm4root5array__T5ArrayTCQCl5mtype9ParameterZQBcCQDjQy4TypeCQDu10identifier10IdentifiermZ2stCQFb7dsymbol12DsymbolTable", "DsymbolTable"],
	// 2.091
//	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeSQBr7globals3LocPSQCi6dscope5ScopeZ11visitAArrayMFCQDpQCn10TypeAArrayZ3feqCQEn4func15FuncDeclaration", "FuncDeclaration"],
//	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeSQBr7globals3LocPSQCi6dscope5ScopeZ11visitAArrayMFCQDpQCn10TypeAArrayZ4fcmpCQEo4func15FuncDeclaration", "FuncDeclaration"],
//	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeSQBr7globals3LocPSQCi6dscope5ScopeZ11visitAArrayMFCQDpQCn10TypeAArrayZ5fhashCQEp4func15FuncDeclaration", "FuncDeclaration"],
//	["_D3dmd5lexer5Lexer4scanMFNbPSQBb6tokens5TokenZ8initdoneb", "bool"],
	// 2.092
//	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeKxSQBt7globals3LocPSQCk6dscope5ScopeZ11visitAArrayMFCQDrQCp10TypeAArrayZ3feqCQEp4func15FuncDeclaration", "FuncDeclaration"],
//	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeKxSQBt7globals3LocPSQCk6dscope5ScopeZ11visitAArrayMFCQDrQCp10TypeAArrayZ4fcmpCQEq4func15FuncDeclaration", "FuncDeclaration"],
//	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeKxSQBt7globals3LocPSQCk6dscope5ScopeZ11visitAArrayMFCQDrQCp10TypeAArrayZ5fhashCQEr4func15FuncDeclaration", "FuncDeclaration"],
//	["_D3dmd5lexer13TimeStampInfo8initdoneb", "bool"],
	// 2.103
	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeKxSQBt8location3LocPSQCl6dscope5ScopeZ11visitAArrayMFCQDsQCq10TypeAArrayZ3feqCQEq4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeKxSQBt8location3LocPSQCl6dscope5ScopeZ11visitAArrayMFCQDsQCq10TypeAArrayZ4fcmpCQEr4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd7typesem12typeSemanticRCQBc5mtype4TypeKxSQBt8location3LocPSQCl6dscope5ScopeZ11visitAArrayMFCQDsQCq10TypeAArrayZ5fhashCQEs4func15FuncDeclaration", "FuncDeclaration"],

	["_D3dmd7typesem6dotExpFCQv5mtype4TypePSQBk6dscope5ScopeCQCb10expression10ExpressionCQDdQBc8DotIdExpEQDtQCz10DotExpFlagZ11visitAArrayMFCQFcQEi10TypeAArrayZ8fd_aaLenCQGf4func15FuncDeclaration", "FuncDeclaration"],
	["_D3dmd7typesem6dotExpFCQv5mtype4TypePSQBk6dscope5ScopeCQCb10expression10ExpressionCQDdQBc8DotIdExpEQDtQCz10DotExpFlagZ8noMemberMFQEdQDsQDdCQFh10identifier10IdentifieriZ4nesti", "int"],
	//["_D3dmd6dmacro10MacroTable6expandMFKSQBi6common9outbuffer9OutBufferkKkAxaZ4nesti", "int"], // x86
	["_D3dmd7dmodule6Module19runDeferredSemanticRZ6nestedi", "int"],
	["_D3dmd10dsymbolsem22DsymbolSemanticVisitor5visitMRCQBx9dtemplate13TemplateMixinZ4nesti", "int"],
	["_D3dmd9dtemplate16TemplateInstance16tryExpandMembersMFPSQCc6dscope5ScopeZ4nesti", "int"],
	["_D3dmd9dtemplate16TemplateInstance12trySemantic3MFPSQBy6dscope5ScopeZ4nesti", "int"],
	["_D3dmd13expressionsem25ExpressionSemanticVisitor5visitMRCQCd10expression7CallExpZ4nesti", "int"],
	["_D3dmd5lexer5Lexer12stringbufferSQBf6common9outbuffer9OutBuffer", "OutBuffer"],
	//["_D3dmd10expression10IntegerExp__T7literalVii0ZQnRZ11theConstantCQCkQCjQCa", "IntegerExp"],
	//["_D3dmd10expression10IntegerExp__T7literalVii1ZQnRZ11theConstantCQCkQCjQCa", "IntegerExp"],
	//["_D3dmd10expression10IntegerExp__T7literalViN1ZQnRZ11theConstantCQCkQCjQCa", "IntegerExp"],

//	["_D3dmd10identifier10Identifier17generateIdWithLocFNbAyaKxSQCe7globals3LocZ8countersHSQDfQDeQCvQCmFNbQBwKxQBwZ3Keyk", "countersType"],
	// 2.103
	["_D3dmd10identifier10Identifier17generateIdWithLocFNbAyaKxSQCe8location3LocZ8countersHSQDgQDfQCwQCnFNbQBxKxQBxZ3Keyk", "countersType"],
	["_D3dmd10identifier10Identifier9newSuffixFNbZ1ik", "size_t"],
];

string cmangled(string s)
{
	version (Win64)
	{
		if (s == "_D3dmd10identifier10Identifier9newSuffixFNbZ1ik")
			return "_D3dmd10identifier10Identifier9newSuffixFNbZ1im"; // size_t
		//if (s ==   "_D3dmd6dmacro10MacroTable6expandMFKSQBi6common9outbuffer9OutBufferkKkAxaZ4nesti")
		//	return "_D3dmd6dmacro10MacroTable6expandMFKSQBi6common9outbuffer9OutBuffermKmAxaZ4nesti";
	}
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

pragma(mangle, "_D3dmd12statementsem15applyAssocArrayFCQBl9statement16ForeachStatementCQCr10expression10ExpressionCQDt5mtype4TypeZ7fdapplyPCQEs4func15FuncDeclaration")
extern __gshared FuncDeclaration* statementsem_fdapply;
pragma(mangle, "_D3dmd12statementsem15applyAssocArrayFCQBl9statement16ForeachStatementCQCr10expression10ExpressionCQDt5mtype4TypeZ6fldeTyPCQErQy12TypeDelegate")
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

	//VarDeclaration.nextSequenceNumber = 0;

	//entrypoint = cast(Module)&entrypoint; // disable generation of C main

	// Package.this.packageTag?
	// funcDeclarationSemantic.printedMain?
	/+
	Type.stringtable.reset();
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

	target.os = Target.OS.Windows;
	global._init();
	//Token._init();
	Id.initialize();
	Expression._init();

	target._init(global.params); // needed by Type._init
	Type._init();
	Module._init();
	CTFloat.initialize();
}

struct Options
{
	string[] importDirs;
	string[] stringImportDirs;

	bool unittestOn;
	bool x64;
	bool msvcrt;
	bool warnings;
	bool warnAsError;
	bool debugOn;
	bool coverage;
	bool doDoc;
	bool noBoundsCheck;
	bool gdcCompiler;
	bool ldcCompiler;
	bool noDeprecated;
	bool deprecatedInfo;
	bool mixinAnalysis;
	bool UFCSExpansions;

	bool predefineDefaultVersions;
	int versionLevel;
	string[] versionIds;
	int debugLevel;
	string[] debugIds;
	string cmdline; // more options

	uint restartMemThreshold;

	void opAssign(const ref Options opts)
	{
		import std.traits;

		static foreach(i, F; typeof(this).tupleof)
			static if(isDynamicArray!(typeof(F)))
				this.tupleof[i] = opts.tupleof[i].dup;
			else
				this.tupleof[i] = opts.tupleof[i];
	}

	bool setImportDirs(string[] dirs)
	{
		if(dirs == importDirs)
			return false;
		importDirs = dirs;
		return true;
	}
	bool setStringImportDirs(string[] dirs)
	{
		if(dirs == stringImportDirs)
			return false;
		stringImportDirs = dirs;
		return true;
	}
	bool setVersionIds(int level, string[] ids)
	{
		if(versionLevel == level && versionIds == ids)
			return false;
		versionLevel = level;
		versionIds = ids;
		return true;
	}
	bool setDebugIds(int level, string[] ids)
	{
		if(debugLevel == level && debugIds == ids)
			return false;
		debugLevel = level;
		debugIds = ids;
		return true;
	}
}

void dmdSetupParams(const ref Options opts)
{
	global = global.init;

	global._init();
	target.os = Target.OS.Windows;
	global.params.errorLimit = 0;
	global.params.color = false;
//	global.params.link = true;
	global.params.useUnitTests = opts.unittestOn;
	global.params.useAssert = opts.debugOn ? CHECKENABLE.on : CHECKENABLE.off;
	global.params.useInvariants = opts.debugOn ? CHECKENABLE.on : CHECKENABLE.off;
	global.params.useIn = opts.debugOn ? CHECKENABLE.on : CHECKENABLE.off;
	global.params.useOut = opts.debugOn ? CHECKENABLE.on : CHECKENABLE.off;
	global.params.useArrayBounds = opts.noBoundsCheck ? CHECKENABLE.on : CHECKENABLE.off; // set correct value later
	global.params.ddoc.doOutput = opts.doDoc;
	global.params.useSwitchError = CHECKENABLE.on;
	global.params.useInline = false;
	global.params.ignoreUnsupportedPragmas = opts.ldcCompiler;
	global.params.obj = false;
	global.params.useDeprecated = !opts.noDeprecated ? DiagnosticReporting.off
		: opts.deprecatedInfo ? DiagnosticReporting.inform : DiagnosticReporting.error ;
	global.params.warnings = !opts.warnings ? DiagnosticReporting.off
		: opts.warnAsError ? DiagnosticReporting.error : DiagnosticReporting.inform;
	global.params.linkswitches = Strings();
	global.params.libfiles = Strings();
	global.params.dllfiles = Strings();
	global.params.objfiles = Strings();
	global.params.ddoc.files = Strings();
	// Default to -m32 for 32 bit dmd, -m64 for 64 bit dmd
	target.isX86_64 = opts.x64;
	target.omfobj = !opts.msvcrt;
	target.cpu = CPU.baseline;
	target.isLP64 = opts.x64;

	string[] cli = opts.cmdline.split(' ');
	foreach(opt; cli)
	{
		switch(opt)
		{
			case "-vtls": global.params.vtls = true; break;
			case "-vgc":  global.params.vgc = true; break;
			// case "-d": // already covered by flags
			// case "-de":
			// case "-release":
			// case "-debug":
			// case "-w":
			// case "-wi":
			// case "-property": global.params.checkProperty = true; break;
			case "-betterC": global.params.betterC = true; break;
			case "-dip25":  global.params.useDIP25 = FeatureState.enabled; break;
			case "-dip1000":  global.params.useDIP25 = global.params.useDIP1000 = FeatureState.enabled; break;
			case "-dip1008":  global.params.ehnogc = true; break;
			case "-revert=import": global.params.vfield = true; break;
			case "-revert=dip25": global.params.useDIP25 = FeatureState.disabled; break;
			case "-transition=field": global.params.vfield = true; break;
			//case "-transition=checkimports": global.params.check10378 = true; break;
			case "-transition=complex": global.params.vcomplex = true; break;
//			case "-transition=vmarkdown": global.params.vmarkdown = true; break;
			case "-preview=dip1021":  global.params.useDIP1021 = true; break;
			case "-preview=fieldwise": global.params.fieldwise = FeatureState.enabled; break;
			case "-preview=intpromote": global.params.fix16997 = true; break;
			case "-preview=dtorfields": global.params.dtorFields = FeatureState.enabled; break;
//			case "-preview=markdown": global.params.markdown = true; break;
			case "-preview=rvaluerefparam": global.params.rvalueRefParam = FeatureState.enabled; break;
			case "-preview=nosharedaccess": global.params.noSharedAccess = FeatureState.enabled; break;
			case "-preview=fixAliasThis": global.params.fixAliasThis = true; break;
			case "-preview=in": global.params.previewIn = true; break;
			case "-preview=inclusiveincontracts": global.params.inclusiveInContracts = true; break;
			case "-preview=shortenedMethods": global.params.shortenedMethods = true; break;
			case "-preview=fixImmutableConv": global.params.fixImmutableConv = true; break;
			case "-preview=systemVariables": global.params.systemVariables = FeatureState.enabled; break;
			default: break;
		}
	}
	global.params.versionlevel = opts.versionLevel;
	global.params.versionids = new Strings();
	foreach(v; opts.versionIds)
		global.params.versionids.push(toStringz(v));

	global.versionids = new Identifiers();

	// Add in command line versions
	if (global.params.versionids)
		foreach (charz; *global.params.versionids)
		{
			auto ident = charz[0 .. strlen(charz)];
			if (VersionCondition.isReserved(ident))
				VersionCondition.addPredefinedGlobalIdent(ident);
			else
				VersionCondition.addGlobalIdent(ident);
		}

	if (opts.predefineDefaultVersions)
		addDefaultVersionIdentifiers(global.params, target);

	// always enable for tooltips
	global.params.ddoc.doOutput = true;

	global.params.debugids = new Strings();
	global.params.debuglevel = opts.debugLevel;
	foreach(d; opts.debugIds)
		global.params.debugids.push(toStringz(d));

	global.debugids = new Identifiers();
	if (global.params.debugids)
		foreach (charz; *global.params.debugids)
			DebugCondition.addGlobalIdent(charz[0 .. strlen(charz)]);

	global.path = new Strings();
	foreach(i; opts.importDirs)
		global.path.push(toStringz(i));

	global.filePath = new Strings();
	foreach(i; opts.stringImportDirs)
		global.filePath.push(toStringz(i));
}

// initialization that are necessary before restarting an analysis (which might run
// for another platform/architecture, different versions)
void dmdReinit()
{
	// Dsymbol.deinitialize();
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

	Objc._init();

	Module._init();
	Module.amodules = Module.amodules.init;
	Module.deferred = Dsymbols();    // deferred Dsymbol's needing semantic() run on them
	Module.deferred2 = Dsymbols();   // deferred Dsymbol's needing semantic2() run on them
	Module.deferred3 = Dsymbols();   // deferred Dsymbol's needing semantic3() run on them
	Module.rootModule = null;

	dinterpret_init();

	clearSemanticStatics();
}
