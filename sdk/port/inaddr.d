module sdk.port.inaddr;

import sdk.port.base;

//
// IPv4 Internet address
// This is an 'on-wire' format structure.
//
struct in_addr
{
        union S_union
	{
                struct S_union_b { UCHAR s_b1,s_b2,s_b3,s_b4; } S_union_b S_un_b;
                struct S_union_w { USHORT s_w1,s_w2; } S_union_w S_un_w;
                ULONG S_addr;
        } 
	S_union S_un;
	
	alias S_un.S_addr s_addr; /* can be used for most tcp & ip code */
	alias S_un.S_un_b.s_b2 s_host;   // host on imp
	alias S_un.S_un_b.s_b1 s_net;    // network
	alias S_un.S_un_w.s_w2 s_imp;    // imp
	alias S_un.S_un_b.s_b4 s_impno;  // imp #
	alias S_un.S_un_b.s_b3 s_lh;     // logical host
}

alias in_addr IN_ADDR;
alias in_addr* PIN_ADDR;
alias in_addr /*FAR*/ *LPIN_ADDR;

