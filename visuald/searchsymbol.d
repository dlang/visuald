// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module searchsymbol;

import windows;
import winctrl;
import comutil;
import hierutil;
import logutil;
import dpackage;

import sdk.win32.commctrl;
import sdk.vsi.vsshell;

class SearchWindow
{
	Window mWindow;
	Window mCanvas;
	Button mBtnClose;
	IVsWindowFrame mWindowFrame;
	SearchPane mSearchPane;
	
	void openWindow()
	{
version(none)
{
		RECT r; 
		mWindow = new Window(cast(Widget)null);
		mCanvas = new Window(mWindow);
		DWORD color = GetSysColor(COLOR_BTNFACE);
		mCanvas.setBackground(color);
		mWindow.setRect(100, 100, 300, 200);
		mCanvas.setRect(5, 5, 290, 190);
		
		mBtnClose = new Button(mCanvas, "Close", 1);
		mBtnClose.setRect(15, 15, 90, 20);
		
		mWindow.setVisible(true);
}
else version(none)
{
		dte2.DTE2 spvsDTE = GetDTE();
		if(!spvsDTE)
			return;
		scope(exit) release(spvsDTE);
		dte.Windows spvsWindows;
		if(SUCCEEDED(spvsDTE.get_Windows(&spvsWindows)))
		{
			scope(exit) release(spvsWindows);
			wchar* sbstrProgID = "VisualDSearch.Control"w;
			wchar* sbstrTitle = "Visual D Search"w;
			wchar* sbstrPosition = "{D9AB8B7C-6FC5-4b53-8F53-4F600CDD9EBB}"w;

/+
			if(SUCCEEDED(spvsWindows.CreateToolWindow(_spvsAddin, sbstrProgID, sbstrTitle, sbstrPosition, &_spdispFlatSolutionExplorer, &_spvsWnd);
                        if (SUCCEEDED(hr))
                        {
                            CComPtr<IObjectWithSite> spObjectWithSite;
                            hr = _spdispFlatSolutionExplorer->QueryInterface(&spObjectWithSite);
                            if (SUCCEEDED(hr))
                            {
                                CComPtr<IUnknown> spunkThis;
                                hr = QueryInterface(IID_PPV_ARGS(&spunkThis));
                                if (SUCCEEDED(hr))
                                {
                                    spObjectWithSite->SetSite(spunkThis);
                                }
                            }
                        }
                    }
                }
            }
+/
        }
  		
}
else
{
		scope auto pIVsUIShell = new ComPtr!(IVsUIShell)(queryService!(IVsUIShell));
		if(!pIVsUIShell.ptr)
			return;
	
		mSearchPane = new SearchPane;
		const(wchar)* caption = "Visual D Search"w.ptr;
		HRESULT hr;
		hr = pIVsUIShell.ptr.CreateToolWindow(CTW_fInitNew, 0, mSearchPane, 
		                                      &GUID_NULL, &g_toolWinCLSID, &GUID_NULL, 
		                                      null, caption, null, &mWindowFrame);
		if(!SUCCEEDED(hr))
			return;
	
		mWindowFrame.Show();
}
		
	}
}

class SearchPane : DisposingComObject, IVsWindowPane
{
	Window mWindow;
	Window mCanvas;
	Button mBtnClose;
	IServiceProvider mSite;

	HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsWindowPane) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}
	
	void Dispose()
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
		RECT r; 
		mWindow = new Window(hwndParent);
		mCanvas = new Window(mWindow);
		DWORD color = GetSysColor(COLOR_BTNFACE);
		mCanvas.setBackground(color);
		mWindow.setRect(100, 100, 300, 200);
		mCanvas.setRect(5, 5, 290, 190);
		
		mBtnClose = new Button(mCanvas, "Hi there", 1);
		mBtnClose.setRect(15, 15, 90, 20);
		
		mWindow.setVisible(true);
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
		mWindow.Dispose();
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
	HRESULT TranslateAccelerator(LPMSG lpmsg)
	{
		mixin(LogCallMix2);
		return returnError(E_NOTIMPL);
	}

	///////////////////////////////////////////////////////////////////

	// the following has been ported from the FlatSolutionExplorer project
private:
	enum COLUMNID
	{
		NONE,
		NAME,
	}
	
    struct COLUMNINFO
    {
        COLUMNID colid;
        BOOL fVisible;
        int cx;
    };

    dte2.DTE2 _spvsDTE2;
//    CComPtr<ISolutionItemIndex> _spsii;
//    DWORD _dwIndexEventsCookie;
//    CComPtr<IAutoComplete2> _spac2;

    Window _wndFileWheel;
    Window _wndFileList;
    Window _wndFileListHdr;
    Window _wndToolbar;
    HIMAGELIST _himlToolbar;

    BOOL _fCompressNameAndPath;
    BOOL _fAlternateRowColor;
    COLUMNINFO[] _rgColumns;

    COLUMNID _colidSort;
    BOOL _fSortAscending;
    COLUMNID _colidGroup;
    COLORREF _crAlternate;

/+	
    BEGIN_MSG_MAP(CFlatSolutionExplorer)
        MESSAGE_HANDLER(WM_INITDIALOG, _OnInitDialog)
        MESSAGE_HANDLER(WM_SIZE, _OnSize)
        MESSAGE_HANDLER(WM_SETFOCUS, _OnSetFocus)
        MESSAGE_HANDLER(WM_CONTEXTMENU, _OnContextMenu)
        MESSAGE_HANDLER(WM_DESTROY, _OnDestroy)
        COMMAND_HANDLER(IDOK, BN_CLICKED, _OnOpenSelectedItem);
        COMMAND_HANDLER(IDC_FILEWHEEL, EN_CHANGE, _OnFileWheelChanged)
        COMMAND_HANDLER(IDR_COMPRESSNAMEANDPATH, BN_CLICKED, _OnCompressNameAndPath)
        COMMAND_HANDLER(IDR_ALTERNATEROWCOLOR, BN_CLICKED, _OnAlternateRowColor)
        COMMAND_HANDLER(IDR_UNGROUPED, BN_CLICKED, _OnGroupSelected)
        COMMAND_HANDLER(IDR_GROUPBYCACHETYPE, BN_CLICKED, _OnGroupSelected)
        COMMAND_HANDLER(IDR_GROUPBYFILETYPE, BN_CLICKED, _OnGroupSelected)
        NOTIFY_HANDLER(IDC_FILELIST, LVN_GETDISPINFO, _OnFileListGetDispInfo)
        NOTIFY_HANDLER(IDC_FILELIST, LVN_COLUMNCLICK, _OnFileListColumnClick)
        NOTIFY_HANDLER(IDC_FILELIST, LVN_DELETEITEM, _OnFileListDeleteItem)
        NOTIFY_HANDLER(IDC_FILELIST, NM_DBLCLK, _OnFileListDblClick)
        NOTIFY_HANDLER(IDC_FILELIST, NM_CUSTOMDRAW, _OnFileListCustomDraw)
        NOTIFY_HANDLER(IDC_FILELISTHDR, HDN_ITEMCHANGED, _OnFileListHdrItemChanged)
        NOTIFY_HANDLER(IDC_TOOLBAR, TBN_GETINFOTIP, _OnToolbarGetInfoTip)
        CHAIN_MSG_MAP(CComCompositeControl<CFlatSolutionExplorer>)
    END_MSG_MAP()
+/

/+	
    BOOL PreTranslateAccelerator(MSG *pmsg, ref HRESULT hrRet);

protected:
    LRESULT _OnInitDialog(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled);
    LRESULT _OnSize(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled);
    LRESULT _OnSetFocus(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled);
    LRESULT _OnContextMenu(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled);
    LRESULT _OnDestroy(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled);
    LRESULT _OnOpenSelectedItem(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled);
    LRESULT _OnFileWheelChanged(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled);
    LRESULT _OnCompressNameAndPath(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled);
    LRESULT _OnAlternateRowColor(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled);
    LRESULT _OnGroupSelected(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled);
    LRESULT _OnFileListGetDispInfo(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled);
    LRESULT _OnFileListColumnClick(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled);
    LRESULT _OnFileListDeleteItem(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled);
    LRESULT _OnFileListDblClick(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled);
    LRESULT _OnFileListCustomDraw(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled);
    LRESULT _OnFileListHdrItemChanged(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled);
    LRESULT _OnToolbarGetInfoTip(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled);

    HRESULT _CreateSortImageList(HIMAGELIST *phiml);
    HRESULT _CreateToolbarImageList(HIMAGELIST *phiml);
    HRESULT _AddSortIcon(int iIndex, BOOL fAscending);
    HRESULT _RemoveSortIcon(int iIndex);
    HRESULT _InitializeViewState();
    HRESULT _InitializeFileList();
    HRESULT _InitializeToolbar();
    HRESULT _InsertListViewColumn(int iIndex, COLUMNID colid, int cx);
    HRESULT _SetSortColumn(COLUMNID colid, int iIndex);
    HRESULT _SetGroupColumn(COLUMNID colid);
    HRESULT _SetCompressedNameAndPath(BOOL fSet);
    HRESULT _ChooseColumns(POINT pt);
    HRESULT _ToggleColumnVisibility(COLUMNID colid);
    void _SetAlternateRowColor();

    HRESULT _InitializeAutoComplete();
    HRESULT _EnableAutoComplete(BOOL fEnable);

    COLUMNID _ColumnIDFromListViewIndex(int iIndex);
    int _ListViewIndexFromColumnID(COLUMNID colid);
    COLUMNID _GroupCommandIDtoColumnID(UINT uiCmd);
    UINT _ColumnIDtoGroupCommandID(COLUMNID colid);
    COLUMNINFO *_ColumnInfoFromColumnID(COLUMNID colid);

    void _MoveSelection(BOOL fDown);
    HRESULT _OpenSolutionItem(int iIndex);
    HRESULT _OpenSolutionItem(PCWSTR pszPath);

    HRESULT _PrepareFileListForResults(in ISolutionItem[] puaResults);
    HRESULT _RefreshFileList();
    HRESULT _AddGroupToFileList(int iGroupId, in ISolutionItemGroup psig);
    HRESULT _AddItemsToFileList(int iGroupId, in ISolutionItem[] pua);

    HRESULT _WriteColumnInfoToRegistry();
    HRESULT _WriteSortInfoToRegistry();
    HRESULT _WriteGroupInfoToRegistry();
    HRESULT _WriteViewOptionToRegistry(PCWSTR pszName, DWORD dw);

    static LRESULT s_HdrWndProc(HWND hwnd, UINT uiMsg, WPARAM wParam, LPARAM lParam, in UINT_PTR uIdSubclass, in DWORD_PTR dwRefData);
    LRESULT _HdrWndProc(HWND hWnd, UINT uiMsg, WPARAM wParam, LPARAM lParam);
+/
	
	this()
	{
		_colidSort = COLUMNID.NAME;
		_fSortAscending = TRUE;
		_colidGroup = COLUMNID.NONE;
		// m_bWindowOnly = TRUE;
		// CalcExtent(m_sizeExtent);
	}

/+
// IObjectWithSite
STDMETHODIMP SetSite(in IUnknown *punkSite)
{
    if (_spsii)
    {
        if (_dwIndexEventsCookie)
        {
            AtlUnadvise(_spsii, __uuidof(ISolutionItemIndexEvents), _dwIndexEventsCookie);
            _dwIndexEventsCookie = 0;
        }

        CComPtr<IObjectWithSite> spows;
        if (SUCCEEDED(_spsii->QueryInterface(&spows)))
        {
            spows->SetSite(NULL);
        }
        _spsii = NULL;
    }

    IObjectWithSiteImpl<CFlatSolutionExplorer>::SetSite(punkSite);

    if (m_spUnkSite)
    {
        CComPtr<IServiceProvider> spsp;
        if (SUCCEEDED(m_spUnkSite->QueryInterface(&spsp)))
        {
            if (SUCCEEDED(spsp->QueryService(SID_SFseAddIn, &_spvsDTE2)))
            {
                CComPtr<IObjectWithSite> spows;
                if (SUCCEEDED(CreateSolutionItemIndex(IID_PPV_ARGS(&spows))))
                {
                    CComPtr<IUnknown> spunkThis;
                    if (SUCCEEDED(QueryInterface(IID_PPV_ARGS(&spunkThis))))
                    {
                        spows->SetSite(spunkThis);
                        if (SUCCEEDED(spows->QueryInterface(&_spsii)))
                        {
                            AtlAdvise(_spsii, spunkThis, __uuidof(ISolutionItemIndexEvents), &_dwIndexEventsCookie);
                        }
                    }
                }
            }
        }
    }
    return S_OK;
}
	
// IOleControl
STDMETHODIMP OnAmbientPropertyChange(DISPID dispid)
{
    if (dispid == DISPID_AMBIENT_BACKCOLOR)
    {
        SetBackgroundColorFromAmbient();
        FireViewChange();
    }
    return IOleControlImpl<CFlatSolutionExplorer>::OnAmbientPropertyChange(dispid);
}

// ISupportsErrorInfo
STDMETHODIMP InterfaceSupportsErrorInfo(REFIID riid)
{
    static const IID* s_rgiid[] =
    {
        &__uuidof(IFlatSolutionExplorer),
    };

    HRESULT hr = S_FALSE;
    for (int i = 0; i < ARRAYSIZE(s_rgiid) && hr == S_FALSE; i++)
    {
        if (InlineIsEqualGUID(*s_rgiid[i], riid))
        {
            hr = S_OK;
        }
    }
    return hr;
}

// ISolutionItemCacheEvents
STDMETHODIMP IndexUpdated()
{
    _RefreshFileList();
    return S_OK;
}
+/

	void _MoveSelection(BOOL fDown)
	{
		// Get the current selection
		int iSel = _wndFileList.SendMessage(LVM_GETNEXTITEM, cast(WPARAM)-1, LVNI_SELECTED);

		LVITEM lvi = {0};
		lvi.iItem = fDown ? iSel+1 : iSel-1;
		lvi.mask = LVIF_STATE;
		lvi.stateMask = LVIS_SELECTED | LVIS_FOCUSED;
		lvi.state = LVIS_SELECTED | LVIS_FOCUSED;
		_wndFileList.SendMessage(LVM_SETITEM, 0, cast(LPARAM)&lvi);
		_wndFileList.SendMessage(LVM_ENSUREVISIBLE, lvi.iItem, FALSE);
	}

/+
BOOL PreTranslateAccelerator(ref MSG *pmsg, __out HRESULT &hrRet)
{
    BOOL fRet = FALSE;
    if ((pmsg->message >= WM_KEYFIRST && pmsg->message <= WM_KEYLAST))
    {
        HWND hwndFocus = ::GetFocus();
        UINT cItems = (UINT)_wndFileList.SendMessage(LVM_GETITEMCOUNT);
        if (cItems && hwndFocus == _wndFileWheel && pmsg->message == WM_KEYDOWN)
        {
            UINT vKey = LOWORD(pmsg->wParam);
            if (vKey == VK_UP || vKey == VK_DOWN)
            {
                fRet = TRUE;
                _MoveSelection(vKey == VK_DOWN);
            }
        }
    }

    if (!fRet)
    {
        OLEINPLACEFRAMEINFO ipfi = {0};
        ipfi.cb = sizeof(ipfi);
        RECT rcPos, rcClip;
        CComPtr<IOleInPlaceFrame> spInPlaceFrame;
        CComPtr<IOleInPlaceUIWindow> spInPlaceUIWindow;
        if (SUCCEEDED(m_spInPlaceSite->GetWindowContext(&spInPlaceFrame, &spInPlaceUIWindow, &rcPos, &rcClip, &ipfi)))
        {
            if (S_OK == OleTranslateAccelerator(spInPlaceFrame, &ipfi, pmsg))
            {
                fRet = TRUE;
            }
        }

        if (!fRet)
        {
            fRet = CComCompositeControl<CFlatSolutionExplorer>::PreTranslateAccelerator(pmsg, hrRet);
        }
    }

    return fRet;
}

HRESULT _PrepareFileListForResults(in IUnknownArray *puaResults)
{
    _wndFileList.SendMessage(LVM_DELETEALLITEMS);
    _wndFileList.SendMessage(LVM_REMOVEALLGROUPS);

    CComPtr<IServiceProvider> spsp;
    if (SUCCEEDED(_spsii->QueryInterface(&spsp)))
    {
        CComPtr<ISolutionItemTypeCache> spsitc;
        if (SUCCEEDED(spsp->QueryService(SID_SSolutionItemTypeCache, &spsitc)))
        {
            HIMAGELIST himl;
            if (SUCCEEDED(spsitc->GetIconImageList(&himl)))
            {
                _wndFileList.SendMessage(LVM_SETIMAGELIST, LVSIL_SMALL, (LPARAM)himl);
            }
        }
    }

    HRESULT hr = S_OK;
    BOOL fEnableGroups = _colidGroup != COLID_NONE;
    if (fEnableGroups)
    {
        DWORD cGroups;
        hr = puaResults->GetCount(&cGroups);
        // Don't enable groups if there is only 1
        if (SUCCEEDED(hr) && cGroups <= 1)
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

HRESULT _AddItemsToFileList(int iGroupId, in IUnknownArray *pua)
{
    LVITEM lvi = {0};
    lvi.pszText = LPSTR_TEXTCALLBACK;
    lvi.iItem = (int)_wndFileList.SendMessage(LVM_GETITEMCOUNT);
    DWORD cItems;
    HRESULT hr = pua->GetCount(&cItems);
    for (DWORD i = 0; i < cItems && SUCCEEDED(hr); i++)
    {
        CComPtr<ISolutionItem> spsi;
        hr = pua->GetItem(i, IID_PPV_ARGS(&spsi));
        if (SUCCEEDED(hr))
        {
            for (int iCol = COLID_NAME; iCol < COLID_MAX; iCol++)
            {
                lvi.iSubItem = iCol;
                if (iCol != COLID_NAME)
                {
                    lvi.mask = LVIF_TEXT;
                }
                else
                {
                    lvi.mask = LVIF_PARAM | LVIF_TEXT | LVIF_IMAGE;
                    lvi.iGroupId = iGroupId;
                    lvi.lParam = (LPARAM)spsi.p;
                    spsi->GetIconIndex(&lvi.iImage);
                    if (iGroupId != -1)
                    {
                        lvi.mask |= LVIF_GROUPID;
                        lvi.iGroupId = iGroupId;
                    }
                }
                if (_wndFileList.SendMessage(LVM_INSERTITEM, 0, (LPARAM)&lvi) != -1 && iCol == COLID_NAME)
                {
                    spsi.Detach();
                }
            }
            spsi = NULL;
        }
        lvi.iItem++;
    }
    return hr;
}

HRESULT _AddGroupToFileList(int iGroupId, in ISolutionItemGroup *psig)
{
    WCHAR szName[MAX_PATH];
    HRESULT hr = psig->GetName(szName, ARRAYSIZE(szName));
    if (SUCCEEDED(hr))
    {
        LVGROUP lvg = {0};
        lvg.cbSize = sizeof(lvg);
        lvg.mask = LVGF_ALIGN | LVGF_HEADER | LVGF_GROUPID | LVGF_STATE;
        lvg.uAlign = LVGA_HEADER_LEFT;
        lvg.iGroupId = iGroupId;
        lvg.pszHeader = szName;
        lvg.state = LVGS_NORMAL;
        hr = _wndFileList.SendMessage(LVM_INSERTGROUP, (WPARAM)-1, (LPARAM)&lvg) != -1 ? S_OK : E_FAIL;
        if (SUCCEEDED(hr))
        {
            CComPtr<IUnknownArray> spItems;
            hr = psig->GetItems(IID_PPV_ARGS(&spItems));
            if (SUCCEEDED(hr))
            {
                hr = _AddItemsToFileList(iGroupId, spItems);
            }
        }
    }
    return hr;
}

HRESULT _EnableAutoComplete(BOOL fEnable)
{
    return _spac2->SetOptions(fEnable ? (ACO_AUTOSUGGEST | ACO_AUTOAPPEND | ACO_USETAB) : ACO_NONE);
}

HRESULT _RefreshFileList()
{
    _wndFileList.SetRedraw(FALSE);

    HRESULT hr = S_OK;
    CString strWordWheel;
    try
    {
        _wndFileWheel.GetWindowText(strWordWheel);
    }
    catch (CAtlException &e)
    {
        hr = e.m_hr;
    }

    if (SUCCEEDED(hr))
    {
        INDEXQUERYPARAMS iqp = { _colidSort, _fSortAscending, _colidGroup };
        CComPtr<IUnknownArray> spResultsArray;
        hr = _spsii->Search(strWordWheel, &iqp, IID_PPV_ARGS(&spResultsArray));
        if (SUCCEEDED(hr))
        {
            hr = _PrepareFileListForResults(spResultsArray);
            if (SUCCEEDED(hr))
            {
                if (_colidGroup != COLID_NONE)
                {
                    DWORD cGroups;
                    hr = spResultsArray->GetCount(&cGroups);
                    for (DWORD iGroup = 0; iGroup < cGroups && SUCCEEDED(hr); iGroup++)
                    {
                        CComPtr<ISolutionItemGroup> spsig;
                        hr = spResultsArray->GetItem(iGroup, IID_PPV_ARGS(&spsig));
                        if (SUCCEEDED(hr))
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
        }

        BOOL fEnableAutoComplete = _wndFileList.SendMessage(LVM_GETITEMCOUNT) == 0;
        _EnableAutoComplete(fEnableAutoComplete);

        if (SUCCEEDED(hr))
        {
            // Select the first item
            LVITEM lviSelect = {0};
            lviSelect.mask = LVIF_STATE;
            lviSelect.iItem = 0;
            lviSelect.state = LVIS_SELECTED;
            lviSelect.stateMask = LVIS_SELECTED;
            _wndFileList.SendMessage(LVM_SETITEM, 0, (LPARAM)&lviSelect);
        }

        _wndFileList.SetRedraw(TRUE);
        _wndFileList.InvalidateRect(NULL, FALSE);
    }
    return hr;
}

// Special icon dimensions for the sort direction indicator
const int c_cxSortIcon = 7;
const int c_cySortIcon = 6;

HRESULT _CreateSortImageList(__deref_out HIMAGELIST *phiml)
{
    // Create an image list for the sort direction indicators
    HIMAGELIST himl = ImageList_Create(c_cxSortIcon, c_cySortIcon, ILC_COLORDDB | ILC_MASK, 2, 1);
    HRESULT hr = himl ? S_OK : E_OUTOFMEMORY;
    if (SUCCEEDED(hr))
    {
        HICON hicn = (HICON)LoadImage(_AtlBaseModule.GetResourceInstance(), MAKEINTRESOURCE(IDI_DESCENDING), IMAGE_ICON, c_cxSortIcon, c_cySortIcon, LR_DEFAULTCOLOR | LR_SHARED);
        hr = hicn ? S_OK : AtlHresultFromLastError();
        if (SUCCEEDED(hr))
        {
            hr = ImageList_ReplaceIcon(himl, -1, hicn) != -1 ? S_OK : E_FAIL;
            if (SUCCEEDED(hr))
            {
                hicn = (HICON)LoadImage(_AtlBaseModule.GetResourceInstance(), MAKEINTRESOURCE(IDI_ASCENDING), IMAGE_ICON, c_cxSortIcon, c_cySortIcon, LR_DEFAULTCOLOR | LR_SHARED);
                hr = hicn ? S_OK : AtlHresultFromLastError();
                if (SUCCEEDED(hr))
                {
                    hr = ImageList_ReplaceIcon(himl, -1, hicn) != -1 ? S_OK : E_FAIL;
                    if (SUCCEEDED(hr))
                    {
                        *phiml = himl;
                        himl = NULL;
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
    // First, get the current header item fmt
    HDITEM hdi = {0};
    hdi.mask = HDI_FORMAT;
    HRESULT hr = _wndFileListHdr.SendMessage(HDM_GETITEM, iIndex, (LPARAM)&hdi) ? S_OK : E_FAIL;
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
        hr = _wndFileListHdr.SendMessage(HDM_SETITEM, iIndex, (LPARAM)&hdi) ? S_OK : E_FAIL;
    }
    return hr;
}

HRESULT _RemoveSortIcon(int iIndex)
{
    // First, get the current header item fmt
    HDITEM hdi = {0};
    hdi.mask = HDI_FORMAT;
    HRESULT hr = _wndFileListHdr.SendMessage(HDM_GETITEM, iIndex, (LPARAM)&hdi) ? S_OK : E_FAIL;
    if (SUCCEEDED(hr))
    {
        // Remove the image mask and alignment
        hdi.fmt &= ~HDF_IMAGE;
        if ((hdi.fmt & HDF_JUSTIFYMASK) == HDF_LEFT)
        {
            hdi.fmt &= ~HDF_BITMAP_ON_RIGHT;
        }
        hr = _wndFileListHdr.SendMessage(HDM_SETITEM, iIndex, (LPARAM)&hdi) ? S_OK : E_FAIL;
    }
    return hr;
}

HRESULT _InsertListViewColumn(int iIndex, COLUMNID colid, int cx)
{
    LVCOLUMN lvc = {0};
    lvc.mask = LVCF_FMT | LVCF_TEXT | LVCF_WIDTH;
    lvc.fmt = s_rgColumns[colid].fmt;
    lvc.cx = cx;

    HRESULT hr = S_OK;
    try
    {
        CString strDisplayName;
        hr = strDisplayName.LoadString(s_rgColumns[colid].uiResIDDisplayName) ? S_OK : E_UNEXPECTED;
        if (SUCCEEDED(hr))
        {
            lvc.pszText = (PWSTR)(PCWSTR)strDisplayName;
            hr = _wndFileList.SendMessage(LVM_INSERTCOLUMN, iIndex, (LPARAM)&lvc) >= 0 ? S_OK : E_FAIL;
            if (SUCCEEDED(hr))
            {
                HDITEM hdi = {0};
                hdi.mask = HDI_LPARAM;
                hdi.lParam = colid;
                hr = _wndFileListHdr.SendMessage(HDM_SETITEM, iIndex, (LPARAM)&hdi) ? S_OK : E_FAIL;
            }
        }
    }
    catch (CAtlException &e)
    {
        hr = e.m_hr;
    }
    return hr;
}

HRESULT _InitializeFileList()
{
    _wndFileList.SendMessage(LVM_SETEXTENDEDLISTVIEWSTYLE, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER | LVS_EX_LABELTIP);

    HIMAGELIST himl;
    HRESULT hr = _CreateSortImageList(&himl);
    if (SUCCEEDED(hr))
    {
        _wndFileListHdr.SendMessage(HDM_SETIMAGELIST, HDMIL_PRIVATE, (LPARAM)himl);

        int cColumnsInserted = 0;
        for (UINT i = 0; i < _rgColumns.GetCount() && SUCCEEDED(hr); i++)
        {
            COLUMNINFO &ci = _rgColumns.GetAt(i);
            if (ci.fVisible)
            {
                // Don't insert the path column if we're compressing path and filename
                if (ci.colid != COLID_PATH || !_fCompressNameAndPath)
                {
                    int cx = ci.cx;
                    if (ci.colid == COLID_NAME && _fCompressNameAndPath)
                    {
                        COLUMNINFO *pci = _ColumnInfoFromColumnID(COLID_PATH);
                        cx += pci->cx;
                    }
                    hr = _InsertListViewColumn(cColumnsInserted++, ci.colid, cx);
                }
            }
        }

        if (SUCCEEDED(hr))
        {
            hr = _AddSortIcon(_ListViewIndexFromColumnID(_colidSort), TRUE);
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

HRESULT _CreateToolbarImageList(__deref_out HIMAGELIST *phiml)
{
    // Create an image list for the sort direction indicators
    HIMAGELIST himl = ImageList_Create(c_cxToolbarIcon, c_cyToolbarIcon, ILC_COLORDDB | ILC_MASK, 4, 1);
    HRESULT hr = himl ? S_OK : E_OUTOFMEMORY;
    if (SUCCEEDED(hr))
    {
        UINT rgIconIds[] = { IDR_COMPRESSNAMEANDPATH, IDR_ALTERNATEROWCOLOR, IDR_UNGROUPED, IDR_GROUPBYCACHETYPE, IDR_GROUPBYFILETYPE };
        for (int i = 0; i < ARRAYSIZE(rgIconIds) && SUCCEEDED(hr); i++)
        {
            HICON hicn = (HICON)LoadImage(_AtlBaseModule.GetResourceInstance(), MAKEINTRESOURCE(rgIconIds[i]), IMAGE_ICON, c_cxToolbarIcon, c_cyToolbarIcon, LR_DEFAULTCOLOR | LR_SHARED);
            hr = hicn ? S_OK : AtlHresultFromLastError();
            if (SUCCEEDED(hr))
            {
                hr = ImageList_ReplaceIcon(himl, -1, hicn) != -1 ? S_OK : E_FAIL;
            }
        }

        if (SUCCEEDED(hr))
        {
            *phiml = himl;
            himl = NULL;
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
    HRESULT hr = _CreateToolbarImageList(&_himlToolbar);
    if (SUCCEEDED(hr))
    {
        HWND hwnd = _wndToolbar.Create(TOOLBARCLASSNAME, m_hWnd, 0, NULL, WS_CHILD | WS_VISIBLE | CCS_BOTTOM | CCS_NODIVIDER | TBSTYLE_FLAT | TBSTYLE_TOOLTIPS, TBSTYLE_EX_DOUBLEBUFFER, IDC_TOOLBAR);
        hr = hwnd ? S_OK : E_FAIL;
        if (SUCCEEDED(hr))
        {
            _wndToolbar.SendMessage(TB_SETIMAGELIST, 0, (LPARAM)_himlToolbar);

            static const TBBUTTON s_tbb[] = {
                { 0, IDR_COMPRESSNAMEANDPATH, TBSTATE_ENABLED, BTNS_CHECK, {0}, NULL, NULL },
                { 1, IDR_ALTERNATEROWCOLOR, TBSTATE_ENABLED, BTNS_CHECK, {0}, NULL, NULL },
                { 10, -1, TBSTATE_ENABLED, BTNS_SEP, {0}, NULL, NULL },
                { 2, IDR_UNGROUPED, TBSTATE_ENABLED, BTNS_CHECKGROUP, {0}, NULL, NULL },
                { 3, IDR_GROUPBYCACHETYPE, TBSTATE_ENABLED, BTNS_CHECKGROUP, {0}, NULL, NULL },
                { 4, IDR_GROUPBYFILETYPE, TBSTATE_ENABLED, BTNS_CHECKGROUP, {0}, NULL, NULL },
            };

            hr = _wndToolbar.SendMessage(TB_ADDBUTTONS, ARRAYSIZE(s_tbb), (LPARAM)s_tbb) ? S_OK : E_FAIL;
            if (SUCCEEDED(hr))
            {
                // Set the initial state of the buttons
                TBBUTTONINFO tbbi = {0};
                tbbi.cbSize = sizeof(tbbi);
                tbbi.dwMask = TBIF_STATE;
                tbbi.fsState = TBSTATE_ENABLED | TBSTATE_CHECKED;
                
                if (_fCompressNameAndPath)
                {
                    hr = _wndToolbar.SendMessage(TB_SETBUTTONINFO, IDR_COMPRESSNAMEANDPATH, (LPARAM)&tbbi) ? S_OK : E_FAIL;
                }

                if (SUCCEEDED(hr) && _fAlternateRowColor)
                {
                    hr = _wndToolbar.SendMessage(TB_SETBUTTONINFO, IDR_ALTERNATEROWCOLOR, (LPARAM)&tbbi) ? S_OK : E_FAIL;
                }

                if (SUCCEEDED(hr))
                {
                    hr = _wndToolbar.SendMessage(TB_SETBUTTONINFO, _ColumnIDtoGroupCommandID(_colidGroup), (LPARAM)&tbbi) ? S_OK : E_FAIL;
                }
            }
        }
    }
    return hr;
}

HRESULT _WriteColumnInfoToRegistry()
{
    CRegKey rk;
    HRESULT hr = AtlHresultFromWin32(rk.Create(HKEY_CURRENT_USER, c_szRegRoot));
    if (SUCCEEDED(hr))
    {
        ULONG cbColInfo = (ULONG)(sizeof(COLUMNINFO)*_rgColumns.GetCount());
        CLocalMemPtr<BYTE> spci;
        hr = spci.Allocate(cbColInfo + sizeof(ULONG));
        if (SUCCEEDED(hr))
        {
            ULONG crc = CRC32Compute((const BYTE *)_rgColumns.GetData(), cbColInfo, CRC32_INITIAL_VALUE);
            *((ULONG *)spci.m_pData) = crc;
            CopyMemory((void *)(spci.m_pData + sizeof(ULONG)), _rgColumns.GetData(), cbColInfo);
            hr = AtlHresultFromWin32(rk.SetBinaryValue(L"ColumnInfo", spci, cbColInfo + sizeof(ULONG)));
        }
    }
    return hr;
}

HRESULT _InitializeViewState()
{
    // Initialize the column info
    CRegKey rk;
    HRESULT hr = AtlHresultFromWin32(rk.Create(HKEY_CURRENT_USER, c_szRegRoot));
    if (SUCCEEDED(hr))
    {
        static const struct
        {
            COLUMNID colid;
            BOOL fVisible;
        }
        s_rgColumnInit[] =
        {
            { COLID_NAME, TRUE },
            { COLID_PATH, TRUE },
            { COLID_SIZE, TRUE },
            { COLID_MODIFIEDDATE, TRUE },
        };

        DWORD cb = 0;
        hr = AtlHresultFromWin32(rk.QueryBinaryValue(L"ColumnInfo", NULL, &cb));
        if (SUCCEEDED(hr))
        {
            hr = AtlHresultFromWin32(ERROR_INVALID_DATA);
            if (cb)
            {
                CLocalMemPtr<BYTE> spci;
                hr = spci.Allocate(cb);
                if (SUCCEEDED(hr))
                {
                    hr = AtlHresultFromWin32(rk.QueryBinaryValue(L"ColumnInfo", spci, &cb));
                    if (SUCCEEDED(hr))
                    {
                        DWORD cbColInfo = ARRAYSIZE(s_rgColumnInit)*sizeof(COLUMNINFO);
                        if (cb != (cbColInfo + sizeof(ULONG)))
                        {
                            hr = AtlHresultFromWin32(ERROR_INVALID_DATA);
                        }
                        else
                        {
                            ULONG crc = *((ULONG *)spci.m_pData);
                            COLUMNINFO *pci = (COLUMNINFO *)(spci.m_pData + sizeof(ULONG));
                            ULONG crcLoad = CRC32Compute((BYTE*)pci, cbColInfo, CRC32_INITIAL_VALUE);
                            if (crcLoad != crc)
                            {
                                hr = AtlHresultFromWin32(ERROR_INVALID_DATA);
                            }
                            else
                            {
                                hr = _rgColumns.SetCount(ARRAYSIZE(s_rgColumnInit)) ? S_OK : E_OUTOFMEMORY;
                                if (SUCCEEDED(hr))
                                {
                                    CopyMemory(_rgColumns.GetData(), pci, cbColInfo);
                                }
                            }
                        }
                    }
                }
            }
        }

        if (FAILED(hr))
        {
            hr = S_OK;
            _rgColumns.RemoveAll();
            try
            {
                for (UINT i = 0; i < ARRAYSIZE(s_rgColumnInit) && SUCCEEDED(hr); i++)
                {
                    COLUMNINFO ci;
                    ci.colid = s_rgColumnInit[i].colid;
                    ci.cx = s_rgColumns[ci.colid].cx;
                    ci.fVisible = s_rgColumnInit[i].fVisible;
                    _rgColumns.Add(ci);
                }
            }
            catch (CAtlException &e)
            {
                hr = e.m_hr;
            }
        }

        if (SUCCEEDED(hr))
        {
            rk.QueryDWORDValue(L"SortColumn", (DWORD &)_colidSort);
            rk.QueryDWORDValue(L"SortAscending", (DWORD &)_fSortAscending);
            rk.QueryDWORDValue(L"GroupColumn", (DWORD &)_colidGroup);
            rk.QueryDWORDValue(L"CompressNameAndPath", (DWORD &)_fCompressNameAndPath);
            rk.QueryDWORDValue(L"AlternateRowColor", (DWORD &)_fAlternateRowColor);
        }
    }
    return hr;
}

LRESULT CALLBACK _HdrWndProc(HWND hwnd, UINT uiMsg, WPARAM wParam, LPARAM lParam)
{
    LRESULT lRet = 0;
    BOOL fHandled = FALSE;
    switch (uiMsg)
    {
    case WM_DESTROY:
        RemoveWindowSubclass(hwnd,  s_HdrWndProc, ID_SUBCLASS_HDR);
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
    }

    if (!fHandled)
    {
        lRet = DefSubclassProc(hwnd, uiMsg, wParam, lParam);
    }
    return lRet;
}

LRESULT CALLBACK s_HdrWndProc(HWND hWnd, UINT uiMsg, WPARAM wParam, LPARAM lParam, in UINT_PTR uIdSubclass, in DWORD_PTR dwRefData)
{
    CFlatSolutionExplorer *pfsec = (CFlatSolutionExplorer*)dwRefData;
    return pfsec ? pfsec->_HdrWndProc(hWnd, uiMsg, wParam, lParam) : DefSubclassProc(hWnd, uiMsg, wParam, lParam);
}

HRESULT _InitializeAutoComplete()
{
    CComPtr<IUnknown> spunksfacl;
    HRESULT hr = spunksfacl.CoCreateInstance(CLSID_ACListISF);
    if (SUCCEEDED(hr))
    {
        CComPtr<IAutoComplete2> spac2;
        hr = spac2.CoCreateInstance(CLSID_AutoComplete);
        if (SUCCEEDED(hr))
        {
            hr = spac2->Init(_wndFileWheel, spunksfacl, NULL, NULL);
            if (SUCCEEDED(hr))
            {
                hr = spac2->SetOptions(ACO_AUTOSUGGEST | ACO_USETAB);
                if (SUCCEEDED(hr))
                {
                    _spac2 = spac2;
                    _EnableAutoComplete(FALSE);
                }
            }
        }
    }
    return hr;
}

LRESULT _OnInitDialog(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
{
    if (SUCCEEDED(_InitializeViewState()))
    {
        _wndFileWheel.Attach(GetDlgItem(IDC_FILEWHEEL));
        _wndFileList.Attach(GetDlgItem(IDC_FILELIST));
        _wndFileListHdr.Attach((HWND)_wndFileList.SendMessage(LVM_GETHEADER));

        _InitializeAutoComplete();

        // HACK:  This header control is created by the listview.  When listview handles LVM_SETIMAGELIST with
        // LVSIL_SMALL it also forwards the message to the header control.  The subclass proc will intercept those
        // messages and prevent resetting the imagelist
        SetWindowSubclass(_wndFileListHdr, s_HdrWndProc, ID_SUBCLASS_HDR, (DWORD_PTR)this);

        _wndFileListHdr.SetDlgCtrlID(IDC_FILELISTHDR);

        _InitializeFileList();

        _InitializeToolbar();
    }
    return CComCompositeControl<CFlatSolutionExplorer>::OnInitDialog(uiMsg, wParam, lParam, fHandled);
}

LRESULT _OnSize(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
{
    int cx = LOWORD(lParam);
    int cy = HIWORD(lParam);

    // Adjust child control sizes
    // - File Wheel stretches to fit horizontally but size is vertically fixed
    // - File List stretches to fit horizontally and vertically but the topleft coordinate is fixed
    // - Toolbar autosizes along the bottom

    _wndToolbar.SendMessage(TB_AUTOSIZE);
    RECT rcToolbar;

    if (_wndToolbar.GetWindowRect(&rcToolbar))
    {
        RECT rcFileWheel;
        if (_wndFileWheel.GetWindowRect(&rcFileWheel))
        {
            ScreenToClient(&rcFileWheel);
            rcFileWheel.right = cx;
            _wndFileWheel.SetWindowPos(NULL, &rcFileWheel, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
            RECT rcFileList;
            if (_wndFileList.GetWindowRect(&rcFileList))
            {
                ScreenToClient(&rcFileList);
                rcFileList.right = cx;
                rcFileList.bottom = cy - (rcToolbar.bottom - rcToolbar.top);
                _wndFileList.SetWindowPos(NULL, &rcFileList, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
            }
        }
    }
    return 0;
}

LRESULT _OnSetFocus(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
{
    // Skip the CComCompositeControl handling
    CComControl<CFlatSolutionExplorer, CAxDialogImpl<CFlatSolutionExplorer>>::OnSetFocus(uiMsg, wParam, lParam, fHandled);

    _wndFileWheel.SetFocus();
    _wndFileWheel.SendMessage(EM_SETSEL, 0, (LPARAM)-1);

    fHandled = TRUE;
    return 0;
}

HRESULT _ToggleColumnVisibility(COLUMNID colid)
{
    HRESULT hr = E_FAIL;
    COLUMNINFO *pci = _ColumnInfoFromColumnID(colid);
    BOOL fVisible = !pci->fVisible;
    if (fVisible)
    {
        int iIndex = 0;
        BOOL fDone = FALSE;
        for (size_t i = 0; i < _rgColumns.GetCount() && !fDone; i++)
        {
            COLUMNINFO &ci = _rgColumns.GetAt(i);
            if (ci.colid == colid)
            {
                fDone = TRUE;
            }
            else if (ci.fVisible && (ci.colid != COLID_PATH || !_fCompressNameAndPath))
            {
                iIndex++;
            }
        }

        hr = _InsertListViewColumn(iIndex, colid, pci->cx);
        if (SUCCEEDED(hr))
        {
            pci->fVisible = TRUE;
        }
    }
    else
    {
        int iCol = _ListViewIndexFromColumnID(colid);

        hr = _wndFileList.SendMessage(LVM_DELETECOLUMN, iCol) ? S_OK : E_FAIL;
        if (SUCCEEDED(hr))
        {
            pci->fVisible = fVisible;
            if (colid == _colidSort)
            {
                hr = _SetSortColumn(COLID_NAME, 0);
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
    HRESULT hr = hmnu ? S_OK : AtlHresultFromLastError();
    if (SUCCEEDED(hr))
    {
        MENUITEMINFO mii = {0};
        mii.cbSize = sizeof(mii);
        mii.fMask = MIIM_FTYPE | MIIM_ID | MIIM_STATE | MIIM_STRING;
        mii.fType = MFT_STRING;
        // Don't include the first column (COLID_NAME) in the list
        try
        {
            for (size_t i = 1; i < _rgColumns.GetCount() && SUCCEEDED(hr); i++)
            {
                COLUMNINFO &ci = _rgColumns.GetAt(i);
                CString strDisplayName;
                hr = strDisplayName.LoadString(s_rgColumns[ci.colid].uiResIDDisplayName) ? S_OK : E_UNEXPECTED;
                if (SUCCEEDED(hr))
                {
                    mii.fState = (ci.colid == COLID_PATH && _fCompressNameAndPath) ? MFS_DISABLED : MFS_ENABLED;
                    if (ci.fVisible)
                    {
                        mii.fState |= MFS_CHECKED;
                    }
                    mii.wID = ci.colid + IDM_COLUMNLISTBASE;
                    mii.dwTypeData = (PWSTR)(PCWSTR)strDisplayName;
                    hr = InsertMenuItem(hmnu, (UINT)i-1, TRUE, &mii) ? S_OK : AtlHresultFromLastError();
                }
            }
        }
        catch (CAtlException &e)
        {
            hr = e.m_hr;
        }

        if (SUCCEEDED(hr))
        {
            UINT uiCmd = TrackPopupMenuEx(hmnu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_HORIZONTAL | TPM_TOPALIGN | TPM_LEFTALIGN, pt.x, pt.y, m_hWnd, NULL);
            if (uiCmd)
            {
                hr = _ToggleColumnVisibility((COLUMNID)(uiCmd - IDM_COLUMNLISTBASE));
            }
        }
        DestroyMenu(hmnu);
    }
    return hr;
}

LRESULT _OnContextMenu(UINT uiMsg, WPARAM wParam, LPARAM lParam, ref BOOL fHandled)
{
    fHandled = FALSE;

    HWND hwndContextMenu = (HWND)wParam;
    // I think the listview is doing the wrong thing with WM_CONTEXTMENU and using its own HWND even if
    // the WM_CONTEXTMENU originated in the header.  Just double check the coordinates to be sure
    if (hwndContextMenu == _wndFileList)
    {
        RECT rcHdr;
        if (_wndFileListHdr.GetWindowRect(&rcHdr))
        {
            POINT pt = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
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
        _wndToolbar.SendMessage(TB_SETIMAGELIST, 0, NULL);
        ImageList_Destroy(_himlToolbar);
        _himlToolbar = NULL;
    }

    fHandled = TRUE;
    return CComCompositeControl<CFlatSolutionExplorer>::OnDestroy(uiMsg, wParam, lParam, fHandled);
}

HRESULT _OpenSolutionItem(PCWSTR pszPath)
{
    CComPtr<ItemOperations> spvsItemOperations;
    HRESULT hr = _spvsDTE2->get_ItemOperations(&spvsItemOperations);
    if (SUCCEEDED(hr))
    {
        CComPtr<Window> spvsWnd;
        hr = spvsItemOperations->OpenFile((BSTR)pszPath, NULL, &spvsWnd);
    }
    return hr;
}

LRESULT _OnOpenSelectedItem(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled)
{
    int iSel = (int)_wndFileList.SendMessage(LVM_GETNEXTITEM, (WPARAM)-1, LVNI_SELECTED);
    if (iSel != -1)
    {
        _OpenSolutionItem(iSel);
    }
    else
    {
        WCHAR szPath[MAX_PATH];
        if (_wndFileWheel.GetWindowText(szPath, ARRAYSIZE(szPath)))
        {
            _OpenSolutionItem(szPath);
        }
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

const static struct
{
    UINT uiCmd;
    COLUMNID colid;
}
s_rgCmdToColIDMap[] = {
    { IDR_UNGROUPED, COLID_NONE },
    { IDR_GROUPBYCACHETYPE, COLID_HITTYPE },
    { IDR_GROUPBYFILETYPE, COLID_CANONICALTYPE }
};

UINT _ColumnIDtoGroupCommandID(COLUMNID colid)
{
    UINT uiRet = IDR_UNGROUPED;
    BOOL fFound = FALSE;
    for (int i = 0; i < ARRAYSIZE(s_rgCmdToColIDMap) && !fFound; i++)
    {
        if (colid == s_rgCmdToColIDMap[i].colid)
        {
            uiRet = s_rgCmdToColIDMap[i].uiCmd;
            fFound = TRUE;
        }
    }
    return uiRet;
}

COLUMNID _GroupCommandIDtoColumnID(UINT uiCmd)
{
    COLUMNID colidRet = COLID_NONE;
    BOOL fFound = FALSE;
    for (int i = 0; i < ARRAYSIZE(s_rgCmdToColIDMap) && !fFound; i++)
    {
        if (uiCmd == s_rgCmdToColIDMap[i].uiCmd)
        {
            colidRet = s_rgCmdToColIDMap[i].colid;
            fFound = TRUE;
        }
    }
    return colidRet;
}

HRESULT _WriteGroupInfoToRegistry()
{
    CRegKey rk;
    HRESULT hr = AtlHresultFromWin32(rk.Create(HKEY_CURRENT_USER, c_szRegRoot));
    if (SUCCEEDED(hr))
    {
        hr = AtlHresultFromWin32(rk.SetDWORDValue(L"GroupColumn", (DWORD)_colidGroup));
    }
    return hr;
}

HRESULT _SetGroupColumn(COLUMNID colid)
{
    _colidGroup = colid;

    _WriteGroupInfoToRegistry();

    return _RefreshFileList();
}

int _ListViewIndexFromColumnID(COLUMNID colid)
{
    int iCol = -1;
    int cCols = (int)_wndFileListHdr.SendMessage(HDM_GETITEMCOUNT);
    for (int i = 0; i < cCols && iCol == -1; i++)
    {
        HDITEM hdi = {0};
        hdi.mask = HDI_LPARAM;
        if (_wndFileListHdr.SendMessage(HDM_GETITEM, i, (LPARAM)&hdi) && (COLUMNID)hdi.lParam == colid)
        {
            iCol = i;
        }
    }
    return iCol;
}

COLUMNINFO *_ColumnInfoFromColumnID(COLUMNID colid)
{
    COLUMNINFO *pci = NULL;
    for (size_t iCol = 0; iCol < _rgColumns.GetCount() && pci == NULL; iCol++)
    {
        COLUMNINFO &ci = _rgColumns.GetAt(iCol);
        if (ci.colid == colid)
        {
            pci = &ci;
        }
    }
    return pci;
}

HRESULT _WriteViewOptionToRegistry(PCWSTR pszName, DWORD dw)
{
    CRegKey rk;
    HRESULT hr = AtlHresultFromWin32(rk.Create(HKEY_CURRENT_USER, c_szRegRoot));
    if (SUCCEEDED(hr))
    {
        hr = AtlHresultFromWin32(rk.SetDWORDValue(pszName, dw));
    }
    return hr;
}


HRESULT _SetCompressedNameAndPath(BOOL fSet)
{
    HRESULT hr = S_OK;
    if (fSet != _fCompressNameAndPath)
    {
        int iName = _ListViewIndexFromColumnID(COLID_NAME);
        COLUMNINFO *pciPath = _ColumnInfoFromColumnID(COLID_PATH);
        COLUMNINFO *pciName = _ColumnInfoFromColumnID(COLID_NAME);

        hr = (iName > -1 && pciPath && pciName) ? S_OK : E_FAIL;
        if (SUCCEEDED(hr))
        {
            _fCompressNameAndPath = fSet;
            _wndFileList.SetRedraw(FALSE);
            _wndFileListHdr.SetRedraw(FALSE);
            if (fSet)
            {
                // If the path column is currently hidden, set it to visible
                if (pciPath->fVisible)
                {
                    int iPath = _ListViewIndexFromColumnID(COLID_PATH);
                    hr = _wndFileList.SendMessage(LVM_DELETECOLUMN, iPath) ? S_OK : E_FAIL;
                }
                else
                {
                    pciPath->fVisible = TRUE;
                }

                _wndFileList.SendMessage(LVM_SETCOLUMNWIDTH, iName, MAKELPARAM(pciName->cx + pciPath->cx, 0));

                // If the list is currently sorted by path, change it to name.  Otherwise, just reset the values
                // for the name column and avoid a requery
                if (_colidSort == COLID_PATH)
                {
                    _SetSortColumn(COLID_NAME, iName);
                }
                else
                {
                    LVITEM lvi = {0};
                    lvi.mask = LVIF_TEXT;
                    lvi.pszText = LPSTR_TEXTCALLBACK;
                    lvi.iSubItem = iName;
                    UINT cItems = (UINT)_wndFileList.SendMessage(LVM_GETITEMCOUNT);
                    for (UINT i = 0; i < cItems; i++)
                    {
                        lvi.iItem = i;
                        _wndFileList.SendMessage(LVM_SETITEM, 0, (LPARAM)&lvi);
                    }
                }
            }
            else
            {
                _wndFileList.SendMessage(LVM_SETCOLUMNWIDTH, iName, MAKELPARAM(pciName->cx, 0));
                hr = _InsertListViewColumn(iName + 1, COLID_PATH, pciPath->cx);
                if (SUCCEEDED(hr))
                {
                    LVITEM lvi = {0};
                    lvi.mask = LVIF_TEXT;
                    lvi.pszText = LPSTR_TEXTCALLBACK;
                    UINT cItems = (UINT)_wndFileList.SendMessage(LVM_GETITEMCOUNT);
                    for (UINT i = 0; i < cItems; i++)
                    {
                        lvi.iItem = i;
                        lvi.iSubItem = iName;
                        _wndFileList.SendMessage(LVM_SETITEM, 0, (LPARAM)&lvi);
                        lvi.iSubItem = iName+1;
                        _wndFileList.SendMessage(LVM_SETITEM, 0, (LPARAM)&lvi);
                    }
                }
            }

            _WriteViewOptionToRegistry(L"CompressNameAndPath", _fCompressNameAndPath);

            _wndFileListHdr.SetRedraw(TRUE);
            _wndFileListHdr.InvalidateRect(NULL, FALSE);
            _wndFileList.SetRedraw(TRUE);
            _wndFileList.InvalidateRect(NULL, FALSE);
        }
    }
    return hr;
}

LRESULT _OnCompressNameAndPath(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled)
{
    TBBUTTONINFO tbbi = {0};
    tbbi.cbSize = sizeof(tbbi);
    tbbi.dwMask = TBIF_STATE;
    if (_wndToolbar.SendMessage(TB_GETBUTTONINFO, IDR_COMPRESSNAMEANDPATH, (LPARAM)&tbbi) != -1)
    {
        _SetCompressedNameAndPath(!!(tbbi.fsState & TBSTATE_CHECKED));
    }
    fHandled = TRUE;
    return 0;
}

LRESULT _OnAlternateRowColor(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled)
{
    TBBUTTONINFO tbbi = {0};
    tbbi.cbSize = sizeof(tbbi);
    tbbi.dwMask = TBIF_STATE;
    if (_wndToolbar.SendMessage(TB_GETBUTTONINFO, IDR_ALTERNATEROWCOLOR, (LPARAM)&tbbi) != -1)
    {
        _fAlternateRowColor = !!(tbbi.fsState & TBSTATE_CHECKED);

        _WriteViewOptionToRegistry(L"AlternateRowColor", _fAlternateRowColor);

        _wndFileList.InvalidateRect(NULL, FALSE);
    }
    fHandled = TRUE;
    return 0;
}

LRESULT _OnGroupSelected(WORD wNotifyCode, WORD wID, HWND hwndCtl, ref BOOL fHandled)
{
    _SetGroupColumn(_GroupCommandIDtoColumnID(wID));
    fHandled = TRUE;
    return 0;
}

COLUMNID _ColumnIDFromListViewIndex(int iIndex)
{
    COLUMNID colid = COLID_NONE;
    HDITEM hdi = {0};
    hdi.mask = HDI_LPARAM;
    if (_wndFileListHdr.SendMessage(HDM_GETITEM, iIndex, (LPARAM)&hdi))
    {
        colid = (COLUMNID)hdi.lParam;
    }
    return colid;
}

LRESULT _OnFileListGetDispInfo(int idCtrl, in NMHDR *pnmh, ref BOOL fHandled)
{
    NMLVDISPINFO *pnmlvdi = (NMLVDISPINFO *)pnmh;
    if (pnmlvdi->item.mask & LVIF_TEXT)
    {
        LVITEM lvi = {0};
        lvi.mask = LVIF_PARAM;
        lvi.iItem = pnmlvdi->item.iItem;
        if (_wndFileList.SendMessage(LVM_GETITEM, 0, (LPARAM)&lvi))
        {
            pnmlvdi->item.mask |= LVIF_DI_SETITEM;
            ISolutionItem *psiWeak = (ISolutionItem *)lvi.lParam;
            switch (_ColumnIDFromListViewIndex(pnmlvdi->item.iSubItem))
            {
            case COLID_NAME:
                if (_fCompressNameAndPath)
                {
                    WCHAR szName[MAX_PATH];
                    if (SUCCEEDED(psiWeak->GetName(szName, ARRAYSIZE(szName))))
                    {
                        WCHAR szPath[MAX_PATH];
                        if (SUCCEEDED(psiWeak->GetPath(szPath, ARRAYSIZE(szPath))))
                        {
                            StringCchPrintf(pnmlvdi->item.pszText, pnmlvdi->item.cchTextMax, L"%s (%s)", szName, szPath);
                        }
                    }
                }
                else
                {
                    psiWeak->GetName(pnmlvdi->item.pszText, pnmlvdi->item.cchTextMax);
                }
                break;
            case COLID_PATH:
                psiWeak->GetPath(pnmlvdi->item.pszText, pnmlvdi->item.cchTextMax);
                break;
            case COLID_SIZE:
                LARGE_INTEGER cb;
                if (SUCCEEDED(psiWeak->GetSize(&cb)))
                {
                    StrFormatByteSize(cb.QuadPart, pnmlvdi->item.pszText, pnmlvdi->item.cchTextMax);
                }
                else
                {
                    pnmlvdi->item.pszText[0] = 0;
                }
                break;

            case COLID_MODIFIEDDATE:
                FILETIME ft;
                if (SUCCEEDED(psiWeak->GetModified(&ft)))
                {
                    SYSTEMTIME st;
                    if (FileTimeToSystemTime(&ft, &st))
                    {
                        DATE dt;
                        if(SystemTimeToVariantTime(&st, &dt))
                        {
                            CComBSTR sbstrLastModified;
                            VarBstrFromDate(dt, GetThreadLocale(), 0, &sbstrLastModified);
                            if (sbstrLastModified)
                            {
                                StringCchCopy(pnmlvdi->item.pszText, pnmlvdi->item.cchTextMax, sbstrLastModified);
                            }
                        }
                    }
                }
                break;

            default:
                pnmlvdi->item.pszText[0] = 0;
                break;
            }
        }
    }
    fHandled = TRUE;
    return 0;
}

HRESULT _WriteSortInfoToRegistry()
{
    CRegKey rk;
    HRESULT hr = AtlHresultFromWin32(rk.Create(HKEY_CURRENT_USER, c_szRegRoot));
    if (SUCCEEDED(hr))
    {
        hr = AtlHresultFromWin32(rk.SetDWORDValue(L"SortColumn", (DWORD)_colidSort));
        if (SUCCEEDED(hr))
        {
            hr = AtlHresultFromWin32(rk.SetDWORDValue(L"SortAscending", (DWORD)_fSortAscending));
        }
    }
    return hr;
}

HRESULT _SetSortColumn(COLUMNID colid, int iIndex)
{
    HRESULT hr = S_OK;
    BOOL fSortAscending = TRUE;
    if (colid == _colidSort)
    {
        fSortAscending = !_fSortAscending;
    }
    else
    {
        int iIndexCur = _ListViewIndexFromColumnID(_colidSort);
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
            _colidSort = colid;
            _fSortAscending = fSortAscending;

            _WriteSortInfoToRegistry();

            hr = _RefreshFileList();
        }
    }
    return hr;
}

LRESULT _OnFileListColumnClick(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
{
    NMLISTVIEW *pnmlv = (NMLISTVIEW *)pnmh;
    _SetSortColumn(_ColumnIDFromListViewIndex(pnmlv->iSubItem), pnmlv->iSubItem);
    fHandled = TRUE;
    return 0;
}

LRESULT _OnFileListDeleteItem(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
{
    NMLISTVIEW *pnmlv = (NMLISTVIEW *)pnmh;
    ISolutionItem *psi = (ISolutionItem *)pnmlv->lParam;
    psi->Release();
    fHandled = TRUE;
    return 0;
}

HRESULT _OpenSolutionItem(int iIndex)
{
    LVITEM lvi = {0};
    lvi.mask = LVIF_PARAM;
    lvi.iItem = iIndex;
    HRESULT hr = _wndFileList.SendMessage(LVM_GETITEM, 0, (LPARAM)&lvi) ? S_OK : E_FAIL;
    if (SUCCEEDED(hr))
    {
        ISolutionItem *psiWeak = (ISolutionItem *)lvi.lParam;
        WCHAR szFullPath[MAX_PATH];
        hr = psiWeak->GetFullPath(szFullPath, ARRAYSIZE(szFullPath));
        if (SUCCEEDED(hr))
        {
            hr = _OpenSolutionItem(szFullPath);
        }
    }
    return hr;
}

LRESULT _OnFileListDblClick(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
{
    NMITEMACTIVATE *pnmitem = (NMITEMACTIVATE*) pnmh;
    if (FAILED(_OpenSolutionItem(pnmitem->iItem)))
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
    NMLVCUSTOMDRAW *pnmlvcd = (NMLVCUSTOMDRAW *)pnmh;
    switch (pnmlvcd->nmcd.dwDrawStage)
    {
    case CDDS_PREPAINT:
        _SetAlternateRowColor();
        lRet = CDRF_NOTIFYITEMDRAW;
        break;

    case CDDS_ITEMPREPAINT:
        {
            // Override the colors so that regardless of the focus state, the control appears focused.
            // We can't rely on the pnmlvcd->nmcd.uItemState for this because there is a known bug
            // with listviews that have the LVS_EX_SHOWSELALWAYS style where this bit is set for
            // every item
            LVITEM lvi;
            lvi.mask = LVIF_STATE;
            lvi.iItem = (int)pnmlvcd->nmcd.dwItemSpec;
            lvi.stateMask = LVIS_SELECTED;
            if (_wndFileList.SendMessage(LVM_GETITEM, 0, (LPARAM)&lvi) && lvi.state & LVIS_SELECTED)
            {
                pnmlvcd->clrText = GetSysColor(COLOR_HIGHLIGHTTEXT);
                pnmlvcd->clrTextBk = GetSysColor(COLOR_HIGHLIGHT);
                pnmlvcd->nmcd.uItemState &= ~CDIS_SELECTED;
                lRet = CDRF_NEWFONT;
            }
            else
            {
                if (_fAlternateRowColor && !(pnmlvcd->nmcd.dwItemSpec % 2))
                {
                    // TODO: Eventually, it might be nice to build a color based on COLOR_HIGHLIGHT.
                    pnmlvcd->clrTextBk = _crAlternate;
                    pnmlvcd->nmcd.uItemState &= ~CDIS_SELECTED;
                    lRet = CDRF_NEWFONT;
                }
            }
        }
        break;

    default:
        break;

    }
    fHandled = TRUE;
    return lRet;
}

LRESULT _OnFileListHdrItemChanged(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
{
    NMHEADER *pnmhdr = (NMHEADER *)pnmh;
    if (pnmhdr->pitem->mask & HDI_WIDTH) 
    {
        COLUMNID colid = _ColumnIDFromListViewIndex(pnmhdr->iItem);
        if (colid == COLID_NAME && _fCompressNameAndPath)
        {
            // Get the size delta and distrubute it between the name and path columns
            COLUMNINFO *pciName = _ColumnInfoFromColumnID(COLID_NAME);
            COLUMNINFO *pciPath = _ColumnInfoFromColumnID(COLID_PATH);

            int cxTotal = pciName->cx + pciPath->cx;
            int cxDelta = pnmhdr->pitem->cxy - cxTotal;
            int iPercentChange = MulDiv(100, cxDelta, cxTotal);
            int cxNameDelta = MulDiv(abs(cxDelta), iPercentChange, 100);
            int cxPathDelta = cxDelta - cxNameDelta;
            pciName->cx += cxNameDelta;
            pciPath->cx += cxPathDelta;
        }
        else
        {
            COLUMNINFO *pci = _ColumnInfoFromColumnID(colid);
            pci->cx = pnmhdr->pitem->cxy;
        }
        _WriteColumnInfoToRegistry();
    }

    fHandled = TRUE;
    return 0;
}

LRESULT _OnToolbarGetInfoTip(int idCtrl, ref NMHDR *pnmh, ref BOOL fHandled)
{
    NMTBGETINFOTIP *pnmtbgit = (NMTBGETINFOTIP *)pnmh;
    LoadString(_AtlBaseModule.GetResourceInstance(), pnmtbgit->iItem, pnmtbgit->pszText, pnmtbgit->cchTextMax);
    fHandled = TRUE;
    return 0;
}
+/

}

class ISolutionItem
{
}

class ISolutionItemGroup
{
}
