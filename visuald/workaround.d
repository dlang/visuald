module workaround;

import std.conv;

///////////////////////////////////////////////////////////////
// fix bad compilation order, causing inner function to be generated
//  before outer functions (bugzilla 2962)
// this must be *parsed* before other usage of the template
static if(__traits(compiles,std.conv.parse!(real,string))){}

//__gshared int[string] x;

version(none) debug
{
	
	// drag in some debug symbols from libraries (see bugzilla ????)
	extern extern(C)
	{
		__gshared int D3vdc4util8TextSpan6__initZ;
		__gshared int D3sdk4port4base4GUID6__initZ;
		__gshared int D3std4json9JSONValue6__initZ;
	}
	shared static this()
	{
		auto x1 = &D3vdc4util8TextSpan6__initZ;
		auto x2 = &D3sdk4port4base4GUID6__initZ;
		auto x3 = &D3std4json9JSONValue6__initZ;
	}
}
