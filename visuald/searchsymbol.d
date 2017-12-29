// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.searchsymbol;

import visuald.windows;
import visuald.winctrl;
import visuald.comutil;
import visuald.hierutil;
import visuald.logutil;
import visuald.stringutil;
import visuald.fileutil;
import visuald.wmmsg;
import visuald.register;
import visuald.dpackage;
import visuald.intellisense;
import visuald.dimagelist;

import sdk.win32.commctrl;
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import dte80a = sdk.vsi.dte80a;
import dte80 = sdk.vsi.dte80;

import stdext.path;
import stdext.string;

import std.utf;
import std.algorithm;
import std.datetime;
import std.math;
import std.string;
import std.path;
import std.file;
import std.conv;
import std.exception;
import std.array;
import core.stdc.stdio : sprintf;

private IVsWindowFrame sWindowFrame;
private	SearchPane sSearchPane;

SearchPane getSearchPane(bool create)
{
	if(!sSearchPane && create)
		sSearchPane = newCom!SearchPane;
	return sSearchPane;
}

bool showSearchWindow()
{
	if(!getSearchPane(true))
		return false;

	if(!sWindowFrame)
	{
		auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell), false);
		if(!pIVsUIShell)
			return false;

		const(wchar)* caption = "Visual D Search"w.ptr;
		HRESULT hr;
		hr = pIVsUIShell.CreateToolWindow(CTW_fInitNew, 0, sSearchPane, 
										  &GUID_NULL, &g_searchWinCLSID, &GUID_NULL, 
										  null, caption, null, &sWindowFrame);
		if(!SUCCEEDED(hr))
			return false;
	}

	if(FAILED(sWindowFrame.Show()))
		return false;
	BOOL fHandled;
	sSearchPane._OnSetFocus(0, 0, 0, fHandled);
	return fHandled != 0;
}

bool showSearchWindow(bool searchFile, string word = "")
{
	if(!showSearchWindow())
		return false;
	
	bool refresh = (sSearchPane._iqp.searchFile != searchFile);
	if(refresh)
		sSearchPane._ReinitViewState(searchFile, false);
	
	if(!searchFile && word.length)
	{
		sSearchPane._iqp.wholeWord = true;
		sSearchPane._iqp.caseSensitive = true;
		sSearchPane._iqp.useRegExp = false;
		refresh = true;
	}
	
	if(sSearchPane._wndFileWheel && word.length)
	{
		sSearchPane._wndFileWheel.SetWindowText(word);
		refresh = true;
	}
	
	if(refresh)
		sSearchPane._RefreshFileList();

	return true;
}

bool closeSearchWindow()
{
	sWindowFrame = release(sWindowFrame);
	sSearchPane = null;
	return true;
}

//const string kImageBmp = "imagebmp";

const int  kColumnInfoVersion = 1;
const bool kToolBarAtTop = true;
const int  kToolBarHeight = 24;
const int  kPaneMargin = 0; // margin for back inside pane
const int  kBackMargin = 2; // margin for controls inside back

struct static_COLUMNINFO
{
	string displayName;
	int fmt;
	int cx;
}

enum COLUMNID
{
	NONE = -1,
	NAME,
	PATH,
	SIZE,
	LINE,
	TYPE,
	SCOPE,
	MODIFIEDDATE,
	KIND,
	MAX
}

const static_COLUMNINFO[] s_rgColumns =
[
	//{ "none", LVCFMT_LEFT, 80 },
	{ "Name", LVCFMT_LEFT, 80 },
	{ "Path", LVCFMT_LEFT, 80 },
	{ "Size", LVCFMT_RIGHT, 80 },
	{ "Line", LVCFMT_RIGHT, 30 },
	{ "Type", LVCFMT_LEFT, 30 },
	{ "Scope", LVCFMT_LEFT, 80 },
	{ "Date", LVCFMT_LEFT, 80 },
	{ "Kind", LVCFMT_LEFT, 80 },
];

struct COLUMNINFO
{
	COLUMNID colid;
	BOOL fVisible;
	int cx;
};

const COLUMNINFO[] default_fileColumns =
[
	{ COLUMNID.NAME, true, 100 },
	{ COLUMNID.PATH, true, 200 },
	{ COLUMNID.MODIFIEDDATE, true, 100 },
];

const COLUMNINFO[] default_symbolColumns =
[
	{ COLUMNID.NAME, true, 100 },
	{ COLUMNID.TYPE, true, 50 },
	{ COLUMNID.PATH, true, 200 },
	{ COLUMNID.LINE, true, 50 },
	{ COLUMNID.SCOPE, true, 100 },
	{ COLUMNID.KIND, true, 100 },
];

struct INDEXQUERYPARAMS
{
	COLUMNID colidSort;
	bool fSortAscending;
	COLUMNID colidGroup;
	bool searchFile;
	bool wholeWord;
	bool caseSensitive;
	bool useRegExp;
}

const HDMIL_PRIVATE = 0xf00d;

class SearchWindowBack : Window
{
	this(Window parent, SearchPane pane)
	{
		mPane = pane;
		super(parent);
	}
	
	override int WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam) 
	{
		BOOL fHandled;
		LRESULT rc = mPane._WindowProc(hWnd, uMsg, wParam, lParam, fHandled);
		if(fHandled)
			return rc;
		
		return super.WindowProc(hWnd, uMsg, wParam, lParam);
	}
	
	SearchPane mPane;
}

class SearchPane : DisposingComObject, IVsWindowPane
{
	static const GUID iid = uuid("FFA501E1-0565-4621-ADEA-9A8F10C1805B");

	IServiceProvider mSite;

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(SearchPane) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsWindowPane) (this, riid, pvObject))
			return S_OK;

		// avoid debug output
		if(*riid == IVsCodeWindow.iid || *riid == IServiceProvider.iid || *riid == IVsTextView.iid)
			return E_NOINTERFACE;
		
		return super.QueryInterface(riid, pvObject);
	}
	
	override void Dispose()
	{
		mSite = release(mSite);
	}
	
	HRESULT SetSite(/+[in]+/ IServiceProvider pSP)
	{
		mixin(LogCallMix2);
		mSite = release(mSite);
		mSite = addref(pSP);
		return S_OK;
	}
	
	HRESULT CreatePaneWindow(in HWND hwndParent, in int x, in int y, in int cx, in int cy,
	                         /+[out]+/ HWND *hwnd)
	{
		mixin(LogCallMix2);

		_wndParent = new Window(hwndParent);
		_wndBack = new SearchWindowBack(_wndParent, this);

		BOOL fHandled;
		_OnInitDialog(WM_INITDIALOG, 0, 0, fHandled);
		_CheckSize();

		_wndBack.setVisible(true);
		return S_OK;
	}
	HRESULT GetDefaultSize(/+[out]+/ SIZE *psize)
	{
		mixin(LogCallMix2);
		psize.cx = 300;
		psize.cy = 200;
		return S_OK;
	}
	HRESULT ClosePane()
	{
		mixin(LogCallMix2);
		if(_wndParent)
		{
			_WriteViewStateToRegistry();

			_wndParent.Dispose();
			_wndParent = null;
			_wndBack = null;
			_wndFileWheel = null;
			_wndFileList = null;
			_wndFileListHdr = null;
			_wndToolbar = null;
			if(_himlToolbar)
				ImageList_Destroy(_himlToolbar);
			_lastResultsArray = null;

			mDlgFont = deleteDialogFont(mDlgFont);
		}
		return S_OK;
	}
	HRESULT LoadViewState(/+[in]+/ IStream pstream)
	{
		mixin(LogCallMix2);
		if(!pstream)
			return E_INVALIDARG;

		HRESULT _doRead(void* p, size_t cnt)
		{
			uint read;
			HRESULT hr = pstream.Read(cast(byte*)p, cnt, &read);
			if(FAILED(hr))
				return hr;
			if(read != cnt)
				return E_UNEXPECTED;
			return hr;
		}

		HRESULT _doReadColumn(ref COLUMNINFO[] columns)
		{
			uint num;
			if(HRESULT hr = _doRead(cast(byte*)&num, num.sizeof))
				return hr;
			if(num > 10)
				return E_UNEXPECTED;
			columns.length = num;
			if(HRESULT hr = _doRead(columns.ptr, columns.length * COLUMNINFO.sizeof))
				return hr;
			return S_OK;
		}

		uint size;
		if(HRESULT hr = _doRead(cast(byte*)&size, size.sizeof))
			return hr;
		if(HRESULT hr = _doReadColumn(_fileColumns))
			return hr;
		if(HRESULT hr = _doReadColumn(_symbolColumns))
			return hr;
		return S_OK;
	}

	HRESULT SaveViewState(/+[in]+/ IStream pstream)
	{
		mixin(LogCallMix2);
		if(!pstream)
			return E_INVALIDARG;

		HRESULT _doWrite(const(void)* p, size_t cnt)
		{
			uint written;
			HRESULT hr = pstream.Write(cast(const(byte)*)p, cnt, &written);
			if(FAILED(hr))
				return hr;
			if(written != cnt)
				return E_UNEXPECTED;
			return hr;
		}

		HRESULT _doWriteColumn(COLUMNINFO[] columns)
		{
			uint num = columns.length;
			if(HRESULT hr = _doWrite(cast(byte*)&num, num.sizeof))
				return hr;
			if(HRESULT hr = _doWrite(columns.ptr, columns.length * COLUMNINFO.sizeof))
				return hr;
			return S_OK;
		}

		// write size overall to allow skipping chunk
		uint size = 2 * uint.sizeof + (_fileColumns.length + _symbolColumns.length) * COLUMNINFO.sizeof;
		if(HRESULT hr = _doWrite(cast(byte*)&size, size.sizeof))
			return hr;

		if(HRESULT hr = _doWriteColumn(_fileColumns))
			return hr;
		if(HRESULT hr = _doWriteColumn(_symbolColumns))
			return hr;
		return S_OK;
	}

	HRESULT TranslateAccelerator(MSG* msg)
	{
		if(msg.message == WM_TIMER)
			_CheckSize();
		
		if(msg.message == WM_TIMER || msg.message == WM_SYSTIMER)
			return E_NOTIMPL; // do not flood debug output
		
		logMessage("TranslateAccelerator", msg.hwnd, msg.message, msg.wParam, msg.lParam);
		
		BOOL fHandled;
		HRESULT hrRet = _HandleMessage(msg.hwnd, msg.message, msg.wParam, msg.lParam, fHandled);

		if(fHandled)
			return hrRet;
		return E_NOTIMPL;
	}

	///////////////////////////////////////////////////////////////////

	// the following has been ported from the FlatSolutionExplorer project
private:
	SolutionItemIndex _spsii;
//    DWORD _dwIndexEventsCookie;

	Window _wndParent;
	SearchWindowBack _wndBack;
	Text _wndFileWheel;
	ListView _wndFileList;
	Window _wndFileListHdr;
	ToolBar _wndToolbar;
	HIMAGELIST _himlToolbar;
	ItemArray _lastResultsArray; // remember to keep reference to SolutionItems referenced in list items
	HFONT mDlgFont;

	BOOL _fCombineColumns;
	BOOL _fAlternateRowColor;
	BOOL _closeOnReturn;
	COLUMNINFO[] _fileColumns;
	COLUMNINFO[] _symbolColumns;
	COLUMNINFO[]* _rgColumns;

	INDEXQUERYPARAMS _iqp;
	COLORREF _crAlternate;

	static HINSTANCE getInstance() { return Widget.getInstance(); }

	int _WindowProc(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled) 
	{
		if(uMsg != WM_NOTIFY)
			logMessage("_WindowProc", hWnd, uMsg, wParam, lParam);
		
		return _HandleMessage(hWnd, uMsg, wParam, lParam, fHandled);
	}
	
	int _HandleMessage(HWND hWnd, uint uMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled) 
	{
		switch(uMsg)
		{
		case WM_CREATE:
		case WM_INITDIALOG:
			return _OnInitDialog(uMsg, wParam, lParam, fHandled);
		case WM_NCCALCSIZE:
			return _OnCalcSize(uMsg, wParam, lParam, fHandled);
		case WM_SIZE:
			return _OnSize(uMsg, wParam, lParam, fHandled);
		case WM_NCACTIVATE:
		case WM_SETFOCUS:
			return _OnSetFocus(uMsg, wParam, lParam, fHandled);
		case WM_CONTEXTMENU:
			return _OnContextMenu(uMsg, wParam, lParam, fHandled);
		case WM_DESTROY:
			return _OnDestroy(uMsg, wParam, lParam, fHandled);
		case WM_KEYDOWN:
		case WM_SYSKEYDOWN:
			return _OnKeyDown(uMsg, wParam, lParam, fHandled);
		case WM_COMMAND:
			ushort id = LOWORD(wParam);
			ushort code = HIWORD(wParam);
			
			if(id == IDC_FILEWHEEL && code == EN_CHANGE)
				return _OnFileWheelChanged(id, code, hWnd, fHandled);
			
			if(code == BN_CLICKED)
			{
				switch(id)
				{
				case IDOK:
					return _OnOpenSelectedItem(code, id, hWnd, fHandled);
				case IDR_COMBINECOLUMNS:
				case IDR_ALTERNATEROWCOLOR:
				case IDR_GROUPBYKIND:
				case IDR_CLOSEONRETURN:
				case IDR_WHOLEWORD:
				case IDR_CASESENSITIVE:
				case IDR_REGEXP:
				case IDR_SEARCHFILE:
				case IDR_SEARCHSYMBOL:
					return _OnCheckBtnClicked(code, id, hWnd, fHandled);
				default:
					break;
				}
			}
			break;
		case WM_NOTIFY:
			NMHDR* nmhdr = cast(NMHDR*)lParam;
			if(nmhdr.idFrom == IDC_FILELIST)
			{
				switch(nmhdr.code)
				{
				case LVN_GETDISPINFO:
					return _OnFileListGetDispInfo(wParam, nmhdr, fHandled);
				case LVN_COLUMNCLICK:
					return _OnFileListColumnClick(wParam, nmhdr, fHandled);
				case LVN_DELETEITEM:
					return _OnFileListDeleteItem(wParam, nmhdr, fHandled);
				case NM_DBLCLK:
					return _OnFileListDblClick(wParam, nmhdr, fHandled);
				case NM_CUSTOMDRAW:
					return _OnFileListCustomDraw(wParam, nmhdr, fHandled);
				default:
					break;
				}
			}
			if (nmhdr.idFrom == IDC_FILELISTHDR && nmhdr.code == HDN_ITEMCHANGED)
				return _OnFileListHdrItemChanged(wParam, nmhdr, fHandled);
			if (nmhdr.idFrom == IDC_TOOLBAR && nmhdr.code == TBN_GETINFOTIP)
				return _OnToolbarGetInfoTip(wParam, nmhdr, fHandled);
			break;
		default:
			break;
		}
		return 0;
	}

	public this()
	{
		_fAlternateRowColor = true;
		_closeOnReturn = true;

		_spsii = new SolutionItemIndex();
		_fileColumns = default_fileColumns.dup;
		_symbolColumns = default_symbolColumns.dup;
		_iqp.colidSort = COLUMNID.NAME;
		_iqp.fSortAscending = true;
		_iqp.colidGroup = COLUMNID.NONE;
		_rgColumns = _iqp.searchFile ? &_fileColumns : &_symbolColumns;
	}

	void _MoveSelection(BOOL fDown)
	{
		// Get the current selection
		int iSel = _wndFileList.SendMessage(LVM_GETNEXTITEM, cast(WPARAM)-1, LVNI_SELECTED);
		int iCnt = _wndFileList.SendMessage(LVM_GETITEMCOUNT);
		if(iSel == 0 && !fDown)
			return;
		if(iSel == iCnt - 1 && fDown)
			return;
		
		LVITEM lvi;
		lvi.iItem = iSel; // fDown ? iSel+1 : iSel-1;
		lvi.mask = LVIF_STATE;
		lvi.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
		lvi.state = 0;
		_wndFileList.SendItemMessage(LVM_SETITEM, lvi);

		lvi.iItem = fDown ? iSel+1 : iSel-1;
		lvi.mask = LVIF_STATE;
		lvi.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
		lvi.state = LVIS_SELECTED | LVIS_FOCUSED;
		_wndFileList.SendItemMessage(LVM_SETITEM, lvi);
		
		_wndFileList.SendMessage(LVM_ENSUREVISIBLE, lvi.iItem, FALSE);
	}

	HRESULT _PrepareFileListForResults(in ItemArray puaResults)
	{
		_wndFileList.SendMessage(LVM_DELETEALLITEMS);
		_wndFileList.SendMessage(LVM_REMOVEALLGROUPS);

		HIMAGELIST himl = LoadImageList(getInstance(), MAKEINTRESOURCEA(BMP_DIMAGELIST), 16, 16);
		if(himl)
			_wndFileList.SendMessage(LVM_SETIMAGELIST, LVSIL_SMALL, cast(LPARAM)himl);

		HRESULT hr = S_OK;
		BOOL fEnableGroups = _iqp.colidGroup != COLUMNID.NONE;
		if (fEnableGroups)
		{
			DWORD cGroups = puaResults.GetCount();
			// Don't enable groups if there is only 1
			if (cGroups <= 1)
			{
				fEnableGroups = FALSE;
			}
		}
    
		if (SUCCEEDED(hr))
		{
			hr = _wndFileList.SendMessage(LVM_ENABLEGROUPVIEW, fEnableGroups) == -1 ? E_FAIL : S_OK;
		}

		return hr;
	}

	HRESULT _AddItemsToFileList(int iGroupId, in ItemArray pua)
	{
		LVITEM lvi;
		lvi.pszText = LPSTR_TEXTCALLBACK;
		lvi.iItem = cast(int)_wndFileList.SendMessage(LVM_GETITEMCOUNT);
		DWORD cItems = pua.GetCount();
		HRESULT hr = S_OK;
		for (DWORD i = 0; i < cItems && SUCCEEDED(hr); i++)
		{
			if(SolutionItem spsi = pua.GetItem(i))
			{
				for (int iCol = COLUMNID.NAME; iCol < COLUMNID.MAX; iCol++)
				{
					lvi.iSubItem = iCol;
					if (iCol != COLUMNID.NAME)
					{
						lvi.mask = LVIF_TEXT;
					}
					else
					{
						lvi.mask = LVIF_PARAM | LVIF_TEXT | LVIF_IMAGE;
						lvi.iGroupId = iGroupId;
						lvi.lParam = cast(LPARAM)cast(void*)spsi;
						lvi.iImage = spsi.GetIconIndex();
						if (iGroupId != -1)
						{
							lvi.mask |= LVIF_GROUPID;
							lvi.iGroupId = iGroupId;
						}
					}
					if (_wndFileList.SendItemMessage(LVM_INSERTITEM, lvi) != -1 && iCol == COLUMNID.NAME)
					{
						//spsi.detach();
					}
				}
				spsi = null;
			}
			lvi.iItem++;
		}
		return hr;
	}

	HRESULT _AddGroupToFileList(int iGroupId, in SolutionItemGroup psig)
	{
		LVGROUP lvg;
		lvg.cbSize = lvg.sizeof;
		lvg.mask = LVGF_ALIGN | LVGF_HEADER | LVGF_GROUPID | LVGF_STATE;
		lvg.uAlign = LVGA_HEADER_LEFT;
		lvg.iGroupId = iGroupId;
		lvg.pszHeader = _toUTF16z(psig.GetName());
		lvg.state = LVGS_NORMAL;
		HRESULT hr = _wndFileList.SendMessage(LVM_INSERTGROUP, cast(WPARAM)-1, cast(LPARAM)&lvg) != -1 ? S_OK : E_FAIL;
		if (SUCCEEDED(hr))
		{
			const(ItemArray) spItems = psig.GetItems();
			if(spItems)
			{
				hr = _AddItemsToFileList(iGroupId, spItems);
			}
		}
		return hr;
	}

	HRESULT _RefreshFileList()
	{
		mixin(LogCallMix);
		
		_wndFileList.SetRedraw(FALSE);

		HRESULT hr = S_OK;
		string strWordWheel = _wndFileWheel.GetWindowText();

		ItemArray spResultsArray;
		hr = _spsii.Search(strWordWheel, &_iqp, &spResultsArray);
		if (SUCCEEDED(hr))
		{
			hr = _PrepareFileListForResults(spResultsArray);
			if (SUCCEEDED(hr))
			{
				if (_iqp.colidGroup != COLUMNID.NONE)
				{
					DWORD cGroups = spResultsArray.GetCount();
					for (DWORD iGroup = 0; iGroup < cGroups && SUCCEEDED(hr); iGroup++)
					{
						if(SolutionItemGroup spsig = spResultsArray.GetGroup(iGroup))
						{
							hr = _AddGroupToFileList(iGroup, spsig);
						}
					}
				}
				else
				{
					hr = _AddItemsToFileList(-1, spResultsArray);
				}
			}
			_lastResultsArray = spResultsArray;
		}

		if (SUCCEEDED(hr))
		{
			// Select the first item
			LVITEM lviSelect;
			lviSelect.mask = LVIF_STATE;
			lviSelect.iItem = 0;
			lviSelect.state = LVIS_SELECTED | LVIS_FOCUSED;
			lviSelect.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
			_wndFileList.SendItemMessage(LVM_SETITEM, lviSelect);
		}

		_wndFileList.SetRedraw(TRUE);
		_wndFileList.InvalidateRect(null, FALSE);
		return hr;
	}

	// Special icon dimensions for the sort direction indicator
	enum int c_cxSortIcon = 7;
	enum int c_cySortIcon = 6;

	HRESULT _CreateSortImageList(out HIMAGELIST phiml)
	{
		// Create an image list for the sort direction indicators
		HIMAGELIST himl = ImageList_Create(c_cxSortIcon, c_cySortIcon, ILC_COLORDDB | ILC_MASK, 2, 1);
		HRESULT hr = himl ? S_OK : E_OUTOFMEMORY;
		if (SUCCEEDED(hr))
		{
			HICON hicn = cast(HICON)LoadImage(getInstance(), MAKEINTRESOURCE(IDI_DESCENDING), IMAGE_ICON, c_cxSortIcon, c_cySortIcon, LR_DEFAULTCOLOR | LR_SHARED);
			hr = hicn ? S_OK : HResultFromLastError();
			if (SUCCEEDED(hr))
			{
				hr = ImageList_ReplaceIcon(himl, -1, hicn) != -1 ? S_OK : E_FAIL;
				if (SUCCEEDED(hr))
				{
					hicn = cast(HICON)LoadImage(getInstance(), MAKEINTRESOURCE(IDI_ASCENDING), IMAGE_ICON, c_cxSortIcon, c_cySortIcon, LR_DEFAULTCOLOR | LR_SHARED);
					hr = hicn ? S_OK : HResultFromLastError();
					if (SUCCEEDED(hr))
					{
						hr = ImageList_ReplaceIcon(himl, -1, hicn) != -1 ? S_OK : E_FAIL;
						if (SUCCEEDED(hr))
						{
							phiml = himl;
							himl = null;
						}
					}
				}
			}
			if (himl)
			{
				ImageList_Destroy(himl);
			}
		}
		return hr;
	}

	HRESULT _AddSortIcon(int iIndex, BOOL fAscending)
	{
		if(iIndex < 0)
			return E_FAIL;
		// First, get the current header item fmt
		HDITEM hdi;
		hdi.mask = HDI_FORMAT;
		HRESULT hr = _wndFileListHdr.SendMessage(HDM_GETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
		if (SUCCEEDED(hr))
		{
			// Add the image mask and alignment
			hdi.mask |= HDI_IMAGE;
			hdi.fmt |= HDF_IMAGE;
			if ((hdi.fmt & HDF_JUSTIFYMASK) == HDF_LEFT)
			{
				hdi.fmt |= HDF_BITMAP_ON_RIGHT;
			}
			hdi.iImage = fAscending;
			hr = _wndFileListHdr.SendMessage(HDM_SETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
		}
		return hr;
	}

	HRESULT _RemoveSortIcon(int iIndex)
	{
		if(iIndex < 0)
			return E_FAIL;
		// First, get the current header item fmt
		HDITEM hdi;
		hdi.mask = HDI_FORMAT;
		HRESULT hr = _wndFileListHdr.SendMessage(HDM_GETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
		if (SUCCEEDED(hr))
		{
			// Remove the image mask and alignment
			hdi.fmt &= ~HDF_IMAGE;
			if ((hdi.fmt & HDF_JUSTIFYMASK) == HDF_LEFT)
			{
				hdi.fmt &= ~HDF_BITMAP_ON_RIGHT;
			}
			hr = _wndFileListHdr.SendMessage(HDM_SETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
		}
		return hr;
	}

	HRESULT _InsertListViewColumn(int iIndex, COLUMNID colid, int cx, bool set = false)
	{
		LVCOLUMN lvc;
		lvc.mask = LVCF_FMT | LVCF_TEXT | LVCF_WIDTH;
		lvc.fmt = s_rgColumns[colid].fmt;
		lvc.cx = cx;

		HRESULT hr = S_OK;
		string strDisplayName = s_rgColumns[colid].displayName;
		lvc.pszText = _toUTF16z(strDisplayName);
		uint msg = set ? LVM_SETCOLUMNW : LVM_INSERTCOLUMNW;
		hr = _wndFileList.SendMessage(msg, iIndex, cast(LPARAM)&lvc) >= 0 ? S_OK : E_FAIL;
		if (SUCCEEDED(hr))
		{
			HDITEM hdi;
			hdi.mask = HDI_LPARAM;
			hdi.lParam = colid;
			hr = _wndFileListHdr.SendMessage(HDM_SETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
		}
		return hr;
	}

	HRESULT _InitializeFileListColumns()
	{
		_wndFileList.SendMessage(LVM_DELETEALLITEMS);
		_wndFileList.SendMessage(LVM_REMOVEALLGROUPS);

		bool hasNameColumn = _wndFileList.SendMessage(LVM_GETCOLUMNWIDTH, 0) > 0;
		// cannot delete col 0, so keep name
		while(_wndFileList.SendMessage(LVM_DELETECOLUMN, 1)) {}
		
		HRESULT hr = S_OK;
		COLUMNID colPath = _iqp.searchFile ? COLUMNID.PATH : COLUMNID.TYPE;
		int cColumnsInserted = 0;
		for (UINT i = 0; i < _rgColumns.length && SUCCEEDED(hr); i++)
		{
			COLUMNINFO* ci = &(*_rgColumns)[i];
			if (ci.fVisible)
			{
				// Don't insert the path column if we're compressing path and filename
				if (ci.colid != colPath || !_fCombineColumns)
				{
					int cx = ci.cx;
					if (ci.colid == COLUMNID.NAME && _fCombineColumns)
					{
						COLUMNINFO *pci = _ColumnInfoFromColumnID(colPath);
						cx += pci.cx;
					}
					bool set = hasNameColumn ? cColumnsInserted == 0 : false;
					hr = _InsertListViewColumn(cColumnsInserted++, ci.colid, cx, set);
				}
			}
		}
		return hr;
	}
	
	HRESULT _InitializeFileList()
	{
		_wndFileList.SendMessage(LVM_SETEXTENDEDLISTVIEWSTYLE, 
		                         LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP,
		                         LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);

		HIMAGELIST himl;
		HRESULT hr = _CreateSortImageList(himl);
		if (SUCCEEDED(hr))
		{
			_wndFileListHdr.SendMessage(HDM_SETIMAGELIST, HDMIL_PRIVATE, cast(LPARAM)himl);

			_InitializeFileListColumns();
			
			if (SUCCEEDED(hr))
			{
				hr = _AddSortIcon(_ListViewIndexFromColumnID(_iqp.colidSort), _iqp.fSortAscending);
				if (SUCCEEDED(hr))
				{
					_RefreshFileList();
				}
			}
		}
		return hr;
	}

	// Special icon dimensions for the toolbar images
	enum int c_cxToolbarIcon = 16;
	enum int c_cyToolbarIcon = 15;

	HRESULT _CreateToolbarImageList(out HIMAGELIST phiml)
	{
		// Create an image list for the sort direction indicators
		int icons = IDR_LAST - IDR_FIRST + 1;
		HIMAGELIST himl = ImageList_Create(c_cxToolbarIcon, c_cyToolbarIcon, ILC_COLORDDB | ILC_MASK, icons, 1);
		HRESULT hr = himl ? S_OK : E_OUTOFMEMORY;
		if (SUCCEEDED(hr))
		{
			// icons  have image index IDR_XXX - IDR_FIRST
			for (int i = IDR_FIRST; i <= IDR_LAST && SUCCEEDED(hr); i++)
			{
				HICON hicn = cast(HICON)LoadImage(getInstance(), MAKEINTRESOURCE(i), 
												  IMAGE_ICON, c_cxToolbarIcon, c_cyToolbarIcon, LR_DEFAULTCOLOR | LR_SHARED);
				hr = hicn ? S_OK : HResultFromLastError();
				if (SUCCEEDED(hr))
				{
					hr = ImageList_ReplaceIcon(himl, -1, hicn) != -1 ? S_OK : E_FAIL;
				}
			}

			if (SUCCEEDED(hr))
			{
				phiml = himl;
				himl = null;
			}

			if (himl)
			{
				ImageList_Destroy(himl);
			}
		}
		return hr;
	}

	HRESULT _InitializeToolbar()
	{
		HRESULT hr = _CreateToolbarImageList(_himlToolbar);
		if (SUCCEEDED(hr))
		{
			int style = CCS_NODIVIDER | TBSTYLE_FLAT | TBSTYLE_TOOLTIPS | CCS_NORESIZE;
			//style |= (kToolBarAtTop ? CCS_TOP : CCS_BOTTOM);
			_wndToolbar = new ToolBar(_wndBack, style, TBSTYLE_EX_DOUBLEBUFFER, IDC_TOOLBAR);
			hr = _wndToolbar.hwnd ? S_OK : E_FAIL;
			if (SUCCEEDED(hr))
			{
				_wndToolbar.setRect(kBackMargin, kBackMargin, 100, kToolBarHeight);
				_wndToolbar.SendMessage(TB_SETIMAGELIST, 0, cast(LPARAM)_himlToolbar);

				TBBUTTON btn2 = { 10, 11, TBSTATE_ENABLED, 1, [0,0], 0, 0 };
				
				TBBUTTON initButton(int id, ubyte style)
				{
					return TBBUTTON(id < 0 ? 10 : id - IDR_FIRST, id, TBSTATE_ENABLED, style, [0,0], 0, 0);
				}
				static const TBBUTTON[] s_tbb = [
					initButton(IDR_SEARCHFILE,        BTNS_CHECKGROUP),
					initButton(IDR_SEARCHSYMBOL,      BTNS_CHECKGROUP),
					initButton(-1, BTNS_SEP),
					initButton(IDR_COMBINECOLUMNS,    BTNS_CHECK),
					initButton(IDR_ALTERNATEROWCOLOR, BTNS_CHECK),
					initButton(IDR_GROUPBYKIND,       BTNS_CHECK),
					initButton(IDR_CLOSEONRETURN,     BTNS_CHECK),
					initButton(-1, BTNS_SEP),
					initButton(IDR_WHOLEWORD,         BTNS_CHECK),
					initButton(IDR_CASESENSITIVE,     BTNS_CHECK),
					initButton(IDR_REGEXP,            BTNS_CHECK),
				];

				hr = _wndToolbar.SendMessage(TB_ADDBUTTONS, s_tbb.length, cast(LPARAM)s_tbb.ptr) ? S_OK : E_FAIL;
				if (SUCCEEDED(hr))
				{
					hr = _InitializeSwitches();
				}
			}
		}
		return hr;
	}

	HRESULT _InitializeSwitches()
	{
		// Set the initial state of the buttons
		HRESULT hr = S_OK;

		_wndToolbar.EnableCheckButton(IDR_COMBINECOLUMNS,    true, _fCombineColumns != 0);
		_wndToolbar.EnableCheckButton(IDR_ALTERNATEROWCOLOR, true, _fAlternateRowColor != 0);
		_wndToolbar.EnableCheckButton(IDR_CLOSEONRETURN,     true, _closeOnReturn != 0);
		_wndToolbar.EnableCheckButton(IDR_GROUPBYKIND,       true, _iqp.colidGroup == COLUMNID.KIND);

		_wndToolbar.EnableCheckButton(IDR_WHOLEWORD,         true, _iqp.wholeWord);
		_wndToolbar.EnableCheckButton(IDR_CASESENSITIVE,     true, !_iqp.caseSensitive); // button on is case INsensitive
		_wndToolbar.EnableCheckButton(IDR_REGEXP,            true, _iqp.useRegExp);
		_wndToolbar.EnableCheckButton(IDR_SEARCHFILE,        true, _iqp.searchFile);
		_wndToolbar.EnableCheckButton(IDR_SEARCHSYMBOL,      true, !_iqp.searchFile);
		
		return hr;
	}
	
	extern(Windows) LRESULT _HdrWndProc(HWND hwnd, UINT uiMsg, WPARAM wParam, LPARAM lParam)
	{
		LRESULT lRet = 0;
		BOOL fHandled = FALSE;
		switch (uiMsg)
		{
		case WM_DESTROY:
			RemoveWindowSubclass(hwnd, &s_HdrWndProc, ID_SUBCLASS_HDR);
			break;

		case HDM_SETIMAGELIST:
			if (wParam == HDMIL_PRIVATE)
			{
				wParam = 0;
			}
			else
			{
				fHandled = TRUE;
			}
			break;
		default:
			break;
		}

		if (!fHandled)
		{
			lRet = DefSubclassProc(hwnd, uiMsg, wParam, lParam);
		}
		return lRet;
	}

	static extern(Windows) LRESULT s_HdrWndProc(HWND hWnd, UINT uiMsg, WPARAM wParam, LPARAM lParam, UINT_PTR uIdSubclass, DWORD_PTR dwRefData)
	{
		if(SearchPane pfsec = cast(SearchPane)cast(void*)dwRefData)
			return pfsec._HdrWndProc(hWnd, uiMsg, wParam, lParam);
		return DefSubclassProc(hWnd, uiMsg, wParam, lParam);
	}
	

	LRESULT _OnInitDialog(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		if(_wndFileWheel)
			return S_OK;

		updateEnvironmentFont();
		if(!mDlgFont)
			mDlgFont = newDialogFont();

		if (SUCCEEDED(_InitializeViewState()))
		{
			_wndFileWheel = new Text(_wndBack, "", IDC_FILEWHEEL);
			int top = kToolBarAtTop ? kToolBarHeight : 1;
			_wndFileWheel.setRect(kBackMargin, top + 2 + kBackMargin, 185, 16);
			_wndFileList = new ListView(_wndBack, LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_ALIGNLEFT | LVS_SHAREIMAGELISTS | WS_BORDER | WS_TABSTOP,
			                            0, IDC_FILELIST);
			_wndFileList.setRect(kBackMargin, top + kBackMargin + 20, 185, 78);
			HWND hdrHwnd = cast(HWND)_wndFileList.SendMessage(LVM_GETHEADER);
			if(hdrHwnd)
			{
				_wndFileListHdr = new Window(hdrHwnd);

				// HACK:  This header control is created by the listview.  When listview handles LVM_SETIMAGELIST with
				// LVSIL_SMALL it also forwards the message to the header control.  The subclass proc will intercept those
				// messages and prevent resetting the imagelist
				SetWindowSubclass(_wndFileListHdr.hwnd, &s_HdrWndProc, ID_SUBCLASS_HDR, cast(DWORD_PTR)cast(void*)this);

				//_wndFileListHdr.SetDlgCtrlID(IDC_FILELISTHDR);
			}
			_InitializeFileList();

			_InitializeToolbar();
		}
		//return CComCompositeControl<CFlatSolutionExplorer>::OnInitDialog(uiMsg, wParam, lParam, fHandled);
		return S_OK;
	}

	LRESULT _OnCalcSize(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
//		_CheckSize();
		return 0;
	}
	
	void _CheckSize()
	{
		RECT r, br;
		_wndParent.GetClientRect(&r);
		_wndBack.GetClientRect(&br);
		if(br.right - br.left != r.right - r.left - 2*kPaneMargin || 
		   br.bottom - br.top != r.bottom - r.top - 2*kPaneMargin)
			_wndBack.setRect(kPaneMargin, kPaneMargin, 
							 r.right - r.left - 2*kPaneMargin, r.bottom - r.top - 2*kPaneMargin);
	}
	
	LRESULT _OnSize(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		int cx = LOWORD(lParam);
		int cy = HIWORD(lParam);

		// Adjust child control sizes
		// - File Wheel stretches to fit horizontally but size is vertically fixed
		// - File List stretches to fit horizontally and vertically but the topleft coordinate is fixed
		// - Toolbar autosizes along the bottom

		_wndToolbar.setRect(kBackMargin, kBackMargin, cx - 2 * kBackMargin, kToolBarHeight);
		
		RECT rcFileWheel;
		if (_wndFileWheel.GetWindowRect(&rcFileWheel))
		{
			_wndBack.ScreenToClient(&rcFileWheel);
			rcFileWheel.right = cx - kBackMargin;
			_wndFileWheel.SetWindowPos(null, &rcFileWheel, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
			RECT rcFileList;
			if (_wndFileList.GetWindowRect(&rcFileList))
			{
				_wndBack.ScreenToClient(&rcFileList);
				rcFileList.right = cx - kBackMargin;
				rcFileList.bottom = cy - (kToolBarAtTop ? 0 : kToolBarHeight) - kBackMargin;
				_wndFileList.SetWindowPos(null, &rcFileList, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
			}
		}
		return 0;
	}

	LRESULT _OnSetFocus(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		// Skip the CComCompositeControl handling
		// CComControl<CFlatSolutionExplorer, CAxDialogImpl<CFlatSolutionExplorer>>::OnSetFocus(uiMsg, wParam, lParam, fHandled);

		if(_wndFileWheel)
		{
			_wndFileWheel.SetFocus();
			_wndFileWheel.SendMessage(EM_SETSEL, 0, cast(LPARAM)-1);
			fHandled = TRUE;
		}
		return 0;
	}

	LRESULT _OnKeyDown(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		//HWND hwndFocus = .GetFocus();
		//UINT cItems = cast(UINT)_wndFileList.SendMessage(LVM_GETITEMCOUNT);
		//if (cItems && hwndFocus == _wndFileWheel.hwnd)
		{
			UINT vKey = LOWORD(wParam);
			switch(vKey)
			{
			case VK_UP:
			case VK_DOWN:
			case VK_PRIOR:
			case VK_NEXT:
				fHandled = TRUE;
				return _wndFileList.SendMessage(uiMsg, wParam, lParam);
				// _MoveSelection(vKey == VK_DOWN);
			case VK_RETURN:
			case VK_EXECUTE:
				return _OnOpenSelectedItem(0, 0, null, fHandled);
			case VK_ESCAPE:
				if(_closeOnReturn)
					sWindowFrame.Hide();
				break;
			default:
				break;
			}
		}
		return 0;
	}
			
	HRESULT _ToggleColumnVisibility(COLUMNID colid)
	{
		HRESULT hr = E_FAIL;
		COLUMNINFO *pci = _ColumnInfoFromColumnID(colid);
		BOOL fVisible = !pci.fVisible;
		if (fVisible)
		{
			int iIndex = 0;
			BOOL fDone = FALSE;
			COLUMNID colPath = _iqp.searchFile ? COLUMNID.PATH : COLUMNID.TYPE;
			for (size_t i = 0; i < _rgColumns.length && !fDone; i++)
			{
				COLUMNINFO *ci = &(*_rgColumns)[i];
				if (ci.colid == colid)
				{
					fDone = TRUE;
				}
				else if (ci.fVisible && (ci.colid != colPath || !_fCombineColumns))
				{
					iIndex++;
				}
			}

			hr = _InsertListViewColumn(iIndex, colid, pci.cx);
			if (SUCCEEDED(hr))
			{
				pci.fVisible = TRUE;
			}
		}
		else
		{
			int iCol = _ListViewIndexFromColumnID(colid);

			hr = _wndFileList.SendMessage(LVM_DELETECOLUMN, iCol) ? S_OK : E_FAIL;
			if (SUCCEEDED(hr))
			{
				pci.fVisible = fVisible;
				if (colid == _iqp.colidSort)
				{
					hr = _SetSortColumn(COLUMNID.NAME, 0);
				}
			}
		}

		if (SUCCEEDED(hr))
		{
			_WriteColumnInfoToRegistry();
		}
		return hr;
	}

	HRESULT _ChooseColumns(POINT pt)
	{
		HMENU hmnu = CreatePopupMenu();
		HRESULT hr = hmnu ? S_OK : HResultFromLastError();
		if (SUCCEEDED(hr))
		{
			MENUITEMINFO mii;
			mii.cbSize = mii.sizeof;
			mii.fMask = MIIM_FTYPE | MIIM_ID | MIIM_STATE | MIIM_STRING;
			mii.fType = MFT_STRING;
			COLUMNID colPath = _iqp.searchFile ? COLUMNID.PATH : COLUMNID.TYPE;
			
			// Don't include the first column (COLUMNID.NAME) in the list
			for (size_t i = COLUMNID.NAME + 1; i < _rgColumns.length && SUCCEEDED(hr); i++)
			{
				COLUMNINFO *ci = &(*_rgColumns)[i];
				string strDisplayName = s_rgColumns[ci.colid].displayName;
				mii.fState = (ci.colid == colPath && _fCombineColumns) ? MFS_DISABLED : MFS_ENABLED;
				if (ci.fVisible)
				{
					mii.fState |= MFS_CHECKED;
				}
				mii.wID = ci.colid + IDM_COLUMNLISTBASE;
				mii.dwTypeData = _toUTF16z(strDisplayName);
				if(!InsertMenuItem(hmnu, cast(UINT)i-1, TRUE, &mii))
					hr = HResultFromLastError();
			}

			if (SUCCEEDED(hr))
			{
				UINT uiCmd = TrackPopupMenuEx(hmnu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_HORIZONTAL | TPM_TOPALIGN | TPM_LEFTALIGN, pt.x, pt.y, _wndBack.hwnd, null);
				if (uiCmd)
				{
					hr = _ToggleColumnVisibility(cast(COLUMNID)(uiCmd - IDM_COLUMNLISTBASE));
				}
			}
			DestroyMenu(hmnu);
		}
		return hr;
	}

	LRESULT _OnContextMenu(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		fHandled = FALSE;

		HWND hwndContextMenu = cast(HWND)wParam;
		// I think the listview is doing the wrong thing with WM_CONTEXTMENU and using its own HWND even if
		// the WM_CONTEXTMENU originated in the header.  Just double check the coordinates to be sure
		if (hwndContextMenu == _wndFileList.hwnd)
		{
			RECT rcHdr;
			if (_wndFileListHdr.GetWindowRect(&rcHdr))
			{
				POINT pt;
				pt.x = GET_X_LPARAM(lParam);
				pt.y = GET_Y_LPARAM(lParam);
				if (PtInRect(&rcHdr, pt))
				{
					fHandled = TRUE;
					_ChooseColumns(pt);
				}
			}
		}
		return 0;
	}

	LRESULT _OnDestroy(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
	{
		if (_himlToolbar)
		{
			_wndToolbar.SendMessage(TB_SETIMAGELIST, 0, cast(LPARAM)null);
			ImageList_Destroy(_himlToolbar);
			_himlToolbar = null;
		}

		fHandled = TRUE;
		// return CComCompositeControl<CFlatSolutionExplorer>::OnDestroy(uiMsg, wParam, lParam, fHandled);
		return 0;
	}

	HRESULT _OpenSolutionItem(string pszPath, int line, string scop)
	{
		HRESULT hr = S_OK;
		hr = OpenFileInSolutionWithScope(pszPath, line, 0, scop, true);
		if(hr == S_OK && _closeOnReturn)
			sWindowFrame.Hide();
		return hr;
	}

	LRESULT _OnOpenSelectedItem(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled)
	{
		int iSel = _wndFileList.SendMessage(LVM_GETNEXTITEM, cast(WPARAM)-1, LVNI_SELECTED);
		if (iSel != -1)
		{
			_OpenSolutionItem(iSel);
		}
		else
		{
			_OpenSolutionItem(_wndFileWheel.GetWindowText(), -1, "");
		}
		fHandled = TRUE;
		return 0;
	}

	LRESULT _OnFileWheelChanged(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled)
	{
		fHandled = TRUE;
		_RefreshFileList();
		return 0;
	}

	static struct CmdToColID 
	{
		uint uiCmd;
		COLUMNID colid;
	}
	
	static const CmdToColID[] s_rgCmdToColIDMap = 
	[
		// { IDR_UNGROUPED, COLUMNID.NONE },
		{ IDR_GROUPBYKIND, COLUMNID.KIND }
	];

/+
	UINT _ColumnIDtoGroupCommandID(COLUMNID colid)
	{
		UINT uiRet = IDR_UNGROUPED;
		BOOL fFound = FALSE;
		for (int i = 0; i < s_rgCmdToColIDMap.length && !fFound; i++)
		{
			if (colid == s_rgCmdToColIDMap[i].colid)
			{
				uiRet = s_rgCmdToColIDMap[i].uiCmd;
				fFound = TRUE;
			}
		}
		return uiRet;
	}
+/
	
	COLUMNID _GroupCommandIDtoColumnID(UINT uiCmd)
	{
		COLUMNID colidRet = COLUMNID.NONE;
		BOOL fFound = FALSE;
		for (int i = 0; i < s_rgCmdToColIDMap.length && !fFound; i++)
		{
			if (uiCmd == s_rgCmdToColIDMap[i].uiCmd)
			{
				colidRet = s_rgCmdToColIDMap[i].colid;
				fFound = TRUE;
			}
		}
		return colidRet;
	}

	HRESULT _SetGroupColumn(COLUMNID colid)
	{
		_iqp.colidGroup = colid;

		_WriteViewOptionToRegistry("GroupColumn"w, _iqp.colidGroup);

		return _RefreshFileList();
	}

	int _ListViewIndexFromColumnID(COLUMNID colid)
	{
		int iCol = -1;
		int cCols = _wndFileListHdr.SendMessage(HDM_GETITEMCOUNT);
		for (int i = 0; i < cCols && iCol == -1; i++)
		{
			HDITEM hdi;
			hdi.mask = HDI_LPARAM;
			if (_wndFileListHdr.SendMessage(HDM_GETITEM, i, cast(LPARAM)&hdi) && hdi.lParam == colid)
			{
				iCol = i;
			}
		}
		return iCol;
	}

	COLUMNINFO *_ColumnInfoFromColumnID(COLUMNID colid)
	{
		COLUMNINFO *pci = null;
		for (size_t iCol = 0; iCol < _rgColumns.length && pci is null; iCol++)
		{
			COLUMNINFO *ci = &(*_rgColumns)[iCol];
			if (ci.colid == colid)
			{
				pci = ci;
			}
		}
		return pci;
	}

	HRESULT _SetCompressedNameAndPath(BOOL fSet)
	{
		HRESULT hr = S_OK;
		if (fSet != _fCombineColumns)
		{
			int iName = _ListViewIndexFromColumnID(COLUMNID.NAME);
			COLUMNID colPath = _iqp.searchFile ? COLUMNID.PATH : COLUMNID.TYPE;
			COLUMNINFO *pciPath = _ColumnInfoFromColumnID(colPath);
			COLUMNINFO *pciName = _ColumnInfoFromColumnID(COLUMNID.NAME);

			hr = (iName > -1 && pciPath && pciName) ? S_OK : E_FAIL;
			if (SUCCEEDED(hr))
			{
				_fCombineColumns = fSet;
				_wndFileList.SetRedraw(FALSE);
				_wndFileListHdr.SetRedraw(FALSE);
				if (fSet)
				{
					// If the path column is currently hidden, set it to visible
					if (pciPath.fVisible)
					{
						int iPath = _ListViewIndexFromColumnID(colPath);
						hr = _wndFileList.SendMessage(LVM_DELETECOLUMN, iPath) ? S_OK : E_FAIL;
					}
					else
					{
						pciPath.fVisible = TRUE;
					}

					_wndFileList.SendMessage(LVM_SETCOLUMNWIDTH, iName, MAKELPARAM(pciName.cx + pciPath.cx, 0));

					// If the list is currently sorted by path, change it to name.  Otherwise, just reset the values
					// for the name column and avoid a requery
					if (_iqp.colidSort == colPath)
					{
						_SetSortColumn(COLUMNID.NAME, iName);
					}
					else
					{
						LVITEM lvi;
						lvi.mask = LVIF_TEXT;
						lvi.pszText = LPSTR_TEXTCALLBACK;
						lvi.iSubItem = iName;
						UINT cItems = cast(UINT)_wndFileList.SendMessage(LVM_GETITEMCOUNT);
						for (UINT i = 0; i < cItems; i++)
						{
							lvi.iItem = i;
							_wndFileList.SendItemMessage(LVM_SETITEM, lvi);
						}
					}
				}
				else
				{
					_wndFileList.SendMessage(LVM_SETCOLUMNWIDTH, iName, MAKELPARAM(pciName.cx, 0));
					pciPath.cx = max(pciPath.cx, 30);
					hr = _InsertListViewColumn(iName + 1, colPath, pciPath.cx);
					if (SUCCEEDED(hr))
					{
						LVITEM lvi;
						lvi.mask = LVIF_TEXT;
						lvi.pszText = LPSTR_TEXTCALLBACK;
						UINT cItems = cast(UINT)_wndFileList.SendMessage(LVM_GETITEMCOUNT);
						for (UINT i = 0; i < cItems; i++)
						{
							lvi.iItem = i;
							lvi.iSubItem = iName;
							_wndFileList.SendItemMessage(LVM_SETITEM, lvi);
							lvi.iSubItem = iName+1;
							_wndFileList.SendItemMessage(LVM_SETITEM, lvi);
						}
					}
				}

				_WriteViewOptionToRegistry("CombineColumns"w, _fCombineColumns);

				_wndFileListHdr.SetRedraw(TRUE);
				_wndFileListHdr.InvalidateRect(null, FALSE);
				_wndFileList.SetRedraw(TRUE);
				_wndFileList.InvalidateRect(null, FALSE);
			}
		}
		return hr;
	}

	LRESULT _OnCheckBtnClicked(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled)
	{
		TBBUTTONINFO tbbi;
		tbbi.cbSize = tbbi.sizeof;
		tbbi.dwMask = TBIF_STATE;
		if (_wndToolbar.SendMessage(TB_GETBUTTONINFO, wID, cast(LPARAM)&tbbi) != -1)
		{
			bool checked = !!(tbbi.fsState & TBSTATE_CHECKED);
			
			switch(wID)
			{
			case IDR_COMBINECOLUMNS:
				_SetCompressedNameAndPath(checked);
				break;
		
			case IDR_ALTERNATEROWCOLOR:
				_fAlternateRowColor = checked;
				_WriteViewOptionToRegistry("AlternateRowColor"w, _fAlternateRowColor);
				_wndFileList.InvalidateRect(null, FALSE);
				break;
			
			case IDR_CLOSEONRETURN:
				_closeOnReturn = checked;
				_WriteViewOptionToRegistry("CloseOnReturn"w, _closeOnReturn);
				break;
			
			case IDR_GROUPBYKIND:
				_SetGroupColumn(checked ? COLUMNID.KIND : COLUMNID.NONE);
				break;

			case IDR_WHOLEWORD:
				_iqp.wholeWord = checked;
				_WriteViewOptionToRegistry("WholeWord"w, _iqp.wholeWord);
				_RefreshFileList();
				break;
			case IDR_CASESENSITIVE:
				_iqp.caseSensitive = !checked;
				_WriteViewOptionToRegistry("CaseSensitive"w, _iqp.caseSensitive);
				_RefreshFileList();
				break;
			case IDR_REGEXP:
				_iqp.useRegExp = checked;
				_WriteViewOptionToRegistry("UseRegExp"w, _iqp.useRegExp);
				_RefreshFileList();
				break;

			case IDR_SEARCHFILE:
				_ReinitViewState(checked, true);
				break;
			case IDR_SEARCHSYMBOL:
				_ReinitViewState(!checked, true);
				break;
			
			default:
				return 1;
			}
		}

		fHandled = TRUE;
		return 0;
	}

	////////////////////////////////////////////////////////////////////////
	COLUMNID _ColumnIDFromListViewIndex(int iIndex)
	{
		COLUMNID colid = COLUMNID.NONE;
		HDITEM hdi;
		hdi.mask = HDI_LPARAM;
		if (_wndFileListHdr.SendMessage(HDM_GETITEM, iIndex, cast(LPARAM)&hdi))
		{
			colid = cast(COLUMNID)hdi.lParam;
		}
		return colid;
	}

	string _timeString(const(SysTime) time)
	{
version(all)
{
		DateTime dt = cast(DateTime) time;
		return dt.toSimpleString();
}
else
{
		char[] buffer = new char[128];
		
//		auto dst = daylightSavingTA(time);
//		auto offset = localTZA + dst;
		auto t = time; // + offset;

		auto len = sprintf(buffer.ptr, "%04d/%02d/%02d %02d:%02d:%02d",
		                   yearFromTime(t), dateFromTime(t), monthFromTime(t) + 1,
		                   hourFromTime(t), minFromTime(t), secFromTime(t));
		
		assert(len < buffer.length);
		buffer = buffer[0 .. len];
		return assumeUnique(buffer);
}
	}
	
	////////////////////////////////////////////////////////////////////////
	LRESULT _OnFileListGetDispInfo(int idCtrl, in NMHDR *pnmh, ref BOOL fHandled)
	{
		NMLVDISPINFO *pnmlvdi = cast(NMLVDISPINFO *)pnmh;
		if (pnmlvdi.item.mask & LVIF_TEXT)
		{
			LVITEM lvi;
			lvi.mask = LVIF_PARAM;
			lvi.iItem = pnmlvdi.item.iItem;
			if (_wndFileList.SendItemMessage(LVM_GETITEM, lvi))
			{
				pnmlvdi.item.mask |= LVIF_DI_SETITEM;
				SolutionItem psiWeak = cast(SolutionItem)cast(void*)lvi.lParam;
				string txt;
				switch (_ColumnIDFromListViewIndex(pnmlvdi.item.iSubItem))
				{
				case COLUMNID.NAME:
					if (_fCombineColumns)
					{
						string name = psiWeak.GetName();
						if(_iqp.searchFile)
						{
							string path = psiWeak.GetPath();
							txt = name ~ " (" ~ path ~ ")";
						}
						else
						{
							string type = psiWeak.GetType();
							if(type.length)
								txt = name ~ " : " ~ type;
							else
								txt = name;
						}
					}
					else
					{
						txt = psiWeak.GetName();
					}
					break;

				case COLUMNID.PATH:
					txt = psiWeak.GetPath();
					break;

				case COLUMNID.SIZE:
					long cb = psiWeak.GetSize();
					txt = to!string(cb);
					break;

				case COLUMNID.MODIFIEDDATE:
					const(SysTime) ft = psiWeak.GetModified();
					if(ft.stdTime() != 0)
						//txt = std.date.toString(ft);
						txt = _timeString(ft);
					break;

				case COLUMNID.LINE:
					int ln = psiWeak.GetLine();
					if(ln >= 0)
						txt = to!string(ln);
					break;

				case COLUMNID.SCOPE:
					txt = psiWeak.GetScope();
					break;

				case COLUMNID.TYPE:
					txt = psiWeak.GetType();
					break;

				case COLUMNID.KIND:
					txt = psiWeak.GetKind();
					break;

				default:
					break;
				}

				wstring wtxt = toUTF16(txt) ~ '\000';
				int cnt = min(wtxt.length, pnmlvdi.item.cchTextMax);
				pnmlvdi.item.pszText[0..cnt] = wtxt.ptr[0..cnt];
			}
		}
		fHandled = TRUE;
		return 0;
	}

	void _ReinitViewState(bool searchFile, bool refresh)
	{
		_WriteViewStateToRegistry();
		_RemoveSortIcon(_ListViewIndexFromColumnID(_iqp.colidSort));

		_iqp.searchFile = searchFile;

		_rgColumns = _iqp.searchFile ? &_fileColumns : &_symbolColumns;
		
		_InitializeViewState();
		_InitializeSwitches();
		_AddSortIcon(_ListViewIndexFromColumnID(_iqp.colidSort), _iqp.fSortAscending);
		
		_InitializeFileListColumns();
		
		_RefreshFileList();
	}

	RegKey _GetCurrentRegKey(bool write)
	{
		GlobalOptions opt = Package.GetGlobalOptions();
		opt.getRegistryRoot();
		wstring regPath = opt.regUserRoot ~ regPathToolsOptions;
		if(_iqp.searchFile)
			regPath ~= "\\SearchFileWindow"w;
		else
			regPath ~= "\\SearchSymbolWindow"w;
		return new RegKey(opt.hUserKey, regPath, write);
	}
	
	HRESULT _InitializeViewState()
	{
		HRESULT hr = S_OK;
	
		try
		{
			scope RegKey keyWinOpts = _GetCurrentRegKey(false);
			if(keyWinOpts.GetDWORD("ColumnInfoVersion"w, 0) == kColumnInfoVersion)
			{
				void[] data = keyWinOpts.GetBinary("ColumnInfo"w);
				if(data !is null)
					*_rgColumns = cast(COLUMNINFO[])data;
			}

			_iqp.colidSort  = cast(COLUMNID) keyWinOpts.GetDWORD("SortColumn"w, _iqp.colidSort);
			_iqp.colidGroup = cast(COLUMNID) keyWinOpts.GetDWORD("GroupColumn"w, _iqp.colidGroup);
			_iqp.fSortAscending   = keyWinOpts.GetDWORD("SortAscending"w, _iqp.fSortAscending) != 0;
			_iqp.wholeWord        = keyWinOpts.GetDWORD("WholeWord"w, _iqp.wholeWord) != 0;
			_iqp.caseSensitive    = keyWinOpts.GetDWORD("CaseSensitive"w, _iqp.caseSensitive) != 0;
			_iqp.useRegExp        = keyWinOpts.GetDWORD("UseRegExp"w, _iqp.useRegExp) != 0;
			_fCombineColumns      = keyWinOpts.GetDWORD("CombineColumns"w, _fCombineColumns) != 0;
			_fAlternateRowColor   = keyWinOpts.GetDWORD("AlternateRowColor"w, _fAlternateRowColor) != 0;
			_closeOnReturn        = keyWinOpts.GetDWORD("closeOnReturn"w, _closeOnReturn) != 0;
		}
		catch(Exception e)
		{
			// ok to fail, defaults still work
		}
    
		return hr;
	}

	HRESULT _WriteViewStateToRegistry()
	{
		_WriteColumnInfoToRegistry();

		HRESULT hr = S_OK;
		try
		{
			scope RegKey keyWinOpts = _GetCurrentRegKey(true);
			keyWinOpts.Set("SortColumn"w, _iqp.colidSort);
			keyWinOpts.Set("GroupColumn"w, _iqp.colidGroup);
			keyWinOpts.Set("SortAscending"w, _iqp.fSortAscending);
			keyWinOpts.Set("WholeWord"w, _iqp.wholeWord);
			keyWinOpts.Set("CaseSensitive"w, _iqp.caseSensitive);
			keyWinOpts.Set("UseRegExp"w, _iqp.useRegExp);
			keyWinOpts.Set("CombineColumns"w, _fCombineColumns);
			keyWinOpts.Set("AlternateRowColor"w, _fAlternateRowColor);
			keyWinOpts.Set("closeOnReturn"w, _closeOnReturn);
		}
		catch(Exception e)
		{
			hr = E_FAIL;
		}
		return hr;
	}

	HRESULT _WriteColumnInfoToRegistry()
	{
		HRESULT hr = S_OK;

		for(int i = 0; i < _rgColumns.length; i++)
			(*_rgColumns)[i].cx = _wndFileList.SendMessage(LVM_GETCOLUMNWIDTH, _ListViewIndexFromColumnID((*_rgColumns)[i].colid));

		try
		{
			scope RegKey keyWinOpts = _GetCurrentRegKey(true);
			keyWinOpts.Set("ColumnInfoVersion"w, kColumnInfoVersion);
			keyWinOpts.Set("ColumnInfo"w, *_rgColumns);
		}
		catch(Exception e)
		{
			hr = E_FAIL;
		}
		return hr;
	}

	HRESULT _WriteViewOptionToRegistry(wstring name, DWORD dw)
	{
		HRESULT hr = S_OK;

		try
		{
			scope RegKey keyWinOpts = _GetCurrentRegKey(true);
			keyWinOpts.Set(toUTF16(name), dw);
		}
		catch(Exception e)
		{
			hr = E_FAIL;
		}
		
		return hr;
	}

	HRESULT _WriteSortInfoToRegistry()
	{
		HRESULT hr = S_OK;

		try
		{
			scope RegKey keyWinOpts = _GetCurrentRegKey(true);
			keyWinOpts.Set("SortColumn"w, _iqp.colidSort);
			keyWinOpts.Set("SortAscending"w, _iqp.fSortAscending);
		}
		catch(Exception e)
		{
			hr = E_FAIL;
		}

		return hr;
	}

	HRESULT _SetSortColumn(COLUMNID colid, int iIndex)
	{
		HRESULT hr = S_OK;
		bool fSortAscending = true;
		if (colid == _iqp.colidSort)
		{
			fSortAscending = !_iqp.fSortAscending;
		}
		else
		{
			int iIndexCur = _ListViewIndexFromColumnID(_iqp.colidSort);
			if (iIndexCur != -1) // Current sort column may have been removed from the list view
			{
				hr = _RemoveSortIcon(iIndexCur);
			}
		}

		if (SUCCEEDED(hr))
		{
			hr = _AddSortIcon(iIndex, fSortAscending);
			if (SUCCEEDED(hr))
			{
				_iqp.colidSort = colid;
				_iqp.fSortAscending = fSortAscending;

				_WriteSortInfoToRegistry();

				hr = _RefreshFileList();
			}
		}
		return hr;
	}

	LRESULT _OnFileListColumnClick(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
	{
		NMLISTVIEW *pnmlv = cast(NMLISTVIEW *)pnmh;
		_SetSortColumn(_ColumnIDFromListViewIndex(pnmlv.iSubItem), pnmlv.iSubItem);
		fHandled = TRUE;
		return 0;
	}

	LRESULT _OnFileListDeleteItem(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
	{
		NMLISTVIEW *pnmlv = cast(NMLISTVIEW *)pnmh;
		SolutionItem psi = cast(SolutionItem)cast(void*)pnmlv.lParam;
		// psi.Release();
		fHandled = TRUE;
		return 0;
	}

	HRESULT _OpenSolutionItem(int iIndex)
	{
		LVITEM lvi;
		lvi.mask = LVIF_PARAM;
		lvi.iItem = iIndex;
		HRESULT hr = _wndFileList.SendItemMessage(LVM_GETITEM, lvi) ? S_OK : E_FAIL;
		if (SUCCEEDED(hr))
		{
			SolutionItem psiWeak = cast(SolutionItem)cast(void*)lvi.lParam;
			string fname = psiWeak.GetFullPath();
version(none)
{
			string scop = !_iqp.searchFile ? psiWeak.GetScope() : null;
			hr = _OpenSolutionItem(fname, psiWeak.GetLine(), scop);
}
else
{
			hr = _OpenSolutionItem(fname, psiWeak.GetLine(), "");
			
			if(hr != S_OK && !_iqp.searchFile && !isAbsolute(fname))
			{
				// guess import path from filename (e.g. "src\core\mem.d") and 
				//  scope (e.g. "core.mem.gc.Proxy") to try opening
				// the file ("core\mem.d")
				string inScope = toLower(psiWeak.GetScope());
				string path = normalizeDir(dirName(toLower(psiWeak.GetPath())));
				inScope = replace(inScope, ".", "\\");
				
				int i;
				for(i = 1; i < path.length; i++)
					if(startsWith(inScope, path[i .. $]))
						break;
				if(i < path.length)
				{
					fname = fname[i .. $];
					hr = _OpenSolutionItem(fname, psiWeak.GetLine(), "");
				}
			}
}
		}
		return hr;
	}

	LRESULT _OnFileListDblClick(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
	{
		NMITEMACTIVATE *pnmitem = cast(NMITEMACTIVATE*) pnmh;
		if (FAILED(_OpenSolutionItem(pnmitem.iItem)))
		{
			MessageBeep(MB_ICONHAND);
		}
		fHandled = TRUE;
		return 0;
	}

	void _SetAlternateRowColor()
	{
		COLORREF cr = GetSysColor(COLOR_HIGHLIGHT);
		BYTE r = GetRValue(cr);
		BYTE g = GetGValue(cr);
		BYTE b = GetBValue(cr);
		BYTE rNew = 236;
		BYTE gNew = 236;
		BYTE bNew = 236;

		if (r > g && r > b)
		{
			rNew = 244;
		}
		else if (g > r && g > b)
		{
			gNew = 244;
		}
		else
		{
			bNew = 244;
		}
		_crAlternate = RGB(rNew, gNew, bNew);
	}

	LRESULT _OnFileListCustomDraw(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
	{
		LRESULT lRet = CDRF_DODEFAULT;
		NMLVCUSTOMDRAW *pnmlvcd = cast(NMLVCUSTOMDRAW *)pnmh;
		switch (pnmlvcd.nmcd.dwDrawStage)
		{
		case CDDS_PREPAINT:
			_SetAlternateRowColor();
			lRet = CDRF_NOTIFYITEMDRAW;
			break;

		case CDDS_ITEMPREPAINT:
		{
			// Override the colors so that regardless of the focus state, the control appears focused.
			// We can't rely on the pnmlvcd.nmcd.uItemState for this because there is a known bug
			// with listviews that have the LVS_EX_SHOWSELALWAYS style where this bit is set for
			// every item
			LVITEM lvi;
			lvi.mask = LVIF_STATE;
			lvi.iItem = cast(int)pnmlvcd.nmcd.dwItemSpec;
			lvi.stateMask = LVIS_SELECTED;
			if (_wndFileList.SendItemMessage(LVM_GETITEM, lvi) && (lvi.state & LVIS_SELECTED))
			{
				pnmlvcd.clrText = GetSysColor(COLOR_HIGHLIGHTTEXT);
				pnmlvcd.clrTextBk = GetSysColor(COLOR_HIGHLIGHT);
				pnmlvcd.nmcd.uItemState &= ~CDIS_SELECTED;
				lRet = CDRF_NEWFONT;
			}
			else
			{
				if (_fAlternateRowColor && !(pnmlvcd.nmcd.dwItemSpec % 2))
				{
					// TODO: Eventually, it might be nice to build a color based on COLOR_HIGHLIGHT.
					pnmlvcd.clrTextBk = _crAlternate;
					pnmlvcd.nmcd.uItemState &= ~CDIS_SELECTED;
					lRet = CDRF_NEWFONT;
				}
			}
			break;
		}

		default:
			break;
		}
		fHandled = TRUE;
		return lRet;
	}

	LRESULT _OnFileListHdrItemChanged(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
	{
		NMHEADER *pnmhdr = cast(NMHEADER *)pnmh;
		if (pnmhdr.pitem.mask & HDI_WIDTH) 
		{
			COLUMNID colid = _ColumnIDFromListViewIndex(pnmhdr.iItem);
			if (colid == COLUMNID.NAME && _fCombineColumns)
			{
				// Get the size delta and distrubute it between the name and path columns
				COLUMNID colPath = _iqp.searchFile ? COLUMNID.PATH : COLUMNID.TYPE;
				COLUMNINFO *pciName = _ColumnInfoFromColumnID(COLUMNID.NAME);
				COLUMNINFO *pciPath = _ColumnInfoFromColumnID(colPath);

				int cxTotal = pciName.cx + pciPath.cx;
				int cxDelta = pnmhdr.pitem.cxy - cxTotal;
				int iPercentChange = MulDiv(100, cxDelta, cxTotal);
				int cxNameDelta = MulDiv(abs(cxDelta), iPercentChange, 100);
				int cxPathDelta = cxDelta - cxNameDelta;
				pciName.cx += cxNameDelta;
				pciPath.cx += cxPathDelta;
			}
			else
			{
				COLUMNINFO *pci = _ColumnInfoFromColumnID(colid);
				pci.cx = pnmhdr.pitem.cxy;
			}
			_WriteColumnInfoToRegistry();
		}

		fHandled = TRUE;
		return 0;
	}

	LRESULT _OnToolbarGetInfoTip(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
	{
		NMTBGETINFOTIP *pnmtbgit = cast(NMTBGETINFOTIP *)pnmh;
		string tip;
		switch(pnmtbgit.iItem)
		{
		case IDR_COMBINECOLUMNS:
			if(_iqp.searchFile)
				tip = "Toggle single/double column display of name and path";
			else
				tip = "Toggle single/double column display of name and type";
			break;
		case IDR_ALTERNATEROWCOLOR:
			tip = "Toggle alternating row background color";
			break;
		case IDR_GROUPBYKIND:
			tip = "Grouped display by kind";
			break;
		case IDR_CLOSEONRETURN:
			tip = "Close search window when item selected or focus lost";
			break;
		case IDR_WHOLEWORD:
			tip = "Match whole word only";
			break;
		case IDR_CASESENSITIVE:
			tip = "Match case insensitive";
			break;
		case IDR_REGEXP:
			tip = "Match by regular expression";
			break;
		case IDR_SEARCHFILE:
			tip = "Search for file in solution";
			break;
		case IDR_SEARCHSYMBOL:
			tip = "Search for symbol in solution";
			break;
		default:
			break;
		}
		wstring wtip = toUTF16(tip) ~ '\000';
		int cnt = min(wtip.length, pnmtbgit.cchTextMax);
		pnmtbgit.pszText[0..cnt] = wtip.ptr[0..cnt];
		fHandled = TRUE;
		return 0;
	}
}

////////////////////////////////////////////////////////////////////////
class SolutionItem //: IUnknown
{
	static const GUID iid = uuid("6EB1B172-33C2-418a-8B67-F428FD456B46");

	this(string path, string relpath)
	{
		int idx = lastIndexOf(path, '\\');
		if(idx < 0)
			def.name = path;
		else
			def.name = path[idx + 1 .. $];

		def.filename = path;
		def.line = -1;
		def.kind = "file";
		if(exists(path))
			_modifiedDate = timeLastModified(path);
		def.inScope = relpath;
	}
	this(Definition d)
	{
		def = d;
		if(def.kind == "module")
			def.line = -1;
	}
	
	int GetIconIndex() const { return 0; }
	
	string GetName() const
	{
		return def.name;
	}
	string GetFullPath() const 
	{
		return def.filename;
	}
	string GetPath() const
	{
		if(def.kind != "file")
			return def.filename;
		
		if(def.inScope.length)
			return def.inScope;
		int idx = lastIndexOf(def.filename, '\\');
		if(idx < 0)
			return "";
		return def.filename[0 .. idx];
	}
	int GetLine() const { return def.line; }
	string GetScope() const { return def.inScope; }
	string GetType() const { return def.type; }
	string GetKind() const { return def.kind; }
	long GetSize() const { return 0; }
	const(SysTime) GetModified() const { return _modifiedDate; }

	//HRESULT GetItem(in IID* riid, void **ppv);
	
	Definition def;
	SysTime _modifiedDate;
}

class SolutionItemGroup //: IUnknown
{
	static const GUID iid = uuid("FCF2F784-0C4E-4c2c-A0CE-E44E3B20D8E2");

	this(string name)
	{
		mName = name;
		mArray = new ItemArray;
	}
	
	void add(SolutionItem item)
	{
		mArray.add(item);
	}
	
	string GetName() const { return mName; }
	const(ItemArray) GetItems() const { return mArray; }
	
	ItemArray mArray;
	string mName;
}

class SolutionItemIndex //: IUnknown
{
	static const GUID iid = uuid("DA2FC9FF-57D4-42bd-9E26-518A42668DEE");

	HRESULT Search(string pszSearch, INDEXQUERYPARAMS *piqp, ItemArray *ppv)
	{
		string[] args = tokenizeArgs(pszSearch);
		auto arr = new ItemArray;
		
		SearchData sd;
		sd.wholeWord = piqp.wholeWord;
		sd.caseSensitive = piqp.caseSensitive;
		sd.useRegExp = piqp.useRegExp;
		if(!sd.init(args))
			return E_FAIL;

		if (piqp.searchFile)
		{
			string solutionpath = GetSolutionFilename();
			string solutiondir = normalizeDir(dirName(solutionpath));
			
			searchSolutionItem(delegate bool(string s)
				{
					string f = s;
					if(s.startsWith(solutiondir)) // case-insensitive?
						f = s[solutiondir.length .. $];
					//makeRelative(s, solutiondir);
					
					if(!sd.matchNames(f, "", "", ""))
						return false;
					if(f == s)
						f = "";
					
					if(piqp.colidGroup == COLUMNID.KIND)
					{
						string ext = extension(s);
						if (!arr.getItemByGroupAndPath(ext, s))
							arr.addByGroup(ext, new SolutionItem(s, f));
					}
					else
					{
						if (!arr.getItemByPath(s))
							arr.add(new SolutionItem(s, f));
					}
					return false;
				});
		}
		else
		{
			Definition[] defs = Package.GetLibInfos().findDefinition(sd);
			foreach(ref def; defs)
			{
				if(piqp.colidGroup == COLUMNID.KIND)
					arr.addByGroup(def.kind, new SolutionItem(def));
				else
					arr.add(new SolutionItem(def));
			}
		}
		arr.sort(piqp.colidSort, piqp.fSortAscending);
		*ppv = arr;
		return S_OK;
	}

}

class ItemArray //: IUnknown
{
	static const GUID iid = uuid("5A97C4DF-DE3A-4bb6-B621-2F9550BFE7C0");
	
	SolutionItem[string] mItemsByPath;
	SolutionItem[] mItems;
	SolutionItemGroup[] mGroups;
	
	this()
	{
	}

	const(SolutionItem) getItemByPath(string path) const
	{
		if (auto it = path in mItemsByPath)
			return *it;
		return null;
	}

	void add(SolutionItem item)
	{
		mItems ~= item;
		mItemsByPath[item.GetFullPath()] = item;
	}
	
	const(SolutionItem) getItemByGroupAndPath(string grp, string path)
	{
		for(int i = 0; i < mGroups.length; i++)
			if(mGroups[i].GetName() == grp)
				return mGroups[i].GetItems().getItemByPath(path);
		return null;
	}

	void addByGroup(string grp, SolutionItem item)
	{
		for(int i = 0; i < mGroups.length; i++)
			if(mGroups[i].GetName() == grp)
				return mGroups[i].add(item);

		auto group = new SolutionItemGroup(grp);
		group.add(item);
		mGroups ~= group;
	}
	
	int GetCount() const { return max(mItems.length, mGroups.length); }
	
	SolutionItemGroup GetGroup(uint idx) const
	{
		if(idx >= mGroups.length)
			return null;
		return cast(SolutionItemGroup)mGroups[idx];
	}
	
	SolutionItem GetItem(uint idx) const 
	{
		if(idx >= mItems.length)
			return null;
		return cast(SolutionItem)mItems[idx]; 
	}
	//HRESULT GetItem(I)(uint idx, I*ptr) const { return E_FAIL; }
	
	void sort(COLUMNID id, bool ascending)
	{
		switch(id)
		{
		case COLUMNID.NAME:
			if(ascending)
				std.algorithm.sort!("a.GetName() < b.GetName()")(mItems);
			else
				std.algorithm.sort!("a.GetName() > b.GetName()")(mItems);
			break;

		case COLUMNID.LINE:
			if(ascending)
				std.algorithm.sort!("a.GetLine() < b.GetLine()")(mItems);
			else
				std.algorithm.sort!("a.GetLine() > b.GetLine()")(mItems);
			break;

		case COLUMNID.TYPE:
			if(ascending)
				std.algorithm.sort!("a.GetType() < b.GetType()")(mItems);
			else
				std.algorithm.sort!("a.GetType() > b.GetType()")(mItems);
			break;
			
		case COLUMNID.PATH:
			if(ascending)
				std.algorithm.sort!("a.GetPath() < b.GetPath()")(mItems);
			else
				std.algorithm.sort!("a.GetPath() > b.GetPath()")(mItems);
			break;
			
		case COLUMNID.SCOPE:
			if(ascending)
				std.algorithm.sort!("a.GetScope() < b.GetScope()")(mItems);
			else
				std.algorithm.sort!("a.GetScope() > b.GetScope()")(mItems);
			break;
			
		case COLUMNID.MODIFIEDDATE:
			if(ascending)
				std.algorithm.sort!("a.GetModified() < b.GetModified()")(mItems);
			else
				std.algorithm.sort!("a.GetModified() > b.GetModified()")(mItems);
			break;
			
		default:
			break;
		}
		
		foreach(grp; mGroups)
			grp.mArray.sort(id, ascending);
	}
	
}

////////////////////////////////////////////////////////////////////////
bool searchHierarchy(IVsHierarchy pHierarchy, VSITEMID item, bool delegate (string) dg)
{
	VARIANT var;
	if((pHierarchy.GetProperty(item, VSHPROPID_Container, &var) == S_OK &&
		((var.vt == VT_BOOL && var.boolVal) || (var.vt == VT_I4 && var.lVal))) || 
	   (pHierarchy.GetProperty(item, VSHPROPID_Expandable, &var) == S_OK &&
		((var.vt == VT_BOOL && var.boolVal) || (var.vt == VT_I4 && var.lVal))))
	{
		if(pHierarchy.GetProperty(item, VSHPROPID_FirstChild, &var) == S_OK &&
		   (var.vt == VT_INT_PTR || var.vt == VT_I4 || var.vt == VT_INT))
		{
			VSITEMID chid = var.lVal;
			while(chid != VSITEMID_NIL)
			{
				if(searchHierarchy(pHierarchy, chid, dg))
					return true;
				
				if(pHierarchy.GetProperty(chid, VSHPROPID_NextSibling, &var) != S_OK ||
				   (var.vt != VT_INT_PTR && var.vt != VT_I4 && var.vt != VT_INT))
					break;
				chid = var.lVal;
			}
		}
		else
		{
			IVsHierarchy nestedHierarchy;
			VSITEMID itemidNested;
			if(pHierarchy.GetNestedHierarchy(item, &IVsHierarchy.iid, cast(void **)&nestedHierarchy, &itemidNested) == S_OK)
			{
				if(searchHierarchy(nestedHierarchy, itemidNested, dg))
					return true;
			}
		}
	}
	else if(IVsProject prj = qi_cast!IVsProject(pHierarchy))
	{
		scope(exit) release(prj);
		BSTR bstrMkDocument;
		if(prj.GetMkDocument(item, &bstrMkDocument) == S_OK)
		{
			string docname = detachBSTR(bstrMkDocument);
			if(dg(docname))
				return true;
		}
	}
	return false;
}

bool searchSolutionItem(bool delegate (string) dg)
{
	if(auto srpSolution = queryService!(IVsSolution))
	{
		scope(exit) release(srpSolution);
		IEnumHierarchies pEnum;
		if(srpSolution.GetProjectEnum(EPF_LOADEDINSOLUTION, &GUID_NULL, &pEnum) == S_OK)
		{
			scope(exit) release(pEnum);
			IVsHierarchy pHierarchy;
			while(pEnum.Next(1, &pHierarchy, null) == S_OK)
			{
				scope(exit) release(pHierarchy);
				VSITEMID itemid = VSITEMID_ROOT;
				if(searchHierarchy(pHierarchy, VSITEMID_ROOT, dg))
					return true;
			}
		}
	}
	return false;
}

//------------------------------------------------------------------------------
// CSolutionItemTypeCache
//------------------------------------------------------------------------------

struct TYPECACHEINFO
{
	string szFriendlyName;
	int iIconIndex;
}

class CSolutionItemTypeCache
{
	this()
	{
		_himl = ImageList_Create(GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), ILC_COLOR32 | ILC_MASK, 16, 8);
	}
	
	~this()
	{
		if (_himl)
			ImageList_Destroy(_himl);
	}

	const(TYPECACHEINFO) *GetTypeInfo(string pszCanonicalType)
	{
		if(TYPECACHEINFO* ti = pszCanonicalType in _mapTypes)
			return ti;

		SHFILEINFO shfi;
		if(SHGetFileInfoW(_toUTF16z(pszCanonicalType), FILE_ATTRIBUTE_NORMAL, &shfi, shfi.sizeof,
		                  SHGFI_ICON | SHGFI_SMALLICON | SHGFI_SHELLICONSIZE | SHGFI_TYPENAME | SHGFI_USEFILEATTRIBUTES))
		{
			TYPECACHEINFO tci;
			tci.iIconIndex = ImageList_ReplaceIcon(_himl, -1, shfi.hIcon);
			if(tci.iIconIndex != -1)
			{
				tci.szFriendlyName = to_string(shfi.szTypeName.ptr);
				_mapTypes[pszCanonicalType] = tci;
			}
			DestroyIcon(shfi.hIcon);
		}
		return pszCanonicalType in _mapTypes;
	}
	
	HIMAGELIST GetIconImageList() { return _himl; }

private:
	TYPECACHEINFO[string] _mapTypes;
	HIMAGELIST _himl;
};

