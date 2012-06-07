// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2012 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module vdc.ivdserver;

import sdk.port.base;
import sdk.win32.oaidl;
import sdk.win32.objbase;
import sdk.win32.oleauto;

interface IVDServer : IUnknown
{
	static const GUID iid = uuid("002a2de9-8bb6-484d-9901-7e4ad4084715");

public:
	HRESULT ConfigureSemanticProject(in BSTR filename, in BSTR imp, in BSTR stringImp, in BSTR versionids, in BSTR debugids, DWORD flags);
	HRESULT ClearSemanticProject();
	HRESULT UpdateModule(in BSTR filename, in BSTR srcText);
	HRESULT GetTip(in BSTR filename, int startLine, int startIndex, int endLine, int endIndex);
	HRESULT GetTipResult(ref int startLine, ref int startIndex, ref int endLine, ref int endIndex, BSTR* answer);
	HRESULT GetSemanticExpansions(in BSTR filename, in BSTR tok, uint line, uint idx);
	HRESULT GetSemanticExpansionsResult(BSTR* stringList);
	HRESULT IsBinaryOperator(in BSTR filename, uint startLine, uint startIndex, uint endLine, uint endIndex, BOOL* pIsOp);
	HRESULT GetParseErrors(in BSTR filename, BSTR* errors);
	HRESULT GetBinaryIsInLocations(in BSTR filename, VARIANT* locs); // array of pairs of DWORD
	HRESULT GetLastMessage(BSTR* message);
}

///////////////////////////////////////////////////////////////////////
uint ConfigureFlags()(bool unittestOn, bool debugOn, bool x64, int versionLevel, int debugLevel)
{
	return (unittestOn ? 1 : 0)
		|  (debugOn    ? 2 : 0)
		|  (x64        ? 4 : 0)
		| ((versionLevel & 0xff) << 8)
		| ((debugLevel & 0xff) << 8);
}

