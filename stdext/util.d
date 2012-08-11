// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2011 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module stdext.util;

////////////////////////////////////////////////////////////////
inout(T) static_cast(T, S = Object)(inout(S) p)
{
	if(!p)
		return null;
	if(__ctfe)
		return cast(inout(T)) p;
	assert(cast(inout(T)) p);
	void* vp = cast(void*)p;
	return cast(inout(T)) vp;
}

////////////////////////////////////////////////////////////////
bool isIn(T...)(T values)
{
	T[0] needle = values[0];
	foreach(v; values[1..$])
		if(v == needle)
			return true;
	return false;
}

