// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module chiernode;

import std.c.windows.windows;
import std.c.windows.com;
import std.string;
import std.path;
import std.utf;

import sdk.vsi.vsshell;

import hierarchy;
import comutil;
import logutil;
import hierutil;
import stringutil;

//import dproject;

enum ICON_TYPE
{
	ICON_Open,
	ICON_Closed,
	ICON_StateImage
}

import chiercontainer;

const UINT IDMX_NULLMENU = 0;

CHierNode[VSITEMID] gVsItemMap;

class CIVsTaskItemArray {}
class OpenDocumentList {}

//---------------------------------------------------------------------------
// Name: CHierNode
//
// Description:
//  Base node class for every object in a hierarchy. Implements the idea of
//  a node that has a parent, but no children.
//
//---------------------------------------------------------------------------
class CHierNode : DisposingDispatchObject
{
	this()
	{
		m_grfStateFlags = ST_DefaultFlags;
		gVsItemMap[GetVsItemID()] = this;
		logCall("added %d to gVsItemMap", GetVsItemID());
	}
	~this()
	{
		gVsItemMap.remove(GetVsItemID());
		logCall("removed %d from gVsItemMap", GetVsItemID());
	}

	/*override*/ void Dispose()
	{
	}

public:
	// IsKindOf checking
	uint GetKindOf() { return 0; }
	bool IsKindOf(uint hKind) { return (hKind == (hKind & GetKindOf())); }

	// return a CHierNode typecasted to a VSITEMID or VISTEMID_ROOT
	// Override in each derived class that can also be a VSITEMID_ROOT
	VSITEMID GetVsItemID() { return cast(VSITEMID) cast(void*) this; }

	// return the itemid of the first child or VSITEMID_NIL
	VSITEMID GetFirstChildID(bool fDisplayOnly = true) { return VSITEMID_NIL; }

	// Used by the hierarchy in response to VSHPROPID_FirstChild/VSHPROPID_NextSibling. These
	// properties are spec'd to only return member items (visible or not)
	VSITEMID GetFirstMemberChildID() { return VSITEMID_NIL; }
	VSITEMID GetNextMemberSiblingID() 
	{
		CHierNode pNode = m_pNodeNext;
		while(pNode && !pNode.IsMemberItem())
			pNode = pNode.m_pNodeNext;

		return pNode ? pNode.GetVsItemID() : VSITEMID_NIL;
	}

	// is this node expandable in the shell?
	// should this node be auto expanded in the shell?
	bool Expandable() { return false; }
	bool ExpandByDefault() { return false; }

	// is this node a container in the shell? it may be a container
	// and still not be expandable if all child items are hidden.
	bool IsContainer() { return false; }

	// traverses to root node via parents
	// the root node is expected to return the associated CVsHierarchy
	CVsHierarchy GetCVsHierarchy()
	{
		if(!GetParent() || IsZombie())
			return null;

		CHierNode pNode = GetRootNode();
		return pNode.GetCVsHierarchy();
	}

	//---------------------------------------------------------------------------
	// Base-implementation of GetNestedHierarchy handles the failure case. Any
	//  node which will contain another hierarchy must over-ride this method.
	//---------------------------------------------------------------------------
 	int GetNestedHierarchy(in IID* riid, void **ppVsHierarchy, out VSITEMID pitemidNested)
	{
		return E_FAIL;
	}

	uint GetContextMenu() { return IDMX_NULLMENU; }

	// all nodes which neeed to handle these functions should over-ride them
	UINT GetIconIndex(ICON_TYPE it)
	{
		assert(false, "You should be calling an over-ridden version of this...");
	}

	string GetCanonicalName()
	{
		string name = GetFullPath();
		return tolower(name);
	}

	string GetFullPath()
	{
		return m_strName;
	}

	int DoDefaultAction()
	{
		// each node which has a "default" action must over-ride
		return S_OK;
	}

	// Property functions
	int GetProperty(VSHPROPID propid, out VARIANT pvar)
	{
		switch(propid)
		{
		case VSHPROPID_Name:
		case VSHPROPID_Caption:
			pvar.vt = VT_BSTR;
			// don't return a display caption longer than _MAX_PATH-1, since the tree control cannot
			// handle it. instead, truncate the caption by ellipsing it (terminating it with "...").
			pvar.bstrVal = allocBSTR(ellipseString(GetDisplayCaption(), _MAX_PATH));
			return S_OK;
		case VSHPROPID_IsNonMemberItem:
			pvar.vt = VT_BOOL;
			pvar.boolVal = IsMemberItem();
			return S_OK;
		case VSHPROPID_Expanded:
			pvar.vt = VT_BOOL;
			pvar.boolVal = IsExpanded();
			return S_OK;
		case VSHPROPID_AltHierarchy:
			pvar.vt = VT_UNKNOWN;
			pvar.punkVal = addref(GetCVsHierarchy());
			return S_OK;
		case VSHPROPID_AltItemid:
			pvar.vt = VT_I4;
			pvar.lVal = GetVsItemID();
			return S_OK;

		case VSHPROPID_BrowseObject:
			return QueryInterface(&IDispatch.iid, cast(void **)&pvar.pdispVal);

		default:
			break;
		}
		return DISP_E_MEMBERNOTFOUND;
	}

	int SetProperty(VSHPROPID propid, in VARIANT var)
	{
		switch(propid)
		{
		case VSHPROPID_Expanded:
			SetIsExpanded(var.boolVal != 0);
			return S_OK;
		default:
			break;
		}
		return DISP_E_MEMBERNOTFOUND;
	}

	// These three are to allow you to do something in response to the label
	// edit.  They just tell you the change in state, the changing of the name of your
	// item will be handled through the SetProperty command. Note they track the
	// following shell commands to our hierarchy:
	//      UIHWCMDID_StartLabelEdit
	//      UIHWCMDID_CommitLabelEdit
	//      UIHWCMDID_CancelLabelEdit
	// Defaults do nothing
	int OnStartLabelEdit()
	{
		return S_OK;
	}
	int OnCommitLabelEdit()
	{
		return S_OK;
	}
	int OnCancelLabelEdit()
	{
		return S_OK;
	}
	
	// VSHPROPID.EditLabel
	int GetEditLabel(BSTR *ppEditLabel)
	{
		//*ppEditLabel = allocBSTR(GetName());
		//return S_OK;
		return E_NOTIMPL;
	}
	int SetEditLabel(in BSTR pEditLabel)
	{
		 return E_NOTIMPL;
	}

	// Task list support. Allows adding tasks to the passed in task array. Default does nothing
	int GetTasks(CIVsTaskItemArray *pTaskItemArray) { return S_OK; }

	// CHierNode Properties
	string GetName() 
	{ 
		return m_strName; 
	}
	void SetName(string newName, CVsHierarchy pCVsHierarchy = null)
	{
		m_strName = newName;
		if (pCVsHierarchy)
			pCVsHierarchy.OnPropertyChanged(this, VSHPROPID_Caption, 0);
	}

	// CHierNode Properties
	// VSHPROPID_Caption
	string GetDisplayCaption() 
	{ 
		return getBaseName(m_strName);
	}

	// VSHPROPID_Parent
	CHierContainer GetParent() { return m_pNodeParent; }
	void SetParent(CHierContainer pNode) { m_pNodeParent = pNode; }
	
	// VSHPROPID_NextSibling
	void SetNext(CHierNode pHierNode) { m_pNodeNext = pHierNode; }
	CHierNode GetNext(bool fDisplayOnly = true)
	{
		CHierNode pNode = m_pNodeNext;

		if(fDisplayOnly)
			while(pNode && !pNode.IsDisplayable())
				pNode = pNode.m_pNodeNext;
		return pNode;
	}

	CHierNode GetHeadEx(bool fDisplayOnly = true) { return null; }

	//---------------------------------------------------------------------------
	// Gets the child of this object's parent that occurs directly before
	//  this node in the parent's list. This is an expensive operation, and is
	//  nowhere as straight-forward as getting the next child in this list.
	//---------------------------------------------------------------------------
	CHierNode GetPrev(bool fDisplayOnly = true)
	{
		if(GetParent())
			return GetParent().GetPrevChildOf(this, fDisplayOnly);
		return null;
	}

	// traverse the parent nodes and return node whose parent is NULL
	CHierNode GetRootNode()
	{
		CHierNode pNode = this;
		while(pNode.GetParent())
			pNode = pNode.GetParent();
		return pNode;
	}

	// is the given node an ancestor of this node
	bool HasAncestor(CHierNode pNode)
	{
		CHierNode pAncestor = GetParent();
		for(; pAncestor; pAncestor = pAncestor.GetParent())
			if (pAncestor is pNode)
				return true;
		return false;
	}

	/+
	int ExtExpand(EXPANDFLAGS expandflags, ref GUID rguidPersistenceSlot = GUID_SolutionExplorer)
	{
		return E_FAIL;
	}
	+/

	//Is this node a zombie, with no Root node in it's hierarchy
	bool IsZombie()
	{
		CHierNode pNode = GetRootNode();
		if (!pNode) // || (VSITEMID_ROOT != pNode.GetVsItemID())) 
			return true;
		return false;
	}

	// Static helper which is used to detect stale itemid's for nodes which have
	// gone away (different than the zombie case).
	static bool IsValidCHierNode(VSITEMID itemid)
	{
		if(itemid in gVsItemMap)
			return true;
		return false;
	}

	// Updates UI
	void ReDraw(bool bUpdateIcon = true, bool bUpdateStateIcon = true, bool bUpdateText = false)
	{
		// Root object or item must be in UI.
		CHierContainer pParent = GetParent();
		if(!pParent || pParent.HaveChildrenBeenEnumerated())
		{
			CVsHierarchy pHier = GetCVsHierarchy();
			if(bUpdateIcon)
				pHier.OnPropertyChanged(this, VSHPROPID_IconIndex, 0);
			if(bUpdateStateIcon)
				pHier.OnPropertyChanged(this, VSHPROPID_StateIconIndex, 0);
			if(bUpdateText)
				pHier.OnPropertyChanged(this, VSHPROPID_Caption, 0);
		}
	}

	int IsDocumentOpen(OpenDocumentList *rgOpenDocuments = null) { return S_FALSE; }
	int CloseDocuments(bool bPromptToSave = false)
	{
		int hrRet = S_OK;  
		assert(!IsZombie());
		if(IsZombie())
			return S_OK;

/+
		// We walk the RDT looking for all running documents attached to this hierarchy and itemid. There
		// are cases where there may be two different editors (not views) open on the same document.
		CComPtr<IEnumRunningDocuments> srpEnumRDT;
		IVsRunningDocumentTable* pRDT = _VxModule.GetIVsRunningDocumentTable();
		ASSERT(pRDT);
		if(!pRDT)
			return S_OK;

		HRESULT hr = pRDT.GetRunningDocumentsEnum(&srpEnumRDT);
		ASSERT(SUCCEEDED(hr));
		if(SUCCEEDED(hr))
		{  
			VSCOOKIE dwDocCookie;
			VSSLNCLOSEOPTIONS saveOptions = bPromptToSave? SLNSAVEOPT_PromptSave : SLNSAVEOPT_NoSave;
			CComPtr<IVsHierarchy> srpOurHier = GetCVsHierarchy().GetIVsHierarchy();
			srpEnumRDT.Reset();
			while(srpEnumRDT.Next(1, &dwDocCookie, NULL) == S_OK)
			{
				// Note we can pass NULL for all parameters we don't care about
				CComPtr<IVsHierarchy> srpHier;
				VSITEMID itemid = VSITEMID_NIL;
				pRDT.GetDocumentInfo(dwDocCookie, NULL/*pgrfRDTFlags*/, NULL/*pdwReadLocks*/, NULL/*pdwEditLocks*/, 
					NULL /*bstrMkDocumentOld*/, &srpHier, &itemid, NULL /*ppunkDocData*/);

				// Is this one of our documents?
				if(srpHier is srpOurHier && itemid == GetVsItemID())
				{
					// This is the only hr return code we care about
					hrRet =  _VxModule.GetIVsSolution().CloseSolutionElement(saveOptions, srpOurHier, dwDocCookie);
					if(FAILED(hrRet))
						break;
				}
			}
		}
+/
		return hrRet;
	}

	int SaveDocument(bool bPromptToSave = false)
	{
		return E_FAIL;
	}

	// VSHPROPID_UserContext
	int GetUserContext(IVsUserContext **ppUserCtx)
	{
		return E_NOTIMPL;
	}

	DWORD GetDisplayOrder() { return 0; }

	HRESULT GetGuidProperty(VSHPROPID propid, out GUID pGuid)
	{
		return E_NOTIMPL;
	}

	// IOleCommandTarget
public:
	int QueryStatus( 
		/* [unique][in] */ in GUID *pguidCmdGroup,
		/* [in] */ ULONG cCmds,
		/* [out][in][size_is] */ OLECMD* prgCmds,
		/* [unique][out][in] */ OLECMDTEXT *pCmdText)
	{
		//ATLTRACENOTIMPL(_T("CHierNode::IOleCommandTarget::QueryStatus"));
		return OLECMDERR.E_NOTSUPPORTED;
	}

	int Exec( 
		/* [unique][in] */ in GUID *pguidCmdGroup,
		/* [in] */ DWORD nCmdID,
		/* [in] */ DWORD nCmdexecopt,
		/* [unique][in] */ VARIANT *pvaIn,
		/* [unique][out][in] */ VARIANT *pvaOut)
	{
		//ATLTRACENOTIMPL(_T("CHierNode::IOleCommandTarget::Exec"));
		return OLECMDERR.E_NOTSUPPORTED;
	}

	// Bit state functions
public:
	void SetIsDisplayable(bool bValue) { SetBits(ST_Displayable, bValue); }
	bool IsDisplayable()          { return IsSet(ST_Displayable); }
	void SetIsOpen(bool bValue)        { SetBits(ST_IsOpen, bValue); }
	bool IsOpen()                 { return IsSet(ST_IsOpen); }
	void SetIsMemberItem(bool bValue)  { SetBits(ST_IsMemberItem, bValue); }
	bool IsMemberItem()           { return IsSet(ST_IsMemberItem); }
	void SetIsExpanded(bool bValue)    { SetBits(ST_Expanded, bValue); }
	bool IsExpanded()             { return IsSet(ST_Expanded); }

	//////////////////////////////////////////////////////////////
	__gshared static ComTypeInfoHolder mTypeHolder;
	shared static this()
	{
		mTypeHolder = new class ComTypeInfoHolder {
			override int GetIDsOfNames( 
				/* [size_is][in] */ LPOLESTR *rgszNames,
				/* [in] */ in UINT cNames,
				/* [size_is][out] */ MEMBERID *pMemId)
			{
				mixin(LogCallMix);
				if (cNames == 1 && to_string(*rgszNames) == "__id")
				{
					*pMemId = 2;
					return S_OK;
				}
				return returnError(E_NOTIMPL);
			}
		};
		addref(mTypeHolder);
	}

	override ComTypeInfoHolder getTypeHolder () { return mTypeHolder; }
	//////////////////////////////////////////////////////////////

	override int Invoke( 
		/* [in] */ in DISPID dispIdMember,
		/* [in] */ in IID* riid,
		/* [in] */ in LCID lcid,
		/* [in] */ in WORD wFlags,
		/* [out][in] */ DISPPARAMS *pDispParams,
		/* [out] */ VARIANT *pVarResult,
		/* [out] */ EXCEPINFO *pExcepInfo,
		/* [out] */ UINT *puArgErr)
	{
		mixin(LogCallMix);

		if(dispIdMember == 1 || dispIdMember == 2)
		{
			if(pDispParams.cArgs == 0)
				return GetProperty(VSHPROPID_Name, *pVarResult);
		}
		return returnError(E_NOTIMPL);
	}
	//////////////////////////////////////////////////////////////

protected:
	CHierContainer m_pNodeParent;
	CHierNode      m_pNodeNext;    // to form a singly-linked list
	string         m_strName;      // this node's name

	uint           m_grfStateFlags;        // ChildrenEnumerated, etc
	enum    // m_grfStateFlags
	{
		ST_ChildrenEnumerated = (1<<0),
		ST_IsOpen             = (1<<1), // File is open in an editor. Note user controlled. does not check
		ST_Displayable        = (1<<2),
		ST_SortedList         = (1<<3), // Containers only. True if a sorted by alpha list.
		ST_IsMemberItem       = (1<<4), // true if this node is a member of the project
		ST_Expanded           = (1<<5),
		ST_FirstUserFlag      = (1<<8), // Derived classes are free to use these upper 24 bits

		ST_DefaultFlags       = (ST_Displayable | ST_IsMemberItem)
	}
	// m_grfStateFlags bit helpers
	bool    IsSet(int bits) { return (m_grfStateFlags & bits) != 0; }
	void    SetBits(int bits, bool bValue)
	{
		if(bValue)
			m_grfStateFlags |=  bits;
		else
			m_grfStateFlags &= ~bits;
	}
}
