module workaround;

import std.conv;

import util;

///////////////////////////////////////////////////////////////
// fix bad compilation order, causing inner function to be generated
//  before outer functions (bugzilla 2962)
// this must be *parsed* before other usage of the template
static if(__traits(compiles,std.conv.parse!(real,string))){}

debug
{
	// drag in some debug symbols from libraries (see bugzilla ????)
	extern extern(C)
	{
		__gshared int D4util8TextSpan6__initZ;
	}
	shared static this()
	{
		auto x = D4util8TextSpan6__initZ;
	}
}
