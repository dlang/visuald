// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.oledatasource;

import core.stdc.string : memcmp, memset, memcpy;

import visuald.windows;
import sdk.win32.objbase;
import sdk.win32.objidl;

import visuald.comutil;
import visuald.hierutil;
import visuald.logutil;

extern(Windows)
{
	void ReleaseStgMedium(in STGMEDIUM* medium);
}

struct VX_DATACACHE_ENTRY
{
    FORMATETC m_formatEtc;
    STGMEDIUM m_stgMedium;
    DATADIR m_nDataDir;
};

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
class OleDataSource : DComObject, IDataObject
{
	VX_DATACACHE_ENTRY[] mCache;
	IDataAdviseHolder mDataAdviseHolder;
	
	~this()
	{
		// free the clipboard data cache
		Empty();
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(IDataObject) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}
	
	//---------------------------------------------------------------------------
	void Empty()
	{
		// release all of the STGMEDIUMs and FORMATETCs
		for (UINT nIndex = 0; nIndex < mCache.length; nIndex++)
        {
            CoTaskMemFree(mCache[nIndex].m_formatEtc.ptd);
            .ReleaseStgMedium(&mCache[nIndex].m_stgMedium);
        }
        mCache.length = 0;
		mDataAdviseHolder = release(mDataAdviseHolder);
    }

/+
	/////////////////////////////////////////////////////////////////////////////
	// OleDataSource clipboard API wrappers
	void SetClipboard(void)
	{
		// attempt OLE set clipboard operation
		SCODE sc = ::OleSetClipboard(this);
		ASSERT(S_OK == sc);
		sc;

		// success - set as current clipboard source
		//  _afxOleState.m_pClipboardSource = this;
		ASSERT(::OleIsCurrentClipboard(this) == S_OK);
	}

	void PASCAL OleDataSource::FlushClipboard()
	{
		if (GetClipboardOwner() != null)
		{
			// active clipboard source and it is on the clipboard - flush it
			::OleFlushClipboard();

			// shouldn't be clipboard owner any more...
			ASSERT(GetClipboardOwner() == null);
		}
	}

	#if 0
	OleDataSource* PASCAL OleDataSource::GetClipboardOwner()
	{
		_AFX_OLE_STATE* pOleState = _afxOleState;
		if (pOleState.m_pClipboardSource == null)
			return null;    // can't own the clipboard if pClipboardSource isn't set

		ASSERT_VALID(pOleState.m_pClipboardSource);
		LPDATAOBJECT lpDataObject = (LPDATAOBJECT)
			pOleState.m_pClipboardSource.GetInterface(&IID_IDataObject);
		if (::OleIsCurrentClipboard(lpDataObject) != S_OK)
		{
			pOleState.m_pClipboardSource = null;
			return null;    // don't own the clipboard anymore
		}

		// return current clipboard sourcew
		return pOleState.m_pClipboardSource;
	}
	#endif
+/
	
	/////////////////////////////////////////////////////////////////////////////
	// OleDataSource cache allocation

	VX_DATACACHE_ENTRY* GetCacheEntry(FORMATETC* lpFormatEtc, DATADIR nDataDir)
	{
		VX_DATACACHE_ENTRY* pEntry = Lookup(lpFormatEtc, nDataDir);
		if (pEntry)
		{
			// cleanup current entry and return it
			CoTaskMemFree(pEntry.m_formatEtc.ptd);
			.ReleaseStgMedium(&pEntry.m_stgMedium);
		}
		else
		{
			// allocate space for item at m_nSize (at least room for 1 item)
			mCache.length = mCache.length + 1;
			pEntry = &mCache[$-1];
		}

		// fill the cache entry with the format and data direction and return it
		pEntry.m_nDataDir = nDataDir;
		pEntry.m_formatEtc = *lpFormatEtc;
		return pEntry;
	}

	/////////////////////////////////////////////////////////////////////////////
	// OleDataSource operations

	// for HGLOBAL based cached render
	void CacheGlobalData(CLIPFORMAT cfFormat, HGLOBAL hGlobal, FORMATETC* lpFormatEtc)
	{
		// fill in FORMATETC struct
		FORMATETC formatEtc;
		lpFormatEtc = _FillFormatEtc(lpFormatEtc, cfFormat, &formatEtc);
		assert(lpFormatEtc);
		if(!lpFormatEtc)
			return;
		
		lpFormatEtc.tymed = TYMED_HGLOBAL;

		// add it to the cache
		VX_DATACACHE_ENTRY* pEntry = GetCacheEntry(lpFormatEtc, DATADIR_GET);
		pEntry.m_stgMedium.tymed = TYMED_HGLOBAL;
		pEntry.m_stgMedium.hGlobal = hGlobal;
		pEntry.m_stgMedium.pUnkForRelease = null;
	}

	// for raw STGMEDIUM* cached render
	void CacheData(CLIPFORMAT cfFormat, STGMEDIUM* lpStgMedium, FORMATETC* lpFormatEtc)
	{
		// fill in FORMATETC struct
		FORMATETC formatEtc;
		lpFormatEtc = _FillFormatEtc(lpFormatEtc, cfFormat, &formatEtc);

		// Only these TYMED_GDI formats can be copied, so can't serve as
		//  cache content (you must use DelayRenderData instead)
		// When using COleServerItem::CopyToClipboard this means providing an
		//  override of COleServerItem::OnGetClipboardData to provide a custom
		//  delayed rendering clipboard object.
		assert(lpStgMedium.tymed != TYMED_GDI ||
				lpFormatEtc.cfFormat == CF_METAFILEPICT ||
				lpFormatEtc.cfFormat == CF_PALETTE ||
				lpFormatEtc.cfFormat == CF_BITMAP);
		lpFormatEtc.tymed = lpStgMedium.tymed;

		// add it to the cache
		VX_DATACACHE_ENTRY* pEntry = GetCacheEntry(lpFormatEtc, DATADIR_GET);
		pEntry.m_stgMedium = *lpStgMedium;
	}

	// for STGMEDIUM* or HGLOBAL based delayed render
	void DelayRenderData(CLIPFORMAT cfFormat, FORMATETC* lpFormatEtc)
	{
		// fill in FORMATETC struct
		FORMATETC formatEtc;
		if (lpFormatEtc is null)
		{
			lpFormatEtc = _FillFormatEtc(lpFormatEtc, cfFormat, &formatEtc);
			lpFormatEtc.tymed = TYMED_HGLOBAL;
		}
		// insure that cfFormat member is set
		if (cfFormat != 0)
			lpFormatEtc.cfFormat = cfFormat;

		// add it to the cache
		VX_DATACACHE_ENTRY* pEntry = GetCacheEntry(lpFormatEtc, DATADIR_GET);
		pEntry.m_stgMedium = pEntry.m_stgMedium;
	}

	//---------------------------------------------------------------------------
	// DelaySetData -- used to allow SetData on given FORMATETC*
	//---------------------------------------------------------------------------
	void DelaySetData(CLIPFORMAT cfFormat, FORMATETC* lpFormatEtc)
	{
		// fill in FORMATETC struct
		FORMATETC formatEtc;
		lpFormatEtc = _FillFormatEtc(lpFormatEtc, cfFormat, &formatEtc);

		// add it to the cache
		VX_DATACACHE_ENTRY* pEntry = GetCacheEntry(lpFormatEtc, DATADIR_SET);
		pEntry.m_stgMedium.tymed = TYMED_NULL;
		pEntry.m_stgMedium.hGlobal = null;
		pEntry.m_stgMedium.pUnkForRelease = null;
	}

	/////////////////////////////////////////////////////////////////////////////
	// OleDataSource cache implementation
	VX_DATACACHE_ENTRY* Lookup(in FORMATETC* lpFormatEtc, DATADIR nDataDir)
	{
		VX_DATACACHE_ENTRY* pLast = null;
		// look for suitable match to lpFormatEtc in cache
		for (UINT nIndex = 0; nIndex < mCache.length; nIndex++)
		{
			// get entry from cache at nIndex
			VX_DATACACHE_ENTRY* pCache = &mCache[nIndex];
			FORMATETC *pCacheFormat = &pCache.m_formatEtc;

			// check for match
			if (pCacheFormat.cfFormat == lpFormatEtc.cfFormat &&
				(pCacheFormat.tymed & lpFormatEtc.tymed) != 0 &&
				pCacheFormat.lindex == lpFormatEtc.lindex &&
				pCacheFormat.dwAspect == lpFormatEtc.dwAspect &&
				pCache.m_nDataDir == nDataDir)
			{
				// for backward compatibility we match even if we never
				// find an exact match for the DVTARGETDEVICE
				const(DVTARGETDEVICE)* ptd1 = pCacheFormat.ptd;
				const(DVTARGETDEVICE)* ptd2 = lpFormatEtc.ptd;
				pLast = pCache;
				if(((ptd1 is null) && (ptd2 is null)) ||
				   ((ptd1 !is null) && (ptd2 !is null) &&
				    (ptd1.tdSize == ptd2.tdSize) &&
				    (memcmp(ptd1, ptd2, ptd1.tdSize)==0)
				   ))
				{
					// exact match, so break now and return it
					break;
				}
				// continue looking for better match
			}
		}
		return pLast;
	}

	/////////////////////////////////////////////////////////////////////////////
	// OleDataSource overidable default implementation
	BOOL OnRenderGlobalData(in FORMATETC* lpFormatEtc, HGLOBAL* phGlobal)
	{
		return FALSE;   // default does nothing
	}

	/+
	//---------------------------------------------------------------------------
	BOOL OnRenderFileData(FORMATETC* lpFormatEtc, CVsFile* /*pFile*/)
	{
		return FALSE;   // default does nothing
	}
	+/

	//---------------------------------------------------------------------------
	BOOL OnRenderData(in FORMATETC* lpFormatEtc, STGMEDIUM* lpStgMedium)
	{
		// attempt TYMED_HGLOBAL as prefered format
		if (lpFormatEtc.tymed & TYMED_HGLOBAL)
		{
			// attempt HGLOBAL delay render hook
			HGLOBAL hGlobal = lpStgMedium.hGlobal;
			if (OnRenderGlobalData(lpFormatEtc, &hGlobal))
			{
				assert(lpStgMedium.tymed != TYMED_HGLOBAL || (lpStgMedium.hGlobal == hGlobal));
				assert(hGlobal != null);
				lpStgMedium.tymed = TYMED_HGLOBAL;
				lpStgMedium.hGlobal = hGlobal;
				return TRUE;
			}

/+
			// attempt CVsFile* based delay render hook
			CVsSharedFile file;
			if (lpStgMedium.tymed == TYMED_HGLOBAL)
			{
				ASSERT(lpStgMedium.hGlobal != null);
				file.SetHandle(lpStgMedium.hGlobal, FALSE);
			}
			if (OnRenderFileData(lpFormatEtc, &file))
			{
				lpStgMedium.tymed = TYMED_HGLOBAL;
				lpStgMedium.hGlobal = file.Detach();
				ASSERT(lpStgMedium.hGlobal != null);
				return TRUE;
			}
			if (lpStgMedium.tymed == TYMED_HGLOBAL)
				file.Detach();
+/
		}

/+
    // attempt TYMED_ISTREAM format
    if (lpFormatEtc.tymed & TYMED_ISTREAM)
    {
        ASSERT(!_T("port COleStreamFile"));
#if 0
        COleStreamFile file;
        if (lpStgMedium.tymed == TYMED_ISTREAM)
        {
            ASSERT(lpStgMedium.pstm != null);
            file.Attach(lpStgMedium.pstm);
        }
        else
        {
            if (!file.CreateMemoryStream())
                return FALSE;

        }
        // get data into the stream
        if (OnRenderFileData(lpFormatEtc, &file))
        {
            lpStgMedium.tymed = TYMED_ISTREAM;
            lpStgMedium.pstm = file.Detach();
            return TRUE;
        }
        if (lpStgMedium.tymed == TYMED_ISTREAM)
            file.Detach();
#endif //0
    }
+/
		
		return FALSE;   // default does nothing
	}

	//---------------------------------------------------------------------------
	BOOL OnSetData(in FORMATETC* lpFormatEtc, in STGMEDIUM* lpStgMedium, BOOL bRelease)
	{
		return FALSE;   // default does nothing
	}

	//---------------------------------------------------------------------------
	override HRESULT GetData(/* [unique][in] */ in FORMATETC *pformatetcIn,
					/* [out] */ STGMEDIUM *pmedium)
	{
		mixin(LogCallMix2);

		// attempt to find match in the cache
		VX_DATACACHE_ENTRY* pCache = Lookup(pformatetcIn, DATADIR_GET);
		if (!pCache)
			return DV_E_FORMATETC;

		// use cache if entry is not delay render
		memset(pmedium, 0, STGMEDIUM.sizeof);
		if (pCache.m_stgMedium.tymed != TYMED_NULL)
		{
			// Copy the cached medium into the lpStgMedium provided by caller.
			if (!_CopyStgMedium(pformatetcIn.cfFormat, pmedium, &pCache.m_stgMedium))
				return DV_E_FORMATETC;

			// format was supported for copying
			return S_OK;
		}

		SCODE sc = DV_E_FORMATETC;

		// attempt STGMEDIUM* based delay render
		if (OnRenderData(pformatetcIn, pmedium))
			sc = S_OK;
		return sc;
	}

	//---------------------------------------------------------------------------
	override HRESULT GetDataHere(/* [unique][in] */ in FORMATETC *pformatetc,
	                             /* [out][in] */ STGMEDIUM *pmedium)
	{
		mixin(LogCallMix2);

		// these two must be the same
		assert(pformatetc.tymed == pmedium.tymed);
		// pformatetc.tymed = pmedium.tymed;    // but just in case...

		// attempt to find match in the cache
		VX_DATACACHE_ENTRY* pCache = Lookup(pformatetc, DATADIR_GET);
		if (!pCache)
			return DV_E_FORMATETC;

		// handle cached medium and copy
		if (pCache.m_stgMedium.tymed != TYMED_NULL)
		{
			// found a cached format -- copy it to dest medium
			assert(pCache.m_stgMedium.tymed == pmedium.tymed);
			if (!_CopyStgMedium(pformatetc.cfFormat, pmedium, &pCache.m_stgMedium))
				return DV_E_FORMATETC;

			// format was supported for copying
			return S_OK;
		}

		SCODE sc = DV_E_FORMATETC;
		// attempt pmedium based delay render
		if (OnRenderData(pformatetc, pmedium))
			sc = S_OK;
		return sc;
	}

	//---------------------------------------------------------------------------
	override HRESULT QueryGetData(/* [unique][in] */ in FORMATETC *pformatetc)
	{
		mixin(LogCallMix2);

		// attempt to find match in the cache
		VX_DATACACHE_ENTRY* pCache = Lookup(pformatetc, DATADIR_GET);
		if (!pCache)
			return DV_E_FORMATETC;

		// it was found in the cache or can be rendered -- success
		return S_OK;
	}

	//---------------------------------------------------------------------------
	override HRESULT GetCanonicalFormatEtc(/* [unique][in] */ in FORMATETC *pformatectIn,
	                                       /* [out] */ FORMATETC *pformatetcOut)
	{
		mixin(LogCallMix2);

		// because we support the target-device (ptd) for server metafile format,
		//  all members of the FORMATETC are significant.
		return DATA_S_SAMEFORMATETC;
	}

	//---------------------------------------------------------------------------
	override HRESULT SetData(/* [unique][in] */ in FORMATETC *pformatetc,
	                         /* [unique][in] */ in STGMEDIUM *pmedium,
	                         /* [in] */ in BOOL fRelease)
	{
		mixin(LogCallMix2);

		assert(pformatetc.tymed == pmedium.tymed);

		// attempt to find match in the cache
		VX_DATACACHE_ENTRY* pCache = Lookup(pformatetc, DATADIR_SET);
		if (!pCache)
			return DV_E_FORMATETC;

		assert(pCache.m_stgMedium.tymed == TYMED_NULL);

		SCODE sc = E_UNEXPECTED;

		// attempt pmedium based SetData
		if (OnSetData(pformatetc, pmedium, fRelease))
			sc = S_OK;
		return sc;
	}

	//---------------------------------------------------------------------------
	override HRESULT EnumFormatEtc(/* [in] */ in DWORD dwDirection,
						  /* [out] */ IEnumFORMATETC *ppenumFormatEtc)
	{
		mixin(LogCallMix2);

		*ppenumFormatEtc = null;

		// generate a format list from the cache
		CEnumFormatEtc pFormatList = newCom!CEnumFormatEtc(this, dwDirection);
		*ppenumFormatEtc = addref(pFormatList);
		return S_OK;
	}

	//---------------------------------------------------------------------------
	override HRESULT DAdvise(/* [in] */ in FORMATETC *pformatetc,
	                         /* [in] */ in DWORD advf,
	                         /* [unique][in] */ IAdviseSink pAdvSink,
	                         /* [out] */ DWORD *pdwConnection)
	{
		mixin(LogCallMix2);

		HRESULT hr = S_OK;
		if (!mDataAdviseHolder)
			hr = CreateDataAdviseHolder(&mDataAdviseHolder);

		if (hr == S_OK)
			hr = mDataAdviseHolder.Advise(this, pformatetc, advf, pAdvSink, pdwConnection);

		return hr;
	}

	//---------------------------------------------------------------------------
	override HRESULT DUnadvise(/* [in] */ in DWORD dwConnection)
	{
		mixin(LogCallMix2);

		HRESULT hr = OLE_E_NOCONNECTION;
		if (mDataAdviseHolder)
			hr = mDataAdviseHolder.Unadvise(dwConnection);
		return hr;
	}

	//---------------------------------------------------------------------------
	override HRESULT EnumDAdvise(/* [out] */ IEnumSTATDATA *ppenumAdvise)
	{
		mixin(LogCallMix2);

		HRESULT hr = E_FAIL;
		if (mDataAdviseHolder)
			hr = mDataAdviseHolder.EnumAdvise(ppenumAdvise);
		return hr;
	}
}

//---------------------------------------------------------------------------
class CEnumFormatEtc : DComObject, IEnumFORMATETC
{
	this(OleDataSource src, DWORD dwDirection)
	{
		mSrc = src;
		mDirection = dwDirection;
		mPos = 0;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IEnumFORMATETC) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	bool findValid()
	{
		while(mPos < mSrc.mCache.length)
		{
			if(mSrc.mCache[mPos].m_nDataDir & mDirection)
				return true;
			mPos++;
		}
		return false;
	}
	
	override HRESULT Next(in ULONG celt,
	    /+[out, size_is(celt), length_is(*pceltFetched )]+/ FORMATETC *rgelt,
	    /+[out]+/ ULONG *pceltFetched)
	{
		uint i;
		for(i = 0; i < celt; i++)
			if(findValid())
				rgelt[i] = mSrc.mCache[mPos++].m_formatEtc;
			else
				break;
		if(pceltFetched)
			*pceltFetched = i;
		return i < celt ? S_FALSE : S_OK;
	}

	override HRESULT Skip(in ULONG celt)
	{
		for(uint i = 0; i < celt; i++)
			if(findValid())
				mPos++;
			else
				return E_FAIL;
		return S_OK;
	}

    override HRESULT Reset()
	{
		mPos = 0;
		return S_OK;
	}

    override HRESULT Clone(/+[out]+/ IEnumFORMATETC *ppenum)
	{
		*ppenum = addref(newCom!CEnumFormatEtc(mSrc, mDirection));
		return S_OK;
	}
	
	OleDataSource mSrc;
	int mPos;
	DWORD mDirection;
}
	
//---------------------------------------------------------------------------
HGLOBAL CopyGlobalMemory(HGLOBAL hDest, HGLOBAL hSource)
{
    assert(hSource);

    // make sure we have suitable hDest
    uint nSize = GlobalSize(hSource);
    assert(nSize < int.max);
    
	if (!hDest)
    {
        hDest = GlobalAlloc(GMEM_SHARE|GMEM_MOVEABLE, nSize);
        if (!hDest)
            return null;
    }
    else if (nSize > GlobalSize(hDest))
    {
        // hDest is not large enough
        return null;
    }

    // copy the bits
    LPVOID lpSource = GlobalLock(hSource);
    LPVOID lpDest = GlobalLock(hDest);
    assert(lpDest && lpSource);
    memcpy(lpDest, lpSource, nSize);
    GlobalUnlock(hDest);
    GlobalUnlock(hSource);

    // success -- return hDest
    return hDest;
}

//---------------------------------------------------------------------------
//---------------------------------------------------------------------------
BOOL _CopyStgMedium(CLIPFORMAT cfFormat, STGMEDIUM* lpDest, STGMEDIUM* lpSource)
{
    if (lpDest.tymed == TYMED_NULL)
    {
        assert(lpSource.tymed != TYMED_NULL);
        switch (lpSource.tymed)
        {
        case TYMED_ENHMF:
        case TYMED_HGLOBAL:
            assert(HGLOBAL.sizeof == HENHMETAFILE.sizeof);
            lpDest.tymed = lpSource.tymed;
            lpDest.hGlobal = null;
            break;  // fall through to CopyGlobalMemory case

        case TYMED_ISTREAM:
            lpDest.pstm = lpSource.pstm;
            lpDest.pstm.AddRef();
            lpDest.tymed = TYMED_ISTREAM;
            return TRUE;

        case TYMED_ISTORAGE:
            lpDest.pstg = lpSource.pstg;
            lpDest.pstg.AddRef();
            lpDest.tymed = TYMED_ISTORAGE;
            return TRUE;

/+
        case TYMED_MFPICT:
            {
                // copy LPMETAFILEPICT struct + embedded HMETAFILE
                HGLOBAL hDest = CopyGlobalMemory(null, lpSource.hGlobal);
                if (hDest == null)
                    return FALSE;
                LPMETAFILEPICT lpPict = cast(LPMETAFILEPICT)GlobalLock(hDest);
                ASSERT(lpPict != null);
                lpPict.hMF = CopyMetaFile(lpPict.hMF, null);
                if (lpPict.hMF == null)
                {
                    GlobalUnlock(hDest);
                    GlobalFree(hDest);
                    return FALSE;
                }
                GlobalUnlock(hDest);

                // fill STGMEDIUM struct
                lpDest.hGlobal = hDest;
                lpDest.tymed = TYMED_MFPICT;
            }
            return TRUE;

        case TYMED_GDI:
            lpDest.tymed = TYMED_GDI;
            lpDest.hGlobal = null;
            break;

        case TYMED_FILE:
            {
                USES_CONVERSION;
                lpDest.tymed = TYMED_FILE;
                ASSERT(lpSource.lpszFileName != null);
                UINT cbSrc = ocslen(lpSource.lpszFileName);
                LPOLESTR szFileName = cast(LPOLESTR)CoTaskMemAlloc((cbSrc+1)*sizeof(OLECHAR));
                lpDest.lpszFileName = szFileName;
                if (szFileName == null)
                    return FALSE;
                memcpy(szFileName, lpSource.lpszFileName,  (cbSrc+1)*sizeof(OLECHAR));
                return TRUE;
            }
+/
        // unable to create + copy other TYMEDs
        default:
            return FALSE;
        }
    }
    assert(lpDest.tymed == lpSource.tymed);

    switch (lpSource.tymed)
    {
    case TYMED_HGLOBAL:
        {
            HGLOBAL hDest = CopyGlobalMemory(lpDest.hGlobal, lpSource.hGlobal);
            if (hDest == null)
                return FALSE;

            lpDest.hGlobal = hDest;
        }
        return TRUE;

/+
    case TYMED_ISTREAM:
        {
            ASSERT(lpDest.pstm != null);
            ASSERT(lpSource.pstm != null);

            // get the size of the source stream
            STATSTG stat;
            if (lpSource.pstm.Stat(&stat, STATFLAG_NONAME) != S_OK)
            {
                // unable to get size of source stream
                return FALSE;
            }
            ASSERT(stat.pwcsName == null);

            // always seek to zero before copy
            LARGE_INTEGER zero = { 0, 0 };
            lpDest.pstm.Seek(zero, STREAM_SEEK_SET, null);
            lpSource.pstm.Seek(zero, STREAM_SEEK_SET, null);

            // copy source to destination
            if (lpSource.pstm.CopyTo(lpDest.pstm, stat.cbSize,
                null, null) != null)
            {
                // copy from source to dest failed
                return FALSE;
            }

            // always seek to zero after copy
            lpDest.pstm.Seek(zero, STREAM_SEEK_SET, null);
            lpSource.pstm.Seek(zero, STREAM_SEEK_SET, null);
        }
        return TRUE;

    case TYMED_ISTORAGE:
        {
            ASSERT(lpDest.pstg != null);
            ASSERT(lpSource.pstg != null);

            // just copy source to destination
            if (lpSource.pstg.CopyTo(0, null, null, lpDest.pstg) != S_OK)
                return FALSE;
        }
        return TRUE;

    case TYMED_FILE:
        {
            USES_CONVERSION;
            ASSERT(lpSource.lpszFileName != null);
            ASSERT(lpDest.lpszFileName != null);
            return CopyFile(OLE2T(lpSource.lpszFileName), OLE2T(lpDest.lpszFileName), FALSE);
        }


    case TYMED_ENHMF:
    case TYMED_GDI:
        {
            ASSERT(sizeof(HGLOBAL) == sizeof(HENHMETAFILE));

            // with TYMED_GDI cannot copy into existing HANDLE
            if (lpDest.hGlobal != null)
                return FALSE;

            // otherwise, use OleDuplicateData for the copy
            lpDest.hGlobal = OleDuplicateData(lpSource.hGlobal, cfFormat, 0);
            if (lpDest.hGlobal == null)
                return FALSE;
        }
        return TRUE;
+/
    // other TYMEDs cannot be copied
    default:
        return FALSE;
    }
}

//---------------------------------------------------------------------------
// Helper for creating default FORMATETC from cfFormat
//---------------------------------------------------------------------------
FORMATETC* _FillFormatEtc(FORMATETC* lpFormatEtc, CLIPFORMAT cfFormat, FORMATETC* lpFormatEtcFill)
{
	if (lpFormatEtc is null && cfFormat != 0)
	{
		lpFormatEtc = lpFormatEtcFill;
		lpFormatEtc.cfFormat = cfFormat;
		lpFormatEtc.ptd = null;
		lpFormatEtc.dwAspect = DVASPECT_CONTENT;
		lpFormatEtc.lindex = -1;
		lpFormatEtc.tymed = -1;
	}
	return lpFormatEtc;
}
	
