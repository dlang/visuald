// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.profiler;

import visuald.windows;
import visuald.winctrl;
import visuald.comutil;
import visuald.dimagelist;
import visuald.register;
import visuald.hierutil;
import visuald.logutil;
import visuald.stringutil;
import visuald.pkgutil;
import visuald.dpackage;
import visuald.intellisense;
import visuald.config;
import visuald.wmmsg;

import sdk.win32.commctrl;
import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;

import stdext.string;

import std.conv;
import std.utf;
import std.stdio;
import std.string;
import std.algorithm;
import std.file;
import std.path;

import core.demangle;

private IVsWindowFrame sWindowFrame;
private	ProfilePane sProfilePane;

bool showProfilerWindow()
{
	if(!sWindowFrame)
	{
		auto pIVsUIShell = ComPtr!(IVsUIShell)(queryService!(IVsUIShell), false);
		if(!pIVsUIShell)
			return false;

		sProfilePane = new ProfilePane();
		const(wchar)* caption = "Visual D Profiler"w.ptr;
		HRESULT hr;
		hr = pIVsUIShell.CreateToolWindow(CTW_fInitNew, 0, sProfilePane, 
										  &GUID_NULL, &g_profileWinCLSID, &GUID_NULL, 
										  null, caption, null, &sWindowFrame);
		if(!SUCCEEDED(hr))
		{
			sProfilePane = null;
			return false;
		}
	}
	if(FAILED(sWindowFrame.Show()))
		return false;
	BOOL fHandled;
	sProfilePane._OnSetFocus(0, 0, 0, fHandled);
	return fHandled != 0;
}

const int  kColumnInfoVersion = 1;
const bool kToolBarAtTop = true;
const int  kToolBarHeight = 24;
const int  kPaneMargin = 0;
const int  kBackMargin = 2;

const HDMIL_PRIVATE = 0xf00d;

struct static_COLUMNINFO
{
	string displayName;
	int fmt;
	int cx;
}

struct COLUMNINFO
{
	COLUMNID colid;
	BOOL fVisible;
	int cx;
};

enum COLUMNID
{
	NONE = -1,
	NAME,
	CALLS,
	TREETIME,
	FUNCTIME,
	CALLTIME,
	MAX
}

static_COLUMNINFO[] s_rgColumns =
[
	//{ "none", LVCFMT_LEFT, 80 },
	{ "Function",  LVCFMT_LEFT, 80 },
	{ "Calls",     LVCFMT_LEFT, 80 },
	{ "Tree Time", LVCFMT_LEFT, 80 },
	{ "Func Time", LVCFMT_LEFT, 80 },
	{ "Call Time", LVCFMT_LEFT, 80 },
];

const COLUMNINFO[] default_Columns =
[
	{ COLUMNID.NAME, true, 300 },
	{ COLUMNID.CALLS, true, 100 },
	{ COLUMNID.TREETIME, true, 100 },
	{ COLUMNID.FUNCTIME, true, 100 },
	{ COLUMNID.CALLTIME, true, 100 },
];

static_COLUMNINFO[] s_rgFanInColumns =
[
	//{ "none", LVCFMT_LEFT, 80 },
	{ "Caller",  LVCFMT_LEFT, 80 },
	{ "Calls",   LVCFMT_LEFT, 80 },
];

static_COLUMNINFO[] s_rgFanOutColumns =
[
	//{ "none", LVCFMT_LEFT, 80 },
	{ "Callee",  LVCFMT_LEFT, 80 },
	{ "Calls",   LVCFMT_LEFT, 80 },
];

const COLUMNINFO[] default_FanColumns =
[
	{ COLUMNID.NAME, true, 300 },
	{ COLUMNID.CALLS, true, 100 },
];

struct INDEXQUERYPARAMS
{
	COLUMNID colidSort;
	bool fSortAscending;
	COLUMNID colidGroup;
}

class ProfileWindowBack : Window
{
	this(Window parent, ProfilePane pane)
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
	
	ProfilePane mPane;
}

class ProfilePane : DisposingComObject, IVsWindowPane
{
	IServiceProvider mSite;

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
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
		_wndBack = new ProfileWindowBack(_wndParent, this);

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
			_wndParent.Dispose();
			_wndParent = null;
			_wndBack = null;
			_wndFileWheel = null;
			_wndFuncList = null;
			_wndFuncListHdr = null;
			_wndFanInList = null;
			_wndFanOutList = null;
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
		return returnError(E_NOTIMPL);
	}
	HRESULT SaveViewState(/+[in]+/ IStream pstream)
	{
		mixin(LogCallMix2);
		return returnError(E_NOTIMPL);
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

private:
	Window _wndParent;
	ProfileWindowBack _wndBack;
	HFONT mDlgFont;

	Text _wndFileWheel;
	ListView _wndFuncList;
	ListView _wndFanInList;
	ListView _wndFanOutList;
	Window _wndFuncListHdr;
	ToolBar _wndToolbar;
	HIMAGELIST _himlToolbar;
	ItemArray _lastResultsArray; // remember to keep reference to ProfileItems referenced in list items
	ProfileItemIndex _spsii;
	int _lastSelectedItem;
	
	BOOL _fShowFanInOut;
	BOOL _fFullDecoration;
	BOOL _fAlternateRowColor;
	BOOL _closeOnReturn;
	COLUMNINFO[] _rgColumns;

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
				case IDR_ALTERNATEROWCOLOR:
				case IDR_GROUPBYKIND:
				case IDR_CLOSEONRETURN:
				case IDR_FANINOUT:
				case IDR_FULLDECO:
				case IDR_REMOVETRACE:
				case IDR_SETTRACE:
				case IDR_REFRESH:
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
				case LVN_ITEMCHANGED:
					return _OnFileListItemChanged(wParam, nmhdr, fHandled);
				case NM_DBLCLK:
					return _OnFileListDblClick(wParam, nmhdr, fHandled);
				case NM_CUSTOMDRAW:
					return _OnFileListCustomDraw(wParam, nmhdr, fHandled);
				default:
					break;
				}
			}
			if(nmhdr.idFrom == IDC_FANINLIST && nmhdr.code == NM_DBLCLK)
				return _OnFanInOutListDblClick(true, nmhdr, fHandled);
			if(nmhdr.idFrom == IDC_FANOUTLIST && nmhdr.code == NM_DBLCLK)
				return _OnFanInOutListDblClick(false, nmhdr, fHandled);
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

	this()
	{
		_fAlternateRowColor = true;
		_closeOnReturn = true;

		_spsii = new ProfileItemIndex();
		_rgColumns = default_Columns.dup;
		_iqp.colidSort = COLUMNID.NAME;
		_iqp.fSortAscending = true;
		_iqp.colidGroup = COLUMNID.NONE;
	}

	void _MoveSelection(BOOL fDown)
	{
		// Get the current selection
		int iSel = _wndFuncList.SendMessage(LVM_GETNEXTITEM, cast(WPARAM)-1, LVNI_SELECTED);
		int iCnt = _wndFuncList.SendMessage(LVM_GETITEMCOUNT);
		if(iSel == 0 && !fDown)
			return;
		if(iSel == iCnt - 1 && fDown)
			return;
		
		_UpdateSelection(iSel, fDown ? iSel+1 : iSel-1);
	}
	
	void _UpdateSelection(int from, int to)
	{
		LVITEM lvi;
		lvi.iItem = from;
		lvi.mask = LVIF_STATE;
		lvi.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
		lvi.state = 0;
		_wndFuncList.SendItemMessage(LVM_SETITEM, lvi);

		lvi.iItem = to;
		lvi.mask = LVIF_STATE;
		lvi.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
		lvi.state = LVIS_SELECTED | LVIS_FOCUSED;
		_wndFuncList.SendItemMessage(LVM_SETITEM, lvi);
		
		_wndFuncList.SendMessage(LVM_ENSUREVISIBLE, lvi.iItem, FALSE);
	}

	HRESULT _PrepareFileListForResults(in ItemArray puaResults)
	{
		_wndFuncList.SendMessage(LVM_DELETEALLITEMS);
		_wndFuncList.SendMessage(LVM_REMOVEALLGROUPS);

		HIMAGELIST himl = ImageList_LoadImageA(getInstance(), kImageBmp.ptr, 16, 10, CLR_DEFAULT,
											IMAGE_BITMAP, LR_LOADTRANSPARENT);
		if(himl)
			_wndFuncList.SendMessage(LVM_SETIMAGELIST, LVSIL_SMALL, cast(LPARAM)himl);

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
			hr = _wndFuncList.SendMessage(LVM_ENABLEGROUPVIEW, fEnableGroups) == -1 ? E_FAIL : S_OK;
		}

		return hr;
	}

	HRESULT _AddItemsToFileList(int iGroupId, in ItemArray pua)
	{
		LVITEM lvi;
		lvi.pszText = LPSTR_TEXTCALLBACK;
		lvi.iItem = cast(int)_wndFuncList.SendMessage(LVM_GETITEMCOUNT);
		DWORD cItems = pua.GetCount();
		HRESULT hr = S_OK;
		for (DWORD i = 0; i < cItems && SUCCEEDED(hr); i++)
		{
			if(ProfileItem spsi = pua.GetItem(i))
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
					if (_wndFuncList.SendItemMessage(LVM_INSERTITEM, lvi) != -1 && iCol == COLUMNID.NAME)
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

	HRESULT _AddGroupToFileList(int iGroupId, in ProfileItemGroup psig)
	{
		LVGROUP lvg;
		lvg.cbSize = lvg.sizeof;
		lvg.mask = LVGF_ALIGN | LVGF_HEADER | LVGF_GROUPID | LVGF_STATE;
		lvg.uAlign = LVGA_HEADER_LEFT;
		lvg.iGroupId = iGroupId;
		lvg.pszHeader = _toUTF16z(psig.GetName());
		lvg.state = LVGS_NORMAL;
		HRESULT hr = _wndFuncList.SendMessage(LVM_INSERTGROUP, cast(WPARAM)-1, cast(LPARAM)&lvg) != -1 ? S_OK : E_FAIL;
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
		
		_wndFuncList.SetRedraw(FALSE);

		HRESULT hr = S_OK;
		string strWordWheel = _wndFileWheel.GetWindowText();

		ItemArray spResultsArray;
		hr = _spsii.Update(strWordWheel, &_iqp, &spResultsArray);
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
						if(ProfileItemGroup spsig = spResultsArray.GetGroup(iGroup))
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
			_wndFuncList.SendItemMessage(LVM_SETITEM, lviSelect);
		}

		_wndFuncList.SetRedraw(TRUE);
		_wndFuncList.InvalidateRect(null, FALSE);
		return hr;
	}

	string _demangle(string txt, bool fullDeco)
	{
		static if(__traits(compiles, (){uint p; decodeDmdString("", p);}))
			uint p = 0;
		else
			int p = 0; // until dmd 2.056
		version(all) // debug // allow std 2.052 in debug builds
			enum hasTypeArg = __traits(compiles, { demangle("",true); });
		else // ensure patched runtime in release
			enum hasTypeArg = true;

		txt = decodeDmdString(txt, p);
		if(txt.length > 2 && txt[0] == '_' && txt[1] == 'D')
		{
			static if(hasTypeArg)
				txt = to!string(demangle(txt, fullDeco));
			else
			{
				pragma(msg, text(__FILE__, "(", __LINE__, "): profiler._demangle uses compatibility mode, this won't allow disabling type info"));
				txt = to!string(demangle(txt));
			}
		}
		return txt;
	}

	void _InsertFanInOut(ListView lv, Fan fan)
	{
		LVITEM lvi;
		lvi.pszText = _toUTF16z(_demangle(fan.func, _fFullDecoration != 0));
		lvi.iItem = cast(int)lv.SendMessage(LVM_GETITEMCOUNT);
		lvi.mask = LVIF_TEXT;
		lv.SendItemMessage(LVM_INSERTITEM, lvi);

		lvi.pszText = _toUTF16z(to!string(fan.calls));
		lvi.iSubItem = 1;
		lvi.mask = LVIF_TEXT;
		lv.SendItemMessage(LVM_SETITEM, lvi);
	}
	
	void RefreshFanInOutList(ProfileItem psi)
	{
		if(!psi || !_fShowFanInOut)
			return;
		
		_wndFanInList.SendMessage(LVM_DELETEALLITEMS);
		_wndFanOutList.SendMessage(LVM_DELETEALLITEMS);

		foreach(fan; psi.mFanIn)
			_InsertFanInOut(_wndFanInList, fan);
		
		foreach(fan; psi.mFanOut)
			_InsertFanInOut(_wndFanOutList, fan);
	}
	
	// Special icon dimensions for the sort direction indicator
	const int c_cxSortIcon = 7;
	const int c_cySortIcon = 6;

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
		HRESULT hr = _wndFuncListHdr.SendMessage(HDM_GETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
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
			hr = _wndFuncListHdr.SendMessage(HDM_SETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
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
		HRESULT hr = _wndFuncListHdr.SendMessage(HDM_GETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
		if (SUCCEEDED(hr))
		{
			// Remove the image mask and alignment
			hdi.fmt &= ~HDF_IMAGE;
			if ((hdi.fmt & HDF_JUSTIFYMASK) == HDF_LEFT)
			{
				hdi.fmt &= ~HDF_BITMAP_ON_RIGHT;
			}
			hr = _wndFuncListHdr.SendMessage(HDM_SETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
		}
		return hr;
	}

	HRESULT _InsertListViewColumn(ListView lv, const(static_COLUMNINFO)[] static_rgColumns, int iIndex, COLUMNID colid, 
								  int cx, bool set = false)
	{
		LVCOLUMN lvc;
		lvc.mask = LVCF_FMT | LVCF_TEXT | LVCF_WIDTH;
		lvc.fmt = static_rgColumns[colid].fmt;
		lvc.cx = cx;

		HRESULT hr = S_OK;
		string strDisplayName = static_rgColumns[colid].displayName;
		lvc.pszText = _toUTF16z(strDisplayName);
		uint msg = set ? LVM_SETCOLUMNW : LVM_INSERTCOLUMNW;
		hr = lv.SendMessage(msg, iIndex, cast(LPARAM)&lvc) >= 0 ? S_OK : E_FAIL;
		
		if (SUCCEEDED(hr) && lv == _wndFuncList)
		{
			HDITEM hdi;
			hdi.mask = HDI_LPARAM;
			hdi.lParam = colid;
			hr = _wndFuncListHdr.SendMessage(HDM_SETITEM, iIndex, cast(LPARAM)&hdi) ? S_OK : E_FAIL;
		}
		return hr;
	}

	HRESULT _InsertListViewColumn(int iIndex, COLUMNID colid, int cx, bool set = false)
	{
		return _InsertListViewColumn(_wndFuncList, s_rgColumns, iIndex, colid, cx, set);
	}

	HRESULT _InitializeListColumns(ListView lv, const(COLUMNINFO)[] rgColumns, const(static_COLUMNINFO)[] static_rgColumns)
	{
		lv.SendMessage(LVM_DELETEALLITEMS);
		lv.SendMessage(LVM_REMOVEALLGROUPS);

		bool hasNameColumn = lv.SendMessage(LVM_GETCOLUMNWIDTH, 0) > 0;
		// cannot delete col 0, so keep name
		while(lv.SendMessage(LVM_DELETECOLUMN, 1)) {}
		
		HRESULT hr = S_OK;
		int cColumnsInserted = 0;
		for (UINT i = 0; i < rgColumns.length && SUCCEEDED(hr); i++)
		{
			const(COLUMNINFO)* ci = &(rgColumns[i]);
			if (ci.fVisible)
			{
				bool set = hasNameColumn ? cColumnsInserted == 0 : false;
				hr = _InsertListViewColumn(lv, static_rgColumns, cColumnsInserted++, ci.colid, ci.cx, set);
			}
		}
		return hr;
	}
	
	HRESULT _InitializeFuncListColumns()
	{
		HRESULT hr;
		hr = _InitializeListColumns(_wndFuncList, _rgColumns, s_rgColumns);
		hr |= _InitializeListColumns(_wndFanInList, default_FanColumns, s_rgFanInColumns);
		hr |= _InitializeListColumns(_wndFanOutList, default_FanColumns, s_rgFanOutColumns);
		return hr;
	}
	
	HRESULT _InitializeFuncList()
	{
		_wndFuncList.SendMessage(LVM_SETEXTENDEDLISTVIEWSTYLE, 
		                         LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP,
		                         LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);

		HIMAGELIST himl;
		HRESULT hr = _CreateSortImageList(himl);
		if (SUCCEEDED(hr))
		{
			_wndFuncListHdr.SendMessage(HDM_SETIMAGELIST, HDMIL_PRIVATE, cast(LPARAM)himl);

			_InitializeFuncListColumns();
			
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
	const int c_cxToolbarIcon = 16;
	const int c_cyToolbarIcon = 15;

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
				_wndToolbar.SendMessage(TB_SETIMAGELIST, 0, cast(LPARAM)_himlToolbar);

				TBBUTTON initButton(int id, ubyte style)
				{
					return TBBUTTON(id < 0 ? IDR_LAST - IDR_FIRST + 1 : id - IDR_FIRST, 
					                id, TBSTATE_ENABLED, style, [0,0], 0, 0);
				}
				static const TBBUTTON s_tbb[] = [
					initButton(IDR_ALTERNATEROWCOLOR, BTNS_CHECK),
					initButton(IDR_CLOSEONRETURN,     BTNS_CHECK),
					initButton(IDR_FULLDECO,          BTNS_CHECK),
					initButton(IDR_FANINOUT,          BTNS_CHECK),
					initButton(-1, BTNS_SEP),
					initButton(IDR_SETTRACE,          BTNS_BUTTON),
					initButton(IDR_REMOVETRACE,       BTNS_BUTTON),
					initButton(IDR_REFRESH,           BTNS_BUTTON),
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

		_wndToolbar.EnableCheckButton(IDR_ALTERNATEROWCOLOR, true, _fAlternateRowColor != 0);
		_wndToolbar.EnableCheckButton(IDR_CLOSEONRETURN,     true, _closeOnReturn != 0);

		//_wndToolbar.EnableCheckButton(IDR_GROUPBYKIND,       true, _iqp.colidGroup == COLUMNID.KIND);
		_wndToolbar.EnableCheckButton(IDR_FANINOUT,          true, _fShowFanInOut != 0);
		_wndToolbar.EnableCheckButton(IDR_FULLDECO,          true, _fFullDecoration != 0);
	
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
		if(ProfilePane pfsec = cast(ProfilePane)cast(void*)dwRefData)
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
			_wndFileWheel.setRect(kBackMargin, top + kBackMargin, 185, 16);
			_wndFuncList = new ListView(_wndBack, LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_ALIGNLEFT | LVS_SHAREIMAGELISTS | WS_BORDER | WS_TABSTOP,
			                            0, IDC_FILELIST);
			_wndFuncList.setRect(kBackMargin, top + kBackMargin + 20, 185, 78);
			HWND hdrHwnd = cast(HWND)_wndFuncList.SendMessage(LVM_GETHEADER);
			if(hdrHwnd)
			{
				_wndFuncListHdr = new Window(hdrHwnd);

				// HACK:  This header control is created by the listview.  When listview handles LVM_SETIMAGELIST with
				// LVSIL_SMALL it also forwards the message to the header control.  The subclass proc will intercept those
				// messages and prevent resetting the imagelist
				SetWindowSubclass(_wndFuncListHdr.hwnd, &s_HdrWndProc, ID_SUBCLASS_HDR, cast(DWORD_PTR)cast(void*)this);

				//_wndFuncListHdr.SetDlgCtrlID(IDC_FILELISTHDR);
			}
			_wndFanInList = new ListView(_wndBack, LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_ALIGNLEFT | LVS_SHAREIMAGELISTS | WS_BORDER | WS_TABSTOP,
			                             0, IDC_FANINLIST);
			_wndFanInList.setRect(kBackMargin, top + 20 + 78, 185, 40);
			_wndFanOutList = new ListView(_wndBack, LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS | LVS_ALIGNLEFT | LVS_SHAREIMAGELISTS | WS_BORDER | WS_TABSTOP,
			                              0, IDC_FANOUTLIST);
			_wndFanOutList.setRect(kBackMargin, top + 20 + 78 + 40, 185, 40);

			_InitializeFuncList();
			
			_wndFanInList.SendMessage(LVM_SETEXTENDEDLISTVIEWSTYLE, 
									  LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP,
									  LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
			_wndFanOutList.SendMessage(LVM_SETEXTENDEDLISTVIEWSTYLE, 
									   LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP,
									   LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);
			
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
		
		return ResizeControls(cx, cy);
	}
	
	LRESULT ResizeControls(int cx, int cy)
	{
		// Adjust child control sizes
		// - File Wheel stretches to fit horizontally but size is vertically fixed
		// - File List stretches to fit horizontally and vertically but the topleft coordinate is fixed
		// - Toolbar autosizes along the bottom

		_wndToolbar.setRect(kBackMargin, kBackMargin, cx - 2 * kBackMargin, kToolBarHeight);

		int hTool = (kToolBarAtTop ? 0 : kToolBarHeight);
		int h     = cy - hTool - 2 * kBackMargin;
		int hFan  = _fShowFanInOut ? h / 4 : 0;
		int hFunc = h - 2 * hFan;
		
		RECT rcFileWheel;
		if (_wndFileWheel.GetWindowRect(&rcFileWheel))
		{
			_wndBack.ScreenToClient(&rcFileWheel);
			rcFileWheel.right = cx - kBackMargin;
			_wndFileWheel.SetWindowPos(null, &rcFileWheel, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
			RECT rcFileList;
					
			if (_wndFuncList.GetWindowRect(&rcFileList))
			{
				_wndBack.ScreenToClient(&rcFileList);
				rcFileList.right = cx - kBackMargin;
				rcFileList.bottom = hFunc + kBackMargin;
				_wndFuncList.SetWindowPos(null, &rcFileList, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
				
				rcFileList.top = rcFileList.bottom;
				rcFileList.bottom += hFan;
				if(_wndFanInList)
					_wndFanInList.SetWindowPos(null, &rcFileList, SWP_NOZORDER | SWP_NOACTIVATE);

				rcFileList.top = rcFileList.bottom;
				rcFileList.bottom += hFan;
				if(_wndFanOutList)
					_wndFanOutList.SetWindowPos(null, &rcFileList, SWP_NOZORDER | SWP_NOACTIVATE);
			}
		}
		return 0;
	}

	void RearrangeControls()
	{
		RECT rcBack;
		if (_wndBack.GetWindowRect(&rcBack))
			ResizeControls(rcBack.right - rcBack.left, rcBack.bottom - rcBack.top);
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
		//UINT cItems = cast(UINT)_wndFuncList.SendMessage(LVM_GETITEMCOUNT);
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
				return _wndFuncList.SendMessage(uiMsg, wParam, lParam);
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
			for (size_t i = 0; i < _rgColumns.length && !fDone; i++)
			{
				COLUMNINFO *ci = &(_rgColumns[i]);
				if (ci.colid == colid)
				{
					fDone = TRUE;
				}
				else if (ci.fVisible)
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

			hr = _wndFuncList.SendMessage(LVM_DELETECOLUMN, iCol) ? S_OK : E_FAIL;
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
			
			// Don't include the first column (COLUMNID.NAME) in the list
			for (size_t i = COLUMNID.NAME + 1; i < _rgColumns.length && SUCCEEDED(hr); i++)
			{
				COLUMNINFO *ci = &(_rgColumns[i]);
				string strDisplayName = s_rgColumns[ci.colid].displayName;
				mii.fState = MFS_ENABLED;
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
		if (hwndContextMenu == _wndFuncList.hwnd)
		{
			RECT rcHdr;
			if (_wndFuncListHdr.GetWindowRect(&rcHdr))
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

	HRESULT _OpenProfileItem(string pszPath, int line)
	{
		HRESULT hr = S_OK;
version(all)
{
		hr = OpenFileInSolution(pszPath, line);
}
else
{
		if(dte80.DTE2 dte = GetDTE())
		{
			scope(exit) release(dte);
			ComPtr!(dte80.ItemOperations) spvsItemOperations;
			hr = dte.ItemOperations(&spvsItemOperations.ptr);
			if (SUCCEEDED(hr))
			{
				ComPtr!(dte80a.Window) spvsWnd;
				hr = spvsItemOperations.OpenFile(_toUTF16z(pszPath), null, &spvsWnd.ptr);
			}
		}
}
		if(hr == S_OK && _closeOnReturn)
			sWindowFrame.Hide();
		return hr;
	}

	LRESULT _OnOpenSelectedItem(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled)
	{
		int iSel = _wndFuncList.SendMessage(LVM_GETNEXTITEM, cast(WPARAM)-1, LVNI_SELECTED);
		if (iSel != -1)
		{
			_OpenProfileItem(iSel);
		}
		else
		{
			_OpenProfileItem(_wndFileWheel.GetWindowText(), -1);
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

	HRESULT _SetGroupColumn(COLUMNID colid)
	{
		_iqp.colidGroup = colid;

		_WriteViewOptionToRegistry("GroupColumn"w, _iqp.colidGroup);

		return _RefreshFileList();
	}

	int _ListViewIndexFromColumnID(COLUMNID colid)
	{
		int iCol = -1;
		int cCols = _wndFuncListHdr.SendMessage(HDM_GETITEMCOUNT);
		for (int i = 0; i < cCols && iCol == -1; i++)
		{
			HDITEM hdi;
			hdi.mask = HDI_LPARAM;
			if (_wndFuncListHdr.SendMessage(HDM_GETITEM, i, cast(LPARAM)&hdi) && hdi.lParam == colid)
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
			COLUMNINFO *ci = &(_rgColumns[iCol]);
			if (ci.colid == colid)
			{
				pci = ci;
			}
		}
		return pci;
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
			case IDR_ALTERNATEROWCOLOR:
				_fAlternateRowColor = checked;
				_WriteViewOptionToRegistry("AlternateRowColor"w, _fAlternateRowColor);
				_wndFuncList.InvalidateRect(null, FALSE);
				break;
			
			case IDR_CLOSEONRETURN:
				_closeOnReturn = checked;
				_WriteViewOptionToRegistry("CloseOnReturn"w, _closeOnReturn);
				break;

			case IDR_FANINOUT:
				_fShowFanInOut = checked;
				_WriteViewOptionToRegistry("ShowFanInOut"w, _fShowFanInOut);
				RearrangeControls();
				break;
				
			case IDR_REFRESH:
				_RefreshFileList();
				break;
				
			case IDR_SETTRACE:
				if(Config cfg = getCurrentStartupConfig())
				{
					scope(exit) release(cfg);
					string workdir = cfg.GetProjectOptions().replaceEnvironment(cfg.GetProjectOptions().debugworkingdir, cfg);
					if(!isabs(workdir))
						workdir = cfg.GetProjectDir() ~ "\\" ~ workdir;
					string tracelog = workdir ~ "trace.log";
					_wndFileWheel.SetWindowText(tracelog);
					_RefreshFileList();
				}
				break;
				
			case IDR_REMOVETRACE:
				string fname = _wndFileWheel.GetWindowText();
				if(std.file.exists(fname))
					std.file.remove(fname);
				_RefreshFileList();
				break;
				
			case IDR_FULLDECO:
				_fFullDecoration = checked;
				_WriteViewOptionToRegistry("FullDecoration"w, _fFullDecoration);
				_RefreshFileList();
				break;
				
/+
			case IDR_GROUPBYKIND:
				_SetGroupColumn(checked ? COLUMNID.KIND : COLUMNID.NONE);
				break;
+/
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
		if (_wndFuncListHdr.SendMessage(HDM_GETITEM, iIndex, cast(LPARAM)&hdi))
		{
			colid = cast(COLUMNID)hdi.lParam;
		}
		return colid;
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
			if (_wndFuncList.SendItemMessage(LVM_GETITEM, lvi))
			{
				pnmlvdi.item.mask |= LVIF_DI_SETITEM;
				ProfileItem psiWeak = cast(ProfileItem)cast(void*)lvi.lParam;
				string txt;
				switch (_ColumnIDFromListViewIndex(pnmlvdi.item.iSubItem))
				{
				case COLUMNID.NAME:
					txt = _demangle(psiWeak.GetName(), _fFullDecoration != 0);
					break;

				case COLUMNID.CALLS:
					long cb = psiWeak.GetCalls();
					txt = to!string(cb);
					break;

				case COLUMNID.TREETIME:
					long cb = psiWeak.GetTreeTime();
					cb = cast(long) (cb * 1000000.0 / _spsii.mTicksPerSec);
					txt = to!string(cb);
					break;

				case COLUMNID.FUNCTIME:
					long cb = psiWeak.GetFuncTime();
					cb = cast(long) (cb * 1000000.0 / _spsii.mTicksPerSec);
					txt = to!string(cb);
					break;

				case COLUMNID.CALLTIME:
					long cb = psiWeak.GetCallTime();
					cb = cast(long) (cb * 1000000.0 / _spsii.mTicksPerSec);
					txt = to!string(cb);
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

	void _ReinitViewState(bool refresh)
	{
		_WriteViewStateToRegistry();
		_RemoveSortIcon(_ListViewIndexFromColumnID(_iqp.colidSort));

		_InitializeViewState();
		_InitializeSwitches();
		_AddSortIcon(_ListViewIndexFromColumnID(_iqp.colidSort), _iqp.fSortAscending);
		
		_InitializeFuncListColumns();
		
		_RefreshFileList();
	}

	RegKey _GetCurrentRegKey(bool write)
	{
		GlobalOptions opt = Package.GetGlobalOptions();
		opt.getRegistryRoot();
		wstring regPath = opt.regUserRoot ~ regPathToolsOptions ~ "\\ProfileSymbolWindow"w;
		return new RegKey(opt.hUserKey, regPath, write);
	}
	
	HRESULT _InitializeViewState()
	{
		HRESULT hr = S_OK;
		try
		{
			scope RegKey keyWinOpts = _GetCurrentRegKey(false);
			if(keyWinOpts.GetDWORD("ColumnInfoVersion"w, 0) == 1)
			{
				void[] data = keyWinOpts.GetBinary("ColumnInfo"w);
				if(data !is null)
					_rgColumns = cast(COLUMNINFO[])data;
			}

			_iqp.colidSort  = cast(COLUMNID) keyWinOpts.GetDWORD("SortColumn"w, _iqp.colidSort);
			_iqp.colidGroup = cast(COLUMNID) keyWinOpts.GetDWORD("GroupColumn"w, _iqp.colidGroup);
			_fAlternateRowColor   = keyWinOpts.GetDWORD("AlternateRowColor"w, _fAlternateRowColor) != 0;
			_closeOnReturn        = keyWinOpts.GetDWORD("closeOnReturn"w, _closeOnReturn) != 0;
			_fShowFanInOut        = keyWinOpts.GetDWORD("ShowFanInOut"w, _fShowFanInOut) != 0;
			_fFullDecoration      = keyWinOpts.GetDWORD("FullDecoration"w, _fFullDecoration) != 0;
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
			_rgColumns[i].cx = _wndFuncList.SendMessage(LVM_GETCOLUMNWIDTH, _ListViewIndexFromColumnID(_rgColumns[i].colid));

		try
		{
			scope RegKey keyWinOpts = _GetCurrentRegKey(true);
			keyWinOpts.Set("ColumnInfoVersion"w, kColumnInfoVersion);
			keyWinOpts.Set("ColumnInfo"w, _rgColumns);
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
		ProfileItem psi = cast(ProfileItem)cast(void*)pnmlv.lParam;
		// psi.Release();
		fHandled = TRUE;
		return 0;
	}

	LRESULT _OnFileListItemChanged(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
	{
		NMLISTVIEW *pnmlv = cast(NMLISTVIEW *)pnmh;

		if (pnmlv.uNewState & LVIS_SELECTED)
		{
			ProfileItem psi = _lastResultsArray.GetItem(pnmlv.iItem);
			RefreshFanInOutList(psi);
			_lastSelectedItem = pnmlv.iItem;
		}
		fHandled = TRUE;
		return 0;
	}

	LRESULT _OnFanInOutListDblClick(bool fanin, ref NMHDR *pnmh, ref BOOL fHandled)
	{
		NMLISTVIEW *pnmlv = cast(NMLISTVIEW *)pnmh;
		ProfileItem psi = _lastResultsArray.GetItem(_lastSelectedItem);
		if(psi)
		{
			Fan[] fan = fanin ? psi.mFanIn : psi.mFanOut;
			if(pnmlv.iItem >= 0 && pnmlv.iItem < fan.length)
			{
				string func = fan[pnmlv.iItem].func;
				int idx = _lastResultsArray.findFunc(func);
				if(idx >= 0)
				{
					int sel = _wndFuncList.SendMessage(LVM_GETNEXTITEM, cast(WPARAM)-1, LVNI_SELECTED);
					_UpdateSelection(sel, idx);
				}
			}
		}
		fHandled = TRUE;
		return 0;
	}
	
	HRESULT _OpenProfileItem(int iIndex)
	{
		ProfileItem psi = _lastResultsArray.GetItem(iIndex);
		if(!psi)
			return E_FAIL;

		SearchData sd;
		sd.wholeWord = true;
		sd.caseSensitive = true;
		sd.noDupsOnSameLine = true;

		string name = _demangle(psi.GetName(), false);
		if(std.string.indexOf(name, '.') >= 0)
		{
			sd.findQualifiedName = true;
			sd.names ~= name;
		}
		else
		{
			if(name == "__Dmain")
				sd.names ~= "main";
			else if(name.length > 0 && name[0] == '_')
				sd.names ~= name[1..$]; // assume extern "C", cutoff '_'
			else
				sd.names ~= name;
		}
		
		Definition[] defs = Package.GetLibInfos().findDefinition(sd);
		if(defs.length == 0)
		{
			showStatusBarText("No definition found for '" ~ sd.names[0] ~ "'");
			return S_FALSE;
		}
		if(defs.length > 1)
		{
			// TODO: match types to find best candidate?
			showStatusBarText("Multiple definitions found for '" ~ sd.names[0] ~ "'");
		}
		
		HRESULT hr = S_FALSE;
		for(int i = 0; i < defs.length && hr != S_OK; i++)
			hr = OpenFileInSolution(defs[i].filename, defs[i].line);
		
		if(hr != S_OK)
			showStatusBarText(format("Cannot open %s(%d) for definition of '%s'", defs[0].filename, defs[0].line, sd.names[0]));

		return hr;
	}

	LRESULT _OnFileListDblClick(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
	{
		NMITEMACTIVATE *pnmitem = cast(NMITEMACTIVATE*) pnmh;
		if (FAILED(_OpenProfileItem(pnmitem.iItem)))
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
			if (_wndFuncList.SendItemMessage(LVM_GETITEM, lvi) && (lvi.state & LVIS_SELECTED))
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
			COLUMNINFO *pci = _ColumnInfoFromColumnID(colid);
			pci.cx = pnmhdr.pitem.cxy;
			
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
		case IDR_ALTERNATEROWCOLOR:
			tip = "Toggle alternating row background color";
			break;
		case IDR_FULLDECO:
			tip = "Show full name decoration";
			break;
		case IDR_CLOSEONRETURN:
			tip = "Close search window when item selected or focus lost";
			break;
		case IDR_FANINOUT:
			tip = "Show Fan In/Out";
			break;
		case IDR_REFRESH:
			tip = "Reread trace log to update display";
			break;
		case IDR_SETTRACE:
			tip = "Set trace log file from current project";
			break;
		case IDR_REMOVETRACE:
			tip = "Delete current trace.log to reinit profiling";
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

class ItemArray
{
	ProfileItem[] mItems;
	ProfileItemGroup[] mGroups;
	
	void add(ProfileItem item)
	{
		mItems ~= item;
	}
	
	void addByGroup(string grp, ProfileItem item)
	{
		for(int i = 0; i < mGroups.length; i++)
			if(mGroups[i].GetName() == grp)
				return mGroups[i].add(item);

		auto group = new ProfileItemGroup(grp);
		group.add(item);
		mGroups ~= group;
	}
	
	int GetCount() const { return max(mItems.length, mGroups.length); }
	
	ProfileItemGroup GetGroup(uint idx) const
	{
		if(idx >= mGroups.length)
			return null;
		return cast(ProfileItemGroup)mGroups[idx];
	}
	
	ProfileItem GetItem(uint idx) const 
	{
		if(idx >= mItems.length)
			return null;
		return cast(ProfileItem)mItems[idx]; 
	}

	int findFunc(string name)
	{
		foreach(i, psi; mItems)
			if(psi.GetName() == name)
				return i;
		return -1;
	}

	void sort(COLUMNID id, bool ascending)
	{
		void doSort(string method)(ref ProfileItem[] items)
		{
			if(ascending)
				std.algorithm.sort!("a." ~ method ~ "() < b." ~ method ~ "()")(items);
			else
				std.algorithm.sort!("a." ~ method ~ "() > b." ~ method ~ "()")(items);
		}
			
		switch(id)
		{
		case COLUMNID.NAME:
			doSort!"GetName"(mItems);
			break;

		case COLUMNID.CALLS:
			doSort!"GetCalls"(mItems);
			break;

		case COLUMNID.TREETIME:
			doSort!"GetTreeTime"(mItems);
			break;
			
		case COLUMNID.FUNCTIME:
			doSort!"GetFuncTime"(mItems);
			break;
			
		case COLUMNID.CALLTIME:
			doSort!"GetCallTime"(mItems);
			break;
			
		default:
			break;
		}
		
		foreach(grp; mGroups)
			grp.mArray.sort(id, ascending);
	}
}

class ProfileItemGroup
{
	this(string name)
	{
		mName = name;
		mArray = new ItemArray;
	}
	
	void add(ProfileItem item)
	{
		mArray.add(item);
	}
	
	string GetName() const { return mName; }
	const(ItemArray) GetItems() const { return mArray; }
	
	ItemArray mArray;
	string mName;
}

struct Fan
{
	string func;
	long calls;
}

class ProfileItem
{
	int GetIconIndex() const { return 0; }

	string GetName() const { return mName; }
	
	long GetCalls() const { return mCalls; }
	long GetTreeTime() const { return mTreeTime; }
	long GetFuncTime() const { return mFuncTime; }
	long GetCallTime() const { return mCalls ? mFuncTime / mCalls : 0; }
	
	string mName;
	long mCalls;
	long mTreeTime;
	long mFuncTime;
	
	Fan[] mFanIn;
	Fan[] mFanOut;
}

class ProfileItemIndex
{
	HRESULT Update(string fname, INDEXQUERYPARAMS *piqp, ItemArray *ppv)
	{
		ItemArray array = new ItemArray;
		*ppv = array;
		
		if(!std.file.exists(fname))
			return S_FALSE;
		
		ubyte[] text; // not valid utf8
		try
		{
			ProfileItem curItem;
			
			File file = File(fname, "rb");
			char[] buf;
			while(file.readln(buf))
			{
				if(buf[0] == '-')
				{
					curItem = new ProfileItem;
					array.add(curItem);
				}
				else if(buf[0] == '=')
				{
					int pos = std.string.indexOf(buf, "Timer Is");
					if(pos > 0)
						mTicksPerSec = parse!long(buf[pos + 9 .. $]);
					break;
				}
				else if(curItem)
				{
					char[] txt = buf;
					munch(txt, " \t\n\r");
					if(txt.length > 0 && isDigit(txt[0]))
					{
						long calls;
						if(parseLong(txt, calls))
						{
							char[] id = parseNonSpace(txt);
							if(id.length > 0)
							{
								munch(txt, " \t\n\r");
								if(txt.length == 0)
								{
									Fan fan = Fan(to!string(id), calls);
									if(curItem.mName)
										curItem.mFanOut ~= fan;
									else
										curItem.mFanIn ~= fan;
								}
							}
						}
					}
					else if(txt.length > 0)
					{
						long calls, treeTime, funcTime;
						char[] id = parseNonSpace(txt);
						if(id.length > 0 &&
						   parseLong(txt, calls) && 
						   parseLong(txt, treeTime) &&
						   parseLong(txt, funcTime))
						{
							munch(txt, " \t\n\r");
							if(txt.length == 0)
							{
								curItem.mName = to!string(id);
								curItem.mCalls = calls;
								curItem.mTreeTime = treeTime;
								curItem.mFuncTime = funcTime;
							}
						}
					}
				}
			}
			
			array.sort(piqp.colidSort, piqp.fSortAscending);
			return S_OK;
		}
		catch(Exception e)
		{
			return E_FAIL;
		}
	}
	
	long mTicksPerSec = 1;
}
