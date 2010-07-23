// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module pkgutil;

import hierutil;
import comutil;

import std.conv;
import sdk.vsi.vsshell;

void showStatusBarText(wstring txt)
{
	auto pIVsStatusbar = queryService!(IVsStatusbar);
	if(pIVsStatusbar)
	{
		scope(exit) release(pIVsStatusbar);
		pIVsStatusbar.SetText((txt ~ "\0"w).ptr);
	}
}

void showStatusBarText(string txt)
{
	showStatusBarText(to!wstring(txt));
}

