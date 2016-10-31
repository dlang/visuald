// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.windows;

import sdk.win32.commctrl;

pragma(lib,"ole32.lib");
pragma(lib,"comctl32.lib");

HRESULT HResultFromLastError()
{
	return HRESULT_FROM_WIN32(GetLastError());
}

int GET_X_LPARAM(LPARAM lp)
{
	return cast(int)cast(short)LOWORD(lp);
}

int GET_Y_LPARAM(LPARAM lp)
{
	return cast(int)cast(short)HIWORD(lp);
}

int MAKELPARAM(int lo, int hi)
{
	return (lo & 0xffff) | (hi << 16);
}

COLORREF RGB(int r, int g, int b)
{
	return cast(COLORREF)(cast(BYTE)r | ((cast(uint)cast(BYTE)g)<<8) | ((cast(uint)cast(BYTE)b)<<16));
}

public import sdk.win32.shellapi;

const WM_SYSTIMER = 0x118;

public import sdk.port.base;

extern(Windows)
{
	uint GetThreadLocale();
	
	UINT DragQueryFileW(HANDLE hDrop, UINT iFile, LPWSTR lpszFile, UINT cch);
	HINSTANCE ShellExecuteW(HWND hwnd, LPCWSTR lpOperation, LPCWSTR lpFile, LPCWSTR lpParameters, LPCWSTR lpDirectory, INT nShowCmd);
}

// use instead of ImageList_LoadImage to avoid reduction to 16 color bitmaps
HIMAGELIST LoadImageList(HINSTANCE hi, LPCSTR lpbmp, int cx, int cy)
{
	auto imglist = ImageList_Create(cx, cy, ILC_MASK | ILC_COLOR24, cx * 10, cx * 10);
	if(!imglist)
		return null;
	auto img = LoadImageA(hi, lpbmp, IMAGE_BITMAP, 0, 0, LR_LOADTRANSPARENT);
	if(!img)
	{
		ImageList_Destroy(imglist);
		return null;
	}
	ImageList_AddMasked(imglist, img, CLR_DEFAULT);
	DeleteObject(img);
	return imglist;
}
