// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.library;

import visuald.comutil;
import visuald.logutil;
import visuald.hierutil;
import visuald.dpackage;
import visuald.dimagelist;
import visuald.intellisense;

import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.win32.commctrl;

import std.json;
import std.conv;
import std.string;

class LibraryManager : DComObject, IVsLibraryMgr
{
	Library[] mLibraries;

	///////////////////////////
	this()
	{
		mLibraries ~= newCom!Library;
	}

	~this()
	{
		Close();
	}
	
	HRESULT Close()
	{
		foreach(lib; mLibraries)
			lib.Close();
		mLibraries = mLibraries.init;
		return S_OK;
	}

	bool IsValidIndex(uint uIndex)
	{
		return uIndex < mLibraries.length;
	}

	//==========================================================================
	// IVsLibraryMgr

	HRESULT GetCount(ULONG *pnCount)
	{
		mixin(LogCallMix2);
		
		if(!pnCount)
			return E_INVALIDARG;

		*pnCount = mLibraries.length;
		return S_OK;
	}

	HRESULT GetLibraryAt(in ULONG uIndex, IVsLibrary *pLibrary)
	{
		mixin(LogCallMix);
		
		if(!pLibrary)
			return E_INVALIDARG;
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		return mLibraries[uIndex].QueryInterface(&IID_IVsLibrary, cast(void**) pLibrary);
	}

	HRESULT GetNameAt(in ULONG uIndex, WCHAR ** pszName)
	{
		mixin(LogCallMix2);
		
		if(!pszName)
			return E_INVALIDARG;
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		return mLibraries[uIndex].GetName(pszName);
	}

	HRESULT ToggleCheckAt(in ULONG uIndex)
	{
		mixin(LogCallMix2);
		
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		mLibraries[uIndex].ToggleCheck();  
		return S_OK;
	}

	HRESULT GetCheckAt(in ULONG uIndex, LIB_CHECKSTATE *pstate)
	{
		mixin(LogCallMix2);
		
		if(!pstate)
			return E_INVALIDARG;
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		return mLibraries[uIndex].GetCheckState(pstate);
	}

	HRESULT SetLibraryGroupEnabled(in LIB_PERSISTTYPE lpt, in BOOL fEnable)
	{
		mixin(LogCallMix2);
		
		return E_NOTIMPL;
	}

}

class Library : DComObject,
                IVsSimpleLibrary2,
                IVsLiteTreeList,
                //IBrowseDataProviderImpl,
                //IBrowseDataProviderEvents,
                IVsSolutionEvents
{
	string          mName = "D-Library";
	LIB_CHECKSTATE  mCheckState;
	HIMAGELIST      mImages;   //image list.

	//Cookie used to hook up the solution events.
	VSCOOKIE        mIVsSolutionEventsCookie;  

	//Array of Projects
	LibraryItem[]   mLibraryItems;
	
	BrowseCounter   mCounterLibList;

	// Find References result
	string[]        mLastFindReferencesResult;
	
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(*riid == IVsLibrary2Ex.iid) // keep out of log file
			return E_NOINTERFACE;

		if(queryInterface!(IVsSimpleLibrary2) (this, riid, pvObject))
			return S_OK;
//		if(queryInterface!(IVsLiteTreeList) (this, riid, pvObject))
//			return S_OK;
		if(queryInterface!(IVsSolutionEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	HRESULT Initialize()
	{
		mixin(LogCallMix2);

		mCheckState = LCS_CHECKED;
		
		if(auto solution = queryService!IVsSolution())
		{
			scope(exit) release(solution);
			if(HRESULT hr = solution.AdviseSolutionEvents(this, &mIVsSolutionEventsCookie))
				return hr;
		}
		return S_OK;
	}
	
	HRESULT Close()
	{
		mixin(LogCallMix2);

		if(mIVsSolutionEventsCookie != 0)
			if(auto solution = queryService!IVsSolution())
			{
				scope(exit) release(solution);
				if(HRESULT hr = solution.UnadviseSolutionEvents(mIVsSolutionEventsCookie))
					return hr;
				mIVsSolutionEventsCookie = 0;	
			}
		
		foreach(lib; mLibraryItems)
		{
			lib.Close();
		}
		return S_OK;
	}

	// ILibrary
	//Return a displayable name for the designated library
	HRESULT GetName(WCHAR **pszName)
	{
		*pszName = allocBSTR(mName);
		return S_OK;
	}

	//Set the selected state for a library item
	HRESULT ToggleCheck()
	{
		mCheckState = mCheckState == LCS_CHECKED ? LCS_UNCHECKED : LCS_CHECKED;
		return S_OK;
	}

	//Get the selected state for a library item
	HRESULT GetCheckState(LIB_CHECKSTATE *pstate)
	{
		assert(pstate);
		*pstate = mCheckState;
		return S_OK;
	}

	HRESULT GetImageList(HANDLE *phImageList)
	{
		return E_NOTIMPL;
	}

	bool IsValidIndex(uint uIndex)
	{
		return uIndex < mLibraryItems.length;
	}

	HRESULT CountChecks(/* [out]  */ ULONG* pcChecked, /* [out]  */ ULONG* pcUnchecked) 
	{
		assert(pcChecked);
		assert(pcUnchecked);
		*pcChecked   = 0;
		*pcUnchecked = 0;

		foreach(lib; mLibraryItems)
		{
			LIB_CHECKSTATE lcs;
			lib.GetCheckState(&lcs);
			if (lcs == LCS_CHECKED)
				(*pcChecked)++;
			else if (lcs == LCS_UNCHECKED)
				(*pcUnchecked)++;
			else 
				assert(false); // check state is not correct
		}
		return S_OK; 
	}


	// IVsSimpleLibrary2 ////////////////////////////////////////////////////////
    //Return E_FAIL if category not supported.
    override HRESULT GetSupportedCategoryFields2(in LIB_CATEGORY2 eCategory, 
		/+[out, retval]+/ DWORD *pCatField)
	{
		mixin(LogCallMix2);
		
		assert(pCatField);

		switch(eCategory)
		{
			case LC_MEMBERTYPE:
				//  LCMT_METHOD   = 0x0001,
				//  LCMT_PROPERTY = 0x0002,
				//  LCMT_EVENT    = 0x0004,
				//  LCMT_FIELD    = 0x0008,
				//  LCMT_CONSTANT = 0x0010,
				//  LCMT_OPERATOR = 0x0020,
				//  LCMT_MAPITEM  = 0x0040,
				//  LCMT_VARIABLE = 0x0080,
				//  LCMT_ENUMITEM = 0x0100,
				//  LCMT_TYPEDEF  = 0x0200,
				//  LCMT_FUNCTION = 0x0400,
				*pCatField = LCMT_ENUMITEM | LCMT_FUNCTION | LCMT_VARIABLE | LCMT_TYPEDEF | LCMT_METHOD | LCMT_FIELD;
				break;

			case LC_MEMBERACCESS:
				//  LCMA_PUBLIC    = 0x0001,
				//  LCMA_PRIVATE   = 0x0002,
				//  LCMA_PROTECTED = 0x0004,
				//  LCMA_PACKAGE   = 0x0008,
				//  LCMA_FRIEND    = 0x0010,
				//  LCMA_SEALED    = 0x0020
				*pCatField = LCMA_PUBLIC; // not in JSON files
				break;

			case LC_CLASSTYPE:
				//  LCCT_CLASS     = 0x0001,
				//  LCCT_INTERFACE = 0x0002,
				//  LCCT_EXCEPTION = 0x0004,
				//  LCCT_STRUCT    = 0x0008,
				//  LCCT_ENUM      = 0x0010,
				//  LCCT_MODULE    = 0x0020,
				//  LCCT_UNION     = 0x0040,
				//  LCCT_INTRINSIC = 0x0080,
				//  LCCT_DELEGATE  = 0x0100,
				//  LCCT_TYPEDEF   = 0x0200,
				//  LCCT_MACRO     = 0x0400,
				//  LCCT_MAP       = 0x0800,
				//  LCCT_GLOBAL    = 0x1000,
				*pCatField = LCCT_CLASS | LCCT_INTERFACE | LCCT_STRUCT | LCCT_ENUM | LCCT_MODULE | LCCT_UNION;
				break;

			case LC_CLASSACCESS:
				//  LCCA_PUBLIC    = 0x0001,
				//  LCCA_PRIVATE   = 0x0002,
				//  LCCA_PROTECTED = 0x0004,
				//  LCCA_PACKAGE   = 0x0008,
				//  LCCA_FRIEND    = 0x0010,
				//  LCCA_SEALED    = 0x0020
				*pCatField = LCCA_PUBLIC; // not in JSON files
				break;

			case LC_ACTIVEPROJECT:
				//  LCAP_SHOWALWAYS   = 0x0001,
				//  LCAP_MUSTBEACTIVE = 0x0002,
				*pCatField = LCAP_SHOWALWAYS;
				break;

			case LC_LISTTYPE:
				//  LLT_CLASSES                 = 0x000001, 
				//  LLT_MEMBERS                 = 0x000002, 
				//  LLT_PHYSICALCONTAINERS      = 0x000004,     
				//  LLT_PACKAGE                 = 0x000004, same as above (old name)
				//  LLT_NAMESPACES              = 0x000008,
				//  LLT_CONTAINMENT             = 0x000010,
				//  LLT_CONTAINEDBY             = 0x000020,
				//  LLT_USESCLASSES             = 0x000040,
				//  LLT_USEDBYCLASSES           = 0x000080,
				//  LLT_NESTEDCLASSES           = 0x000100,
				//  LLT_INHERITEDINTERFACES     = 0x000200,
				//  LLT_INTERFACEUSEDBYCLASSES  = 0x000400,
				//  LLT_DEFINITIONS             = 0x000800,
				//  LLT_REFERENCES              = 0x001000,
				//  LLT_HIERARCHY               = 0x002000, 
				*pCatField = LLT_NAMESPACES | LLT_PACKAGE | LLT_CLASSES | LLT_MEMBERS;
				break;

			case LC_VISIBILITY:
				//  LCV_VISIBLE  = 0x0001,
				//  LCV_HIDDEN   = 0x0002,
				*pCatField = LCV_VISIBLE;
				break;

			case LC_MODIFIER:
				//  LCMDT_VIRTUAL       = 0x0001,
				//  LCMDT_PUREVIRTUAL   = 0x0002,
				//  LCMDT_NONVIRTUAL    = 0x0004,
				//  LCMDT_FINAL         = 0x0008,
				//  LCMDT_STATIC        = 0x0010,
				*pCatField = LCMDT_STATIC | LCMDT_FINAL;
				break;

			case LC_HIERARCHYTYPE:
				*pCatField = LCHT_BASESANDINTERFACES;
				break;
				
			case LC_NODETYPE:
			case LC_MEMBERINHERITANCE:
			case LC_SEARCHMATCHTYPE:
				
			default:
				*pCatField = 0;
				return E_FAIL;
		}

		return S_OK;
	}

	//Retrieve a IVsObjectList interface of LISTTYPE
	override HRESULT GetList2(in LIB_LISTTYPE2 eListType, in LIB_LISTFLAGS eFlags, in VSOBSEARCHCRITERIA2 *pobSrch, 
		/+[out, retval]+/ IVsSimpleObjectList2 *ppList)
	{
		mixin(LogCallMix2);

//		if (eFlags & LLF_USESEARCHFILTER)
//			return E_NOTIMPL;

		assert(ppList);
		if(pobSrch && to_tmpwstring(pobSrch.szName) == "Find All References"w) // (pobSrch.grfOptions & VSOBSO_LISTREFERENCES))
		{
			if (eListType != LLT_MEMBERS) // also called with LLT_NAMESPACES and LLT_CLASSES, so avoid duplicates
				return E_FAIL;
			auto frl = newCom!FindReferencesList(mLastFindReferencesResult);
			return frl.QueryInterface(&IVsSimpleObjectList2.iid, cast(void**) ppList);
		}
		else
		{
			auto ol = newCom!ObjectList(this, eListType, eFlags, pobSrch);
			return ol.QueryInterface(&IVsSimpleObjectList2.iid, cast(void**) ppList);
		}
	}

    //Get various settings for the library
    override HRESULT GetLibFlags2(/+[out, retval]+/ LIB_FLAGS2 *pfFlags)
	{
		mixin(LogCallMix2);
		assert(pfFlags);
		
		*pfFlags = LF_PROJECT | LF_EXPANDABLE;
		return S_OK;
	}

    //Counter to check if the library has changed
    override HRESULT UpdateCounter(/+[out]+/ ULONG *pCurUpdate)
	{
		// mixin(LogCallMix2);

		assert(pCurUpdate);
		*pCurUpdate = Package.GetLibInfos().updateCounter();
		return S_OK;
	}

    // Unqiue guid identifying each library that never changes (even across shell instances)
    override HRESULT GetGuid(GUID* ppguidLib)
	{
		mixin(LogCallMix2);

		assert(ppguidLib);
		*ppguidLib = g_omLibraryCLSID;
		return S_OK;
	}

    // Returns the separator string used to separate namespaces, classes and members 
    // eg. "::" for VC and "." for VB
    override HRESULT GetSeparatorStringWithOwnership(BSTR *pszSeparator)
	{
		mixin(LogCallMix2);
		*pszSeparator = allocBSTR(".");
		return S_OK;
	}

    //Retrieve the persisted state of this library from the passed stream 
    //(essentially information for each browse container being browsed). Only
    //implement for GLOBAL browse containers
    override HRESULT LoadState(/+[in]+/ IStream pIStream, in LIB_PERSISTTYPE lptType)
	{
		mixin(LogCallMix2);
		// we do not save/load persisted state
		return E_NOTIMPL; 
	}

    //Save the current state of this library to the passed stream 
    //(essentially information for each browse container being browsed). Only
    //implement for GLOBAL browse containers
    override HRESULT SaveState(/+[in]+/ IStream pIStream, in LIB_PERSISTTYPE lptType)
	{
		mixin(LogCallMix2);
		// we do not save/load persisted state
		return E_NOTIMPL; 
	}

    // Used to obtain a list of browse containers corresponding to the given
    // project (hierarchy). Only return a list if your package owns this hierarchy
    // Meaningful only for libraries providing PROJECT browse containers.
    override HRESULT GetBrowseContainersForHierarchy(/+[in]+/ IVsHierarchy pHierarchy,
        in ULONG celt,
        /+[in, out, size_is(celt)]+/ VSBROWSECONTAINER *rgBrowseContainers,
        /+[out, optional]+/ ULONG *pcActual)
	{
		mixin(LogCallMix2);

		if (pcActual)
			*pcActual = 0;

		//Do we have this project?
		foreach(lib; mLibraryItems)
		{
			if(lib.GetHierarchy() is pHierarchy)
			{
				if (celt && rgBrowseContainers)
				{
					rgBrowseContainers[0].pguidLib = cast(GUID*) &g_omLibraryCLSID;
					if(HRESULT hr = lib.GetText(TTO_DEFAULT, &rgBrowseContainers[0].szName))
						return hr;
				}
				if (pcActual)
					*pcActual = 1;// We always only have one library. 
				break;
			}
		}
		return S_OK;
	}

    // Start browsing the component specified in PVSCOMPONENTSELECTORDATA (name is equivalent to that
    // returned thru the liblist's GetText method for this browse container). 
    // Only meaningful for registered libraries for a given type of GLOBAL browse container 
    override HRESULT AddBrowseContainer(in PVSCOMPONENTSELECTORDATA pcdComponent, 
		/+[in, out]+/ LIB_ADDREMOVEOPTIONS *pgrfOptions, 
		/+[out]+/ BSTR *pbstrComponentAdded)
	{
		mixin(LogCallMix2);
		// we do not support GLOBAL browse containers
		return E_NOTIMPL; 
	}

    // Stop browsing the component identified by name (name is equivalent to that
    // returned thru the liblist's GetText method for this browse container 
    // Only meaningful for registered libraries for a given type of GLOBAL browse container 
    override HRESULT RemoveBrowseContainer(in DWORD dwReserved, in LPCWSTR pszLibName)
	{
		mixin(LogCallMix2);
		// we do not support GLOBAL browse containers
		return E_NOTIMPL; 
	}
	
    override HRESULT CreateNavInfo(/+[ size_is (ulcNodes)]+/ in SYMBOL_DESCRIPTION_NODE *rgSymbolNodes, in ULONG ulcNodes, 
		/+[out]+/ IVsNavInfo * ppNavInfo)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL; 
	}

	// IVsLiteTreeList ////////////////////////////////////////////////////////
    //Fetches VSTREEFLAGS
    override HRESULT GetFlags(/+[out]+/ VSTREEFLAGS *pFlags)
	{
		mixin(LogCallMix2);

		//State change and update only
		*pFlags = TF_NOEVERYTHING ^ (TF_NOSTATECHANGE | TF_NOUPDATES);
		
		return S_OK;
	}
	
    //Count of items in this list
    override HRESULT GetItemCount(/+[out]+/ ULONG* pCount)
	{
		mixin(LogCallMix2);
		assert(pCount);

		*pCount = mLibraryItems.length;
		return S_OK;
	}
	
    //An item has been expanded, get the next list
    override HRESULT GetExpandedList(in ULONG Index, 
		/+[out]+/ BOOL *pfCanRecurse, 
		/+[out]+/ IVsLiteTreeList *pptlNode)
	{
		mixin(LogCallMix2);

		assert(_false); // TF_NOEXPANSION is set: this shouldn't be called
		return E_FAIL;
	}
	
    //Called during a ReAlign command if TF_CANTRELOCATE isn't set.  Return
    //E_FAIL if the list can't be located, in which case the list will be discarded.
    override HRESULT LocateExpandedList(/+[in]+/ IVsLiteTreeList ExpandedList, 
		/+[out]+/ ULONG *iIndex)
	{
		mixin(LogCallMix2);
		
		assert(_false); // TF_NOEXPANSION and TF_NORELOCATE is set: this shouldn't be called
		return E_FAIL;
	}
    //Called when a list is collapsed by the user.
    override HRESULT OnClose(/+[out]+/ VSTREECLOSEACTIONS *ptca)
	{
		mixin(LogCallMix2);
		
		assert(ptca);

		// Since handing the list back out is almost free and
		// the list isn't expandable, there's no reason for
		// the tree to keep a reference.
		*ptca = TCA_CLOSEANDDISCARD;
		return S_OK;
	}
    //Get a pointer to the main text for the list item. Caller will NOT free, implementor
    //can reuse buffer for each call to GetText except for TTO_SORTTEXT. See VSTREETEXTOPTIONS for tto details
    override HRESULT GetText(in ULONG uIndex, in VSTREETEXTOPTIONS tto, 
		/+[out]+/ const( WCHAR)**ppszText)
	{
		// mixin(LogCallMix2);
		assert(ppszText);
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		return mLibraryItems[uIndex].GetText(tto, ppszText);
	}
    //Get a pointer to the tip text for the list item. Like GetText, caller will NOT free, implementor
    //can reuse buffer for each call to GetTipText. If you want tiptext to be same as TTO_DISPLAYTEXT, you can
    //E_NOTIMPL this call.
    override HRESULT GetTipText(in ULONG uIndex, in VSTREETOOLTIPTYPE eTipType, 
		/+[out]+/ const( WCHAR)**ppszText)
	{
		mixin(LogCallMix2);

		assert(ppszText);
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		return mLibraryItems[uIndex].GetTipText(eTipType, ppszText);
	}
	
    //Is this item expandable?  Not called if TF_NOEXPANSION is set
    override HRESULT GetExpandable(in ULONG uIndex, 
		/+[out]+/ BOOL *pfExpandable)
	{
		mixin(LogCallMix2);
		
		assert(pfExpandable);
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		*pfExpandable = FALSE;
		return S_OK;
	}
	
    //Retrieve information to draw the item
    /+[local]+/ override HRESULT GetDisplayData(in ULONG uIndex, 
		/+[out]+/ VSTREEDISPLAYDATA *pData)
	{
		//mixin(LogCallMix2);

		assert(pData);
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		GetImageList(&pData.hImageList);

		BOOL fIsLibraryChecked = (mCheckState == LCS_UNCHECKED) ? FALSE : TRUE;
		return mLibraryItems[uIndex].GetDisplayData(fIsLibraryChecked, pData);
	}
	
    //Return latest update increment.  True/False isn't sufficient here since
    //multiple trees may be using this list.  Returning an update counter > than
    //the last one cached by a given tree will force calls to GetItemCount and
    //LocateExpandedList as needed.
    override HRESULT UpdateCounter(/+[out]+/ ULONG *pCurUpdate,  
		/+[out]+/ VSTREEITEMCHANGESMASK *pgrfChanges)
	{
		// mixin(LogCallMix2);

		return mCounterLibList.UpdateCounter(pCurUpdate, pgrfChanges);
	}

    // If prgListChanges is NULL, should return the # of changes in pcChanges. Otherwise
    // *pcChanges will indicate the size of the array (so that caller can allocate the array) to fill
    // with the VSTREELISTITEMCHANGE records
    override HRESULT GetListChanges(/+[in,out]+/ ULONG *pcChanges, 
		/+[ size_is (*pcChanges)]+/ in VSTREELISTITEMCHANGE *prgListChanges)
	{
		mixin(LogCallMix2);

		// bad "in" in annotation of VSI SDK vsshell.h
		return mCounterLibList.GetListChanges(pcChanges, cast(VSTREELISTITEMCHANGE *)prgListChanges);
	}
	
    //Toggles the state of the given item (may be more than two states)
    override HRESULT ToggleState(in ULONG uIndex, 
		/+[out]+/ VSTREESTATECHANGEREFRESH *ptscr)
	{
		mixin(LogCallMix2);

		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;
		assert(ptscr);

		if(HRESULT hr = mLibraryItems[uIndex].ToggleState())
			return hr;

		*ptscr = TSCR_CURRENT | TSCR_PARENTS | TSCR_CHILDREN | TSCR_PARENTSCHILDREN;

		LIB_CHECKSTATE lcs;
		mLibraryItems[uIndex].GetCheckState(&lcs);

		// check if this change the library state
		BOOL fUpdateLibraryCounter    = FALSE;
		ULONG cChecked;
		ULONG cUnchecked;

		CountChecks(&cChecked,&cUnchecked);

		if (lcs == LCS_CHECKED) // item has been checked
		{
			// we should update if the library has been unchecked
			fUpdateLibraryCounter = (mCheckState == LCS_UNCHECKED);

			if (!cUnchecked) // the last unchecked has been checked
				mCheckState = LCS_CHECKED;// change the library state
			else
				// change the library state
				mCheckState = LCS_CHECKEDGRAY;
		}
		else // item has been unchecked
		{
			if (mCheckState != LCS_UNCHECKED)
			{
				if (!cChecked)
				{
					// the last checked has been unchecked
					mCheckState = LCS_UNCHECKED;
					// we should update if the library is unchecked
					fUpdateLibraryCounter = TRUE;
				}
				else
					mCheckState = LCS_CHECKEDGRAY;
			}
		}

		if (fUpdateLibraryCounter)
		{
version(todo)
{
			// notify any lists for the change
			CBrowseNode * pBrowseNode = mLibraryItem[uIndex];
			if (lcs == LCS_CHECKED)
				NotifyOnBrowseDataAdded(LLT_PACKAGE, pBrowseNode);
			else
				NotifyOnBrowseDataRemoved(LLT_PACKAGE, pBrowseNode);
}
		}
		return S_OK; 
	}

	// IVsSolutionEvents //////////////////////////////////////////////////////
    // fAdded   == TRUE means project added to solution after solution open.
    // fAdded   == FALSE means project added to solution during solution open.
    override HRESULT OnAfterOpenProject(/+[in]+/ IVsHierarchy pIVsHierarchy, in BOOL fAdded)
	{
		mixin(LogCallMix2);
		assert(pIVsHierarchy);

		//Do we already have this project?
		foreach(lib; mLibraryItems)
			if(lib.GetHierarchy() is pIVsHierarchy)
				return S_OK;

		// check to see if this is a myc project
		GUID guidProject;
		HRESULT hr = pIVsHierarchy.GetGuidProperty(VSITEMID_ROOT, VSHPROPID_TypeGuid, &guidProject);
		if(FAILED(hr))
			return hr;

		if (guidProject != g_projectFactoryCLSID)
			return S_OK;

		//Create a new project info struct
		auto libraryItem = new LibraryItem(this, pIVsHierarchy);
		mLibraryItems ~= libraryItem;

version(todo)
{
		// inform the lists if any
		NotifyOnBrowseDataAdded(LLT_PACKAGE, pLibraryItem);
}

		// update the liblist
		VSTREELISTITEMCHANGE listChanges;
		listChanges.grfChange = TCT_ITEMADDED; 
		listChanges.Index     = mLibraryItems.length - 1;

		return mCounterLibList.Increment(listChanges);
	}
	
    // fRemoving == TRUE means project being removed from   solution before solution close.
    // fRemoving == FALSE   means project being removed from solution during solution close.
    override HRESULT OnQueryCloseProject(/+[in]+/ IVsHierarchy   pHierarchy, in BOOL fRemoving, 
		/+[in,out]+/ BOOL *pfCancel)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
	
    // fRemoved == TRUE means   project removed from solution before solution close.
    // fRemoved == FALSE means project removed from solution during solution close.
    override HRESULT OnBeforeCloseProject(/+[in]+/   IVsHierarchy pHierarchy, in BOOL fRemoved)
	{
		mixin(LogCallMix2);

		assert(pHierarchy);

		//Do we have this project?
		int idx;
		for(idx = 0; idx < mLibraryItems.length; idx++)
			if(mLibraryItems[idx].GetHierarchy() is pHierarchy)
				break;

		if(idx >= mLibraryItems.length)
			return S_OK;

		// remove the data
		LibraryItem libraryItem = mLibraryItems[idx];
		mLibraryItems = mLibraryItems[0..idx] ~ mLibraryItems[idx+1..$];

version(todo)
{
		// inform the lists if any
		NotifyOnBrowseDataRemoved(LLT_PACKAGE, pLibraryItem);
}

		// update the liblist
		VSTREELISTITEMCHANGE listChanges;
		listChanges.grfChange = TCT_ITEMDELETED; 
		listChanges.Index     = idx;
		HRESULT hr = mCounterLibList.Increment(listChanges);

		libraryItem.Close();
		return hr;
	}

    // stub hierarchy   is placeholder hierarchy for unloaded project.
    override HRESULT OnAfterLoadProject(/+[in]+/ IVsHierarchy pStubHierarchy,   /+[in]+/ IVsHierarchy pRealHierarchy)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    override HRESULT OnQueryUnloadProject(/+[in]+/   IVsHierarchy pRealHierarchy, 
		/+[in,out]+/ BOOL *pfCancel)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    override HRESULT OnBeforeUnloadProject(/+[in]+/ IVsHierarchy pRealHierarchy, /+[in]+/   IVsHierarchy pStubHierarchy)
	{
		mixin(LogCallMix2);
		return S_OK;
	}

    // fNewSolution == TRUE means   solution is being created now.
    // fNewSolution == FALSE means solution was created previously, is being loaded.
    override HRESULT OnAfterOpenSolution(/+[in]+/ IUnknown   pUnkReserved, in BOOL fNewSolution)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    override HRESULT OnQueryCloseSolution(/+[in]+/   IUnknown pUnkReserved, 
		/+[in,out]+/ BOOL *pfCancel)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    override HRESULT OnBeforeCloseSolution(/+[in]+/ IUnknown pUnkReserved)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    override HRESULT OnAfterCloseSolution(/+[in]+/   IUnknown pUnkReserved)
	{
		mixin(LogCallMix2);
		return S_OK;
	}

}

enum useJSON = false;

static if(useJSON)
	alias JSONValue InfoObject;
else
	alias BrowseNode InfoObject;

int GetInfoCount(BrowseNode val)   { return val ? val.members.length : 0; }
string GetInfoName(BrowseNode val) { return val ? val.name : null; }
string GetInfoKind(BrowseNode val) { return val ? val.kind : null; }
string GetInfoType(BrowseNode val) { return val ? val.type : null; }
string GetInfoBase(BrowseNode val) { return val ? val.GetBase() : null; }
string[] GetInfoInterfaces(BrowseNode val) { return val ? val.GetInterfaces() : null; }
string GetInfoFilename(BrowseNode val) { return val ? val.GetFile() : null; }
int GetInfoLine(BrowseNode val) { return val ? val.line : -1; }
string GetInfoScope(BrowseNode val) { return val ? val.GetScope() : null; }

BrowseNode GetInfoObject(BrowseNode val, ULONG idx)
{
	if(!val || idx >= val.members.length)
		return null;
	return val.members[idx];
}

// move to intellisense.d?
int GetInfoCount(JSONValue val)
{
	if(val.type == JSON_TYPE.ARRAY)
		return val.array.length;
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* m = "members" in val.object)
			if(m.type == JSON_TYPE.ARRAY)
				return m.array.length;
	return 0;
}

string GetInfoName(JSONValue val)
{
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* v = "name" in val.object)
			if(v.type == JSON_TYPE.STRING)
				return v.str;
	if(val.type == JSON_TYPE.STRING)
		return val.str;
	return null;
}

string GetInfoKind(JSONValue val)
{
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* v = "kind" in val.object)
			if(v.type == JSON_TYPE.STRING)
				return v.str;
	if(val.type == JSON_TYPE.STRING)
		return "class";
	return null;
}

string GetInfoType(JSONValue val)
{
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* v = "type" in val.object)
			if(v.type == JSON_TYPE.STRING)
				return v.str;
	return null;
}

string GetInfoBase(JSONValue val)
{
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* v = "base" in val.object)
			if(v.type == JSON_TYPE.STRING)
				return v.str;
	return null;
}

string[] GetInfoInterfaces(JSONValue val)
{
	string[] ifaces;
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* v = "interfaces" in val.object)
			if(v.type == JSON_TYPE.ARRAY)
				foreach(i, iface; v.array)
					if(iface.type == JSON_TYPE.STRING)
						ifaces ~= iface.str;
	return ifaces;
}

string GetInfoFilename(JSONValue val)
{
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* v = "file" in val.object)
			if(v.type == JSON_TYPE.STRING)
				return v.str;
	return null;
}

int GetInfoLine(JSONValue val)
{
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* v = "line" in val.object)
			if(v.type == JSON_TYPE.INTEGER)
				return cast(int) v.integer - 1;
	return -1;
}

JSONValue GetInfoObject(JSONValue val, ULONG idx)
{
	if(val.type == JSON_TYPE.ARRAY)
		if(idx < val.array.length)
			return val.array[idx];
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* m = "members" in val.object)
			if(m.type == JSON_TYPE.ARRAY)
				if(idx < m.array.length)
					return m.array[idx];
	return JSONValue();
}

bool HasFunctionPrototype(string kind)
{
	switch(kind)
	{
		case "constructor":
		case "destructor":
		case "allocator":
		case "deallocator":
		case "delegate":
		case "function":
		case "function decl":
			return true;
		default:
			return false;
	}
}

LIB_LISTTYPE2 GetListType(string kind)
{
	switch(kind)
	{
		case "union":
		case "struct":
		case "anonymous struct":
		case "anonymous union":
		case "interface":
		case "enum":
		case "class":            return LLT_CLASSES;
		case "module":           return LLT_NAMESPACES | LLT_HIERARCHY | LLT_PACKAGE;
		case "variable":
		case "constructor":
		case "destructor":
		case "allocator":
		case "deallocator":
		case "enum member":
		case "template":
		case "alias":
		case "typedef":
		case "delegate":
		case "function decl":
		case "function":         return LLT_MEMBERS;
			
		// not expected to show up in json file
		case "attribute":
		case "function alias":
		case "alias this":
		case "pragma":
		case "import":
		case "static import":
		case "static if":
		case "static assert":
		case "template instance":
		case "mixin":
		case "debug":
		case "version":          return LLT_MEMBERS;
		default:                 return LLT_MEMBERS;
	}
}

///////////////////////////////////////////////////////////////////////
class ObjectList : DComObject, IVsSimpleObjectList2
{
	// CComPtr<IBrowseDataProvider> m_srpIBrowseDataProvider;
	// VSCOOKIE         m_dwIBrowseDataProviderEventsCookie;
	Library mLibrary;   // Holds a pointer to the library
	LIB_LISTTYPE  mListType;     //type of the list
	LIB_LISTFLAGS mFlags;
	const(VSOBSEARCHCRITERIA2) *mObSrch; // assume valid through the lifetime of the list
	
	BrowseCounter mCounter;
	LibraryInfo mLibInfo;
	ObjectList mParent;
	InfoObject mObject;
	InfoObject[] mMembers;
		
	this(Library lib, in LIB_LISTTYPE2 eListType, in LIB_LISTFLAGS eFlags, in VSOBSEARCHCRITERIA2 *pobSrch)
	{
		mLibrary = lib;
		mListType = eListType;
		mFlags = eFlags;
		mObSrch = pobSrch;
		initMembers();
	}

	this(Library lib, LibraryInfo libInfo, ObjectList parent, InfoObject object,
		 in LIB_LISTTYPE2 eListType, in LIB_LISTFLAGS eFlags, in VSOBSEARCHCRITERIA2 *pobSrch)
	{
		mListType = eListType;
		mFlags = eFlags;
		mObSrch = pobSrch;
		
		mLibrary = lib;
		mLibInfo = libInfo;
		mParent = parent;
		mObject = object;
		initMembers();
	}
	
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsSimpleObjectList2) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	void initMembers()
	{
		InfoObject[] arr;
		if(!mParent)
		{
			// all modules from the library
			auto infos = Package.GetLibInfos();
			foreach(info; infos.mInfos)
				static if(!useJSON)
					arr ~= info.mModules;
				else
					if(info.mModules.type == JSON_TYPE.ARRAY)
						arr ~= info.mModules.array;
				
		}
		else if(mObject)
		{
			arr = mObject.members;
			string base = mObject.GetBase();
			string[] ifaces = mObject.GetInterfaces();
			
			bool hasBase = base.length || ifaces.length;
			// do not show base class of enums in the tree
			if(mObject.kind == "enum")
				hasBase = false;

			if(hasBase && (mListType & LLT_CLASSES))
			{
				InfoObject bc = new InfoObject;
				bc.name = "Base Classes";
				bc.kind = "class";
				bc.parent = mObject;
				bc.line = -2;
				mMembers ~= bc;

				void addBase(string name, string kind)
				{
					auto infos = Package.GetLibInfos();
					InfoObject n = infos.findClass(name, mObject);
					if(!n)
					{
						n = new InfoObject;
						n.name = name;
						n.kind = kind;
						n.parent = bc;
						n.line = -2;
					}
					bc.members ~= n;
				}

				if(base.length)
					addBase(base, "class");
				foreach(iface; ifaces)
					addBase(iface, "interface");
			}
		}

		string searchName;
		if((mFlags & LLF_USESEARCHFILTER) && mObSrch && mObSrch.szName)
		{
			searchName = to_string(mObSrch.szName);
			if(!(mObSrch.grfOptions & VSOBSO_CASESENSITIVE))
				searchName = toLower(searchName);
		}
			
		foreach(v; arr)
		{
			void addIfCorrectKind(InfoObject val)
			{
				string kind = GetInfoKind(val);
				if(mListType & GetListType(kind))
					mMembers ~= val;
			}
			if(searchName.length)
			{
				void searchRecurse(InfoObject val)
				{
					string name = GetInfoName(val);
					if(!(mObSrch.grfOptions & VSOBSO_CASESENSITIVE))
						name = toLower(name);
					
					bool rc;
					switch(mObSrch.eSrchType)
					{
						case SO_ENTIREWORD:
							rc = (name == searchName);
							break;
						case SO_SUBSTRING:
							rc = (indexOf(name, searchName) >= 0);
							break;
						case SO_PRESTRING:
							rc = startsWith(name, searchName);
							break;
						default:
							rc = false;
							break;
					}
					if(rc)
						addIfCorrectKind(val);

					foreach(v2; val.members)
						searchRecurse(v2);
				}
				searchRecurse(v);
			}
			else
				addIfCorrectKind(v);
		}
	}
	
	int GetCount()
	{
		return mMembers.length;
	}
	
	bool IsValidIndex(/* [in] */ ULONG uIndex)
	{
		return uIndex < GetCount();
	}

	InfoObject GetObject(ULONG idx)
	{
		if(idx >= mMembers.length)
			return null;
		return mMembers[idx];
	}
		
	string GetName(ULONG idx)
	{
		InfoObject v = GetObject(idx);
		return GetInfoName(v);
	}

	string GetKind(ULONG idx)
	{
		InfoObject v = GetObject(idx);
		return GetInfoKind(v);
	}
	
	InfoObject GetModule()
	{
		if(GetInfoKind(mObject) == "module")
			return mObject;
		if(mParent)
			return mParent.GetModule();
		return null;
	}

	InfoObject GetModule(ULONG idx)
	{
		if(GetKind(idx) == "module")
			return GetObject(idx);
		return GetModule();
	}
	
	// IVsLiteTreeList ///////////////////////////////////////////////////////
	override HRESULT GetFlags(/+[out]+/ VSTREEFLAGS *pFlags)
	{
		mixin(LogCallMix2);
		assert(pFlags);

		if (GetCount() > 0) // mListType & (LLT_PACKAGE | LLT_CLASSES))
		{
			//State change and expansion
			*pFlags = TF_NOEVERYTHING ^ (TF_NOSTATECHANGE | TF_NOUPDATES | TF_NOEXPANSION); 
		}
		else
		{
			//State change only
			*pFlags = TF_NOEVERYTHING ^ (TF_NOSTATECHANGE | TF_NOUPDATES);  
		}
		return S_OK;
	}
    //Count of items in this list
	override HRESULT GetItemCount(/+[out]+/ ULONG* pCount)
	{
		mixin(LogCallMix2);
		assert(pCount);
		
		*pCount = GetCount();
		return S_OK;
	}
	
	//Called when a list is collapsed by the user.
	override HRESULT OnClose(/+[out]+/ VSTREECLOSEACTIONS *ptca)
	{
		mixin(LogCallMix2);
		
		assert(ptca);
		*ptca = TCA_NOTHING;
		
		return E_NOTIMPL;
	}

	override HRESULT GetTextWithOwnership(in ULONG uIndex, in VSTREETEXTOPTIONS tto, 
		/+[out]+/ BSTR *pbstrText)
	{
		//mixin(LogCallMix2);
		
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		auto val = GetObject(uIndex);
		string name = GetInfoName(val);
		if(mFlags & LLF_USESEARCHFILTER)
		{
			string scp = GetInfoScope(val);
			if(scp.length)
				name = scp ~ "." ~ name;
		}
		Definition def;
		if(val)
			def.setFromBrowseNode(val);

		if(HasFunctionPrototype(def.kind))
		{
			string ret = def.GetReturnType();
			name = ret ~ " " ~ name ~ "(";
			for(int i = 0; i < def.GetParameterCount(); i++)
			{
				string pname, description, display;
				def.GetParameterInfo(i, pname, display, description);
				if(i > 0)
					name ~= ", ";
				name ~= display;
			}
			name ~= ")";
		}		
		*pbstrText = allocBSTR(name);
		return S_OK;
	}
    
	//If you want tiptext to be same as TTO_DISPLAYTEXT, you can E_NOTIMPL this call.
	override HRESULT GetTipTextWithOwnership(in ULONG uIndex, in VSTREETOOLTIPTYPE eTipType, 
		/+[out]+/ BSTR *pbstrText)
	{
		mixin(LogCallMix2);

		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		string kind = GetKind(uIndex);
		string name = GetName(uIndex);
		*pbstrText = allocBSTR(kind ~ " " ~ name);
		return S_OK;
	} 
    
    //Retrieve information to draw the item
    /+[local]+/ HRESULT GetDisplayData(in ULONG Index, /+[out]+/ VSTREEDISPLAYDATA *pData)
	{
		//mixin(LogCallMix2);
		pData.Mask = TDM_IMAGE | TDM_SELECTEDIMAGE;
		string kind = GetKind(Index);
		switch(kind)
		{
			case "class":            pData.Image = CSIMG_CLASS; break;
			case "module":           pData.Image = CSIMG_PACKAGE; break;
			case "variable":         pData.Image = CSIMG_FIELD; break;
			case "constructor":
			case "destructor":
			case "allocator":
			case "deallocator":
			case "function decl":
			case "function":         pData.Image = CSIMG_MEMBER; break;
			case "delegate":         pData.Image = CSIMG_MEMBER; break;
			case "interface":        pData.Image = CSIMG_INTERFACE; break;
			case "union":            pData.Image = CSIMG_UNION; break;
			case "struct":           pData.Image = CSIMG_STRUCT; break;
			case "anonymous struct": pData.Image = CSIMG_STRUCT; break;
			case "anonymous union":  pData.Image = CSIMG_UNION; break;
			case "enum":             pData.Image = CSIMG_ENUM; break;
			case "enum member":      pData.Image = CSIMG_ENUMMEMBER; break;
			case "template":         pData.Image = CSIMG_TEMPLATE; break;
			case "alias":
			case "typedef":          pData.Image = CSIMG_UNKNOWN7; break;
				
			// not expected to show up in json file
			case "attribute":
			case "function alias":
			case "alias this":
			case "pragma":
			case "import":
			case "static import":
			case "static if":
			case "static assert":
			case "template instance":
			case "mixin":
			case "debug":
			case "version":
				pData.Image = CSIMG_BLITZ; 
				break;
			default:
				pData.Image = CSIMG_STOP;
		}
		pData.SelectedImage = pData.Image;
		
		return S_OK;
	}
    //Return latest update increment.  True/False isn't sufficient here since
    //multiple trees may be using this list.  Returning an update counter > than
    //the last one cached by a given tree will force calls to GetItemCount and
    //LocateExpandedList as needed.
	override HRESULT UpdateCounter(/+[out]+/ ULONG *pCurUpdate)
	{
		// mixin(LogCallMix2);
	    return mCounter.UpdateCounter(pCurUpdate, null);
	}

	// IVsObjectList /////////////////////////////////////////////////////////////
	override HRESULT GetCapabilities2(/+[out]+/  LIB_LISTCAPABILITIES *pCapabilities)
	{
		mixin(LogCallMix2);
		*pCapabilities = LLC_NONE;
		return S_OK;
	}
    // Get a sublist
	override HRESULT GetList2(in ULONG uIndex, in LIB_LISTTYPE2 ListType, in LIB_LISTFLAGS Flags, in VSOBSEARCHCRITERIA2 *pobSrch, 
		/+[out]+/ IVsSimpleObjectList2 *ppList)
	{
		mixin(LogCallMix2);
		auto obj = GetObject(uIndex);
		if(!obj)
			return E_UNEXPECTED;

		auto list = newCom!ObjectList(mLibrary, mLibInfo, this, obj, ListType, Flags, pobSrch);
		return list.QueryInterface(&IVsSimpleObjectList2.iid, cast(void**) ppList);
	}
	
	override HRESULT GetCategoryField2(in ULONG uIndex, in LIB_CATEGORY2 Category, 
		/+[out,retval]+/ DWORD* pField)
	{
		mixin(LogCallMix2);
		assert(pField);

		if(Category == LC_LISTTYPE && uIndex == BrowseCounter.NULINDEX)
		{
			// child list types supported under this list
			*pField = LLT_NAMESPACES | LLT_CLASSES | LLT_MEMBERS;
			return S_OK;
		}
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;
		*pField = 0;

		switch (Category)
		{
			case LC_LISTTYPE:
				switch (GetKind(uIndex))
				{
					case "module":
						*pField = LLT_NAMESPACES | LLT_CLASSES | LLT_MEMBERS;
						break;
					case "class":
					case "interface":
						*pField = LLT_CLASSES | LLT_MEMBERS | LLT_HIERARCHY;
						break;
					case "union":
					case "struct":
					case "anonymous struct":
					case "anonymous union":
					case "enum":
						*pField = LLT_CLASSES | LLT_MEMBERS;
						break;
					default:
						*pField = 0;
						break;
				}
				break;
			case LC_VISIBILITY:
				*pField = LCV_VISIBLE;
				break;
			case LC_MEMBERTYPE:
				assert(uIndex != BrowseCounter.NULINDEX);
				return E_NOTIMPL; // m_rgpBrowseNode[uIndex]->GetCategoryField(eCategory, pField);
				
			case LC_HIERARCHYTYPE:
				switch (GetKind(uIndex))
				{
					case "class":
					case "interface":
						*pField = LLT_CLASSES | LLT_MEMBERS | LLT_HIERARCHY;
						break;
					default:
						*pField = 0;
						return E_FAIL;
				}
				break;
				
			case LC_NODETYPE:
			case LC_MEMBERINHERITANCE:
			case LC_SEARCHMATCHTYPE:
				
			default:
				*pField = 0;
				return E_FAIL;
		}
		return S_OK;
	}

	override HRESULT GetExpandable3(in ULONG Index, in LIB_LISTTYPE2 ListTypeExcluded, 
		/+[out]+/ BOOL *pfExpandable)
	{
		//mixin(LogCallMix2);
		assert(pfExpandable);
		
		InfoObject obj = GetObject(Index);
		if(GetInfoCount(obj) > 0) // mListType & (LLT_PACKAGE | LLT_CLASSES))
			*pfExpandable = TRUE;
		else
			*pfExpandable = FALSE;
		
		return S_OK;
	}
	
	override HRESULT GetNavInfo(in ULONG uIndex, /+[out]+/ IVsNavInfo * ppNavInfo)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	override HRESULT GetNavInfoNode(in ULONG Index, 
		/+[out]+/ IVsNavInfoNode * ppNavInfoNode)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	
	override HRESULT LocateNavInfoNode(/+[in]+/ IVsNavInfoNode  pNavInfoNode, 
		/+[out]+/ ULONG * pulIndex)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	
	override HRESULT GetBrowseObject(in ULONG Index, 
		/+[out]+/ IDispatch *ppdispBrowseObj)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	override HRESULT GetUserContext(in ULONG Index, 
		/+[out]+/ IUnknown *ppunkUserCtx)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	override HRESULT ShowHelp(in ULONG Index)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	override HRESULT GetSourceContextWithOwnership(in ULONG Index, 
		/+[out]+/ BSTR *pszFileName, 
		/+[out]+/ ULONG *pulLineNum)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	override HRESULT GetProperty(in ULONG Index, in VSOBJLISTELEMPROPID propid, 
		/+[out]+/ VARIANT *pvar)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}

    // Returns the count of itemids (these must be from a single hierarchy) that make up the source files
    // for the list element at Index. Also returns the hierarchy ptr and itemid if requested.
    // If there are >1 itemids, return VSITEMID_SELECTION and a subsequent call will be made
    // on GetMultipleSourceItems to get them. If there are no available source items, return
    // VSITEMID_ROOT to indicate the root of the hierarchy as a whole.
	override HRESULT CountSourceItems(in ULONG Index, 
		/+[out]+/ IVsHierarchy *ppHier, 
		/+[out]+/ VSITEMID *pitemid, 
		/+[out, retval]+/ ULONG *pcItems)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Used if CountSourceItems returns > 1. Details for filling up these out params are same 
    // as IVsMultiItemSelect::GetSelectedItems
	override HRESULT GetMultipleSourceItems(in ULONG Index, in VSGSIFLAGS grfGSI, in ULONG cItems, 
		/+[out, size_is(cItems)]+/ VSITEMSELECTION *rgItemSel)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Return TRUE if navigation to source of the specified type (definition or declaration),
    // is possible, FALSE otherwise
	override HRESULT CanGoToSource(in ULONG Index, in VSOBJGOTOSRCTYPE SrcType, 
		/+[out]+/ BOOL *pfOK)
	{
		mixin(LogCallMix2);
		if(SrcType != GS_ANY)
		{
			if(SrcType == GS_DEFINITION && GetKind(Index) == "function decl")
				return E_FAIL;
			if(SrcType == GS_DECLARATION && GetKind(Index) != "function decl")
				return E_FAIL;
			if(SrcType != GS_DECLARATION && SrcType != GS_DEFINITION)
				return E_FAIL;
		}
		*pfOK = TRUE;
		return S_OK;
	}
    // Called to cause navigation to the source (definition or declration) for the
    // item Index. You must must coordinate with the project system to open the
    // source file and navigate it to the approp. line. Return S_OK on success or an
    // hr error (along with rich error info if possible) if the navigation failed.
	override HRESULT GoToSource(in ULONG Index, in VSOBJGOTOSRCTYPE SrcType)
	{
		mixin(LogCallMix2);
		
		string file, modname;

		auto mod = GetModule(Index);
		if(mod)
		{
			file = GetInfoFilename(mod);
			modname = GetInfoName(mod);
		}
		auto obj = GetObject(Index);
		int line = GetInfoLine(obj);
		if(file.length == 0)
			file = GetInfoFilename(obj);

		return OpenFileInSolution(file, line, 0, modname, true);
	}
	
	override HRESULT GetContextMenu(in ULONG Index, 
		/+[out]+/ CLSID *pclsidActive, 
		/+[out]+/ LONG *pnMenuId, 
		/+[out]+/ IOleCommandTarget *ppCmdTrgtActive)
	{
		// mixin(LogCallMix2);
		return E_NOTIMPL;
	}   
	override HRESULT QueryDragDrop(in ULONG Index, /+[in]+/ IDataObject pDataObject, in DWORD grfKeyState, 
		/+[in, out]+/DWORD * pdwEffect)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	override HRESULT DoDragDrop(in ULONG Index, /+[in]+/ IDataObject  pDataObject, in DWORD grfKeyState, 
		/+[in, out]+/DWORD * pdwEffect)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Says whether the item Index can be renamed or not. If the passed in pszNewName is NULL,
    // it simply answers the general question of whether or not that item supports rename
    // (return TRUE or FALSE). If pszNewName is non-NULL, do validation of the new name
    // and return TRUE if successful rename with that new name is possible or an an error hr (along with FALSE)
    // if the name is somehow invalid (and set the rich error info to indicate to the user
    // what was wrong) 
	override HRESULT CanRename(in ULONG Index, in LPCOLESTR pszNewName, 
		/+[out]+/ BOOL *pfOK)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Called when the user commits the Rename operation. Guaranteed that CanRename has already
    // been called with the newname so that you've had a chance to validate the name. If
    // Rename succeeds, return S_OK, other wise error hr (and set the rich error info)
    // indicating the problem encountered.
	override HRESULT DoRename(in ULONG Index, in LPCOLESTR pszNewName, in VSOBJOPFLAGS grfFlags)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Says whether the item Index can be deleted or not. Return TRUE if it can, FALSE if not.
	override HRESULT CanDelete(in ULONG Index, 
		/+[out]+/ BOOL *pfOK)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Called when the user asks to delete the item at Index. Will only happen if CanDelete on
    // the item previously returned TRUE. On a successful deletion this should return S_OK, if
    // the deletion failed, return the failure as an error hresult and set any pertinent error
    // info in the standard ole error info.
	override HRESULT DoDelete(in ULONG Index, in VSOBJOPFLAGS grfFlags)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Used to add the description pane text in OBject Browser. Also an alternate
    // mechanism for providing tooltips (ODO_TOOLTIPDESC is set in that case)
	override HRESULT FillDescription2(in ULONG Index, in VSOBJDESCOPTIONS grfOptions, /+[in]+/ IVsObjectBrowserDescription3 pobDesc)
	{
		mixin(LogCallMix2);
		
		auto val = GetObject(Index);
		Definition def;
		if(val)
			def.setFromBrowseNode(val);
		if(!val || def.line < -1)
			return S_OK; // no description for auto generated nodes
		
		if(HasFunctionPrototype(def.kind))
		{
			string ret = def.GetReturnType();
			pobDesc.AddDescriptionText3(_toUTF16z(ret),      OBDS_TYPE, null);
			pobDesc.AddDescriptionText3(" ",                 OBDS_MISC, null);
			pobDesc.AddDescriptionText3(_toUTF16z(def.name), OBDS_NAME, null);
			pobDesc.AddDescriptionText3("(",                 OBDS_MISC, null);
			for(int i = 0; i < def.GetParameterCount(); i++)
			{
				string name, description, disp;
				def.GetParameterInfo(i, name, disp, description);
				if(i > 0)
					pobDesc.AddDescriptionText3(", ",        OBDS_COMMA, null);
				pobDesc.AddDescriptionText3(_toUTF16z(disp), OBDS_PARAM, null);
			}
			pobDesc.AddDescriptionText3(")\n",               OBDS_MISC, null);
		}
		else
		{
			pobDesc.AddDescriptionText3("Name: ",            OBDS_MISC, null);
			pobDesc.AddDescriptionText3(_toUTF16z(def.name), OBDS_NAME, null);
			if(def.type.length)
			{
				pobDesc.AddDescriptionText3("\nType: ",          OBDS_MISC, null);
				pobDesc.AddDescriptionText3(_toUTF16z(def.type), OBDS_TYPE, null);
			}
			if(def.kind.length)
			{
				pobDesc.AddDescriptionText3("\nKind: ",          OBDS_MISC, null);
				pobDesc.AddDescriptionText3(_toUTF16z(def.kind), OBDS_TYPE, null);
			}
			string base = GetInfoBase(val);
			if(base.length)
			{
				pobDesc.AddDescriptionText3("\nBase: ",      OBDS_MISC, null);
				pobDesc.AddDescriptionText3(_toUTF16z(base), OBDS_TYPE, null);
			}
			string[] ifaces = GetInfoInterfaces(val);
			if(ifaces.length)
			{
				pobDesc.AddDescriptionText3("\nInterfaces: ", OBDS_MISC, null);
				foreach(i, iface; ifaces)
				{
					if(i > 0)
						pobDesc.AddDescriptionText3(", ", OBDS_MISC, null);
					pobDesc.AddDescriptionText3(_toUTF16z(iface), OBDS_TYPE, null);
				}
			}
		}
		string filename = GetInfoFilename(GetModule(Index));
		if(filename.length == 0)
			filename = GetInfoFilename(val);
		if(filename.length)
		{
			string msg = "\n\nFile: " ~ filename;
			pobDesc.AddDescriptionText3(_toUTF16z(msg),          OBDS_MISC, null);
			if(def.line >= 0)
			{
				msg = "(" ~ to!string(def.line) ~ ")";
				pobDesc.AddDescriptionText3(_toUTF16z(msg),      OBDS_MISC, null);
			}
		}
		return S_OK;
	}
	
    // These three methods give the list a chance to provide clipboard formats for a drag-drop or 
    // copy/paste operation.
    // Caller first calls EnumClipboardFormats(index, flags, 0, NULL, &cExpected) to get the count
    // of clipboard formats the list is interested in providing, allocates an array of that size,
    // and then calls EnumClipboardFormats(index, flags, cExpected, prgCFs, &cActual)
    // Flags indicate whether this is part of a multiple selction of items. In the 
    // returned array, the list can indicate which formats it supports, on what STGMEDIUM and
    // whether the format is a composite one (caller does the actual rendering after calling
    // GetExtendedClipboardVariant) vs one that the list itself will render thru GetClipboardFormat
    // In the case of a multi-select, typically the list would only support composite formats
    // enabling the caller to write the format in the form: 
    // <count of items><foo variant from selected item1><foo variant from selected item2>..
    // (Note that only certain persistable VARIANT types are supported (as per CComVariant::WriteToStream).
    // In the single select case, the list is free to provide both traditional and composite formats
    // and will be called respectively on GetClipboardFormat or GetExtendedClipboardVariant for each.
    // Note that CV/OB will automatically provide a CF_NAVINFO and a CF_TEXT/CF_UNICODETEXT format, so
    // EnumClipboardFormats should NOT return these values.
	override HRESULT EnumClipboardFormats(in ULONG Index, 
        in VSOBJCFFLAGS grfFlags,
        in ULONG  celt, 
        /+[in, out, size_is(celt)]+/ VSOBJCLIPFORMAT *rgcfFormats,
        /+[out, optional]+/ ULONG *pcActual)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	override HRESULT GetClipboardFormat(in ULONG Index,
        in    VSOBJCFFLAGS grfFlags,
        in    FORMATETC *pFormatetc,
        in    STGMEDIUM *pMedium)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
	override HRESULT GetExtendedClipboardVariant(in ULONG Index,
        in VSOBJCFFLAGS grfFlags,
        in const( VSOBJCLIPFORMAT)*pcfFormat,
        /+[out]+/ VARIANT *pvarFormat)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}

}

class FindReferencesList : DComObject, IVsSimpleObjectList2
{
	string[] mReferences;

	this(string[] refs)
	{
		mReferences = refs;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsSimpleObjectList2) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	bool IsValidIndex(uint uIndex)
	{
		return uIndex < mReferences.length;
	}

	string getSourceLoc(uint Index, int* line = null, int *col = null)
	{
		if (!IsValidIndex(Index))
			return null;

		string r = mReferences[Index];

		auto idx = indexOf(r, ':');
		if(idx > 0)
		{
			string[] num = split(r[0..idx], ",");
			if(num.length == 4)
			{
				try
				{
					if(line)
						*line = parse!int(num[0]) - 1;
					if(col)
						*col = parse!int(num[1]);
					return r[idx+1..$];
				}
				catch(ConvException)
				{
				}
			}
		}
		return null;
	}

	///////////////////////////////////////////////////////////////////
    HRESULT GetFlags(/+[out]+/ VSTREEFLAGS *pFlags)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetCapabilities2(/+[out]+/  LIB_LISTCAPABILITIES2 *pgrfCapabilities)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT UpdateCounter(/+[out]+/ ULONG *pCurUpdate)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetItemCount(/+[out]+/ ULONG* pCount)
	{
		mixin(LogCallMix2);
		*pCount = mReferences.length;
		return S_OK;
	}
    /+[local]+/ HRESULT GetDisplayData(in ULONG Index, 
									   /+[out]+/ VSTREEDISPLAYDATA *pData)
	{
		mixin(LogCallMix2);
		if (!IsValidIndex(Index))
			return E_UNEXPECTED;

		pData.Mask = TDM_IMAGE | TDM_SELECTEDIMAGE;
		pData.Image = CSIMG_BLITZ; 
		pData.SelectedImage = pData.Image;

		return S_OK;
	}
    HRESULT GetTextWithOwnership(in ULONG Index, in VSTREETEXTOPTIONS tto, 
								 /+[out]+/ BSTR *pbstrText)
	{
		mixin(LogCallMix2);
		switch(tto)
		{
			case TTO_DEFAULT:
			case TTO_SORTTEXT:
			case TTO_SEARCHTEXT:
				int line, col;
				string file = getSourceLoc(Index, &line, &col);
				file ~= "(" ~ to!string(line) ~ "," ~ to!string(col) ~ ")";
				*pbstrText = allocBSTR(file);
				return S_OK;
			default:
				break;
		}
		return E_FAIL;
	}
    HRESULT GetTipTextWithOwnership(in ULONG Index, in VSTREETOOLTIPTYPE eTipType, 
									/+[out]+/ BSTR *pbstrText)
	{
		mixin(LogCallMix2);
		if (!IsValidIndex(Index))
			return E_UNEXPECTED;

		*pbstrText = allocBSTR(mReferences[Index]);
		return S_OK;
	}
    HRESULT GetCategoryField2(in ULONG Index, in LIB_CATEGORY2 Category, 
							  /+[out,retval]+/ DWORD *pfCatField)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetBrowseObject(in ULONG Index, 
							/+[out]+/ IDispatch *ppdispBrowseObj)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetUserContext(in ULONG Index, 
						   /+[out]+/ IUnknown *ppunkUserCtx)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT ShowHelp(in ULONG Index)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetSourceContextWithOwnership(in ULONG Index, 
										  /+[out]+/ BSTR *pbstrFileName, 
										  /+[out]+/ ULONG *pulLineNum)
	{
		mixin(LogCallMix2);
		version(none)
		{
			int line;
			string file = getSourceLoc(Index, &line);
			if (!file)
				return E_FAIL;

			*pbstrFileName = allocBSTR(file);
			*pulLineNum = line;
			return S_OK;
		}
		else
			return E_NOTIMPL;
	}
    HRESULT CountSourceItems(in ULONG Index, 
							 /+[out]+/ IVsHierarchy *ppHier, 
							 /+[out]+/ VSITEMID *pitemid, 
							 /+[out, retval]+/ ULONG *pcItems)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetMultipleSourceItems(in ULONG Index, in VSGSIFLAGS grfGSI, in ULONG cItems, 
								   /+[out, size_is(cItems)]+/ VSITEMSELECTION *rgItemSel)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT CanGoToSource(in ULONG Index, in VSOBJGOTOSRCTYPE SrcType, 
						  /+[out]+/ BOOL *pfOK)
	{
		mixin(LogCallMix2);
		if (!IsValidIndex(Index) || !pfOK)
			return E_UNEXPECTED;
		
		*pfOK = (SrcType == GS_ANY || SrcType == GS_REFERENCE);
		return S_OK;
	}
    HRESULT GoToSource(in ULONG Index, in VSOBJGOTOSRCTYPE SrcType)
	{
		mixin(LogCallMix2);

		int line, col;
		string file = getSourceLoc(Index, &line, &col);
		string modname;

		if(!file)
			return E_FAIL;
		return OpenFileInSolution(file, line, col, modname, true);
	}
    HRESULT GetContextMenu(in ULONG Index, 
						   /+[out]+/ CLSID *pclsidActive, 
						   /+[out]+/ LONG *pnMenuId, 
						   /+[out]+/ IOleCommandTarget *ppCmdTrgtActive)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT QueryDragDrop(in ULONG Index, /+[in]+/ IDataObject pDataObject, in DWORD grfKeyState, 
						  /+[in, out]+/DWORD * pdwEffect)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT DoDragDrop(in ULONG Index, /+[in]+/ IDataObject  pDataObject, in DWORD grfKeyState, 
					   /+[in, out]+/DWORD * pdwEffect)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT CanRename(in ULONG Index, in LPCOLESTR pszNewName, 
					  /+[out]+/ BOOL *pfOK)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT DoRename(in ULONG Index, in LPCOLESTR pszNewName, in VSOBJOPFLAGS grfFlags)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT CanDelete(in ULONG Index, 
					  /+[out]+/ BOOL *pfOK)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT DoDelete(in ULONG Index, in VSOBJOPFLAGS grfFlags)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT FillDescription2(in ULONG Index, in VSOBJDESCOPTIONS grfOptions, /+[in]+/ IVsObjectBrowserDescription3 pobDesc)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT EnumClipboardFormats(in ULONG Index, in VSOBJCFFLAGS grfFlags, in ULONG  celt, 
								 /+[in, out, size_is(celt)]+/ VSOBJCLIPFORMAT *rgcfFormats, 
								 /+[out, optional]+/ ULONG *pcActual)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetClipboardFormat(in ULONG Index, in VSOBJCFFLAGS grfFlags, in FORMATETC *pFormatetc, in STGMEDIUM *pMedium)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetExtendedClipboardVariant(in ULONG Index, in VSOBJCFFLAGS grfFlags, in const( VSOBJCLIPFORMAT)*pcfFormat, 
										/+[out]+/ VARIANT *pvarFormat)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetProperty(in ULONG Index, in VSOBJLISTELEMPROPID propid, 
						/+[out]+/ VARIANT *pvar)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetNavInfo(in ULONG Index, 
					   /+[out]+/ IVsNavInfo * ppNavInfo)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetNavInfoNode(in ULONG Index, 
						   /+[out]+/ IVsNavInfoNode * ppNavInfoNode)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT LocateNavInfoNode(/+[in]+/ IVsNavInfoNode  pNavInfoNode, 
							  /+[out]+/ ULONG * pulIndex)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetExpandable3(in ULONG Index, in LIB_LISTTYPE2 ListTypeExcluded, 
						   /+[out]+/ BOOL *pfExpandable)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetList2(in ULONG Index, in LIB_LISTTYPE2 ListType, in LIB_LISTFLAGS Flags, in VSOBSEARCHCRITERIA2 *pobSrch, 
					 /+[out, retval]+/ IVsSimpleObjectList2 *ppIVsSimpleObjectList2)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT OnClose(/+[out]+/ VSTREECLOSEACTIONS *ptca)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
};

class LibraryItem
{
	this(Library lib, IVsHierarchy pIVsHierarchy)
	{
		mLibrary = lib;
		mHierarchy = addref(pIVsHierarchy);
	}
	
	IVsHierarchy GetHierarchy() { return mHierarchy; }
	
	void Close()
	{
		mHierarchy = release(mHierarchy);
	}

	HRESULT ToggleState()
	{
		mCheckState = mCheckState == LCS_CHECKED ? LCS_UNCHECKED : LCS_CHECKED;
		return S_OK;
	}

	HRESULT GetCheckState(/* [out] */ LIB_CHECKSTATE *pstate)
	{
		assert(pstate);
		*pstate = mCheckState;
		return S_OK;
	}

	// Get a pointer to the main text for the list
	HRESULT GetText(/* [in]  */ VSTREETEXTOPTIONS tto, /* [out] */ const(WCHAR) **ppszText)
	{
		*ppszText = "LibItem.GetText"w.ptr;
		return S_OK;
	}

	HRESULT GetTipText(in VSTREETOOLTIPTYPE eTipType, const( WCHAR)**ppszText)
	{
		*ppszText = "LibItem.GetTipText"w.ptr;
		return S_OK;
	}

	HRESULT GetDisplayData(/* [in]  */ BOOL fIsLibraryChecked, 
						   /* [out] */ VSTREEDISPLAYDATA * pData)
	{
		assert(pData);

		return E_NOTIMPL;
	}

	Library mLibrary;
	IVsHierarchy mHierarchy;
	LIB_CHECKSTATE mCheckState;
}

struct BrowseCounter
{
	enum DWORD NULINDEX = ~0;

	HRESULT ResetChanges()
	{
		m_cChanges = 0;
		m_fIsCounterDirty = FALSE;
		m_listChanges.Index     = NULINDEX;
		m_listChanges.grfChange = TCT_NOCHANGE;
		return S_OK;
	}

	HRESULT Increment(/* [in] */  VSTREELISTITEMCHANGE listChanges)
	{
		if (m_fIsCounterDirty)
		{
			m_listChanges.Index     = NULINDEX;
			m_listChanges.grfChange = TCT_TOOMANYCHANGES;
		}
		else
		{
			m_listChanges = listChanges; 
		}

		m_fIsCounterDirty = TRUE;
		m_uCounter ++;
		m_cChanges ++;

		return S_OK;
	}

	HRESULT UpdateCounter(
		/* [out] */ ULONG *                 puCurUpdate,
		/* [out] */ VSTREEITEMCHANGESMASK * pgrfChanges)
	{
		if(puCurUpdate)
			*puCurUpdate = m_uCounter;
		if(pgrfChanges)
			*pgrfChanges = m_listChanges.grfChange;
		return S_OK;
	}

	HRESULT GetListChanges(/*[in,out]                 */ ULONG *                pcChanges, 
						   /*[in, size_is(*pcChanges)]*/ VSTREELISTITEMCHANGE * prgListChanges)
	{
		assert(pcChanges);
		assert(m_cChanges == 1);
		assert(m_fIsCounterDirty);
		assert((m_listChanges.Index != NULINDEX) || 
			   (m_listChanges.grfChange == TCT_TOOMANYCHANGES) );
		assert(m_listChanges.grfChange != TCT_NOCHANGE);

		if (!prgListChanges)
		{
			*pcChanges = m_cChanges;
			return S_OK;
		}

		assert(*pcChanges == 1);
		prgListChanges[0] = m_listChanges;
		m_fIsCounterDirty = FALSE;
		m_cChanges = 0;
		m_listChanges.Index = NULINDEX;
		m_listChanges.grfChange = TCT_NOCHANGE;

		return S_OK;
	}

private:
	ULONG m_uCounter;
	ULONG m_cChanges;
	BOOL  m_fIsCounterDirty;
	VSTREELISTITEMCHANGE m_listChanges = { NULINDEX, TCT_NOCHANGE };
}

Definition[] GetObjectLibraryDefinitions(wstring word)
{
	Definition[] defs;

	if(auto objmgr = queryService!(IVsObjectManager))
	{
		scope(exit) release(objmgr);
		if(auto objmgr2 = qi_cast!IVsObjectManager2(objmgr))
		{
			scope(exit) release(objmgr2);
			IVsEnumLibraries2 enumLibs;
			if(objmgr2.EnumLibraries(&enumLibs) == S_OK)
			{
				VSOBSEARCHCRITERIA2 searchOpts;
				searchOpts.szName = _toUTF16zw(word);
				searchOpts.eSrchType = SO_ENTIREWORD;
				searchOpts.grfOptions = VSOBSO_CASESENSITIVE;

				scope(exit) release(enumLibs);
				DWORD fetched;
				IVsLibrary2 lib;
				while(enumLibs.Next(1, &lib, &fetched) == S_OK && fetched == 1)
				{
					scope(exit) release(lib);
					if(auto slib = qi_cast!IVsSimpleLibrary2(lib))
					{
						scope(exit) release(slib);
						IVsSimpleObjectList2 reslist;
						if(slib.GetList2(LLT_MEMBERS, LLF_USESEARCHFILTER, &searchOpts, &reslist) == S_OK)
						{
							scope(exit) release(reslist);
							ULONG items;
							if(reslist.GetItemCount(&items) == S_OK && items > 0)
							{
								BOOL ok;
								for(ULONG it = 0; it < items; it++)
									if(reslist.CanGoToSource(it, GS_DEFINITION, &ok) == S_OK && ok)
									{
										
									}
							}
						}
					}
				}
			}
		}
	}
	return defs;
}
