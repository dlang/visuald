// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.trackprojectdocument;

import visuald.windows;
import visuald.comutil;

import sdk.win32.oleauto;
import sdk.win32.objbase;
import sdk.vsi.vsshell;
import sdk.vsi.ivstrackprojectdocuments2;
import visuald.hierutil;
import visuald.hierarchy;
import visuald.chiernode;

import std.utf;

enum ProjectEventFlags
{	
	None             = 0,
	IsNestedProject  = 0x1
}

// All events involving Adding, Removing, and Renaming of items in the project
// need to be announced to the IVsTrackProjectDocuments service. This service
// inturns manages broadcasting these events to interesting parties.
// For example, these events allow the Source Code Control (SCC) manager
// to coordinate SCC for the project items. These events allow the debugger to
// manage its list of breakpoints. There will be other interested parties.
//
// The class encapsulates the shell's IVsTrackProjectDocuments2 interface
// That makes it more consistent for project's rename/add/delete code.
// These methods are invoked when an project change originates internally. 
// The methods just pass off to the shell methods in 
// SID_SVsTrackProjectDocuments2, which notifies other hierarchies
// that we are about to change or have changed some files.
// 

class CVsTrackProjectDocuments2Helper
{
public:

	this(CVsHierarchy hier)
	{
		mHierarchy = hier;
	}

	bool CanAddItem(
		/* [in] */ string            file,
		/* [in] */ ProjectEventFlags flags = ProjectEventFlags.None)
	{
		IVsTrackProjectDocuments2 srpIVsTrackProjectDocuments2 = GetIVsTrackProjectDocuments2();
		if(!srpIVsTrackProjectDocuments2)
			return true;
		scope(exit) release(srpIVsTrackProjectDocuments2);

		IVsProject pIVsProject = cast(IVsProject) mHierarchy;
		assert(pIVsProject);

		VSQUERYADDFILERESULTS fSummaryResult = VSQUERYADDFILERESULTS_AddOK;
		VSQUERYADDFILEFLAGS   fInputFlags = (flags & ProjectEventFlags.IsNestedProject) ? VSADDFILEFLAGS_IsNestedProjectFile : VSADDFILEFLAGS_NoFlags;

		auto pszFile = _toUTF16z(file);
		if(SUCCEEDED(srpIVsTrackProjectDocuments2.OnQueryAddFiles(pIVsProject, 1, &pszFile,
									  &fInputFlags, &fSummaryResult, null)))
		{
			if(VSQUERYADDFILERESULTS_AddNotOK == fSummaryResult) 
				return false;
		}
		return true;
	}

	void OnItemAdded( 
		/* [in] */ CHierNode         pCHierNode,
		/* [in] */ ProjectEventFlags flags = ProjectEventFlags.None)
	{
		IVsTrackProjectDocuments2 srpIVsTrackProjectDocuments2 = GetIVsTrackProjectDocuments2();
		if(!srpIVsTrackProjectDocuments2)
			return;
		scope(exit) release(srpIVsTrackProjectDocuments2);

		IVsProject pIVsProject = cast(IVsProject) mHierarchy;
		assert(pIVsProject);

		ScopedBSTR cbstrMkDokument;
		HRESULT hr = pIVsProject.GetMkDocument(pCHierNode.GetVsItemID(), &cbstrMkDokument.bstr);
		if (FAILED(hr))
			return;

		VSADDFILEFLAGS fInputFlags = (flags & ProjectEventFlags.IsNestedProject) ? VSADDFILEFLAGS_IsNestedProjectFile : VSADDFILEFLAGS_NoFlags;
		
		wchar*[] rgstrDocuments = [ cbstrMkDokument.bstr ];
		hr = srpIVsTrackProjectDocuments2.OnAfterAddFilesEx(pIVsProject, 1, rgstrDocuments.ptr, &fInputFlags);
		assert(SUCCEEDED(hr));
	}

	bool CanRenameItem( 
		/* [in] */ CHierNode         pCHierNode,
		/* [in] */ string            newName,
		/* [in] */ ProjectEventFlags flags = ProjectEventFlags.None)
	{
		return true;
	}

	void OnItemRenamed(
		/* [in] */ CHierNode         pCHierNode,
		/* [in] */ string            oldName,
		/* [in] */ ProjectEventFlags flags = ProjectEventFlags.None)
	{
	}

	bool CanDeleteItem(
		/* [in] */ CHierNode         pCHierNode,
		/* [in] */ ProjectEventFlags flags = ProjectEventFlags.None)
	{
		return true;
	}

	void OnItemDeleted(
		/* [in] */ string            file,
		/* [in] */ ProjectEventFlags flags = ProjectEventFlags.None)
	{
	}

protected:
	IVsTrackProjectDocuments2 GetIVsTrackProjectDocuments2()
	{
		return queryService!(SVsTrackProjectDocuments, IVsTrackProjectDocuments2);
	}

protected:
	CVsHierarchy mHierarchy;
};

