// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.config;

import std.string;
import std.conv;
import std.path;
import std.utf;
import std.array;

import stdext.path;
import stdext.array;
import stdext.file;
import stdext.string;
import stdext.util;

import xml = visuald.xmlwrap;

import visuald.windows;
import sdk.port.vsi;
import sdk.win32.objbase;
import sdk.vsi.vsshell;

import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.hierarchy;
import visuald.chiernode;
import visuald.dproject;
import visuald.dpackage;
import visuald.build;
import visuald.propertypage;
import visuald.stringutil;
import visuald.fileutil;
import visuald.lexutil;

///////////////////////////////////////////////////////////////

const string[] kPlatforms = [ "Win32", "x64" ];

enum string kToolResourceCompiler = "Resource Compiler";
const string kCmdLogFileExtension = "build";

///////////////////////////////////////////////////////////////

T clone(T)(T object)
{
	auto size = object.classinfo.init.length;
	object = cast(T) ((cast(void*)object) [0..size].dup.ptr );
//	object.__monitor = null;
	return object;
}

///////////////////////////////////////////////////////////////

ubyte  toUbyte(string s) { return to!(ubyte)(s); }
float  toFloat(string s) { return to!(float)(s); }
string uintToString(uint x) { return to!(string)(x); }

string toElem(bool b) { return b ? "1" : "0"; }
string toElem(float f) { return to!(string)(f); }
string toElem(string s) { return s; }
string toElem(uint x) { return uintToString(x); }

void _fromElem(xml.Element e, ref string x) { x = e.text(); }
void _fromElem(xml.Element e, ref bool x)   { x = e.text() == "1"; }
void _fromElem(xml.Element e, ref ubyte x)  { x = toUbyte(e.text()); }
void _fromElem(xml.Element e, ref uint x)   { x = toUbyte(e.text()); }
void _fromElem(xml.Element e, ref float x)  { x = toFloat(e.text()); }

void fromElem(T)(xml.Element e, string s, ref T x)
{
	if(xml.Element el = xml.getElement(e, s))
		_fromElem(el, x);
}

enum Compiler
{
	DMD,
	GDC,
	LDC
}

enum OutputType
{
	Executable,
	StaticLib,
	DLL
};

enum Subsystem
{
	NotSet,
	Console,
	Windows,
	Native,
	Posix
};

class ProjectOptions
{
	bool obj;		// write object file
	bool link;		// perform link
	ubyte lib;		// write library file instead of object file(s) (1: static, 2:dynamic)
	ubyte subsystem;
	bool multiobj;		// break one object file into multiple ones
	bool oneobj;		// write one object file instead of multiple ones
	bool trace;		// insert profiling hooks
	bool quiet;		// suppress non-error messages
	bool verbose;		// verbose compile
	bool vtls;		// identify thread local variables
	ubyte symdebug;		// insert debug symbolic information
	bool optimize;		// run optimizer
	ubyte cpu;		// target CPU
	bool isX86_64;		// generate X86_64 bit code
	bool isLinux;		// generate code for linux
	bool isOSX;		// generate code for Mac OSX
	bool isWindows;		// generate code for Windows
	bool isFreeBSD;		// generate code for FreeBSD
	bool isSolaris;		// generate code for Solaris
	bool scheduler;		// which scheduler to use
	bool useDeprecated;	// allow use of deprecated features
	bool useAssert;		// generate runtime code for assert()'s
	bool useInvariants;	// generate class invariant checks
	bool useIn;		// generate precondition checks
	bool useOut;		// generate postcondition checks
	ubyte useArrayBounds;	// 0: no array bounds checks
	// 1: array bounds checks for safe functions only
	// 2: array bounds checks for all functions
	bool noboundscheck;	// no array bounds checking at all
	bool useSwitchError;	// check for switches without a default
	bool useUnitTests;	// generate unittest code
	bool useInline;		// inline expand functions
	bool release;		// build release version
	bool preservePaths;	// !=0 means don't strip path from source file
	bool warnings;		// enable warnings
	bool infowarnings;	// enable informational warnings
	bool checkProperty;	// enforce property syntax
	bool genStackFrame;	// always generate stack frame
	bool pic;		// generate position-independent-code for shared libs
	bool cov;		// generate code coverage data
	bool nofloat;		// code should not pull in floating point support
	bool ignoreUnsupportedPragmas;	// rather than error on them
	float Dversion;		// D version number

	ubyte compiler;		// 0: DMD, 1: GDC, 2:LDC
	bool otherDMD;		// use explicit program path 
	string program;		// program name
	string imppath;		// array of char*'s of where to look for import modules
	string fileImppath;	// array of char*'s of where to look for file import modules
	string outdir;		// target output directory
	string objdir;		// .obj/.lib file output directory
	string objname;		// .obj file output name
	string libname;		// .lib file output name

	bool doDocComments;	// process embedded documentation comments
	string docdir;		// write documentation file to docdir directory
	string docname;		// write documentation file to docname
	string ddocfiles;	// macro include files for Ddoc
	string modules_ddoc; // generate modules.ddoc for candydoc

	bool doHdrGeneration;	// process embedded documentation comments
	string hdrdir;		// write 'header' file to docdir directory
	string hdrname;		// write 'header' file to docname

	bool doXGeneration;	// write JSON file
	string xfilename;	// write JSON file to xfilename

	uint debuglevel;	// debug level
	string debugids;	// debug identifiers

	uint versionlevel;	// version level
	string versionids;	// version identifiers

	bool dump_source;
	uint mapverbosity;
	bool createImplib;

	string defaultlibname;	// default library for non-debug builds
	string debuglibname;	// default library for debug builds

	string moduleDepsFile;	// filename for deps output

	bool run;		// run resulting executable
	string runargs;		// arguments for executable

	bool runCv2pdb;		// run cv2pdb on executable
	bool cv2pdbPre2043;		// pass version before 2.043 for older aa implementation
	bool cv2pdbNoDemangle;	// do not demangle symbols
	bool cv2pdbEnumType;	// use enumerator type 
	string pathCv2pdb;	// exe path for cv2pdb 
	string cv2pdbOptions;	// more options for cv2pdb 

	enum
	{
		kCombinedCompileAndLink,
		kSingleFileCompilation,
		kSeparateCompileAndLink,
		kSeparateCompileOnly,
	}
	uint compilationModel = kCombinedCompileAndLink;
	
	// Linker stuff
	string objfiles;
	string linkswitches;
	string libfiles;
	string libpaths;
	string deffile;
	string resfile;
	string exefile;

	string additionalOptions;
	string preBuildCommand;
	string postBuildCommand;

	// debug options
	string debugtarget;
	string debugarguments;
	string debugworkingdir;
	bool debugattach;
	string debugremote;
	ubyte debugEngine; // 0: mixed, 1: mago
	bool debugStdOutToOutputWindow;
	bool pauseAfterRunning;

	string filesToClean;
	
	this(bool dbg, bool x64)
	{
		Dversion = 2.043;
		exefile = "$(OutDir)\\$(ProjectName).exe";
		outdir = "$(ConfigurationName)";
		objdir = "$(OutDir)";
		debugtarget = "$(TARGETPATH)";
		pathCv2pdb = "$(VisualDInstallDir)cv2pdb\\cv2pdb.exe";
		program = "$(DMDInstallDir)windows\\bin\\dmd.exe";
		xfilename = "$(IntDir)\\$(TargetName).json";
		doXGeneration = true;
		
		filesToClean = "*.obj;*.cmd;*.build;*.json;*.dep";
		setDebug(dbg);
		setX64(x64);
	}

	void setDebug(bool dbg)
	{
		runCv2pdb = dbg;
		symdebug = dbg ? 1 : 0;
		release = dbg ? 0 : 1;
	}
	void setX64(bool x64)
	{
		isX86_64 = x64;
	}

	string objectFileExtension() { return compiler == 0 ? "obj" : "o"; }
	string otherCompilerPath() { return otherDMD ? program : null; }

	string buildDMDCommandLine(bool compile = true, bool performLink = true, bool deps = true, bool syntaxOnly = false)
	{
		string cmd;
		if(otherDMD && program.length)
			cmd = quoteNormalizeFilename(program);
		else
			cmd = "dmd";
		if(performLink && Package.GetGlobalOptions().demangleError)
			cmd = "\"$(VisualDInstallDir)pipedmd.exe\" " ~ cmd;
		
		if(lib == OutputType.StaticLib && performLink)
			cmd ~= " -lib";
		if(multiobj)
			cmd ~= " -multiobj";
		if(trace)
			cmd ~= " -profile";
		if(quiet)
			cmd ~= " -quiet";
		if(verbose)
			cmd ~= " -v";
		if(Dversion >= 2 && vtls)
			cmd ~= " -vtls";
		if(symdebug == 1)
			cmd ~= " -g";
		if(symdebug == 2)
			cmd ~= " -gc";
		if(optimize)
			cmd ~= " -O";
		if(useDeprecated)
			cmd ~= " -d";
		if(Dversion >= 2 && noboundscheck)
			cmd ~= " -noboundscheck";
		if(useUnitTests)
			cmd ~= " -unittest";
		if(useInline)
			cmd ~= " -inline";
		if(release)
			cmd ~= " -release";
		else
			cmd ~= " -debug";
		if(preservePaths)
			cmd ~= " -op";
		if(warnings)
			cmd ~= " -w";
		if(infowarnings)
			cmd ~= " -wi";
		if(checkProperty)
			cmd ~= " -property";
		if(genStackFrame)
			cmd ~= " -gs";
		if(cov)
			cmd ~= " -cov";
		if(nofloat)
			cmd ~= " -nofloat";
		if(ignoreUnsupportedPragmas)
			cmd ~= " -ignore";

		if(doDocComments && compile && !syntaxOnly)
		{
			cmd ~= " -D";
			if(docdir.length)
				cmd ~= " -Dd" ~ quoteNormalizeFilename(docdir);
			if(docname.length)
				cmd ~= " -Df" ~ quoteNormalizeFilename(docname);
		}

		if(doHdrGeneration && compile && !syntaxOnly)
		{
			cmd ~= " -H";
			if(hdrdir.length)
				cmd ~= " -Hd" ~ quoteNormalizeFilename(hdrdir);
			if(hdrname.length)
				cmd ~= " -Hf" ~ quoteNormalizeFilename(hdrname);
		}

		if(doXGeneration && compile && !syntaxOnly)
		{
			cmd ~= " -X";
			if(xfilename.length)
				cmd ~= " -Xf" ~ quoteNormalizeFilename(xfilename);
		}

		string[] imports = tokenizeArgs(imppath);
		foreach(imp; imports)
			if(strip(imp).length)
				cmd ~= " -I" ~ quoteNormalizeFilename(strip(imp));

		string[] globalimports = tokenizeArgs(Package.GetGlobalOptions().ImpSearchPath);
		foreach(gimp; globalimports)
			if(strip(gimp).length)
				cmd ~= " -I" ~ quoteNormalizeFilename(strip(gimp));

		string[] fileImports = tokenizeArgs(fileImppath);
		foreach(imp; fileImports)
			if(strip(imp).length)
				cmd ~= " -J" ~ quoteNormalizeFilename(strip(imp));

		string[] versions = tokenizeArgs(versionids);
		foreach(ver; versions)
			if(strip(ver).length)
				cmd ~= " -version=" ~ strip(ver);

		string[] ids = tokenizeArgs(debugids);
		foreach(id; ids)
			if(strip(id).length)
				cmd ~= " -debug=" ~ strip(id);
	
		if(deps && !syntaxOnly)
			cmd ~= " -deps=" ~ quoteNormalizeFilename(getDependenciesPath());
		if(performLink)
			cmd ~= linkCommandLine();
		return cmd;
	}
	
	string buildGDCCommandLine(bool compile = true, bool performLink = true, bool deps = true, bool syntaxOnly = false)
	{
		string cmd;
		if(otherDMD && program.length)
			cmd = quoteNormalizeFilename(program);
		else
			cmd = "gdc";

//		if(lib && performLink)
//			cmd ~= " -lib";
//		if(multiobj)
//			cmd ~= " -multiobj";
		if(lib == OutputType.DLL)
			cmd ~= " -mdll";
		if(subsystem == Subsystem.Windows)
			cmd ~= " -mwindows";
		else if(subsystem == Subsystem.Console)
			cmd ~= " -mconsole";
		if(isX86_64)
			cmd ~= " -m64";
		else
			cmd ~= " -m32";
		if(trace)
			cmd ~= " -pg";
//		if(quiet)
//			cmd ~= " -quiet";
		if(verbose)
			cmd ~= " -fd-verbose";
		if(Dversion < 2)
			cmd ~= " -fd-version=1";
		if(Dversion >= 2 && vtls)
			cmd ~= " -fd-vtls";
		if(symdebug == 1)
			cmd ~= " -g";
		if(symdebug == 2)
			cmd ~= " -fdebug-c";
		if(optimize)
			cmd ~= " -O3";
		if(useDeprecated)
			cmd ~= " -fdeprecated";
		if(Dversion >= 2 && noboundscheck)
			cmd ~= " -fno-bounds-check";
		if(useUnitTests)
			cmd ~= " -funittest";
		if(!useInline)
			cmd ~= " -fno-inline-functions";
		if(release)
			cmd ~= " -frelease";
		else
			cmd ~= " -fdebug";
//		if(preservePaths)
//			cmd ~= " -op";
		if(warnings)
			cmd ~= " -Werror";
		if(infowarnings)
			cmd ~= " -Wall";
		if(checkProperty)
			cmd ~= " -fproperty";
		if(genStackFrame)
			cmd ~= " -fno-omit-frame-pointer";
		if(cov)
			cmd ~= " -fprofile-arcs -ftest-coverage";
//		if(nofloat)
//			cmd ~= " -nofloat";
		if(ignoreUnsupportedPragmas)
			cmd ~= " -fignore-unknown-pragmas";

		if(doDocComments && compile && !syntaxOnly)
		{
			cmd ~= " -fdoc";
			if(docdir.length)
				cmd ~= " -fdoc-dir=" ~ quoteNormalizeFilename(docdir);
			if(docname.length)
				cmd ~= " -fdoc-file=" ~ quoteNormalizeFilename(docname);
		}

		if(doHdrGeneration && compile && !syntaxOnly)
		{
			cmd ~= " -fintfc";
			if(hdrdir.length)
				cmd ~= " -fintfc-dir=" ~ quoteNormalizeFilename(hdrdir);
			if(hdrname.length)
				cmd ~= " -fintfc-file=" ~ quoteNormalizeFilename(hdrname);
		}

		if(doXGeneration && compile && !syntaxOnly)
		{
			string xfile = xfilename.length ? xfilename : "$(OUTDIR)\\$(SAFEPROJECTNAME).json";
			cmd ~= " -fXf=" ~ quoteNormalizeFilename(xfile);
		}

		string[] imports = tokenizeArgs(imppath);
		foreach(imp; imports)
			if(strip(imp).length)
				cmd ~= " -I" ~ quoteNormalizeFilename(strip(imp));

		string[] globalimports = tokenizeArgs(Package.GetGlobalOptions().ImpSearchPath);
		foreach(gimp; globalimports)
			if(strip(gimp).length)
				cmd ~= " -I" ~ quoteNormalizeFilename(strip(gimp));

		string[] fileImports = tokenizeArgs(fileImppath);
		foreach(imp; fileImports)
			if(strip(imp).length)
				cmd ~= " -J" ~ quoteNormalizeFilename(strip(imp));

		string[] versions = tokenizeArgs(versionids);
		foreach(ver; versions)
			if(strip(ver).length)
				cmd ~= " -fversion=" ~ strip(ver);

		string[] ids = tokenizeArgs(debugids);
		foreach(id; ids)
			if(strip(id).length)
				cmd ~= " -fdebug=" ~ strip(id);

		if(deps && !syntaxOnly)
			cmd ~= " -fdeps=" ~ quoteNormalizeFilename(getDependenciesPath());
		if(performLink)
			cmd ~= linkCommandLine();
		return cmd;
	}

	string buildCommandLine(bool compile = true, bool performLink = true, bool deps = true, bool syntaxOnly = false)
	{
		if(compiler == Compiler.DMD)
			return buildDMDCommandLine(compile, performLink, deps, syntaxOnly);

		if(!compile && performLink && lib == OutputType.StaticLib)
			return buildARCommandLine();

		return buildGDCCommandLine(compile, performLink, deps, syntaxOnly);
	}

	string buildARCommandLine()
	{
		string cmd = "ar cru " ~ quoteNormalizeFilename(getTargetPath());
		return cmd;
	}

	string linkDMDCommandLine()
	{
		string cmd;
		
		string dmdoutfile = getTargetPath();
		if(usesCv2pdb())
			dmdoutfile ~= "_cv";

		cmd ~= " -of" ~ quoteNormalizeFilename(dmdoutfile);
		cmd ~= " -map \"$(INTDIR)\\$(SAFEPROJECTNAME).map\"";
		switch(mapverbosity)
		{
			case 0: cmd ~= " -L/NOMAP"; break; // actually still creates map file
			case 1: cmd ~= " -L/MAP:ADDRESS"; break;
			case 2: break;
			case 3: cmd ~= " -L/MAP:FULL"; break;
			case 4: cmd ~= " -L/MAP:FULL -L/XREF"; break;
			default: break;
		}

		if(lib != OutputType.StaticLib)
		{
			if(createImplib)
				cmd ~= " -L/IMPLIB:$(OUTDIR)\\$(PROJECTNAME).lib";
			if(objfiles.length)
				cmd ~= " " ~ objfiles;
			if(deffile.length)
				cmd ~= " " ~ deffile;
			if(libfiles.length)
				cmd ~= " " ~ libfiles;
			if(resfile.length)
				cmd ~= " " ~ resfile;

			switch(subsystem)
			{
				default:
				case Subsystem.NotSet: break;
				case Subsystem.Console: cmd ~= " -L/SUBSYSTEM:CONSOLE"; break;
				case Subsystem.Windows: cmd ~= " -L/SUBSYSTEM:WINDOWS"; break;
				case Subsystem.Native:  cmd ~= " -L/SUBSYSTEM:NATIVE"; break;
				case Subsystem.Posix:   cmd ~= " -L/SUBSYSTEM:POSIX"; break;
			}
		}
		return cmd;
	}

	string linkGDCCommandLine()
	{
		string cmd;

		string dmdoutfile = getTargetPath();
		if(usesCv2pdb())
			dmdoutfile ~= "_cv";

		cmd ~= " -o " ~ quoteNormalizeFilename(dmdoutfile);
		switch(mapverbosity)
		{
			case 0: // no map
				break;
			default:
				cmd ~= " -Wl,-Map=\"$(INTDIR)\\$(SAFEPROJECTNAME).map\"";
				break;
		}

		string[] lpaths = tokenizeArgs(libpaths);
		lpaths ~= tokenizeArgs(Package.GetGlobalOptions().LibSearchPath);
		foreach(lp; lpaths)
			cmd ~= " -Wl,-L," ~ quoteFilename(lp);

		if(lib != OutputType.StaticLib)
		{
//			if(createImplib)
//				cmd ~= " -L/IMPLIB:$(OUTDIR)\\$(PROJECTNAME).lib";
			if(objfiles.length)
				cmd ~= " " ~ objfiles;
			if(deffile.length)
				cmd ~= " " ~ deffile;
// added later in getCommandFileList
//			if(libfiles.length)
//				cmd ~= " " ~ libfiles;
			if(resfile.length)
				cmd ~= " " ~ resfile;
		}
		return cmd;
	}

	string optlinkCommandLine(string[] lnkfiles, string inioptions)
	{
		string cmd;
		string dmdoutfile = getTargetPath();
		if(usesCv2pdb())
			dmdoutfile ~= "_cv";
		string mapfile = "\"$(INTDIR)\\$(SAFEPROJECTNAME).map\"";

		static string plusList(string[] lnkfiles, string ext)
		{
			if(ext.length == 0 || ext[0] != '.')
				ext = "." ~ ext;
			string s;
			foreach(i, file; lnkfiles)
			{
				if(toLower(extension(file)) != ext)
					continue;
				if(s.length > 0)
					s ~= "+";
				s ~= quoteNormalizeFilename(file);
			}
			return s;
		}

		inioptions ~= " " ~ additionalOptions;
		string[] opts = tokenizeArgs(inioptions, false);
		string addopts;
		foreach(ref opt; opts)
		{
			opt = unquoteArgument(opt);
			if(opt.startsWith("-L"))
				addopts ~= " " ~ quoteFilename(opt[2..$]);
			if(opt[0] != '-')
				lnkfiles ~= opt;
		}

		cmd ~= plusList(lnkfiles, objectFileExtension());
		cmd ~= ",";
		cmd ~= quoteNormalizeFilename(dmdoutfile);
		cmd ~= ",";
		cmd ~= mapfile;
		cmd ~= ",";

		string[] libs = tokenizeArgs(libfiles);
		libs ~= "user32.lib";
		libs ~= "kernel32.lib";
		cmd ~= plusList(lnkfiles ~ libs, ".lib");
		string[] lpaths = tokenizeArgs(libpaths);
		lpaths ~= tokenizeArgs(Package.GetGlobalOptions().LibSearchPath);
		foreach(lp; lpaths)
			cmd ~= "+" ~ quoteFilename(normalizeDir(lp));
		cmd ~= ",";

		if(deffile.length)
			cmd ~= quoteNormalizeFilename(deffile);
		else
			cmd ~= plusList(lnkfiles, ".def");
		cmd ~= ",";

		if(resfile.length)
			cmd ~= quoteNormalizeFilename(resfile);
		else
			cmd ~= plusList(lnkfiles, ".res");

		// options
		// "/m" to geneate map?
		switch(mapverbosity)
		{
			case 0: cmd ~= "/NOMAP"; break; // actually still creates map file
			case 1: cmd ~= "/MAP:ADDRESS"; break;
			case 2: break;
			case 3: cmd ~= "/MAP:FULL"; break;
			case 4: cmd ~= "/MAP:FULL/XREF"; break;
			default: break;
		}

		if(symdebug)
			cmd ~= "/CO";
		cmd ~= "/NOI";

		if(lib != OutputType.StaticLib)
		{
			if(createImplib)
				cmd ~= "/IMPLIB:$(OUTDIR)\\$(PROJECTNAME).lib";
		}
		cmd ~= addopts;
		return cmd;
	}

	string linkCommandLine()
	{
		if(compiler == Compiler.GDC)
			return linkGDCCommandLine();
		else
			return linkDMDCommandLine();
	}

	string getOutputDirOption()
	{
		if(compiler != Compiler.DMD)
			return ""; // does not work with GDC
		else
			return " -od" ~ quoteFilename(objdir);
	}

	string getTargetPath()
	{
		if(exefile.length)
			return normalizePath(exefile);
		if(lib == OutputType.StaticLib)
			return "$(OutDir)\\$(ProjectName).lib";
		return "$(OutDir)\\$(ProjectName).exe";
	}

	string getDependenciesPath()
	{
		return normalizeDir(objdir) ~ "$(ProjectName).dep";
	}

	string getCommandLinePath()
	{
		return normalizeDir(objdir) ~ "$(ProjectName)." ~ kCmdLogFileExtension;
	}

	bool usesCv2pdb()
	{
		return (/*compiler == Compiler.DMD && */symdebug && runCv2pdb && lib != OutputType.StaticLib && debugEngine != 1);
	}
	
	string appendCv2pdb()
	{
		if(usesCv2pdb())
		{
			string target = getTargetPath();
			string cmd = quoteFilename(pathCv2pdb);
			if(Dversion < 2)
				cmd ~= " -D" ~ to!(string)(Dversion) ~ " ";
			else if(cv2pdbPre2043)
				cmd ~= " -D2.001";
			if(cv2pdbEnumType)
				cmd ~= " -e";
			if(cv2pdbNoDemangle)
				cmd ~= " -n";
			if(cv2pdbOptions.length)
				cmd ~= " " ~ cv2pdbOptions;

			cmd ~= " " ~ quoteFilename(target ~ "_cv") ~ " " ~ quoteFilename(target);
			return cmd;
		}
		return "";
	}

	string replaceEnvironment(string cmd, Config config, string inputfile = "", string outputfile = "")
	{
		if(indexOf(cmd, '$') < 0)
			return cmd;
		
		string configname = config.mName;
		string projectpath = config.GetProjectPath();
		string safeprojectpath = projectpath.replace(" ", "_");

		string[string] replacements;
	
		string solutionpath = GetSolutionFilename();
		if(solutionpath.length)
			addFileMacros(solutionpath, "SOLUTION", replacements);
		replacements["PLATFORMNAME"] = config.mPlatform;
		addFileMacros(projectpath, "PROJECT", replacements);
		replacements["PROJECTNAME"] = config.GetProjectName();
		addFileMacros(safeprojectpath, "SAFEPROJECT", replacements);
		replacements["SAFEPROJECTNAME"] = config.GetProjectName().replace(" ", "_");
		addFileMacros(inputfile.length ? inputfile : projectpath, "INPUT", replacements);
		replacements["CONFIGURATIONNAME"] = configname;
		replacements["OUTDIR"] = outdir;
		replacements["INTDIR"] = objdir;
		Package.GetGlobalOptions().addReplacements(replacements);

		string targetpath = outputfile.length ? outputfile : getTargetPath();
		string target = replaceMacros(targetpath, replacements);
		addFileMacros(target, "TARGET", replacements);

		return replaceMacros(cmd, replacements);
	}

	void writeXML(xml.Element elem)
	{
		elem ~= new xml.Element("obj", toElem(obj));
		elem ~= new xml.Element("link", toElem(link));
		elem ~= new xml.Element("lib", toElem(lib));
		elem ~= new xml.Element("subsystem", toElem(subsystem));
		elem ~= new xml.Element("multiobj", toElem(multiobj));
		elem ~= new xml.Element("singleFileCompilation", toElem(compilationModel));
		elem ~= new xml.Element("oneobj", toElem(oneobj));
		elem ~= new xml.Element("trace", toElem(trace));
		elem ~= new xml.Element("quiet", toElem(quiet));
		elem ~= new xml.Element("verbose", toElem(verbose));
		elem ~= new xml.Element("vtls", toElem(vtls));
		elem ~= new xml.Element("symdebug", toElem(symdebug));
		elem ~= new xml.Element("optimize", toElem(optimize));
		elem ~= new xml.Element("cpu", toElem(cpu));
		elem ~= new xml.Element("isX86_64", toElem(isX86_64));
		elem ~= new xml.Element("isLinux", toElem(isLinux));
		elem ~= new xml.Element("isOSX", toElem(isOSX));
		elem ~= new xml.Element("isWindows", toElem(isWindows));
		elem ~= new xml.Element("isFreeBSD", toElem(isFreeBSD));
		elem ~= new xml.Element("isSolaris", toElem(isSolaris));
		elem ~= new xml.Element("scheduler", toElem(scheduler));
		elem ~= new xml.Element("useDeprecated", toElem(useDeprecated));
		elem ~= new xml.Element("useAssert", toElem(useAssert));
		elem ~= new xml.Element("useInvariants", toElem(useInvariants));
		elem ~= new xml.Element("useIn", toElem(useIn));
		elem ~= new xml.Element("useOut", toElem(useOut));
		elem ~= new xml.Element("useArrayBounds", toElem(useArrayBounds));
		elem ~= new xml.Element("noboundscheck", toElem(noboundscheck));
		elem ~= new xml.Element("useSwitchError", toElem(useSwitchError));
		elem ~= new xml.Element("useUnitTests", toElem(useUnitTests));
		elem ~= new xml.Element("useInline", toElem(useInline));
		elem ~= new xml.Element("release", toElem(release));
		elem ~= new xml.Element("preservePaths", toElem(preservePaths));
		elem ~= new xml.Element("warnings", toElem(warnings));
		elem ~= new xml.Element("infowarnings", toElem(infowarnings));
		elem ~= new xml.Element("checkProperty", toElem(checkProperty));
		elem ~= new xml.Element("genStackFrame", toElem(genStackFrame));
		elem ~= new xml.Element("pic", toElem(pic));
		elem ~= new xml.Element("cov", toElem(cov));
		elem ~= new xml.Element("nofloat", toElem(nofloat));
		elem ~= new xml.Element("Dversion", toElem(Dversion));
		elem ~= new xml.Element("ignoreUnsupportedPragmas", toElem(ignoreUnsupportedPragmas));

		elem ~= new xml.Element("compiler", toElem(compiler));
		elem ~= new xml.Element("otherDMD", toElem(otherDMD));
		elem ~= new xml.Element("program", toElem(program));
		elem ~= new xml.Element("imppath", toElem(imppath));
		elem ~= new xml.Element("fileImppath", toElem(fileImppath));
		elem ~= new xml.Element("outdir", toElem(outdir));
		elem ~= new xml.Element("objdir", toElem(objdir));
		elem ~= new xml.Element("objname", toElem(objname));
		elem ~= new xml.Element("libname", toElem(libname));

		elem ~= new xml.Element("doDocComments", toElem(doDocComments));
		elem ~= new xml.Element("docdir", toElem(docdir));
		elem ~= new xml.Element("docname", toElem(docname));
		elem ~= new xml.Element("modules_ddoc", toElem(modules_ddoc));
		elem ~= new xml.Element("ddocfiles", toElem(ddocfiles));

		elem ~= new xml.Element("doHdrGeneration", toElem(doHdrGeneration));
		elem ~= new xml.Element("hdrdir", toElem(hdrdir));
		elem ~= new xml.Element("hdrname", toElem(hdrname));

		elem ~= new xml.Element("doXGeneration", toElem(doXGeneration));
		elem ~= new xml.Element("xfilename", toElem(xfilename));

		elem ~= new xml.Element("debuglevel", toElem(debuglevel));
		elem ~= new xml.Element("debugids", toElem(debugids));

		elem ~= new xml.Element("versionlevel", toElem(versionlevel));
		elem ~= new xml.Element("versionids", toElem(versionids));

		elem ~= new xml.Element("dump_source", toElem(dump_source));
		elem ~= new xml.Element("mapverbosity", toElem(mapverbosity));
		elem ~= new xml.Element("createImplib", toElem(createImplib));

		elem ~= new xml.Element("defaultlibname", toElem(defaultlibname));
		elem ~= new xml.Element("debuglibname", toElem(debuglibname));

		elem ~= new xml.Element("moduleDepsFile", toElem(moduleDepsFile));

		elem ~= new xml.Element("run", toElem(run));
		elem ~= new xml.Element("runargs", toElem(runargs));

		elem ~= new xml.Element("runCv2pdb", toElem(runCv2pdb));
		elem ~= new xml.Element("pathCv2pdb", toElem(pathCv2pdb));
		elem ~= new xml.Element("cv2pdbPre2043", toElem(cv2pdbPre2043));
		elem ~= new xml.Element("cv2pdbNoDemangle", toElem(cv2pdbNoDemangle));
		elem ~= new xml.Element("cv2pdbEnumType", toElem(cv2pdbEnumType));
		elem ~= new xml.Element("cv2pdbOptions", toElem(cv2pdbOptions));

		// Linker stuff
		elem ~= new xml.Element("objfiles", toElem(objfiles));
		elem ~= new xml.Element("linkswitches", toElem(linkswitches));
		elem ~= new xml.Element("libfiles", toElem(libfiles));
		elem ~= new xml.Element("libpaths", toElem(libpaths));
		elem ~= new xml.Element("deffile", toElem(deffile));
		elem ~= new xml.Element("resfile", toElem(resfile));
		elem ~= new xml.Element("exefile", toElem(exefile));

		elem ~= new xml.Element("additionalOptions", toElem(additionalOptions));
		elem ~= new xml.Element("preBuildCommand", toElem(preBuildCommand));
		elem ~= new xml.Element("postBuildCommand", toElem(postBuildCommand));
	
		elem ~= new xml.Element("filesToClean", toElem(filesToClean));
	}
	void writeDebuggerXML(xml.Element elem)
	{
		elem ~= new xml.Element("debugtarget", toElem(debugtarget));
		elem ~= new xml.Element("debugarguments", toElem(debugarguments));
		elem ~= new xml.Element("debugworkingdir", toElem(debugworkingdir));
		elem ~= new xml.Element("debugattach", toElem(debugattach));
		elem ~= new xml.Element("debugremote", toElem(debugremote));
		elem ~= new xml.Element("debugEngine", toElem(debugEngine));
		elem ~= new xml.Element("debugStdOutToOutputWindow", toElem(debugStdOutToOutputWindow));
		elem ~= new xml.Element("pauseAfterRunning", toElem(pauseAfterRunning));
	}

	void readXML(xml.Element elem)
	{
		fromElem(elem, "obj", obj);
		fromElem(elem, "link", link);
		fromElem(elem, "lib", lib);
		fromElem(elem, "subsystem", subsystem);
		fromElem(elem, "multiobj", multiobj);
		fromElem(elem, "singleFileCompilation", compilationModel);
		fromElem(elem, "oneobj", oneobj);
		fromElem(elem, "trace", trace);
		fromElem(elem, "quiet", quiet);
		fromElem(elem, "verbose", verbose);
		fromElem(elem, "vtls", vtls);
		fromElem(elem, "symdebug", symdebug);
		fromElem(elem, "optimize", optimize);
		fromElem(elem, "cpu", cpu);
		fromElem(elem, "isX86_64", isX86_64);
		fromElem(elem, "isLinux", isLinux);
		fromElem(elem, "isOSX", isOSX);
		fromElem(elem, "isWindows", isWindows);
		fromElem(elem, "isFreeBSD", isFreeBSD);
		fromElem(elem, "isSolaris", isSolaris);
		fromElem(elem, "scheduler", scheduler);
		fromElem(elem, "useDeprecated", useDeprecated);
		fromElem(elem, "useAssert", useAssert);
		fromElem(elem, "useInvariants", useInvariants);
		fromElem(elem, "useIn", useIn);
		fromElem(elem, "useOut", useOut);
		fromElem(elem, "useArrayBounds", useArrayBounds);
		fromElem(elem, "noboundscheck", noboundscheck);
		fromElem(elem, "useSwitchError", useSwitchError);
		fromElem(elem, "useUnitTests", useUnitTests);
		fromElem(elem, "useInline", useInline);
		fromElem(elem, "release", release);
		fromElem(elem, "preservePaths", preservePaths);
		fromElem(elem, "warnings", warnings);
		fromElem(elem, "infowarnings", infowarnings);
		fromElem(elem, "checkProperty", checkProperty);
		fromElem(elem, "genStackFrame", genStackFrame);
		fromElem(elem, "pic", pic);
		fromElem(elem, "cov", cov);
		fromElem(elem, "nofloat", nofloat);
		fromElem(elem, "Dversion", Dversion);
		fromElem(elem, "ignoreUnsupportedPragmas", ignoreUnsupportedPragmas );

		fromElem(elem, "compiler", compiler);
		fromElem(elem, "otherDMD", otherDMD);
		fromElem(elem, "program", program);
		fromElem(elem, "imppath", imppath);
		fromElem(elem, "fileImppath", fileImppath);
		fromElem(elem, "outdir", outdir);
		fromElem(elem, "objdir", objdir);
		fromElem(elem, "objname", objname);
		fromElem(elem, "libname", libname);

		fromElem(elem, "doDocComments", doDocComments);
		fromElem(elem, "docdir", docdir);
		fromElem(elem, "docname", docname);
		fromElem(elem, "modules_ddoc", modules_ddoc);
		fromElem(elem, "ddocfiles", ddocfiles);

		fromElem(elem, "doHdrGeneration", doHdrGeneration);
		fromElem(elem, "hdrdir", hdrdir);
		fromElem(elem, "hdrname", hdrname);

		fromElem(elem, "doXGeneration", doXGeneration);
		fromElem(elem, "xfilename", xfilename);

		fromElem(elem, "debuglevel", debuglevel);
		fromElem(elem, "debugids", debugids);

		fromElem(elem, "versionlevel", versionlevel);
		fromElem(elem, "versionids", versionids);

		fromElem(elem, "dump_source", dump_source);
		fromElem(elem, "mapverbosity", mapverbosity);
		fromElem(elem, "createImplib", createImplib);

		fromElem(elem, "defaultlibname", defaultlibname);
		fromElem(elem, "debuglibname", debuglibname);

		fromElem(elem, "moduleDepsFile", moduleDepsFile);

		fromElem(elem, "run", run);
		fromElem(elem, "runargs", runargs);

		fromElem(elem, "runCv2pdb", runCv2pdb);
		fromElem(elem, "pathCv2pdb", pathCv2pdb);
		fromElem(elem, "cv2pdbPre2043", cv2pdbPre2043);
		fromElem(elem, "cv2pdbNoDemangle", cv2pdbNoDemangle);
		fromElem(elem, "cv2pdbEnumType", cv2pdbEnumType);
		fromElem(elem, "cv2pdbOptions", cv2pdbOptions);

		// Linker stuff
		fromElem(elem, "objfiles", objfiles);
		fromElem(elem, "linkswitches", linkswitches);
		fromElem(elem, "libfiles", libfiles);
		fromElem(elem, "libpaths", libpaths);
		fromElem(elem, "deffile", deffile);
		fromElem(elem, "resfile", resfile);
		fromElem(elem, "exefile", exefile);
	
		fromElem(elem, "additionalOptions", additionalOptions);
		fromElem(elem, "preBuildCommand", preBuildCommand);
		fromElem(elem, "postBuildCommand", postBuildCommand);

		fromElem(elem, "debugtarget", debugtarget);
		fromElem(elem, "debugarguments", debugarguments);
		fromElem(elem, "debugworkingdir", debugworkingdir);
		fromElem(elem, "debugattach", debugattach);
		fromElem(elem, "debugremote", debugremote);
		fromElem(elem, "debugEngine", debugEngine);
		fromElem(elem, "debugStdOutToOutputWindow", debugStdOutToOutputWindow);
		fromElem(elem, "pauseAfterRunning", pauseAfterRunning);

		fromElem(elem, "filesToClean", filesToClean);
	}
};

class ConfigProvider : DisposingComObject,
	// IVsExtensibleObject,
	IVsCfgProvider2, 
	IVsProjectCfgProvider
{
	this(Project prj)
	{
		mProject = prj;
//		mConfigs ~= addref(new Config(this, "Debug"));
//		mConfigs ~= addref(new Config(this, "Release"));
	}

	Config addConfig(string name, string platform)
	{
		Config cfg = newCom!Config(this, name, platform);
		mConfigs ~= addref(cfg);
		return cfg;
	}

	void addConfigsToXml(xml.Document doc)
	{
		foreach(Config cfg; mConfigs)
		{
			auto config = new xml.Element("Config");
			xml.setAttribute(config, "name", cfg.mName);
			xml.setAttribute(config, "platform", cfg.mPlatform);

			ProjectOptions opt = cfg.GetProjectOptions();
			opt.writeXML(config);
			doc ~= config;
		}
	}

	override void Dispose()
	{
		foreach(Config cfg; mConfigs)
			release(cfg);
		mConfigs = mConfigs.init;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(IVsCfgProvider) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsCfgProvider2) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProjectCfgProvider) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// IVsCfgProvider
	override int GetCfgs( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ IVsCfg *rgpcfg,
		/* [optional][out] */ ULONG *pcActual,
		/* [optional][out] */ VSCFGFLAGS *prgfFlags)
	{
		debug(FULL_DBG) mixin(LogCallMix);

		for(int i = 0; i < celt && i < mConfigs.length; i++)
			rgpcfg[i] = addref(mConfigs[i]);
		if(pcActual)
			*pcActual = mConfigs.length;
		if(prgfFlags)
			*prgfFlags = cast(VSCFGFLAGS) 0;
		return S_OK;
	}

	// IVsProjectCfgProvider
	override int OpenProjectCfg( 
		/* [in] */ in wchar* szProjectCfgCanonicalName,
		/* [out] */ IVsProjectCfg *ppIVsProjectCfg)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int get_UsesIndependentConfigurations( 
		/* [out] */ BOOL *pfUsesIndependentConfigurations)
	{
		logCall("%s.get_UsesIndependentConfigurations(pfUsesIndependentConfigurations=%s)", this, _toLog(pfUsesIndependentConfigurations));
		return returnError(E_NOTIMPL);
	}

	// IVsCfgProvider2
	override int GetCfgNames( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ BSTR *rgbstr,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		int j, cnt = 0;
		for(int i = 0; i < mConfigs.length; i++)
		{
			for(j = 0; j < i; j++)
				if(mConfigs[i].mName == mConfigs[j].mName)
					break;
			if(j >= i)
			{
				if(cnt < celt && rgbstr)
					rgbstr[cnt] = allocBSTR(mConfigs[i].mName);
				cnt++;
			}
		}
		if(pcActual)
			*pcActual = cnt;
		return S_OK;
	}


	override int GetPlatformNames( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ BSTR *rgbstr,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		int j, cnt = 0;
		for(int i = 0; i < mConfigs.length; i++)
		{
			for(j = 0; j < i; j++)
				if(mConfigs[i].mPlatform == mConfigs[j].mPlatform)
					break;
			if(j >= i)
			{
				if(cnt < celt)
					rgbstr[cnt] = allocBSTR(mConfigs[i].mPlatform);
				cnt++;
			}
		}
		if(pcActual)
			*pcActual = cnt;
		return S_OK;
	}

	override int GetCfgOfName( 
		/* [in] */ in wchar* pszCfgName,
		/* [in] */ in wchar* pszPlatformName,
		/* [out] */ IVsCfg *ppCfg)
	{
		mixin(LogCallMix);
		string cfg = to_string(pszCfgName);
		string plat = to_string(pszPlatformName);
		
		for(int i = 0; i < mConfigs.length; i++)
			if((plat == "" || plat == mConfigs[i].mPlatform) &&
			   (cfg == "" || mConfigs[i].mName == cfg))
			{
				*ppCfg = addref(mConfigs[i]);
				return S_OK;
			}

		return returnError(E_INVALIDARG);
	}

	extern(D) void NotifyConfigEvent(void delegate(IVsCfgProviderEvents) dg)
	{
		// make a copy of the callback list, because it might change during execution of the callback
		IVsCfgProviderEvents[] cbs;

		foreach(cb; mCfgProviderEvents)
			cbs ~= cb;

		foreach(cb; cbs)
			dg(cb);
	}

	override int AddCfgsOfCfgName( 
		/* [in] */ in wchar* pszCfgName,
		/* [in] */ in wchar* pszCloneCfgName,
		/* [in] */ in BOOL fPrivate)
	{
		mixin(LogCallMix);

		string strCfgName = to_string(pszCfgName);
		string strCloneCfgName = to_string(pszCloneCfgName);

		// Check if the CfgName already exists and that CloneCfgName exists
		Config clonecfg;
		foreach(c; mConfigs)
			if(c.mName == strCfgName)
				return returnError(E_FAIL);
			else if(c.mName == strCloneCfgName)
				clonecfg = c;
		
		if(strCloneCfgName.length && !clonecfg)
			return returnError(E_FAIL);

		//if(!mProject.QueryEditProjectFile())
		//	return returnError(E_ABORT);
    
		int cnt = mConfigs.length;
		for(int i = 0; i < cnt; i++)
			if(mConfigs[i].mName == strCloneCfgName)
			{
				Config config = newCom!Config(this, strCfgName, mConfigs[i].mPlatform, mConfigs[i].mProjectOptions);
				mConfigs ~= addref(config);
			}

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnCfgNameAdded(pszCfgName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file 
		return S_OK;
	}

	override int DeleteCfgsOfCfgName( 
		/* [in] */ in wchar* pszCfgName)
	{
		logCall("%s.DeleteCfgsOfCfgName(pszCfgName=%s)", this, _toLog(pszCfgName));

		string strCfgName = to_string(pszCfgName);
		int cnt = mConfigs.length;
		for(int i = 0; i < mConfigs.length; )
			if(mConfigs[i].mName == strCfgName)
				mConfigs = mConfigs[0..i] ~ mConfigs[i+1..$];
			else
				i++;
		if(cnt == mConfigs.length)
			return returnError(E_FAIL);

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnCfgNameDeleted(pszCfgName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file 
		return S_OK;
	}

	override int RenameCfgsOfCfgName( 
		/* [in] */ in wchar* pszOldName,
		/* [in] */ in wchar* pszNewName)
	{
		mixin(LogCallMix2);

		string strOldName = to_string(pszOldName);
		string strNewName = to_string(pszNewName);

		Config config;
		foreach(c; mConfigs)
			if(c.mName == strNewName)
				return returnError(E_FAIL);
			else if(c.mName == strOldName)
				config = c;

		if(!config)
			return returnError(E_FAIL);

		//if(!mProject.QueryEditProjectFile())
		//	return returnError(E_ABORT);

		foreach(c; mConfigs)
			if(c.mName == strOldName)
				config.mName = strNewName;

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnCfgNameRenamed(pszOldName, pszNewName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file 
		return S_OK;
	}

	override int AddCfgsOfPlatformName( 
		/* [in] */ in wchar* pszPlatformName,
		/* [in] */ in wchar* pszClonePlatformName)
	{
		logCall("%s.AddCfgsOfPlatformName(pszPlatformName=%s,pszClonePlatformName=%s)", this, _toLog(pszPlatformName), _toLog(pszClonePlatformName));

		string strPlatformName = to_string(pszPlatformName);
		string strClonePlatformName = to_string(pszClonePlatformName);

		// Check if the CfgName already exists and that CloneCfgName exists
		Config clonecfg;
		foreach(c; mConfigs)
			if(c.mPlatform == strPlatformName)
				return returnError(E_FAIL);
			else if(c.mPlatform == strClonePlatformName)
				clonecfg = c;

		if(strClonePlatformName.length && !clonecfg)
			return returnError(E_FAIL);

		//if(!mProject.QueryEditProjectFile())
		//	return returnError(E_ABORT);

		int cnt = mConfigs.length;
		for(int i = 0; i < cnt; i++)
			if(mConfigs[i].mPlatform == strClonePlatformName)
			{
				Config config = newCom!Config(this, mConfigs[i].mName, strPlatformName, mConfigs[i].mProjectOptions);
				mConfigs ~= addref(config);
			}

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnPlatformNameAdded(pszPlatformName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file 
		return S_OK;
	}

	override int DeleteCfgsOfPlatformName( 
		/* [in] */ in wchar* pszPlatformName)
	{
		logCall("%s.DeleteCfgsOfPlatformName(pszPlatformName=%s)", this, _toLog(pszPlatformName));

		string strPlatformName = to_string(pszPlatformName);
		int cnt = mConfigs.length;
		for(int i = 0; i < mConfigs.length; )
			if(mConfigs[i].mPlatform == strPlatformName)
				mConfigs = mConfigs[0..i] ~ mConfigs[i+1..$];
			else
				i++;
		if(cnt == mConfigs.length)
			return returnError(E_FAIL);

		NotifyConfigEvent(delegate (IVsCfgProviderEvents cb) { cb.OnPlatformNameDeleted(pszPlatformName); });

		mProject.GetProjectNode().SetProjectFileDirty(true); // dirty the project file 
		return S_OK;
	}

	override int GetSupportedPlatformNames( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ BSTR *rgbstr,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		for(int cnt = 0; cnt < kPlatforms.length && cnt < celt && rgbstr; cnt++)
			rgbstr[cnt] = allocBSTR(kPlatforms[cnt]);
		if(pcActual)
			*pcActual = kPlatforms.length;
		return S_OK;
	}

	override int GetCfgProviderProperty( 
		/* [in] */ in VSCFGPROPID propid,
		/* [out] */ VARIANT *var)
	{
		mixin(LogCallMix);

		switch(propid)
		{
		case VSCFGPROPID_SupportsCfgAdd:
		case VSCFGPROPID_SupportsCfgDelete:
		case VSCFGPROPID_SupportsCfgRename:
		case VSCFGPROPID_SupportsPlatformAdd:
		case VSCFGPROPID_SupportsPlatformDelete:
			var.vt = VT_BOOL;
			var.boolVal = true;
			return S_OK;
		default:
			break;
		}
		return returnError(E_NOTIMPL);
	}

	override int AdviseCfgProviderEvents( 
		/* [in] */ IVsCfgProviderEvents pCPE,
		/* [out] */ VSCOOKIE *pdwCookie)
	{
		mixin(LogCallMix);

		*pdwCookie = ++mLastCfgProviderEventsCookie;
		mCfgProviderEvents[mLastCfgProviderEventsCookie] = addref(pCPE);

		return S_OK;
	}

	override int UnadviseCfgProviderEvents( 
		/* [in] */ in VSCOOKIE dwCookie)
	{
		logCall("%s.UnadviseCfgProviderEvents(dwCookie=%s)", this, _toLog(dwCookie));

		if(dwCookie in mCfgProviderEvents)
		{
			release(mCfgProviderEvents[dwCookie]);
			mCfgProviderEvents.remove(dwCookie);
			return S_OK;
		}
		return returnError(E_FAIL);
	}

private:

	Project mProject;
	Config[] mConfigs;
	IVsCfgProviderEvents[VSCOOKIE] mCfgProviderEvents;
	VSCOOKIE mLastCfgProviderEventsCookie;
}

interface ConfigModifiedListener : IUnknown
{
	void OnConfigModified();
}

class Config :	DisposingComObject, 
		IVsProjectCfg2,
		IVsDebuggableProjectCfg,
		IVsBuildableProjectCfg,
		ISpecifyPropertyPages
{
	static const GUID iid = { 0x402744c1, 0xe382, 0x4877, [ 0x9e, 0x38, 0x26, 0x9c, 0xb7, 0xa3, 0xb8, 0x9d ] };

	this(ConfigProvider provider, string name, string platform, ProjectOptions opts = null)
	{
		mProvider = provider;
		if (opts)
		{
			mProjectOptions = clone(opts);
			mProjectOptions.setDebug(name == "Debug");
			mProjectOptions.setX64(platform == "x64");
		}
		else
			mProjectOptions = new ProjectOptions(name == "Debug", platform == "x64");
		mBuilder = new CBuilderThread(this);
		mName = name;
		mPlatform = platform;
	}

	override void Dispose()
	{
		mBuilder.Dispose();
	}

	override ULONG AddRef()
	{
		return super.AddRef();
	}
	override ULONG Release()
	{
		return super.Release();
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(Config) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsCfg) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProjectCfg) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsProjectCfg2) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(ISpecifyPropertyPages) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsDebuggableProjectCfg) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsBuildableProjectCfg) (this, riid, pvObject))
			return S_OK;

		return super.QueryInterface(riid, pvObject);
	}

	// ISpecifyPropertyPages
	override int GetPages( /* [out] */ CAUUID *pPages)
	{
		mixin(LogCallMix);
		return PropertyPageFactory.GetProjectPages(pPages);
	}

	// IVsCfg
	override int get_DisplayName(BSTR *pbstrDisplayName)
	{
		logCall("%s.get_DisplayName(pbstrDisplayName=%s)", this, _toLog(pbstrDisplayName));

		*pbstrDisplayName = allocBSTR(mName ~ "|" ~ mPlatform);
		return S_OK;
	}
    
	override int get_IsDebugOnly(BOOL *pfIsDebugOnly)
	{
		logCall("%s.get_IsDebugOnly(pfIsDebugOnly=%s)", this, _toLog(pfIsDebugOnly));

		*pfIsDebugOnly = (mName == "Debug");
		return S_OK;
	}
    
	override int get_IsReleaseOnly(BOOL *pfIsReleaseOnly)
	{
		logCall("%s.get_IsReleaseOnly(pfIsReleaseOnly=%s)", this, _toLog(pfIsReleaseOnly));

		*pfIsReleaseOnly = (mName == "Release");
		return S_OK;
	}
    
	// IVsProjectCfg
	override int EnumOutputs(IVsEnumOutputs *ppIVsEnumOutputs)
	{
		mixin(LogCallMix);

		*ppIVsEnumOutputs = addref(newCom!DEnumOutputs(this, 0));
		return S_OK;
	}

	override int OpenOutput(in wchar* szOutputCanonicalName, IVsOutput *ppIVsOutput)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int get_ProjectCfgProvider(/* [out] */ IVsProjectCfgProvider *ppIVsProjectCfgProvider)
	{
		mixin(LogCallMix);
		*ppIVsProjectCfgProvider = addref(mProvider);
		return S_OK;
	}

	override int get_BuildableProjectCfg( /* [out] */ IVsBuildableProjectCfg *ppIVsBuildableProjectCfg)
	{
		mixin(LogCallMix);
		*ppIVsBuildableProjectCfg = addref(this);
		return S_OK;
	}

	override int get_CanonicalName( /* [out] */ BSTR *pbstrCanonicalName)
	{
		logCall("get_CanonicalName(pbstrCanonicalName=%s)", _toLog(pbstrCanonicalName));
		return returnError(E_NOTIMPL);
	}

	override int get_Platform( /* [out] */ GUID *pguidPlatform)
	{
		// The documentation says this is obsolete, so don't do anything.
		//		mixin(LogCallMix);
		*pguidPlatform = GUID(); //GUID_VS_PLATFORM_WIN32_X86;
		return returnError(E_NOTIMPL);
	}

	override int get_IsPackaged( /* [out] */ BOOL *pfIsPackaged)
	{
		logCall("get_IsPackaged(pfIsPackaged=%s)", _toLog(pfIsPackaged));
		return returnError(E_NOTIMPL);
	}

	override int get_IsSpecifyingOutputSupported( /* [out] */ BOOL *pfIsSpecifyingOutputSupported)
	{
		logCall("get_IsSpecifyingOutputSupported(pfIsSpecifyingOutputSupported=%s)", _toLog(pfIsSpecifyingOutputSupported));
		return returnError(E_NOTIMPL);
	}

	override int get_TargetCodePage( /* [out] */ UINT *puiTargetCodePage)
	{
		logCall("get_TargetCodePage(puiTargetCodePage=%s)", _toLog(puiTargetCodePage));
		return returnError(E_NOTIMPL);
	}

	override int get_UpdateSequenceNumber( /* [out] */ ULARGE_INTEGER *puliUSN)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int get_RootURL( /* [out] */ BSTR *pbstrRootURL)
	{
		logCall("get_RootURL(pbstrRootURL=%s)", _toLog(pbstrRootURL));
		return returnError(E_NOTIMPL);
	}

	// IVsProjectCfg2
	override int get_CfgType( 
		/* [in] */ in IID* iidCfg,
		/* [iid_is][out] */ void **ppCfg)
	{
		debug(FULL_DBG) mixin(LogCallMix);
		return QueryInterface(iidCfg, ppCfg);
	}

	override int get_OutputGroups( 
		/* [in] */ in ULONG celt,
		/* [size_is][out][in] */ IVsOutputGroup *rgpcfg,
		/* [optional][out] */ ULONG *pcActual)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int OpenOutputGroup( 
		/* [in] */ in wchar* szCanonicalName,
		/* [out] */ IVsOutputGroup *ppIVsOutputGroup)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int OutputsRequireAppRoot( 
		/* [out] */ BOOL *pfRequiresAppRoot)
	{
		logCall("%s.OutputsRequireAppRoot(pfRequiresAppRoot=%s)", this, _toLog(pfRequiresAppRoot));
		return returnError(E_NOTIMPL);
	}

	override int get_VirtualRoot( 
		/* [out] */ BSTR *pbstrVRoot)
	{
		logCall("%s.get_VirtualRoot(pbstrVRoot=%s)", this, _toLog(pbstrVRoot));
		return returnError(E_NOTIMPL);
	}

	override int get_IsPrivate( 
		/* [out] */ BOOL *pfPrivate)
	{
		logCall("%s.get_IsPrivate(pfPrivate=%s)", this, _toLog(pfPrivate));
		return returnError(E_NOTIMPL);
	}

	// IVsDebuggableProjectCfg
	override int DebugLaunch( 
		/* [in] */ in VSDBGLAUNCHFLAGS grfLaunch)
	{
		logCall("%s.DebugLaunch(grfLaunch=%s)", this, _toLog(grfLaunch));

		string prg = mProjectOptions.replaceEnvironment(mProjectOptions.debugtarget, this);
		if (prg.length == 0)
			return S_OK;

		if(!isAbsolute(prg))
			prg = GetProjectDir() ~ "\\" ~ prg;
		//prg = quoteFilename(prg);

		string workdir = mProjectOptions.replaceEnvironment(mProjectOptions.debugworkingdir, this);
		if(!isAbsolute(workdir))
			workdir = GetProjectDir() ~ "\\" ~ workdir;

		string args = mProjectOptions.replaceEnvironment(mProjectOptions.debugarguments, this);
		if(DBGLAUNCH_NoDebug & grfLaunch)
		{
			if(mProjectOptions.pauseAfterRunning)
			{
				args = "/c " ~ quoteFilename(prg) ~ " " ~ args ~ " & pause";
				prg = getCmdPath();
			}
			ShellExecuteW(null, null, toUTF16z(quoteFilename(prg)), toUTF16z(args), toUTF16z(workdir), SW_SHOWNORMAL);
			return(S_OK);
		}

		HRESULT hr = E_NOTIMPL;
		// When the debug target is the project build output, the project have to use 
		// IVsSolutionDebuggingAssistant2 to determine if the target was deployed.
		// The interface allows the project to find out where the outputs were deployed to 
		// and direct the debugger to the deployed locations as appropriate.
		// Projects start out their debugging sessions by calling MapOutputToDeployedURLs().

		// Here we do not use IVsSolutionDebuggingAssistant2 because our debug target is 
		// explicitly set in the project options and it is not built by the project.
		// For demo of how to use IVsSolutionDebuggingAssistant2 refer to MycPrj sample in the 
		// Environment SDK. 

		if(IVsDebugger srpVsDebugger = queryService!(IVsDebugger))
		{
			scope(exit) release(srpVsDebugger);

			// if bstr-parameters not passed as BSTR parameters, VS2010 crashes on some systems
			//  not sure if they can be free'd afterwards...
			VsDebugTargetInfo dbgi;

			dbgi.cbSize = VsDebugTargetInfo.sizeof;
			dbgi.bstrRemoteMachine = null;
			string remote = mProjectOptions.replaceEnvironment(mProjectOptions.debugremote, this);

			if(remote.length == 0)
			{
				if(!std.file.exists(prg))
				{
					UtilMessageBox("The program to launch does not exist:\n" ~ prg, MB_OK, "Launch Debugger");
					return S_FALSE;
				}
				if(workdir.length && !isExistingDir(workdir))
				{
					UtilMessageBox("The working directory does not exist:\n" ~ workdir, MB_OK, "Launch Debugger");
					return S_FALSE;
				}
			}
			else
				dbgi.bstrRemoteMachine = allocBSTR(remote); // _toUTF16z(remote);

			dbgi.dlo = DLO_CreateProcess; // DLO_Custom;    // specifies how this process should be launched
			// clsidCustom is the clsid of the debug engine to use to launch the debugger
			switch(mProjectOptions.debugEngine)
			{
			case 1:
				GUID GUID_MaGoDebugger = uuid("{97348AC0-2B6B-4B99-A245-4C7E2C09D403}");
				dbgi.clsidCustom = GUID_MaGoDebugger;
				break;
			case 2:
				dbgi.clsidCustom = GUID_COMPlusNativeEng; // the mixed-mode debugger (works only on x86)
				break;
			default:
				dbgi.clsidCustom = GUID_NativeOnlyEng; // works for x64
				break;
			}
			dbgi.bstrMdmRegisteredName = null; // used with DLO_AlreadyRunning. The name of the
			                                   // app as it is registered with the MDM.
			dbgi.bstrExe = allocBSTR(prg); // _toUTF16z(prg);
			dbgi.bstrCurDir = allocBSTR(workdir); // _toUTF16z(workdir);
			dbgi.bstrArg = allocBSTR(args); // _toUTF16z(args);
			dbgi.fSendStdoutToOutputWindow = mProjectOptions.debugStdOutToOutputWindow;

			hr = srpVsDebugger.LaunchDebugTargets(1, &dbgi);
			if (FAILED(hr))
			{
				string msg = format("cannot launch debugger on %s\nhr = %x", prg, hr);
				mProvider.mProject.SetErrorInfo(E_FAIL, msg);
				hr = E_FAIL;
			}
		}
		return(hr);
	}

	override int QueryDebugLaunch( 
		/* [in] */ in VSDBGLAUNCHFLAGS grfLaunch,
		/* [out] */ BOOL *pfCanLaunch)
	{
//		mixin(LogCallMix);
		*pfCanLaunch = true;
		return S_OK; // returnError(E_NOTIMPL);
	}

	// IVsBuildableProjectCfg
	override int get_ProjectCfg( 
		/* [out] */ IVsProjectCfg *ppIVsProjectCfg)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int AdviseBuildStatusCallback( 
		/* [in] */ IVsBuildStatusCallback pIVsBuildStatusCallback,
		/* [out] */ VSCOOKIE *pdwCookie)
	{
		mixin(LogCallMix);

		*pdwCookie = ++mLastBuildStatusCookie;
		mBuildStatusCallbacks[mLastBuildStatusCookie] = addref(pIVsBuildStatusCallback);
		mTicking[mLastBuildStatusCookie] = false;
		mStarted[mLastBuildStatusCookie] = false;
		return S_OK;
	}

	override int UnadviseBuildStatusCallback( 
		/* [in] */ in VSCOOKIE dwCookie)
	{
//		mixin(LogCallMix);

		if(dwCookie in mBuildStatusCallbacks)
		{
			release(mBuildStatusCallbacks[dwCookie]);
			mBuildStatusCallbacks.remove(dwCookie);
			mTicking.remove(dwCookie);
			mStarted.remove(dwCookie);
			return S_OK;
		}
		return returnError(E_FAIL);
	}

	override int StartBuild( 
		/* [in] */ IVsOutputWindowPane pIVsOutputWindowPane,
		/* [in] */ in DWORD dwOptions)
	{
		mixin(LogCallMix);

		if(dwOptions & VS_BUILDABLEPROJECTCFGOPTS_REBUILD)
			return mBuilder.Start(CBuilderThread.Operation.eRebuild, pIVsOutputWindowPane);
		return mBuilder.Start(CBuilderThread.Operation.eBuild, pIVsOutputWindowPane);
	}

	override int StartClean( 
		/* [in] */ IVsOutputWindowPane pIVsOutputWindowPane,
		/* [in] */ in DWORD dwOptions)
	{
		mixin(LogCallMix);
	
		return mBuilder.Start(CBuilderThread.Operation.eClean, pIVsOutputWindowPane);
	}

	override int StartUpToDateCheck( 
		/* [in] */ IVsOutputWindowPane pIVsOutputWindowPane,
		/* [in] */ in DWORD dwOptions)
	{
		mixin(LogCallMix);
	
		HRESULT rc = mBuilder.Start(CBuilderThread.Operation.eCheckUpToDate, pIVsOutputWindowPane);
		return rc == S_OK ? S_OK : E_FAIL; // E_FAIL used to indicate "not uptodate"
		//return returnError(E_NOTIMPL); //S_OK;
	}

	override int QueryStatus( 
		/* [out] */ BOOL *pfBuildDone)
	{
		logCall("%s.QueryStatus(pfBuildDone=%s)", this, _toLog(pfBuildDone));
		mBuilder.QueryStatus(pfBuildDone);
		return S_OK;
	}

	override int Stop( 
		/* [in] */ in BOOL fSync)
	{
		logCall("%s.Stop(fSync=%s)", this, _toLog(fSync));
		mBuilder.Stop(fSync);
		return S_OK;
	}

	override int Wait( 
		/* [in] */ in DWORD dwMilliseconds,
		/* [in] */ in BOOL fTickWhenMessageQNotEmpty)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int QueryStartBuild( 
		/* [in] */ in DWORD dwOptions,
		/* [optional][out] */ BOOL *pfSupported,
		/* [optional][out] */ BOOL *pfReady)
	{
		debug(FULL_DBG) mixin(LogCallMix);
		
		if(pfSupported)
			*pfSupported = true;
		if(pfReady)
		{
			mBuilder.QueryStatus(pfReady);
		}
		return S_OK; // returnError(E_NOTIMPL);
	}

	override int QueryStartClean( 
		/* [in] */ in DWORD dwOptions,
		/* [optional][out] */ BOOL *pfSupported,
		/* [optional][out] */ BOOL *pfReady)
	{
		mixin(LogCallMix);
		if(pfSupported)
			*pfSupported = true;
		if(pfReady)
		{
			mBuilder.QueryStatus(pfReady);
		}
		return S_OK; // returnError(E_NOTIMPL);
	}

	override int QueryStartUpToDateCheck( 
		/* [in] */ in DWORD dwOptions,
		/* [optional][out] */ BOOL *pfSupported,
		/* [optional][out] */ BOOL *pfReady)
	{
		mixin(LogCallMix);
		if(pfSupported)
			*pfSupported = true;
		if(pfReady)
		{
			mBuilder.QueryStatus(pfReady);
		}
		return S_OK; // returnError(E_NOTIMPL);
	}

	//////////////////////////////////////////////////////////////////////////////
	void AddModifiedListener(ConfigModifiedListener listener)
	{
		mModifiedListener.addunique(listener);
	}

	void RemoveModifiedListener(ConfigModifiedListener listener)
	{
		mModifiedListener.remove(listener);
	}
		
	//////////////////////////////////////////////////////////////////////////////
	void SetDirty()
	{
		mProvider.mProject.GetProjectNode().SetProjectFileDirty(true);
		
		foreach(listener; mModifiedListener)
			listener.OnConfigModified();
	}

	CProjectNode GetProjectNode() { return mProvider.mProject.GetProjectNode(); }
	string GetProjectPath() { return mProvider.mProject.GetFilename(); }
	string GetProjectDir() { return dirName(mProvider.mProject.GetFilename()); }
	string GetProjectName() { return mProvider.mProject.GetProjectNode().GetName(); }
	Project GetProject() { return mProvider.mProject; }

	ProjectOptions GetProjectOptions() { return mProjectOptions; }

	string GetTargetPath()
	{
		string exe = mProjectOptions.getTargetPath();
		return mProjectOptions.replaceEnvironment(exe, this);
	}

	string GetDependenciesPath()
	{
		string exe = mProjectOptions.getDependenciesPath();
		return mProjectOptions.replaceEnvironment(exe, this);
	}

	string GetLinkDependenciesPath()
	{
		string dep = GetDependenciesPath();
		assert(dep[$-4..$] == ".dep");
		return dep[0..$-4] ~ ".lnkdep";
	}

	bool hasLinkDependencies()
	{
		bool doLink = mProjectOptions.compilationModel != ProjectOptions.kSeparateCompileOnly;
		bool separateLink = mProjectOptions.compilationModel == ProjectOptions.kSeparateCompileAndLink;
		if (mProjectOptions.compiler == Compiler.GDC && mProjectOptions.lib == OutputType.StaticLib)
			separateLink = true;
		bool useOptlink = mProjectOptions.compiler == Compiler.DMD && separateLink && mProjectOptions.lib != OutputType.StaticLib;
		return doLink && useOptlink && Package.GetGlobalOptions().optlinkDeps;
	}

	string GetCommandLinePath()
	{
		string exe = mProjectOptions.getCommandLinePath();
		return mProjectOptions.replaceEnvironment(exe, this);
	}

	string GetOutDir()
	{
		return mProjectOptions.replaceEnvironment(mProjectOptions.outdir, this);
	}

	string GetIntermediateDir()
	{
		return mProjectOptions.replaceEnvironment(mProjectOptions.objdir, this);
	}

	string[] GetDependencies(CFileNode file)
	{
		string tool = GetCompileTool(file);
		if(tool == "Custom" || tool == kToolResourceCompiler)
		{
			string outfile = GetOutputFile(file);
			string dep = file.GetDependencies();
			dep = mProjectOptions.replaceEnvironment(dep, this, file.GetFilename(), outfile);
			string[] deps = tokenizeArgs(dep);
			deps ~= file.GetFilename();
			string workdir = GetProjectDir();
			foreach(ref string s; deps)
				s = makeFilenameAbsolute(s, workdir);
			return deps;
		}
		if(tool == "DMDsingle")
		{
			string outfile = GetOutputFile(file);
			string depfile = outfile ~ ".dep";
			depfile = mProjectOptions.replaceEnvironment(depfile, this, file.GetFilename(), outfile);

			string workdir = GetProjectDir();
			string deppath = makeFilenameAbsolute(depfile, workdir);
		
			string[] files;
			bool depok = false;
			if(std.file.exists(deppath))
				depok = getFilenamesFromDepFile(deppath, files);
			if(!depok)
				files ~= deppath; // force update without if dependency file does not exist or is invalid

			files ~= file.GetFilename();
			files ~= getDDocFileList();
			makeFilenamesAbsolute(files, workdir);
			return files;
		}
		return null;
	}

	bool isUptodate(CFileNode file)
	{
		string fcmd = GetCompileCommand(file);
		if(fcmd.length == 0)
			return true;

		string outfile = GetOutputFile(file);
		outfile = mProjectOptions.replaceEnvironment(outfile, this, file.GetFilename(), outfile);

		string workdir = GetProjectDir();
		string cmdfile = makeFilenameAbsolute(outfile ~ "." ~ kCmdLogFileExtension, workdir);
		
		if(!compareCommandFile(cmdfile, fcmd))
			return false;

		string[] deps = GetDependencies(file);
		
		outfile = makeFilenameAbsolute(outfile, workdir);
		string oldestFile, newestFile;
		long targettm = getOldestFileTime( [ outfile ], oldestFile );
		long sourcetm = getNewestFileTime(deps, newestFile);

		return targettm > sourcetm;
	}

	static bool IsResource(CFileNode file)
	{
		string tool = file.GetTool();
		if(tool == "")
			if(toLower(extension(file.GetFilename())) == ".rc")
				return true;
		return tool == kToolResourceCompiler;
	}
	
	static string GetStaticCompileTool(CFileNode file)
	{
		string tool = file.GetTool();
		if(tool == "")
		{
			string fname = file.GetFilename();
			string ext = toLower(extension(fname));
			if(isIn(ext, ".d", ".ddoc", ".def", ".lib", ".obj", ".o", ".res"))
				tool = "DMD";
			else if(ext == "rc")
				tool = kToolResourceCompiler;
		}
		return tool;
	}
	
	string GetCompileTool(CFileNode file)
	{
		string tool = file.GetTool();
		if(tool == "")
		{
			string fname = file.GetFilename();
			string ext = toLower(extension(fname));
			if(ext == ".d" && mProjectOptions.compilationModel == ProjectOptions.kSingleFileCompilation)
				tool = "DMDsingle";
			else if(isIn(ext, ".d", ".ddoc", ".def", ".lib", ".obj", ".o", ".res"))
				tool = "DMD";
			else if(ext == "rc")
				tool = kToolResourceCompiler;
		}
		return tool;
	}

	string GetOutputFile(CFileNode file)
	{
		string tool = GetCompileTool(file);
		string fname;
		if(tool == "DMD")
			return file.GetFilename();
		if(tool == "DMDsingle")
			fname = mProjectOptions.objdir ~ "\\" ~ safeFilename(stripExtension(file.GetFilename())) ~ "." ~ mProjectOptions.objectFileExtension();
		if(tool == kToolResourceCompiler)
			fname = mProjectOptions.objdir ~ "\\" ~ safeFilename(stripExtension(file.GetFilename()), "_") ~ ".res";
		if(tool == "Custom")
			fname = file.GetOutFile();
		if(fname.length)
			fname = mProjectOptions.replaceEnvironment(fname, this, file.GetFilename());
		return fname;
	}

	string expandedAbsoluteFilename(string name)
	{
		string workdir = GetProjectDir();
		string expname = mProjectOptions.replaceEnvironment(name, this);
		string absname = makeFilenameAbsolute(expname, workdir);
		return absname;
	}
	
	string GetBuildLogFile()
	{
		return expandedAbsoluteFilename("$(INTDIR)\\$(SAFEPROJECTNAME).buildlog.html");
	}
	
	string[] GetBuildFiles()
	{
		string workdir = normalizeDir(GetProjectDir());
		string outdir = normalizeDir(makeFilenameAbsolute(GetOutDir(), workdir));
		string intermediatedir = normalizeDir(makeFilenameAbsolute(GetIntermediateDir(), workdir));
		
		string target = makeFilenameAbsolute(GetTargetPath(), workdir);
		string cmdfile = makeFilenameAbsolute(GetCommandLinePath(), workdir);

		string[] files;
		files ~= target;
		files ~= cmdfile;
		files ~= cmdfile ~ ".rsp";
		files ~= makeFilenameAbsolute(GetDependenciesPath(), workdir);
		files ~= makeFilenameAbsolute(GetLinkDependenciesPath(), workdir);
		
		if(mProjectOptions.usesCv2pdb())
		{
			files ~= target ~ "_cv";
			files ~= setExtension(target, "pdb");
		}
		string mapfile = expandedAbsoluteFilename("$(INTDIR)\\$(SAFEPROJECTNAME).map");
		files ~= mapfile;
		string buildlog = GetBuildLogFile();
		files ~= buildlog;

		if(mProjectOptions.createImplib)
			files ~= setExtension(target, "lib");

		if(mProjectOptions.doDocComments)
		{
			if(mProjectOptions.docdir.length)
				files ~= expandedAbsoluteFilename(normalizeDir(mProjectOptions.docdir)) ~ "*.html";
			if(mProjectOptions.docname.length)
				files ~= expandedAbsoluteFilename(mProjectOptions.docname);
			if(mProjectOptions.modules_ddoc)
				files ~= expandedAbsoluteFilename(mProjectOptions.modules_ddoc);
		}
		if(mProjectOptions.doHdrGeneration)
		{
			if(mProjectOptions.hdrdir.length)
				files ~= expandedAbsoluteFilename(normalizeDir(mProjectOptions.hdrdir)) ~ "*.di";
			if(mProjectOptions.hdrname.length)
				files ~= expandedAbsoluteFilename(mProjectOptions.hdrname);
		}
		if(mProjectOptions.doXGeneration)
		{
			if(mProjectOptions.xfilename.length)
				files ~= expandedAbsoluteFilename(mProjectOptions.xfilename);
		}

		string[] toclean = tokenizeArgs(mProjectOptions.filesToClean);
		foreach(s; toclean)
		{
			string uqs = unquoteArgument(s);
			files ~= outdir ~ uqs;
			if(outdir != intermediatedir)
				files ~= intermediatedir ~ uqs;
		}
		searchNode(mProvider.mProject.GetRootNode(), 
			delegate (CHierNode n) { 
				if(CFileNode file = cast(CFileNode) n)
				{
					string outname = GetOutputFile(file);
					if (outname.length && outname != file.GetFilename())
					{
						files ~= makeFilenameAbsolute(outname, workdir);
						files ~= makeFilenameAbsolute(outname ~ "." ~ kCmdLogFileExtension, workdir);
					}
				}
				return false;
			});
		
		return files;
	}

	string GetCompileCommand(CFileNode file, bool syntaxOnly = false)
	{
		string tool = GetCompileTool(file);
		string cmd;
		string outfile = GetOutputFile(file);
		if(tool == kToolResourceCompiler)
		{
			cmd = "rc /fo" ~ quoteFilename(outfile);
			string include = Package.GetGlobalOptions().IncSearchPath;
			if(include.length)
			{
				string[] incs = tokenizeArgs(include);
				foreach(string inc; incs)
					cmd ~= " /I" ~ quoteFilename(inc);
				cmd = mProjectOptions.replaceEnvironment(cmd, this, outfile);
			}
			cmd ~= " " ~ quoteFilename(file.GetFilename());
		}
		if(tool == "Custom")
		{
			cmd = file.GetCustomCmd();
		}
		if(tool == "DMDsingle")
		{
			string depfile = GetOutputFile(file) ~ ".dep";
			cmd = "echo Compiling " ~ file.GetFilename() ~ "...\n";
			cmd ~= mProjectOptions.buildCommandLine(true, false, false, syntaxOnly);
			if(syntaxOnly && mProjectOptions.compiler == Compiler.DMD)
				cmd ~= " -c -o-";
			else if(syntaxOnly)
				cmd ~= " -c -fsyntax-only";
			else if(mProjectOptions.compiler == Compiler.DMD)
				cmd ~= " -c -of" ~ quoteFilename(outfile) ~ " -deps=" ~ quoteFilename(depfile);
			else
				cmd ~= " -c -o " ~ quoteFilename(outfile) ~ " -fdeps=" ~ quoteFilename(depfile);
			cmd ~= " " ~ file.GetFilename();
			foreach(ddoc; getDDocFileList())
				cmd ~= " " ~ ddoc;
		}
		if(cmd.length)
		{
			cmd = getEnvironmentChanges() ~ cmd ~ "\n";
			cmd ~= "if errorlevel 1 echo Building " ~ outfile ~ " failed!\n";
			cmd = mProjectOptions.replaceEnvironment(cmd, this, file.GetFilename(), outfile);
		}
		return cmd;
	}

	string getEnvironmentChanges()
	{
		string cmd;
		GlobalOptions globOpt = Package.GetGlobalOptions();
		if(globOpt.ExeSearchPath.length)
			cmd ~= "set PATH=" ~ replaceCrLf(globOpt.ExeSearchPath) ~ ";%PATH%\n";
		
		if(globOpt.LibSearchPath.length || mProjectOptions.libpaths.length)
		{
			string lpath = replaceCrLf(globOpt.LibSearchPath);
			if(mProjectOptions.libpaths.length && !_endsWith(lpath, ";"))
				lpath ~= ";";
			lpath ~= mProjectOptions.libpaths;
			
			cmd ~= "set DMD_LIB=" ~ lpath ~ "\n";
		}
		return cmd;
	}

	string getModuleName(string fname)
	{
		string ext = toLower(extension(fname));
		if(ext != ".d" && ext != ".di")
			return "";
		
		string modname = getModuleDeclarationName(fname);
		if(modname.length > 0)
			return modname;
		return stripExtension(baseName(fname));
	}

	string getModulesDDocCommandLine(string[] files, ref string modules_ddoc)
	{
		if(!mProjectOptions.doDocComments)
			return "";
		string mod_cmd;
		modules_ddoc = strip(mProjectOptions.modules_ddoc);
		if(modules_ddoc.length > 0)
		{
			modules_ddoc = quoteFilename(modules_ddoc);
			mod_cmd = "echo MODULES = >" ~ modules_ddoc ~ "\n";
			string workdir = GetProjectDir();
			for(int i = 0; i < files.length; i++)
			{
				string fname = makeFilenameAbsolute(files[i], workdir);
				string mod = getModuleName(fname);
				if(mod.length > 0)
				{
					if(indexOf(mod, '.') < 0)
						mod = "." ~ mod;
					mod_cmd ~= "echo     $$(MODULE " ~ mod ~ ") >>" ~ modules_ddoc ~ "\n";
				}
			}
		}
		return mod_cmd;
	}

	string getCommandFileList(string[] files, string responsefile, ref string precmd)
	{
		if(mProjectOptions.compiler == Compiler.GDC)
			foreach(ref f; files)
				f = replace(f, "\\", "/");

		string fcmd = std.string.join(files, " ");
		if(fcmd.length > 100)
		{
			precmd ~= "\n";
			precmd ~= "echo " ~ files[0] ~ " >" ~ quoteFilename(responsefile) ~ "\n";
			for(int i = 1; i < files.length; i++)
				precmd ~= "echo " ~ files[i] ~ " >>" ~ quoteFilename(responsefile) ~ "\n";
			precmd ~= "\n";
			fcmd = " @" ~ quoteFilename(responsefile);
		}
		else
			fcmd = " " ~ fcmd;
		
		if(mProjectOptions.compiler == Compiler.GDC && mProjectOptions.libfiles.length)
			fcmd ~= " " ~ replace(mProjectOptions.libfiles, "\\", "/");

		return fcmd;
	}

	string[] getObjectFileList(string[] dfiles)
	{
		string[] files = dfiles.dup;
		string[] remove;
		bool singleObj = (mProjectOptions.compilationModel == ProjectOptions.kCombinedCompileAndLink);
		string targetObj;
		foreach(ref f; files)
			if(f.endsWith(".d") || f.endsWith(".D"))
			{
				if(singleObj)
				{
					if(targetObj.length)
						remove ~= f;
					else
					{
						targetObj = "$(OutDir)\\$(ProjectName).obj";
						f = targetObj;
					}
				}
				else
				{
					string fname = stripExtension(f);
					if(!mProjectOptions.preservePaths)
						fname = baseName(fname);
					if(mProjectOptions.compiler == Compiler.DMD)
						f = mProjectOptions.objdir ~ "\\" ~ fname ~ "." ~ mProjectOptions.objectFileExtension();
					else
						f = fname ~ "." ~ mProjectOptions.objectFileExtension();
				}
			}

		foreach(r; remove)
			files.remove(r);
		return files;
	}
	
	string getLinkFileList(string[] dfiles, ref string precmd)
	{
		string[] files = getObjectFileList(dfiles);
		string responsefile = GetCommandLinePath() ~ ".lnkarg";
		return getCommandFileList(files, responsefile, precmd);
	}
	
	string[] getSourceFileList()
	{
		string[] files;
		searchNode(mProvider.mProject.GetRootNode(), 
			delegate (CHierNode n) { 
				if(CFileNode file = cast(CFileNode) n)
					files ~= file.GetFilename();
				return false;
			});
		return files;
	}

	string[] getDDocFileList()
	{
		string[] files;
		searchNode(mProvider.mProject.GetRootNode(), 
			delegate (CHierNode n) { 
				if(CFileNode file = cast(CFileNode) n)
				{
					string fname = file.GetFilename();
					if(extension(fname) == ".ddoc")
						files ~= fname;
				}
				return false;
			});
		return files;
	}

	string[] getInputFileList()
	{
		string[] files;
		searchNode(mProvider.mProject.GetRootNode(), 
			delegate (CHierNode n) { 
				if(CFileNode file = cast(CFileNode) n)
				{
					string fname = GetOutputFile(file);
					if(fname.length)
						if(file.GetTool() != "Custom" || file.GetLinkOutput())
							files ~= fname;
				}
				return false;
			});

		string[] libs = getLibsFromDependentProjects();
		foreach(lib; libs)
		{
			// dmd also understands ".json", ".map" and ".exe", but these are shortcuts for output files
			string ext = toLower(extension(lib));
			if(ext.isIn(".d", ".di", ".o", ".obj", ".lib", ".a", ".ddoc", ".res", ".def", ".dd", ".htm", ".html", ".xhtml"))
				files ~= lib;
		}
		return files;
	}
	
	string getCommandLine()
	{
		bool doLink       = mProjectOptions.compilationModel != ProjectOptions.kSeparateCompileOnly;
		bool separateLink = mProjectOptions.compilationModel == ProjectOptions.kSeparateCompileAndLink;
		if (mProjectOptions.compiler == Compiler.GDC && mProjectOptions.lib == OutputType.StaticLib)
			separateLink = true;
		if (mProjectOptions.compiler == Compiler.DMD && mProjectOptions.lib != OutputType.StaticLib && doLink)
			separateLink = true;
		bool useOptlink = mProjectOptions.compiler == Compiler.DMD && separateLink && mProjectOptions.lib != OutputType.StaticLib;
		string opt = mProjectOptions.buildCommandLine(true, !separateLink && doLink, true);
		if(mProjectOptions.additionalOptions.length)
			opt ~= " " ~ mProjectOptions.additionalOptions;

		string precmd = getEnvironmentChanges();
		string[] files = getInputFileList();
		quoteFilenames(files);

		string responsefile = GetCommandLinePath() ~ ".rsp";
		string fcmd = getCommandFileList(files, responsefile, precmd);
		
		string[] srcfiles = getSourceFileList();
		string modules_ddoc;
		string mod_cmd = getModulesDDocCommandLine(srcfiles, modules_ddoc);
		if(mod_cmd.length > 0)
		{
			precmd ~= mod_cmd ~ "\nif errorlevel 1 goto reportError\n";
			fcmd ~= " " ~ modules_ddoc;
		}

		auto globOpts = Package.GetGlobalOptions();
		if(separateLink || !doLink)
		{
			bool singleObj = (mProjectOptions.compilationModel == ProjectOptions.kCombinedCompileAndLink);
			if(singleObj)
				opt ~= " -c -of\"$(OutDir)\\$(ProjectName).obj\"";
			else
				opt ~= " -c" ~ mProjectOptions.getOutputDirOption();
		}
		string cmd = precmd ~ opt ~ fcmd ~ "\n";
		cmd = cmd ~ "if errorlevel 1 goto reportError\n";
		
		if(separateLink && doLink)
		{
			string prelnk, lnkcmd;
			if(useOptlink)
			{
				string libs, options;
				string linkpath = globOpts.getOptlinkPath(mProjectOptions.otherCompilerPath(), &libs, &options);
				lnkcmd = linkpath ~ " ";
				if(globOpts.demangleError || globOpts.optlinkDeps)
					lnkcmd = "\"$(VisualDInstallDir)pipedmd.exe\" "
						~ (globOpts.demangleError ? null : "-nodemangle ")
						~ (globOpts.optlinkDeps ? "-deps " ~ quoteFilename(GetLinkDependenciesPath()) ~ " " : null)
						~ lnkcmd;
				string[] lnkfiles = getObjectFileList(files);
				string cmdfiles = mProjectOptions.optlinkCommandLine(lnkfiles, options);
				lnkcmd ~= getLinkFileList([cmdfiles], prelnk);
				if(libs.length)
					prelnk = "set LIB=" ~ libs ~ "\n" ~ prelnk;
			}
			else
			{
				lnkcmd = mProjectOptions.buildCommandLine(false, true, false);
				if(mProjectOptions.additionalOptions.length)
					lnkcmd ~= " " ~ mProjectOptions.additionalOptions;
				lnkcmd ~= getLinkFileList(files, prelnk);
			}
			cmd = cmd ~ "\n" ~ prelnk ~ lnkcmd ~ "\n";
			cmd = cmd ~ "if errorlevel 1 goto reportError\n";
		}
		
		string cv2pdb = mProjectOptions.appendCv2pdb();
		if(cv2pdb.length && doLink)
		{
			string cvtarget = quoteFilename(mProjectOptions.getTargetPath() ~ "_cv");
			cmd ~= "if not exist " ~ cvtarget ~ " (echo " ~ cvtarget ~ " not created! && goto reportError)\n";
			cmd ~= "echo Converting debug information...\n";
			cmd ~= cv2pdb;
			cmd ~= "\nif errorlevel 1 goto reportError\n";
		}

		string pre = strip(mProjectOptions.preBuildCommand);
		if(pre.length)
			cmd = pre ~ "\nif errorlevel 1 goto reportError\n" ~ cmd;
		
		string post = strip(mProjectOptions.postBuildCommand);
		if(post.length)
			cmd = cmd ~ "\nif errorlevel 1 goto reportError\n" ~ post ~ "\n\n";
		
		string target = quoteFilename(mProjectOptions.getTargetPath());
		cmd ~= "if not exist " ~ target ~ " (echo " ~ target ~ " not created! && goto reportError)\n";
		cmd ~= "\ngoto noError\n";
		cmd ~= "\n:reportError\n";
		cmd ~= "echo Building " ~ GetTargetPath() ~ " failed!\n";
		cmd ~= "\n:noError\n";

		return mProjectOptions.replaceEnvironment(cmd, this);
	}

	bool writeLinkDependencyFile()
	{
		string workdir = normalizeDir(GetProjectDir());
		string depfile = makeFilenameAbsolute(GetDependenciesPath(), workdir);
		string files[] = getInputFileList();
		files = getObjectFileList(files);
		string prefix = "target (";
		string postfix = ") : public : object \n";
		string deps;
		foreach(f; files)
		{
			deps ~= prefix ~ replace(f, "\\", "\\\\") ~ postfix;
		}
		bool fromMap = mProjectOptions.mapverbosity >= 3;
		try
		{
			std.file.write(depfile, deps);
			return true;
		}
		catch(Exception e)
		{
		}
		return false;
	}
	
	string[] getLibsFromDependentProjects()
	{
		string[] libs;
		auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
		if(!solutionBuildManager)
			return libs;

		scope(exit) release(solutionBuildManager);
		
		ULONG cActual;
		if(HRESULT hr = solutionBuildManager.GetProjectDependencies(mProvider.mProject, 0, null, &cActual))
			return libs;
		IVsHierarchy[] pHier = new IVsHierarchy [cActual];

		if(HRESULT hr = solutionBuildManager.GetProjectDependencies(mProvider.mProject, cActual, pHier.ptr, &cActual))
			return libs;
		
		for(int i = 0; i < cActual; i++)
		{
			IVsProjectCfg prjcfg;
			if(pHier[i].QueryInterface(&IVsProjectCfg.iid, cast(void**)&prjcfg) != S_OK)
			{
				IVsCfg cfg;
				IVsGetCfgProvider gcp;
				IVsCfgProvider cp;
				IVsCfgProvider2 cp2;
				if(pHier[i].QueryInterface(&IVsGetCfgProvider.iid, cast(void**)&gcp) == S_OK)
					gcp.GetCfgProvider(&cp);
				else
					pHier[i].QueryInterface(&IVsCfgProvider.iid, cast(void**)&cp);
				if(cp)
				{
					cp.QueryInterface(&IVsCfgProvider2.iid, cast(void**)&cp2);
					if(cp2)
					{
						cp2.GetCfgOfName(_toUTF16z(mName), _toUTF16z(mPlatform), &cfg);
						if(!cfg)
							cp2.GetCfgs(1, &cfg, null, null); // TODO: find a "similar" config?
						if(cfg)
							cfg.QueryInterface(&IVsProjectCfg.iid, cast(void**)&prjcfg);
					}
				}
				release(cfg);
				release(gcp);
				release(cp);
				release(cp2);
			}
			if(prjcfg)
			{
				scope(exit) release(prjcfg);

				IVsEnumOutputs eo;
				if(prjcfg.EnumOutputs(&eo) == S_OK)
				{
					scope(exit) release(eo);
					ULONG fetched;
					IVsOutput pIVsOutput;
					while(eo.Next(1, &pIVsOutput, &fetched) == S_OK && fetched == 1)
					{
						ScopedBSTR target;
						if(pIVsOutput.get_CanonicalName(&target.bstr) == S_OK)
						{
							string targ = target.detach();
							libs ~= targ;
						}
						release(pIVsOutput);
					}
				}

			}
			release(pHier[i]);
		}
		return libs;
	}

	int addJSONFiles(ref string[] files)
	{
		int cnt = 0;
		alias mProjectOptions opt;
		if(opt.doXGeneration)
		{
			void addJSONFile(string xfile)
			{
				xfile = makeFilenameAbsolute(xfile, GetProjectDir());
				if(xfile.length && std.file.exists(xfile))
				{
					addunique(files, xfile);
					cnt++;
				}
			}
			if(opt.compilationModel == ProjectOptions.kSingleFileCompilation)
			{
				searchNode(mProvider.mProject.GetRootNode(), 
					delegate (CHierNode n) { 
						if(CFileNode file = cast(CFileNode) n)
						{
							string tool = GetCompileTool(file);
							if(tool == "DMDsingle")
							{
								string outfile = GetOutputFile(file);
								string xfile = opt.replaceEnvironment(opt.xfilename, this, file.GetFilename(), outfile);
								addJSONFile(xfile);
							}
						}
						return false;
					});
			}
			else
			{
				string xfile = opt.replaceEnvironment(opt.xfilename, this);
				addJSONFile(xfile);
			}
		}
		return cnt;
	}
	
	// tick the sink and check if build can continue or not.
	BOOL FFireTick()
	{
		foreach(cb; mBuildStatusCallbacks)
		{
			//if (m_rgfTicking[i])
			{
				BOOL fContinue = TRUE;
				HRESULT hr = cb.Tick(&fContinue);
				assert(SUCCEEDED(hr));
				if (!fContinue)
					return FALSE;
			}
		}
		return TRUE;
	}

	void FFireBuildBegin(ref BOOL fContinue)
	{
		fContinue = TRUE;
		foreach(key, cb; mBuildStatusCallbacks)
		{
			HRESULT hr = cb.BuildBegin(&fContinue);
			if(FAILED(hr) || !fContinue)
				break;
			mStarted[key] = true;
		}
	}

	void FFireBuildEnd(BOOL fSuccess)
	{
		// make a copy in case BuildEnd calls Unadvise
		IVsBuildStatusCallback[] cbs;
		foreach(key, cb; mBuildStatusCallbacks)
			if(mStarted[key])
			{
				cbs ~= cb;
				mStarted[key] = false;
			}

		foreach(cb; cbs)
		{
			HRESULT hr = cb.BuildEnd(fSuccess);
			assert(SUCCEEDED(hr));
		}
		Package.scheduleUpdateLibrary();
	}

	CBuilderThread getBuilder() { return mBuilder; }

	string getName() { return mName; }
	string getPlatform() { return mPlatform; }

private:
	string mName;
	string mPlatform;
	ConfigProvider mProvider;
	ProjectOptions mProjectOptions;
	CBuilderThread mBuilder;

	ConfigModifiedListener[] mModifiedListener;
	IVsBuildStatusCallback[VSCOOKIE] mBuildStatusCallbacks;
	bool[VSCOOKIE] mTicking;
	bool[VSCOOKIE] mStarted;

	VSCOOKIE mLastBuildStatusCookie;
};


class DEnumOutFactory : DComObject, IClassFactory
{
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface2!(IClassFactory) (this, IID_IClassFactory, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT CreateInstance(IUnknown UnkOuter, in IID* riid, void** pvObject)
	{
		logCall("%s.CreateInstance(riid=%s)", this, _toLog(riid));

		assert(!UnkOuter);
		DEnumOutputs eo = newCom!DEnumOutputs(null, 0);
		return eo.QueryInterface(riid, pvObject);
	}
	override HRESULT LockServer(in BOOL fLock)
	{
		return returnError(E_NOTIMPL);
	}
}

class DEnumOutputs : DComObject, IVsEnumOutputs, ICallFactory, IExternalConnection, IMarshal
{
	// {785486EE-2FB9-47f5-85A9-5790A60B5CEB}
	static const GUID iid = { 0x785486ee, 0x2fb9, 0x47f5, [ 0x85, 0xa9, 0x57, 0x90, 0xa6, 0xb, 0x5c, 0xeb ] };

	string[] mTargets;
	int mPos;

	this(Config cfg, int pos)
	{
		if(cfg)
			mTargets ~= makeFilenameAbsolute(cfg.GetTargetPath(), cfg.GetProjectDir());
		mPos = pos;
	}

	this(DEnumOutputs eo)
	{
		mTargets = eo.mTargets;
		mPos = eo.mPos;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsEnumOutputs) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(ICallFactory) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IExternalConnection) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IMarshal) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT Reset()
	{
		mixin(LogCallMix);

		mPos = 0;
		return S_OK;
	}

	override HRESULT Next(in ULONG cElements, IVsOutput *rgpIVsOutput, ULONG *pcElementsFetched)
	{
		mixin(LogCallMix);

		if(mPos >= mTargets.length || cElements < 1)
		{
			if(pcElementsFetched)
				*pcElementsFetched = 0;
			return returnError(S_FALSE);
		}
		
		if(pcElementsFetched)
			*pcElementsFetched = 1;
		*rgpIVsOutput = addref(newCom!VsOutput(mTargets[mPos]));
		mPos++;
		return S_OK;
	}

	override HRESULT Skip(in ULONG cElements)
	{
		logCall("%s.Skip(cElements=%s)", this, _toLog(cElements));

		mPos += cElements;
		if(mPos > mTargets.length)
		{
			mPos = mTargets.length;
			return S_FALSE;
		}
		return S_OK;
	}

	override HRESULT Clone(IVsEnumOutputs *ppIVsEnumOutputs)
	{
		mixin(LogCallMix);

		*ppIVsEnumOutputs = addref(newCom!DEnumOutputs(this));
		return S_OK;
	}

	// ICallFactory
	override HRESULT CreateCall(
		/+[in]+/  in IID*              riid,
		/+[in]+/  IUnknown          pCtrlUnk,
		/+[in]+/  in IID*              riid2,
		/+[out, iid_is(riid2)]+/ IUnknown *ppv )
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	// IExternalConnection
	override DWORD AddConnection (
		/+[in]+/ in DWORD extconn,
		/+[in]+/ in DWORD reserved )
	{
		mixin(LogCallMix);

		return ++mExternalReferences;
	}

	override DWORD ReleaseConnection(
		/+[in]+/ in DWORD extconn,
		/+[in]+/ in DWORD reserved,
		/+[in]+/ in BOOL  fLastReleaseCloses )
	{
		mixin(LogCallMix);

		--mExternalReferences;
		if(mExternalReferences == 0)
			CoDisconnectObject(this, 0);

		return mExternalReferences;
	}

	int mExternalReferences;

	// IMarshall
	override HRESULT GetUnmarshalClass
		(
		/+[in]+/ in IID* riid,
		/+[in, unique]+/ in void *pv,
		/+[in]+/ in DWORD dwDestContext,
		/+[in, unique]+/ in void *pvDestContext,
		/+[in]+/ in DWORD mshlflags,
		/+[out]+/ CLSID *pCid
		)
	{
		mixin(LogCallMixNoRet);

		*cast(GUID*)pCid = g_unmarshalCLSID;
		return S_OK;
		//return returnError(E_NOTIMPL);
	}

	override HRESULT GetMarshalSizeMax
		(
		/+[in]+/ in IID* riid,
		/+[in, unique]+/ in void *pv,
		/+[in]+/ in DWORD dwDestContext,
		/+[in, unique]+/ in void *pvDestContext,
		/+[in]+/ in DWORD mshlflags,
		/+[out]+/ DWORD *pSize
		)
	{
		mixin(LogCallMixNoRet);

		*pSize = 256;
		return S_OK;
		//return returnError(E_NOTIMPL);
	}

	override HRESULT MarshalInterface
		(
		/+[in, unique]+/ IStream pStm,
		/+[in]+/ in IID* riid,
		/+[in, unique]+/ in void *pv,
		/+[in]+/ in DWORD dwDestContext,
		/+[in, unique]+/ in void *pvDestContext,
		/+[in]+/ in DWORD mshlflags
		)
	{
		mixin(LogCallMixNoRet);

		if(HRESULT hr = pStm.Write(cast(void*)&iid, iid.sizeof, null))
			return hr;
		int length = mTargets.length;
		if(HRESULT hr = pStm.Write(&length, length.sizeof, null))
			return hr;
		foreach(s; mTargets)
		{
			length = s.length;
			if(HRESULT hr = pStm.Write(&length, length.sizeof, null))
				return hr;
			if(HRESULT hr = pStm.Write(cast(void*)s.ptr, length, null))
				return hr;
		}

		if(HRESULT hr = pStm.Write(&mPos, mPos.sizeof, null))
			return hr;
		return S_OK;
	}

	override HRESULT UnmarshalInterface
		(
		/+[in, unique]+/ IStream pStm,
		/+[in]+/ in IID* riid,
		/+[out]+/ void **ppv
		)
	{
		mixin(LogCallMix);

		GUID miid;
		if(HRESULT hr = pStm.Read(&miid, iid.sizeof, null))
			return returnError(hr);
		assert(miid == iid);

		int cnt;
		if(HRESULT hr = pStm.Read(&cnt, cnt.sizeof, null))
			return hr;

		DEnumOutputs eo = newCom!DEnumOutputs(null, 0);
		for(int i = 0; i < cnt; i++)
		{
			int length;
			if(HRESULT hr = pStm.Read(&length, length.sizeof, null))
				return hr;
			char[] s = new char[length];
			if(HRESULT hr = pStm.Read(s.ptr, length, null))
				return hr;
			eo.mTargets ~= cast(string) s;
		}

		if(HRESULT hr = pStm.Read(&eo.mPos, eo.mPos.sizeof, null))
			return hr;
		return eo.QueryInterface(riid, ppv);
	}

	override HRESULT ReleaseMarshalData(/+[in, unique]+/ IStream pStm)
	{
		mixin(LogCallMix2);
		return returnError(E_NOTIMPL);
	}

	override HRESULT DisconnectObject(/+[in]+/ in DWORD dwReserved)
	{
		logCall("%s.DisconnectObject(dwReserved=%s)", this, _toLog(dwReserved));
		return returnError(E_NOTIMPL);
	}

}

class VsOutput : DComObject, IVsOutput
{
	string mTarget;

	this(string target)
	{
		mTarget = target;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsOutput) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT get_DisplayName(BSTR *pbstrDisplayName)
	{
		logCall("%s.get_DisplayName(pbstrDisplayName=%s)", this, _toLog(pbstrDisplayName));

		*pbstrDisplayName = allocBSTR(mTarget);
		return S_OK;
	}

	override HRESULT get_CanonicalName(BSTR *pbstrCanonicalName)
	{
		logCall("%s.get_CanonicalName(pbstrCanonicalName=%s)", this, _toLog(pbstrCanonicalName));
		*pbstrCanonicalName = allocBSTR(mTarget);
		return S_OK;
	}

	override HRESULT get_DeploySourceURL(BSTR *pbstrDeploySourceURL)
	{
		logCall("%s.get_DeploySourceURL(pbstrDeploySourceURL=%s)", this, _toLog(pbstrDeploySourceURL));

		*pbstrDeploySourceURL = allocBSTR("file:///" ~ mTarget);
		return S_OK;
	}

	// obsolete method
	override HRESULT get_Type(/+[out]+/ GUID *pguidType)
	{
		logCall("%s.get_Type(pguidType=%s)", this, _toLog(pguidType));
		*pguidType = GUID_NULL;
		return S_OK;
	}
}

Config GetActiveConfig(IVsHierarchy pHierarchy)
{
	if(!pHierarchy)
		return null;
	
	auto solutionBuildManager = queryService!(IVsSolutionBuildManager)();
	scope(exit) release(solutionBuildManager);

	IVsProjectCfg activeCfg;
	if(solutionBuildManager.FindActiveProjectCfg(null, null, pHierarchy, &activeCfg) == S_OK)
	{
		scope(exit) release(activeCfg);
		if(Config cfg = qi_cast!Config(activeCfg))
			return cfg;
	}
	return null;
}
