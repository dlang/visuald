module sdk.port.prsht;

import sdk.port.base;

const PSP_DEFAULT                = 0x00000000;
const PSP_DLGINDIRECT            = 0x00000001;
const PSP_USEHICON               = 0x00000002;
const PSP_USEICONID              = 0x00000004;
const PSP_USETITLE               = 0x00000008;
const PSP_RTLREADING             = 0x00000010;


struct _PROPSHEETPAGEA;
struct _PROPSHEETPAGEW;

extern(Windows)
{
	typedef UINT function(HWND hwnd, UINT uMsg, _PROPSHEETPAGEA *ppsp) *LPFNPSPCALLBACKA;
	typedef UINT function(HWND hwnd, UINT uMsg, _PROPSHEETPAGEW *ppsp) *LPFNPSPCALLBACKW;
}

