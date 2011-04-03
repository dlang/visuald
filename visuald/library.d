module library;

import comutil;
import logutil;
import hierutil;
import dpackage;
import intellisense;

import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.win32.commctrl;

import std.json;

class LibraryManager : DComObject, IVsLibraryMgr
{
	Library[] mLibraries;

	///////////////////////////
	this()
	{
		mLibraries ~= new Library;
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
                IVsLibrary,
                IVsLiteTreeList,
                IVsSolutionEvents
                //IBrowseDataProviderImpl,
                //IBrowseDataProviderEvents,
{
	string          mName = "D-Lib";
	LIB_CHECKSTATE  mCheckState;
	LIB_FLAGS       mLibFlags;
	HIMAGELIST      mImages;   //image list.

	//UpdateCounter Version Stamp
	ULONG           mLibraryCounter; 

	//Cookie used to hook up the solution events.
	VSCOOKIE        mIVsSolutionEventsCookie;  

    //Array of Projects
    LibraryItem[]   mLibraryItems;
	
	BrowseCounter   mCounterLibList;
	
	HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(*riid == IVsLibrary2Ex.iid) // keep out of log file
			return E_NOINTERFACE;

		if(queryInterface!(IVsLibrary) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsLiteTreeList) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsSolutionEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	HRESULT Initialize()
	{
		mCheckState = LCS_CHECKED;
		mLibFlags   = LF_PROJECT | LF_EXPANDABLE;
		mLibraryCounter = 0;
		
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


	// IVsLibrary ////////////////////////////////////////////////////////
    //Return E_FAIL if category not supported.
    HRESULT GetSupportedCategoryFields(in LIB_CATEGORY eCategory, 
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
				*pCatField = LCMT_FUNCTION | LCMT_VARIABLE;
				break;

			case LC_MEMBERACCESS:
				//  LCMA_PUBLIC    = 0x0001,
				//  LCMA_PRIVATE   = 0x0002,
				//  LCMA_PROTECTED = 0x0004,
				//  LCMA_PACKAGE   = 0x0008,
				//  LCMA_FRIEND    = 0x0010,
				//  LCMA_SEALED    = 0x0020
				*pCatField = LCMA_PUBLIC;
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
				*pCatField = LCCT_CLASS;
				break;

			case LC_CLASSACCESS:
				//  LCCA_PUBLIC    = 0x0001,
				//  LCCA_PRIVATE   = 0x0002,
				//  LCCA_PROTECTED = 0x0004,
				//  LCCA_PACKAGE   = 0x0008,
				//  LCCA_FRIEND    = 0x0010,
				//  LCCA_SEALED    = 0x0020
				*pCatField = LCCA_PUBLIC; 
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
				*pCatField = LLT_PACKAGE | LLT_CLASSES | LLT_MEMBERS;
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

			default:
				assert(FALSE); // Unknown category
				*pCatField = 0;
				return E_FAIL;
		}

		return S_OK;
	}

    //Retrieve a IVsObjectList interface of LISTTYPE
    HRESULT GetList(in LIB_LISTTYPE eListType,  in LIB_LISTFLAGS eFlags, in VSOBSEARCHCRITERIA *pobSrch, 
		/+[out, retval]+/ IVsObjectList *ppList)
	{
		mixin(LogCallMix2);

		if (eFlags & LLF_USESEARCHFILTER)
			return E_NOTIMPL;

		assert(ppList);
		auto ol = new ObjectList(this, eListType); //, eFlags, pobSrch);
		return ol.QueryInterface(&IVsObjectList.iid, cast(void**) ppList);
	}

    //Retreive a list of library contents (either PROJECT or GLOBAL.  Return S_FALSE and NULL if library not expandable
    HRESULT GetLibList(in LIB_PERSISTTYPE lptType, 
		/+[out, retval]+/ IVsLiteTreeList *ppList)
	{
		mixin(LogCallMix2);
		assert(ppList);

		if (LPT_PROJECT != lptType)
			return E_INVALIDARG;  // We only support project browse containers

		if(HRESULT hr = mCounterLibList.ResetChanges())
			return hr;

		*ppList = addref(this);
		return S_OK;
	}

    //Get various settings for the library
    HRESULT GetLibFlags(/+[out, retval]+/ LIB_FLAGS *pfFlags)
	{
		mixin(LogCallMix2);

		assert(pfFlags);
		*pfFlags = mLibFlags;
		return S_OK;
	}

    //Counter to check if the library has changed
    HRESULT UpdateCounter(/+[out]+/ ULONG *pCurUpdate)
	{
		mixin(LogCallMix2);

		assert(pCurUpdate);
		*pCurUpdate = mLibraryCounter;
		return S_OK;
	}

    // Unqiue guid identifying each library that never changes (even across shell instances)
    HRESULT GetGuid(const(GUID)**ppguidLib)
	{
		mixin(LogCallMix2);

		assert(ppguidLib);
		*ppguidLib = &g_omLibraryCLSID;
		return S_OK;
	}

    // Returns the separator string used to separate namespaces, classes and members 
    // eg. "::" for VC and "." for VB
    HRESULT GetSeparatorString(LPCWSTR *pszSeparator)
	{
		mixin(LogCallMix2);
		*pszSeparator = "."w.ptr;
		return S_OK;
	}

    //Retrieve the persisted state of this library from the passed stream 
    //(essentially information for each browse container being browsed). Only
    //implement for GLOBAL browse containers
    HRESULT LoadState(/+[in]+/ IStream pIStream, in LIB_PERSISTTYPE lptType)
	{
		mixin(LogCallMix2);
		// we do not save/load persisted state
		return E_NOTIMPL; 
	}

    //Save the current state of this library to the passed stream 
    //(essentially information for each browse container being browsed). Only
    //implement for GLOBAL browse containers
    HRESULT SaveState(/+[in]+/ IStream pIStream, in LIB_PERSISTTYPE lptType)
	{
		mixin(LogCallMix2);
		// we do not save/load persisted state
		return E_NOTIMPL; 
	}

    // Used to obtain a list of browse containers corresponding to the given
    // project (hierarchy). Only return a list if your package owns this hierarchy
    // Meaningful only for libraries providing PROJECT browse containers.
    HRESULT GetBrowseContainersForHierarchy(/+[in]+/ IVsHierarchy pHierarchy,
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
					if(HRESULT hr = GetGuid(&rgBrowseContainers[0].pguidLib))
						return hr;
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
    HRESULT AddBrowseContainer(in PVSCOMPONENTSELECTORDATA pcdComponent, 
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
    HRESULT RemoveBrowseContainer(in DWORD dwReserved, in LPCWSTR pszLibName)
	{
		mixin(LogCallMix2);
		// we do not support GLOBAL browse containers
		return E_NOTIMPL; 
	}

	// IVsLiteTreeList ////////////////////////////////////////////////////////
    //Fetches VSTREEFLAGS
    HRESULT GetFlags(/+[out]+/ VSTREEFLAGS *pFlags)
	{
		mixin(LogCallMix2);

		//State change and update only
		*pFlags = TF_NOEVERYTHING ^ (TF_NOSTATECHANGE | TF_NOUPDATES);
		
		return S_OK;
	}
	
    //Count of items in this list
    HRESULT GetItemCount(/+[out]+/ ULONG* pCount)
	{
		mixin(LogCallMix2);
		assert(pCount);

		*pCount = mLibraryItems.length;
		return S_OK;
	}
	
    //An item has been expanded, get the next list
    HRESULT GetExpandedList(in ULONG Index, 
		/+[out]+/ BOOL *pfCanRecurse, 
		/+[out]+/ IVsLiteTreeList *pptlNode)
	{
		mixin(LogCallMix2);

		assert(false); // TF_NOEXPANSION is set: this shouldn't be called
		return E_FAIL;
	}
	
    //Called during a ReAlign command if TF_CANTRELOCATE isn't set.  Return
    //E_FAIL if the list can't be located, in which case the list will be discarded.
    HRESULT LocateExpandedList(/+[in]+/ IVsLiteTreeList ExpandedList, 
		/+[out]+/ ULONG *iIndex)
	{
		mixin(LogCallMix2);
		
		assert(false); // TF_NOEXPANSION and TF_NORELOCATE is set: this shouldn't be called
		return E_FAIL;
	}
    //Called when a list is collapsed by the user.
    HRESULT OnClose(/+[out]+/ VSTREECLOSEACTIONS *ptca)
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
    HRESULT GetText(in ULONG uIndex, in VSTREETEXTOPTIONS tto, 
		/+[out]+/ const( WCHAR)**ppszText)
	{
		mixin(LogCallMix2);
		assert(ppszText);
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		return mLibraryItems[uIndex].GetText(tto, ppszText);
	}
    //Get a pointer to the tip text for the list item. Like GetText, caller will NOT free, implementor
    //can reuse buffer for each call to GetTipText. If you want tiptext to be same as TTO_DISPLAYTEXT, you can
    //E_NOTIMPL this call.
    HRESULT GetTipText(in ULONG uIndex, in VSTREETOOLTIPTYPE eTipType, 
		/+[out]+/ const( WCHAR)**ppszText)
	{
		mixin(LogCallMix2);

		assert(ppszText);
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		return mLibraryItems[uIndex].GetTipText(eTipType, ppszText);
	}
	
    //Is this item expandable?  Not called if TF_NOEXPANSION is set
    HRESULT GetExpandable(in ULONG uIndex, 
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
    /+[local]+/ HRESULT GetDisplayData(in ULONG uIndex, 
		/+[out]+/ VSTREEDISPLAYDATA *pData)
	{
		mixin(LogCallMix2);

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
    HRESULT UpdateCounter(/+[out]+/ ULONG *pCurUpdate,  
		/+[out]+/ VSTREEITEMCHANGESMASK *pgrfChanges)
	{
		mixin(LogCallMix2);

		return mCounterLibList.UpdateCounter(pCurUpdate, pgrfChanges);
	}

    // If prgListChanges is NULL, should return the # of changes in pcChanges. Otherwise
    // *pcChanges will indicate the size of the array (so that caller can allocate the array) to fill
    // with the VSTREELISTITEMCHANGE records
    HRESULT GetListChanges(/+[in,out]+/ ULONG *pcChanges, 
		/+[ size_is (*pcChanges)]+/ in VSTREELISTITEMCHANGE *prgListChanges)
	{
		mixin(LogCallMix2);

		// bad "in" in annotation of VSI SDK vsshell.h
		return mCounterLibList.GetListChanges(pcChanges, cast(VSTREELISTITEMCHANGE *)prgListChanges);
	}
	
    //Toggles the state of the given item (may be more than two states)
    HRESULT ToggleState(in ULONG uIndex, 
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

		if (fUpdateLibraryCounter)
			mLibraryCounter++;
		else
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
    HRESULT OnAfterOpenProject(/+[in]+/ IVsHierarchy pIVsHierarchy, in BOOL fAdded)
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
    HRESULT OnQueryCloseProject(/+[in]+/ IVsHierarchy   pHierarchy, in BOOL fRemoving, 
		/+[in,out]+/ BOOL *pfCancel)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
	
    // fRemoved == TRUE means   project removed from solution before solution close.
    // fRemoved == FALSE means project removed from solution during solution close.
    HRESULT OnBeforeCloseProject(/+[in]+/   IVsHierarchy pHierarchy, in BOOL fRemoved)
	{
		mixin(LogCallMix2);

		assert(pHierarchy);

		//Do we have this project?
		int idx;
		for(idx = 0; idx < mLibraryItems.length; idx)
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
    HRESULT OnAfterLoadProject(/+[in]+/ IVsHierarchy pStubHierarchy,   /+[in]+/ IVsHierarchy pRealHierarchy)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    HRESULT OnQueryUnloadProject(/+[in]+/   IVsHierarchy pRealHierarchy, 
		/+[in,out]+/ BOOL *pfCancel)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    HRESULT OnBeforeUnloadProject(/+[in]+/ IVsHierarchy pRealHierarchy, /+[in]+/   IVsHierarchy pStubHierarchy)
	{
		mixin(LogCallMix2);
		return S_OK;
	}

    // fNewSolution == TRUE means   solution is being created now.
    // fNewSolution == FALSE means solution was created previously, is being loaded.
    HRESULT OnAfterOpenSolution(/+[in]+/ IUnknown   pUnkReserved, in BOOL fNewSolution)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    HRESULT OnQueryCloseSolution(/+[in]+/   IUnknown pUnkReserved, 
		/+[in,out]+/ BOOL *pfCancel)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    HRESULT OnBeforeCloseSolution(/+[in]+/ IUnknown pUnkReserved)
	{
		mixin(LogCallMix2);
		return S_OK;
	}
    HRESULT OnAfterCloseSolution(/+[in]+/   IUnknown pUnkReserved)
	{
		mixin(LogCallMix2);
		return S_OK;
	}

}

string GetInfoName(JSONValue val)
{
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* v = "name" in val.object)
			if(v.type == JSON_TYPE.STRING)
				return v.str;
	return null;
}

string GetInfoKind(JSONValue val)
{
	if(val.type == JSON_TYPE.OBJECT)
		if(JSONValue* v = "kind" in val.object)
			if(v.type == JSON_TYPE.STRING)
				return v.str;
	return null;
}

class ObjectList : DComObject, IVsObjectList
{
	// CComPtr<IBrowseDataProvider> m_srpIBrowseDataProvider;
	// VSCOOKIE         m_dwIBrowseDataProviderEventsCookie;
	Library mLibrary;   // Holds a pointer to the library
	LIB_LISTTYPE  mListType;     //type of the list
	BrowseCounter mCounter;
	LibraryInfo mLibInfo;
	JSONValue mObject;
		
	this(Library lib, in LIB_LISTTYPE eListType)
	{
		mLibrary = lib;
		mListType = eListType;
		
		LibraryInfos infos = Package.GetLibInfos();
		mLibInfo = infos.findInfo("phobos");
		if(mLibInfo)
			mObject = mLibInfo.mModules;
	}

	this(Library lib, LibraryInfo libInfo, JSONValue object)
	{
		mLibrary = lib;
		mLibInfo = libInfo;
		mObject = object;
	}
	
	HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsObjectList) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsLiteTreeList) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	int GetCount()
	{
		if(!mLibInfo)
			return 0;
		if(mObject.type == JSON_TYPE.ARRAY)
			return mObject.array.length;
		if(mObject.type == JSON_TYPE.OBJECT)
			if(JSONValue* m = "members" in mObject.object)
				if(m.type == JSON_TYPE.ARRAY)
					return m.array.length;
		return 0;
	}
	
	bool IsValidIndex(/* [in] */ ULONG uIndex)
	{
		return uIndex < GetCount();
	}

	JSONValue GetObject(ULONG idx)
	{
		if(!mLibInfo)
			return JSONValue();
		if(mObject.type == JSON_TYPE.ARRAY)
			if(idx < mObject.array.length)
				return mObject.array[idx];
		if(mObject.type == JSON_TYPE.OBJECT)
			if(JSONValue* m = "members" in mObject.object)
				if(m.type == JSON_TYPE.ARRAY)
					if(idx < mObject.array.length)
						return m.array[idx];
		return JSONValue();
	}
		
	string GetName(ULONG idx)
	{
		JSONValue v = GetObject(idx);
		return GetInfoName(v);
	}

	string GetKind(ULONG idx)
	{
		JSONValue v = GetObject(idx);
		return GetInfoKind(v);
	}
	
	// IVsLiteTreeList ///////////////////////////////////////////////////////
    HRESULT GetFlags(/+[out]+/ VSTREEFLAGS *pFlags)
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
    HRESULT GetItemCount(/+[out]+/ ULONG* pCount)
	{
		mixin(LogCallMix2);
		assert(pCount);
		
		*pCount = GetCount();
		return S_OK;
	}
	
    //An item has been expanded, get the next list
    HRESULT GetExpandedList(in ULONG Index, 
		/+[out]+/ BOOL *pfCanRecurse, 
		/+[out]+/ IVsLiteTreeList *pptlNode)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}

	//Called during a ReAlign command if TF_CANTRELOCATE isn't set.  Return
    //E_FAIL if the list can't be located, in which case the list will be discarded.
    HRESULT LocateExpandedList(/+[in]+/ IVsLiteTreeList ExpandedList, 
		/+[out]+/ ULONG *iIndex)
	{
		mixin(LogCallMix2);
		return E_FAIL;
	}
    
	//Called when a list is collapsed by the user.
    HRESULT OnClose(/+[out]+/ VSTREECLOSEACTIONS *ptca)
	{
		mixin(LogCallMix2);
		
		assert(ptca);
		*ptca = TCA_NOTHING;
		
		return E_NOTIMPL;
	}

	//Get a pointer to the main text for the list item. Caller will NOT free, implementor
    //can reuse buffer for each call to GetText except for TTO_SORTTEXT. See VSTREETEXTOPTIONS for tto details
    HRESULT GetText(in ULONG uIndex, in VSTREETEXTOPTIONS tto, 
		/+[out]+/ const( WCHAR)**ppszText)
	{
		mixin(LogCallMix2);
		
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		string name = GetName(uIndex);
		
		static wchar* wname;
		wname = _toUTF16z(name); // keep until next call
		*ppszText = wname;
		return S_OK;
	}
    
	//Get a pointer to the tip text for the list item. Like GetText, caller will NOT free, implementor
    //can reuse buffer for each call to GetTipText. If you want tiptext to be same as TTO_DISPLAYTEXT, you can
    //E_NOTIMPL this call.
    HRESULT GetTipText(in ULONG Index, in VSTREETOOLTIPTYPE eTipType, 
		/+[out]+/ const( WCHAR)**ppszText)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	} 
    
	//Is this item expandable?  Not called if TF_NOEXPANSION is set
    HRESULT GetExpandable(in ULONG uIndex, 
		/+[out]+/ BOOL *pfExpandable)
	{
		mixin(LogCallMix2);
		assert(pfExpandable);
		
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;

		if (GetCount() > 0) // mListType & (LLT_PACKAGE | LLT_CLASSES))
			*pfExpandable = TRUE;
		else
			*pfExpandable = FALSE;
		return S_OK;
	}
	
    //Retrieve information to draw the item
    /+[local]+/ HRESULT GetDisplayData(in ULONG Index, 
		/+[out]+/ VSTREEDISPLAYDATA *pData)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    //Return latest update increment.  True/False isn't sufficient here since
    //multiple trees may be using this list.  Returning an update counter > than
    //the last one cached by a given tree will force calls to GetItemCount and
    //LocateExpandedList as needed.
    HRESULT UpdateCounter(/+[out]+/ ULONG *pCurUpdate,  
		/+[out]+/ VSTREEITEMCHANGESMASK *pgrfChanges)
	{
		mixin(LogCallMix2);
	    return mCounter.UpdateCounter(pCurUpdate, pgrfChanges);
	}
    
	// If prgListChanges is NULL, should return the # of changes in pcChanges. Otherwise
    // *pcChanges will indicate the size of the array (so that caller can allocate the array) to fill
    // with the VSTREELISTITEMCHANGE records
    HRESULT GetListChanges(/+[in,out]+/ ULONG *pcChanges, 
		/+[ size_is (*pcChanges)]+/ in VSTREELISTITEMCHANGE *prgListChanges)
	{
		mixin(LogCallMix2);
	    return mCounter.GetListChanges(pcChanges, cast(VSTREELISTITEMCHANGE *) prgListChanges);
	}
    //Toggles the state of the given item (may be more than two states)
    HRESULT ToggleState(in ULONG Index, 
		/+[out]+/ VSTREESTATECHANGEREFRESH *ptscr)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}

	// IVsObjectList /////////////////////////////////////////////////////////////
    HRESULT GetCapabilities(/+[out]+/  LIB_LISTCAPABILITIES *pCapabilities)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Get a sublist
    HRESULT GetList(in ULONG uIndex, in LIB_LISTTYPE ListType, in LIB_LISTFLAGS Flags, in VSOBSEARCHCRITERIA *pobSrch, 
		/+[out]+/ IVsObjectList *ppList)
	{
		mixin(LogCallMix2);
		auto obj = GetObject(uIndex);
		if(obj.type != JSON_TYPE.OBJECT)
			return E_UNEXPECTED;

		auto list = new ObjectList(mLibrary, mLibInfo, obj);
		return list.QueryInterface(&IVsObjectList.iid, cast(void**) ppList);
	}
	
    HRESULT GetCategoryField(in ULONG uIndex, in LIB_CATEGORY Category, 
		/+[out,retval]+/ DWORD* pField)
	{
		mixin(LogCallMix2);
		assert(pField);

		if(Category == LC_LISTTYPE && uIndex == BrowseCounter.NULINDEX)
		{
			// child list types supported under this list
			*pField = LLT_PACKAGE | LLT_CLASSES | LLT_MEMBERS;
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
						*pField = LLT_PACKAGE;
						break;
					case "class":
						*pField = LLT_CLASSES;
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
			default:
				return E_NOTIMPL;
		}
		return S_OK;
	}

    HRESULT GetExpandable2(in ULONG Index, in LIB_LISTTYPE ListTypeExcluded, 
		/+[out]+/ BOOL *pfExpandable)
	{
		mixin(LogCallMix2);
		assert(pfExpandable);

		if (GetCount() > 0) // mListType & (LLT_PACKAGE | LLT_CLASSES))
			*pfExpandable = TRUE;
		else
			*pfExpandable = FALSE;
		
		return S_OK;
	}
	
    HRESULT GetNavigationInfo(in ULONG uIndex, /+[in, out]+/ VSOBNAVIGATIONINFO2 *pobNav)
	{
		mixin(LogCallMix2);
		if (!IsValidIndex(uIndex))
			return E_UNEXPECTED;
		
		assert(pobNav);

		if(HRESULT hr = mLibrary.GetGuid(&(pobNav.pguidLib)))
			return hr;
		assert(pobNav.pName);
		pobNav.pName.lltName = mListType;
		return GetText(uIndex, 0, &pobNav.pName.pszName);
	}
    HRESULT LocateNavigationInfo(in VSOBNAVIGATIONINFO2 *pobNav, in VSOBNAVNAMEINFONODE *pobName, in BOOL fDontUpdate, 
		/+[out]+/ BOOL *pfMatchedName, 
		/+[out]+/ ULONG *pIndex)
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
    HRESULT GetSourceContext(in ULONG Index, 
		/+[out]+/ const( WCHAR)**pszFileName, 
		/+[out]+/ ULONG *pulLineNum)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}

    // Returns the count of itemids (these must be from a single hierarchy) that make up the source files
    // for the list element at Index. Also returns the hierarchy ptr and itemid if requested.
    // If there are >1 itemids, return VSITEMID_SELECTION and a subsequent call will be made
    // on GetMultipleSourceItems to get them. If there are no available source items, return
    // VSITEMID_ROOT to indicate the root of the hierarchy as a whole.
    HRESULT CountSourceItems(in ULONG Index, 
		/+[out]+/ IVsHierarchy *ppHier, 
		/+[out]+/ VSITEMID *pitemid, 
		/+[out, retval]+/ ULONG *pcItems)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Used if CountSourceItems returns > 1. Details for filling up these out params are same 
    // as IVsMultiItemSelect::GetSelectedItems
    HRESULT GetMultipleSourceItems(in ULONG Index, in VSGSIFLAGS grfGSI, in ULONG cItems, 
		/+[out, size_is(cItems)]+/ VSITEMSELECTION *rgItemSel)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Return TRUE if navigation to source of the specified type (definition or declaration),
    // is possible, FALSE otherwise
    HRESULT CanGoToSource(in ULONG Index, in VSOBJGOTOSRCTYPE SrcType, 
		/+[out]+/ BOOL *pfOK)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Called to cause navigation to the source (definition or declration) for the
    // item Index. You must must coordinate with the project system to open the
    // source file and navigate it to the approp. line. Return S_OK on success or an
    // hr error (along with rich error info if possible) if the navigation failed.
    HRESULT GoToSource(in ULONG Index, in VSOBJGOTOSRCTYPE SrcType)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetContextMenu(in ULONG Index, 
		/+[out]+/ CLSID *pclsidActive, 
		/+[out]+/ LONG *pnMenuId, 
		/+[out]+/ IOleCommandTarget *ppCmdTrgtActive)
	{
		// mixin(LogCallMix2);
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
    // Says whether the item Index can be renamed or not. If the passed in pszNewName is NULL,
    // it simply answers the general question of whether or not that item supports rename
    // (return TRUE or FALSE). If pszNewName is non-NULL, do validation of the new name
    // and return TRUE if successful rename with that new name is possible or an an error hr (along with FALSE)
    // if the name is somehow invalid (and set the rich error info to indicate to the user
    // what was wrong) 
    HRESULT CanRename(in ULONG Index, in LPCOLESTR pszNewName, 
		/+[out]+/ BOOL *pfOK)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Called when the user commits the Rename operation. Guaranteed that CanRename has already
    // been called with the newname so that you've had a chance to validate the name. If
    // Rename succeeds, return S_OK, other wise error hr (and set the rich error info)
    // indicating the problem encountered.
    HRESULT DoRename(in ULONG Index, in LPCOLESTR pszNewName, in VSOBJOPFLAGS grfFlags)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Says whether the item Index can be deleted or not. Return TRUE if it can, FALSE if not.
    HRESULT CanDelete(in ULONG Index, 
		/+[out]+/ BOOL *pfOK)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Called when the user asks to delete the item at Index. Will only happen if CanDelete on
    // the item previously returned TRUE. On a successful deletion this should return S_OK, if
    // the deletion failed, return the failure as an error hresult and set any pertinent error
    // info in the standard ole error info.
    HRESULT DoDelete(in ULONG Index, in VSOBJOPFLAGS grfFlags)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    // Used to add the description pane text in OBject Browser. Also an alternate
    // mechanism for providing tooltips (ODO_TOOLTIPDESC is set in that case)
    HRESULT FillDescription(in ULONG Index, in VSOBJDESCOPTIONS grfOptions, /+[in]+/ IVsObjectBrowserDescription2 pobDesc)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
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
    HRESULT EnumClipboardFormats(in ULONG Index, 
        in VSOBJCFFLAGS grfFlags,
        in ULONG  celt, 
        /+[in, out, size_is(celt)]+/ VSOBJCLIPFORMAT *rgcfFormats,
        /+[out, optional]+/ ULONG *pcActual)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetClipboardFormat(in ULONG Index,
        in    VSOBJCFFLAGS grfFlags,
        in    FORMATETC *pFormatetc,
        in    STGMEDIUM *pMedium)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}
    HRESULT GetExtendedClipboardVariant(in ULONG Index,
        in VSOBJCFFLAGS grfFlags,
        in const( VSOBJCLIPFORMAT)*pcfFormat,
        /+[out]+/ VARIANT *pvarFormat)
	{
		mixin(LogCallMix2);
		return E_NOTIMPL;
	}

}

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
		*puCurUpdate = m_uCounter;
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
};
