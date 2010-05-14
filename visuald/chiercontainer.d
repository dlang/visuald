// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module chiercontainer;

import windows;
import std.string;
import std.path;
import std.utf;

import sdk.vsi.vsshell;

import hierarchy;
import chiernode;
import hierutil;
import comutil;

//-----------------------------------------------------------------------------
// Name: CHierContainer
//
// Description:
//  Class for every object in a hierarchy that has children. Implements the
//  idea of a node that has children, relies on CHierNode to take care of
//  parent/sibling info.
//
//-----------------------------------------------------------------------------
class CHierContainer : public CHierNode
{
	~this()
	{
		//DeleteAll(null);
	}

	void removeFromItemMap(bool recurse)
	{
		if(recurse)
		{
			for(CHierNode n = GetHeadEx(false); n; n = n.GetNext(false))
				n.removeFromItemMap(recurse);
		}
		super.removeFromItemMap(recurse);
	}
	
public:
	// CHierNode overrides
	bool Expandable() { return GetHead(true) !is null; }
	bool ExpandByDefault() { return false; }
	bool IsContainer() { return true; }

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
	
	VSITEMID GetFirstChildID(bool fDisplayOnly = true)
	{
		CHierNode head = GetHeadEx(fDisplayOnly);
		return head ? head.GetVsItemID() : VSITEMID_NIL;
	}

	// Used by the hierarchy in response to VSHPROPID_FirstChild/VSHPROPID_NextSibling. These
	// properties are spec'd to only return member items (visible or not)
	VSITEMID GetFirstMemberChildID()
	{
		CHierNode pNode = GetHeadEx(false);
		while(pNode && !pNode.IsMemberItem())
			pNode = pNode.GetNext(false);

		return pNode ? pNode.GetVsItemID() : VSITEMID_NIL;
	}

	// CHierContainer methods
	int Refresh(CVsHierarchy pCVsHierarchy)
	{
		DeleteAll(pCVsHierarchy);
		SetChildrenBeenEnumerated(false);
		return S_OK;
	}

	int EnumerateChildren() { return S_OK; }

	CHierNode GetHeadEx(bool fDisplayOnly = true)
	{
		if (!HaveChildrenBeenEnumerated())
		{
			// CWaitCursor cursWait;
			HRESULT hr = EnumerateChildren();
			SetChildrenBeenEnumerated(true);
			if(FAILED(hr))
				//  Failed to enumerate children. Just return that we don't have any. 
				return null;
		}
		return GetHead(fDisplayOnly);
	}
	CHierNode GetHead(bool fDisplayOnly = true)
	{
		if (!fDisplayOnly)
			return m_pHeadNode;

		CHierNode pNode = m_pHeadNode;
		if (pNode && !pNode.IsDisplayable())
			pNode = pNode.GetNext();

		return pNode;
	}
	CHierNode GetTail()
	{
		return m_pTailNode;
	}
	int GetCount(bool fDisplayOnly = true)  // return number of children
	{
		int n = 0;
		CHierNode pNext = GetHead(fDisplayOnly);

		while (pNext)
		{
			pNext = pNext.GetNext(fDisplayOnly);
			++n;
		}
		return n;
	}
	

	CHierNode GetPrevChildOf(CHierNode pCurrent, bool fDisplayOnly = true)
	{
		assert(m_pHeadNode);
		if (pCurrent is m_pHeadNode)
			return null;
		
		CHierNode pNodePrev = m_pHeadNode;
		while (pNodePrev && pNodePrev.GetNext(fDisplayOnly) !is pCurrent)
			pNodePrev = pNodePrev.GetNext(fDisplayOnly);

		// If the node we end up with isn't displayable, then there are not
		// any displayble nodes...
		if (pNodePrev && (fDisplayOnly && !pNodePrev.IsDisplayable()))
			pNodePrev = null;

		return pNodePrev;
	}

	// Override to get custom add behavior such as keeping the list sorted.
	// If not sorted list, it calls AddTail(), else calls AddSorted();
	void Add(CHierNode pNode)
	{
		if(IsSortedList())
			AddSorted(null, pNode);
		else
			AddTail(pNode);
	}

	void AddAfter(CHierNode pCurrNode, CHierNode pNewNode)
	{
		if(IsSortedList())
		{
			AddSorted(pCurrNode, pNewNode);
		}
		else if (pCurrNode)
		{
			pNewNode.SetNext(pCurrNode.GetNext(false));
			pNewNode.SetParent(pCurrNode.GetParent());
			pCurrNode.SetNext(pNewNode);

			if (pCurrNode is m_pTailNode)
				m_pTailNode = pNewNode;

			// Finally, inform the hierarchy.
			NotifyHierarchyOfAdd(pNewNode);
		}
		else
		{
			AddHead(pNewNode);
		}
	}

	void    AddHead(CHierNode pNode)
	{
		assert(pNode);

		pNode.SetParent(this);
		pNode.SetNext(m_pHeadNode);

		m_pHeadNode = pNode;
		if (!m_pTailNode)
			m_pTailNode = pNode;

		NotifyHierarchyOfAdd(pNode);
//		addref(pNode);
	}

	void    AddTail(CHierNode pNode)
	{
		assert(pNode);
		pNode.SetParent(this);
		pNode.SetNext(null);

		if(m_pTailNode)
		{
			assert(m_pHeadNode);
			m_pTailNode.SetNext(pNode);
			m_pTailNode = pNode;
		}
		else
		{
			assert(!m_pHeadNode);
			m_pHeadNode = m_pTailNode = pNode;
		}
		
		NotifyHierarchyOfAdd(pNode);
//		addref(pNode);
	}

	HRESULT Remove(CHierNode pNode)
	{
		assert(pNode);

		CHierNode pNodeCur  = m_pHeadNode; // The node to be removed
		CHierNode pNodePrev = null;        // fix this node's next pointer

		while (pNode !is pNodeCur && pNodeCur)
		{   // find pNode in list of children
			pNodePrev = pNodeCur;
			pNodeCur = pNodeCur.GetNext(false);
		}
		// ASSERT if caller gave a node not in the list
		assert(pNodeCur);
		if (!pNodeCur)
			return E_FAIL;

		// Then we found the node in the list. (this is a good thing!)
		if (pNodeCur is m_pHeadNode)
		{   // pNode is the HeadNode
			assert(pNode is m_pHeadNode);
			m_pHeadNode = pNode.GetNext(false);
			if (!m_pHeadNode)
			{   // single child case
				m_pTailNode = null;
			}
		}
		else if (pNodeCur is m_pTailNode)
		{   // We are removing the last node.
			m_pTailNode = pNodePrev;
			pNodePrev.SetNext(null);
		}
		else
		{   // We are just removing a node in the middle.
			pNodePrev.SetNext(pNode.GetNext(false));
		}

		pNode.SetParent(null);
		pNode.SetNext(null);
//		release(pNode);
		pNode.removeFromItemMap(true);
		
		return S_OK;
	}

	HRESULT Delete(CHierNode pNode, CVsHierarchy pCVsHierarchy)
	{
		if (!pNode)
			return E_INVALIDARG;

		HRESULT hr;
		if (pCVsHierarchy)
		{
			hr = pCVsHierarchy.OnItemDeleted(pNode);
			assert(SUCCEEDED(hr));
		}
		return Remove(pNode);
	}
	void    DeleteAll(CVsHierarchy pCVsHierarchy)
	{
		while (GetHead(false))
		{
			HRESULT hr = Delete(GetHead(false), pCVsHierarchy);
			assert(SUCCEEDED(hr));
		}
	}
/+
	HRESULT CloseDocuments(bool bPromptToSave = FALSE);

	// returns the node from child list who's GetDisplayName() == pszName
	CHierNode GetNodeByName(LPCTSTR pszName, bool fDisplayOnly = TRUE);
	CHierNode GetNodeByIndex(DWORD dwIndex, bool fDisplayOnly = TRUE);
	CHierNode GetNodeByVariant(VARIANT *pvar, bool fDisplayOnly = TRUE);
+/
	// Allows walking of nodes based on the IsKindOf node type.
	uint      GetNodeOfTypeCount(UINT nodeType, bool fDisplayOnly = true)
	{
		uint cnt = 0;
		for(CHierNode pNode = GetHead(fDisplayOnly); pNode; pNode = pNode.GetNext(fDisplayOnly))
			if(pNode.IsKindOf(nodeType))
				cnt++;
		return cnt;
	}
	CHierNode GetFirstNodeOfType(UINT nodeType, bool fDisplayOnly = TRUE)
	{
		for(CHierNode pNode = GetHead(fDisplayOnly); pNode; pNode = pNode.GetNext(fDisplayOnly))
			if(pNode.IsKindOf(nodeType))
				return pNode;
		return null;
	}
	CHierNode GetNextNodeOfType(UINT nodeType, CHierNode pPrevNode, bool fDisplayOnly = TRUE)
	{
		assert(pPrevNode && pPrevNode.IsKindOf(nodeType) && pPrevNode.GetParent() is this);
		for(CHierNode pNode = pPrevNode.GetNext(fDisplayOnly); pNode; pNode = pNode.GetNext(fDisplayOnly))
			if(pNode.IsKindOf(nodeType))
				return pNode;
		return null;
	}

	HRESULT   GetConfigProvider(VARIANT *pvar) { return E_NOTIMPL; }

	// Finds node 
	//CHierNode GetMatchingNode(LPCTSTR pszRelPath, bool fDisplayOnly = TRUE);

	// Sorted list info
	void SetIsSortedList(bool bValue) { SetBits(ST_SortedList, bValue); }
	bool IsSortedList() { return IsSet(ST_SortedList); }

	bool HaveChildrenBeenEnumerated() { return IsSet(ST_ChildrenEnumerated); }
	void SetChildrenBeenEnumerated(bool bValue) { SetBits(ST_ChildrenEnumerated, bValue); }

protected:
	void NotifyHierarchyOfAdd(CHierNode pNodeAdded)
	{
		if (HaveChildrenBeenEnumerated() && pNodeAdded.IsDisplayable())
		{
			CHierNode pNodePrev = GetCVsHierarchy().GetPrevDisplayableNode(pNodeAdded);
			GetCVsHierarchy().OnItemAdded(this, pNodePrev, pNodeAdded);
		}
	}

	// Used by sorted lists.
	void AddSorted(CHierNode pStartingNode, CHierNode pNode)
	{
		pNode.SetParent(this);
		pNode.SetNext(null);
		// Search for insertion point by doing an alpha comparison amongst the nodes
		// If we are passed a start node, use it as the previous, and its ptr as the curNode,
		// otherwise just start at the beginning.
		CHierNode pCurNode = pStartingNode ? pStartingNode.GetNext(false) : m_pHeadNode;
		CHierNode pPrevNode = pStartingNode;

		// Optimization to help project loads where the items are being added sorted, and there aren't really
		// any duplicates. If no startingNode is specified, do a quick check against the tail to see if it belongs there
		if(!pStartingNode && m_pTailNode)
		{
			if (CompareFilenamesForSort(m_pTailNode.GetName(), pNode.GetName()) < 0)
			{
				AddTail(pNode);
				return;
			}
		}

		while(pCurNode)
		{   // ASSERT that there are not two items with the same name since the sorting relies on this.
			if (CompareFilenamesForSort(pCurNode.GetName(), pNode.GetName()) > 0)
			{   // Insert before this folder
				if(pPrevNode)
				{   // Inserting somewhere in the middle
					pPrevNode.SetNext(pNode);
				}
				else
				{   // Inserting at the head
					m_pHeadNode = pNode;
				}
				// Update who the just added node points to, we're done.
				pNode.SetNext(pCurNode);
				break;
			}
			pPrevNode = pCurNode;
			pCurNode = pCurNode.GetNext(false);

		}
		// Past the end of the list, so this node becomes the new tail and maybe the new head too
		if(!pCurNode)
		{
			if(!m_pHeadNode)
			{
				assert(!m_pTailNode && !pPrevNode);
				m_pHeadNode = pNode;
				m_pTailNode = pNode;
			}
			else
			{
				assert(m_pTailNode && pPrevNode is m_pTailNode);
				m_pTailNode.SetNext(pNode);
				m_pTailNode = pNode;
			}
		}

		NotifyHierarchyOfAdd(pNode);
	}

	/////////////////////////////////
	CHierNode m_pHeadNode;
	CHierNode m_pTailNode;
}

