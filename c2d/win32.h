
#define __cplusplus
#define UNICODE
#define _M_IX86

// take the newest MS stuff
#define _MSC_VER 1600
#define _MSC_FULL_VER 160000000

// remove annotations
#define __SPECSTRINGS_STRICT_LEVEL 1  // 0 for Win SDK 7.1?

// Win SDK 6.0A specific?
#define __allowed(x)
#define __deref_opt_out_z

#define __notnull
#define __maybenull
#define __exceptthat
#define __readonly
#define __refparam
#define __valid
#define __notvalid
#define __reserved
#define __nullterminated
#define __volatile
#define __nonvolatile
#define __w64
#define __ptr64

#define __in
#define __in_opt
#define __out
#define __out_opt
#define __inout
#define __inout_opt
#define __pre
#define __post
#define __deref
#define __deref_in
#define __deref_out
#define __deref_inout
#define __deref_inout_opt
#define __deref_opt_inout_bcount_part_opt(p,s)

#define __success(b)
#define __ecount(n)
#define __in_ecount(n)
#define __out_ecount(n)
#define __elem_writableTo(size)
#define __byte_writableTo(size)
#define __elem_readableTo(size)
#define __byte_readableTo(size)

#define __drv_declspec(x)
#define __inner_checkReturn
#define __inner_control_entrypoint(ep)

#define __inline
#define __forceinline

#define _huge
#define __huge

// translate into invalid expression, so these get expanded
#define __declspec(x) __noexpr __declspec(x)
#define __stdcall     __noexpr __stdcall
#define __cdecl       __noexpr __cdecl

#define __export
#define __override

#define _cdecl __cdecl

#pragma regex("$_ident1 $_ident2 $_ident3 pp4d:___stdcall", "extern(Windows) $_ident1 $_ident2 $_ident3")
#pragma regex("$_ident1 $_ident2          pp4d:___stdcall", "extern(Windows) $_ident1 $_ident2")
#pragma regex("$_ident1                   pp4d:___stdcall", "extern(Windows) $_ident1")
#pragma regex("$_ident1 (pp4d:___stdcall* $_ident2)", "extern(Windows) $_ident1 (*$_ident2)")
#pragma regex("$_ident1* (pp4d:___stdcall* $_ident2)", "extern(Windows) $_ident1* (*$_ident2)")
#pragma regex("pp4d:___declspec($args)", "/+__declspec($args)+/")

#pragma regex("$_ident1 $_ident2 $_ident3 &", "ref $_ident1 $_ident2 $_ident3")
#pragma regex("$_ident1 $_ident2          &", "ref $_ident1 $_ident2")
#pragma regex("$_ident1                   &", "ref $_ident1")

//#pragma regex("alias const CONST;")
//#pragma regex("CONST", "const")
#pragma regex("$_ident const*", "dconst($_ident)*");
#pragma regex("const $_ident*", "dconst($_ident)*");

#define DUMMYUNIONNAME
#define DUMMYUNIONNAME2
#define DUMMYUNIONNAME3
#define DUMMYUNIONNAME4
#define DUMMYUNIONNAME5
#define DUMMYUNIONNAME6
#define DUMMYUNIONNAME7
#define DUMMYUNIONNAME8
#define DUMMYUNIONNAME9

#define DUMMYSTRUCTNAME
#define DUMMYSTRUCTNAME2
#define DUMMYSTRUCTNAME3
#define DUMMYSTRUCTNAME4
#define DUMMYSTRUCTNAME5

#define _VARIANT_BOOL    VARIANT_BOOL

// windef.h and ktmtypes.h
#pragma regex("UOW UOW;", "UOW uow;")

#include "winnt.h"
#if 0
#include "windows.h"
#include "iphlpapi.h"
#include "commctrl.h"

//#include "objidl.idl"
//#include "objidl.h"
/*
#include "sdkddkver.h"
#include "basetsd.h"
#include "ntstatus.h"
#include "winnt.h"
#include "winbase.h"
#include "winuser.h" 
#include "ktmtypes.h"
#include "winerror.h"
#include "winreg.h" 
#include "reason.h"
#include "wingdi.h"
#include "prsht.h"
#include "iphlpapi.h"
#include "iprtrmib.h"
#include "ipexport.h"
#include "iptypes.h"
#include "tcpestats.h"
			// /*"inaddr.h", "in6addr.h",
#include "ipifcons.h"
#include "ipmib.h"
#include "tcpmib.h"
#include "udpmib.h"
#include "ifmib.h"
#include "ifdef.h"
#include "nldef.h"
#include "shellapi.h"
#include "rpcdce.h"
 // /*, "rpcdcep.h"
*/

/*
		win_idl_files ~= [ "unknwn.idl", "oaidl.idl", "wtypes.idl", "oleidl.idl", 
			"ocidl.idl", "objidl.idl", "docobj.idl", "oleauto.h", "objbase.h",
			"mshtmcid.h", "xmldom.idl", "xmldso.idl", "xmldomdid.h", "xmldsodid.h", "idispids.h" ];
*/
#endif
