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
	static GUID iid = uuid("002a2de9-8bb6-484d-9901-7e4ad4084715");

public:
	HRESULT ExecCommand(in BSTR cmd, BSTR* answer);
	HRESULT ExecCommandAsync(in BSTR cmd, ULONG* cmdID);

	HRESULT ConfigureSemanticProject(in BSTR imp, in BSTR stringImp, in BSTR versionids, in BSTR debugids, DWORD flags);
	HRESULT ClearSemanticProject();
	HRESULT UpdateModule(in BSTR filename, in BSTR srcText);
	HRESULT GetType(in BSTR filename, ref int startLine, ref int startIndex, ref int endLine, ref int endIndex, BSTR* answer);
	HRESULT GetSemanticExpansions(in BSTR filename, in BSTR tok, uint line, uint idx, BSTR* stringList);
	HRESULT IsBinaryOperator(in BSTR filename, uint startLine, uint startIndex, uint endLine, uint endIndex, BOOL* pIsOp);
	HRESULT GetParseErrors(in BSTR filename, BSTR* errors);
}

