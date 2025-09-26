// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module vdc.ivdserver;

version(MAIN) {} else version = noServer;

version(noServer):
import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

////////////////////////////////////////////////////////////////////////////////
// interface IVDServer
//
// This interface is under development and subject to change without notice
//
// This is the interface that is used by Visual D to retrieve parser and semantic
// information about edited files. Visual D instantiates an object of IVDServer
// in-process or out-of-process, depending on the registration of the COM class.
// The motivation for out-of-process creation: avoiding application freezes due
// to stop-the-world garbage collections on large amounts of memory (in case of
// the current D runtime, 200MB are enough to make this annoying).
//
// Visual D creates a single thread for communicating with the server and expects
// expensive calls to be asynchronous: methods GetTip, GetDefinition, GetSemanticExpansions
// and UpdateModule return immediately, but start some background processing.
// The client (aka Visual D) polls the result with GetTipResult, GetDefinitionResult,
// GetSemanticExpansionsResult and GetParseErrors, repectively, until they return successfully.
// While doing so, GetLastMessage is called to get status line messages (e.g. "parsing module...")
//
// All methods reference modules by their file name.
//
// Line numbers are 1-based
// Column index are 0-based

interface IVDServer : IUnknown
{
	static const GUID iid = uuid("002a2de9-8bb6-484d-9901-7e4ad4084715");

public:
	// set compilation options for the given file
	//
	// filename:   file name
	// imp:        new-line delimited list of import folders
	// stringImp:  new-line delimited list of string import folders
	// versionids: new-line delimited list of version identifiers defined on the command line
	// debugids:   new-line delimited list of debug identifiers defined on the command line
	// cmdline:    space delimited additional command line options
	// flags:      see ConfigureFlags
	//
	// Options are taken from the project that contains the file. If the file
	// is used in multiple projects, which one is chosen is undefined.
	// If the file is not contained in a project, the options of the current
	// startup-project are used.
	//
	// This function is usually called after UpdateModule, assuming that parsing does
	// not depend on compilation options, so any semantic analysis should be deferred
	// until ConfigureSemanticProject is called.
	HRESULT ConfigureSemanticProject(const BSTR filename, const BSTR imp, const BSTR stringImp, const BSTR versionids, const BSTR debugids, const BSTR cmdline, DWORD flags);

	// delete all semantic and parser information
	HRESULT ClearSemanticProject();

	// parse file given the current text in the editor
	//
	// filename:   file name
	// srcText:    current text in editor
	// flags:      bit 0 - verbose:    display parsing message?
	//             bit 1 - idTypes:    evaluate identifier types
	//
	// it is assumed that the actual parsing is forwarded to some other thread
	// and that the status can be polled by GetParseErrors
	//
	// ConfigureSemanticProject is usually called after UpdateModule, assuming that parsing does
	// not depend on compilation options, so any semantic analysis should be deferred
	// until ConfigureSemanticProject is invoked.
	HRESULT UpdateModule(const BSTR filename, const BSTR srcText, const DWORD flags);

	// request tool tip text for a given text location
	//
	// filename:   file name
	// startLine, startIndex, endLine, endIndex: selected range in the editor
	//                                           if start==end, mouse hovers without selection
	// flags:      1 - try to evaluate constants/expressions
	// flags:      2 - quote code for highlighting
	// flags:      4 - return all overloads (rather than the current best match)
	// flags:      8 - add links to symbols as #<name,file,lline,col>#
	// flags:     16 - add size and alignment info
	//
	// it is assumed that the semantic analysis is forwarded to some other thread
	// and that the status can be polled by GetTipResult
	HRESULT GetTip(const BSTR filename, int startLine, int startIndex, int endLine, int endIndex, int flags);

	// get the result of the previous GetTip
	//
	// startLine, startIndex, endLine, endIndex: return the range of the evaluated expression
	//                                           to show a tool tip, this range must not be empty
	// answer: the tool tip text to display
	//
	// return S_FALSE as long as the semantic analysis is still running
	HRESULT GetTipResult(ref int startLine, ref int startIndex, ref int endLine, ref int endIndex, BSTR* answer);

	// request a list of expansions for a given text location
	//
	// filename:   file name
	// tok:        the prefix of the identifier to expand, allowing filtering results
	// line, idx:  the location of the caret in the text editor
	// expr:       the expression to evaluate at the insertion point in case of parser issues
	//             with the current text
	// it is assumed that the semantic analysis is forwarded to some other thread
	// and that the status can be polled by GetSemanticExpansionsResult
	HRESULT GetSemanticExpansions(const BSTR filename, const BSTR tok, uint line, uint idx, const BSTR expr);

	// get the result of the previous GetSemanticExpansions
	//
	// stringList: a new-line delimited list of expansions
	//
	// return S_FALSE as long as the semantic analysis is still running
	//
	// format of each line: name:type:description
	HRESULT GetSemanticExpansionsResult(BSTR* stringList);

	// not used
	HRESULT IsBinaryOperator(const BSTR filename, uint startLine, uint startIndex, uint endLine, uint endIndex, BOOL* pIsOp);

	// return the parse errors found in the file
	//
	// filename:   file name
	// errors: new-line delimited list of errors, each line has the format:
	//        startLine,startIndex,endLine,endIndex:  error text
	//
	// the range given by startLine,startIndex,endLine,endIndex will be marked
	// as erronous by underlining it in the editor
	//
	// return S_FALSE as long as the parsing is still running
	HRESULT GetParseErrors(const BSTR filename, BSTR* errors);

	// return the locations where "in" and "is" are used as binary operators
	//
	// filename:   file name
	// locs:       an array of pairs of DWORDs line,index that gives the text location of the "i"
	//
	// this method is called once after GetParseErrors returned successfully
	HRESULT GetBinaryIsInLocations(const BSTR filename, VARIANT* locs);

	// return the document outline, i.e. a simple description of the AST
	//
	// filename:   file name
	//
	// stringList: a new-line delimited list of selected AST nodes
	//
	// format of each line: depth:line:endline:description
	//
	// this method might be called once after GetParseErrors returned successfully
	HRESULT GetDocumentOutline(const BSTR filename, BSTR* stringList);

	// return a message to be displayed in the status line of the IDE
	//
	// it is assumed that a message is returned only once.
	// return S_FALSE if there is no new message to display
	HRESULT GetLastMessage(BSTR* message);

	// request the identifier type information for the file
	//
	// filename:   file name
	// startLine:  
	// endLine:    results may be restricted to identifiers within this range
	// flags:      bit 0 - resolveTypes:   resolve field/alias identifier types
	//             bit 1 - syncExec:       no asynchronous execution
	//
	// this method is called once after GetParseErrors returned successfully
	HRESULT GetIdentifierTypes(const BSTR filename, int startLine, int endLine, int flags);

	// return the identifier type information for the last request
	//
	// types: new-line delimited list of info, each line has the format:
	//        identifier:deftype(;type,startLine,startIndex)*
	//
	// the identifier will be marked as "type" starting with text position
	// startLine,startIndex and "deftype" for the beginning of the file
	//
	HRESULT GetIdentifierTypesResult(BSTR* types);

	// request location of definition for a given text location
	//
	// filename:   file name
	// startLine, startIndex, endLine, endIndex: selected range in the editor
	//                                           if start==end, mouse hovers without selection
	//
	// it is assumed that the semantic analysis is forwarded to some other thread
	// and that the status can be polled by GetDefinitionResult
	HRESULT GetDefinition(const BSTR filename, int startLine, int startIndex, int endLine, int endIndex);

	// get the result of the previous GetDefinition
	//
	// file name: file where the declaration can be found
	// startLine, startIndex, endLine, endIndex: return the text span of the declaration
	//
	// return S_FALSE as long as the semantic analysis is still running
	HRESULT GetDefinitionResult(ref int startLine, ref int startIndex, ref int endLine, ref int endIndex, BSTR* filename);

	// request a list of references for a given text location
	//
	// filename:   file name
	// tok:        the identifier to reference
	// line, idx:  the location of the caret in the text editor
	// expr:       the expression to evaluate at the insertion point in case of parser issues
	//             with the current text
	// moduleOnly: only search current module
	//
	// it is assumed that the reference finding is forwarded to some other thread
	// and that the status can be polled by GetReferencesResult
	HRESULT GetReferences(const BSTR filename, const BSTR tok, uint line, uint idx, const BSTR expr, const BOOL moduleOnly);
	HRESULT GetReferencesResult(BSTR* stringList);

	// set the comment tasks tokens used to populate the task list
	//
	// tasks:     \n separated list of identifiers (letter, digit, '_' or '@')
	HRESULT ConfigureCommentTasks(const BSTR tasks);

	// return the comment tasks found in the file
	//
	// filename:   file name
	// errors: new-line delimited list of tasks, each line has the format:
	//        startLine,startIndex,:  task text
	//
	// the tasks will be inserted into the task list window
	//
	// return S_FALSE as long as the parsing is still running
	HRESULT GetCommentTasks(const BSTR filename, BSTR* tasks);

	// return the locations of call arguments with parameter storage class ref, out or lazy
	//
	// filename:   file name
	// locs:       an array of triplets of DWORDs type,line,index that gives the text
	//             location of the argument expression. type is 0/1/2 for ref/out/lazy
	//
	// this method is called once after GetParseErrors returned successfully
	HRESULT GetParameterStorageLocs(const BSTR filename, VARIANT* locs);
}

///////////////////////////////////////////////////////////////////////
uint ConfigureFlags()(bool unittestOn, bool debugOn, bool x64, bool cov, bool doc, bool nobounds, bool gdc,
					  int versionLevel, int debugLevel, bool noDeprecated, bool deprecateInfo,
					  bool ldc, bool msvcrt, bool warnings, bool warnAsError,
					  bool mixinAnalysis, bool ufcsExpansions)
{
	return (unittestOn ? 1 : 0)
		|  (debugOn    ? 2 : 0)
		|  (x64        ? 4 : 0)
		|  (cov        ? 8 : 0)
		|  (doc        ? 16 : 0)
		|  (nobounds   ? 32 : 0)
		|  (gdc        ? 64 : 0)
		|  (noDeprecated ? 128 : 0)
		|  (deprecateInfo  ? 0x40_00_00_00 : 0)
		| ((versionLevel & 0xff) << 8)
		| ((debugLevel   & 0xff) << 16)
		|  (mixinAnalysis  ? 0x01_00_00_00 : 0)
		|  (ufcsExpansions ? 0x02_00_00_00 : 0)
		|  (ldc            ? 0x04_00_00_00 : 0)
		|  (msvcrt         ? 0x08_00_00_00 : 0)
		|  (warnings       ? 0x10_00_00_00 : 0)
		|  (warnAsError    ? 0x20_00_00_00 : 0);
}

// from D_Parser: types returned by GetIdentifierTypes
enum TypeReferenceKind : uint
{
	Unknown,

	Interface,
	Enum,
	EnumValue,
	Template,
	Class,
	Struct,
	Union,
	TemplateTypeParameter,

	Constant,
	LocalVariable,
	ParameterVariable,
	TLSVariable,
	SharedVariable,
	GSharedVariable,
	MemberVariable,
	Variable,

	Alias,
	Module,
	Package = Module, // todo
	Function,
	Method,
	BasicType,

	DebugIdentifier,
	VersionIdentifier,
}

enum ParameterStorageClass
{
	Ref,
	Out,
	Lazy
}

struct ParameterStorageLoc
{
	int type;
	int line;
	int col;
}
