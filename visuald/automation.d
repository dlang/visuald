// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2014 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.automation;

import visuald.windows;
import std.path;

import stdext.path;

import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.vsi.vslangproj : prjOutputTypeWinExe;
static import dte = sdk.vsi.dte80a;
static import dte2 = sdk.vsi.dte80;

import visuald.comutil;
import visuald.logutil;
import visuald.dproject;
import visuald.dpackage;
import visuald.hierutil;
import visuald.chiernode;
import visuald.chiercontainer;
import visuald.pkgutil;

enum HideProjectItems = true;

class ExtProjectItem : DisposingDispatchObject, dte.ProjectItem
{
	this(ExtProject prj, ExtProjectItems parent, CHierNode node)
	{
		mExtProject = prj;
		mParent = parent;
		mNode = node;
	}

	override void Dispose()
	{
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(dte.ProjectItem) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	/+[id(0x0000000a), propget, hidden, helpstring("Returns value indicating whether object was changed since the last time it was saved."), helpcontext(0x0000eadb)]+/
	override HRESULT get_IsDirty(/+[out, retval]+/ VARIANT_BOOL* lpfReturn)
	{
		mixin(LogCallMix);
		*lpfReturn = mDirty;
		return S_OK;
	}

	/+[id(0x0000000a), propput, hidden, helpstring("Returns value indicating whether object was changed since the last time it was saved."), helpcontext(0x0000eadb)]+/
	override HRESULT put_IsDirty(in VARIANT_BOOL dirty)
	{
		mixin(LogCallMix);
		mDirty = dirty != 0;
		return S_OK;
	}

	/+[id(0x0000000b), propget, helpstring("Returns the full pathnames of the files associated with a project item."), helpcontext(0x0000eac9)]+/
	override HRESULT get_FileNames(in short index,
					  /+[out, retval]+/ BSTR* lpbstrReturn)
	{
		mixin(LogCallMix);
		*lpbstrReturn = allocBSTR(mNode.GetFullPath());
		return S_OK;
	}

	/+[id(0x0000000c), helpstring("Saves the project."), helpcontext(0x0000ea8f)]+/
	override HRESULT SaveAs(in BSTR NewFileName,
				   /+[out, retval]+/ VARIANT_BOOL* lpfReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x0000000d), propget, helpstring("Returns the number of files associated with the project item."), helpcontext(0x0000eac4)]+/
	override HRESULT get_FileCount(/+[out, retval]+/ short* lpsReturn)
	{
		*lpsReturn = 1;
		return S_OK;
	}

	/+[id(00000000), propget, helpstring("Sets/returns the name of the project."), helpcontext(0x0000eae9)]+/
	override HRESULT get_Name(/+[out, retval]+/ BSTR* pbstrReturn)
	{
		mixin(LogCallMix);
		*pbstrReturn = allocBSTR(mNode.GetDisplayCaption());
		return S_OK;
	}

	/+[id(00000000), propput, helpstring("Sets/returns the name of the project."), helpcontext(0x0000eae9)]+/
	override HRESULT put_Name(in BSTR pbstrReturn)
	{
		mixin(LogCallMix);
		return S_FALSE;
	}

	/+[id(0x00000036), propget, helpstring("Returns the collection containing the object supporting this property."), helpcontext(0x0000eab1)]+/
	override HRESULT get_Collection(/+[out, retval]+/ dte.ProjectItems * lppcReturn)
	{
		mixin(LogCallMix);
		*lppcReturn = addref(mParent);
		return S_OK;
	}

	/+[id(0x00000038), propget, helpstring("Returns the Properties collection."), helpcontext(0x0000eaf9)]+/
	override HRESULT get_Properties(/+[out, retval]+/ dte.Properties * ppObject)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x000000c8), propget, helpstring("Returns the top-level extensibility object."), helpcontext(0x0000eac1)]+/
	override HRESULT get_DTE(/+[out, retval]+/ dte.DTE * lppaReturn)
	{
		logCall("%s.get_DTE()", this);
		return GetDTE(lppaReturn);
	}

	/+[id(0x000000c9), get_propget, helpstring("Returns a GUID String indicating the kind or type of the object."), helpcontext(0x0000eadd)]+/
	override HRESULT get_Kind(/+[out, retval]+/ BSTR* lpbstrFileName)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x000000cb), get_propget, helpstring("Returns a ProjectItems collection for the object."), helpcontext(0x0000eaf6)]+/
	override HRESULT get_ProjectItems(/+[out, retval]+/ dte.ProjectItems * lppcReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x000000cc), propget, helpstring("Returns value indicating whether the ProjectItem is open for a particular view."), helpcontext(0x0000eadc)]+/
	override HRESULT get_IsOpen(/+[ optional , defaultvalue("{FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF}")]+/ in BSTR ViewKind,
				   /+[out, retval]+/ VARIANT_BOOL* lpfReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x000000cd), helpstring("Opens the ProjectItem object in the specified view."), helpcontext(0x0000ea88)]+/
	override HRESULT Open(/+[ optional , defaultvalue("{00000000-0000-0000-0000-000000000000}")]+/ in BSTR ViewKind,
				 /+[out, retval]+/ dte.Window * lppfReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x000000ce), helpstring("Removes an object from a collection."), helpcontext(0x0000ea8c)]+/
	override HRESULT Remove()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x0000006b), helpstring("Expands views of the project structure to show the ProjectItem."), helpcontext(0x0000ea7d)]+/
	override HRESULT ExpandView()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x0000006c), propget, helpstring("Returns an interface or object that can be accessed at run time by name."), helpcontext(0x0000ea7f)]+/
	override HRESULT get_Object(/+[out, retval]+/ IDispatch * ProjectItemModel)
	{
		mixin(LogCallMix);
		*ProjectItemModel = addref(this);
		return S_OK;
	}

	/+[id(0x0000006d), propget, helpstring("Get an Extender for this object under the specified category."), helpcontext(0x0000eb84)]+/
	override HRESULT get_Extender(in BSTR ExtenderName,
					 /+[out, retval]+/ IDispatch * Extender)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x0000006e), propget, helpstring("Get a list of available Extenders on this object."), helpcontext(0x0000eb85)]+/
	override HRESULT get_ExtenderNames(/+[out, retval]+/ VARIANT* ExtenderNames)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x0000006f), propget, helpstring("Get the Extension Category ID of this object."), helpcontext(0x0000eb86)]+/
	override HRESULT get_ExtenderCATID(/+[out, retval]+/ BSTR* pRetval)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000071), propget, helpstring("Returns value indicating whether object was changed since the last time it was saved."), helpcontext(0x0000eadb)]+/
	override HRESULT get_Saved(/+[out, retval]+/ VARIANT_BOOL* lpfReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000071), propput, helpstring("Returns value indicating whether object was changed since the last time it was saved."), helpcontext(0x0000eadb)]+/
	override HRESULT put_Saved(in VARIANT_BOOL lpfReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000074), propget, helpstring("Returns the ConfigurationManager object for this item."), helpcontext(0x0000ece9)]+/
	override HRESULT get_ConfigurationManager(/+[out, retval]+/ dte.ConfigurationManager * ppConfigurationManager)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000075), propget, helpstring("Returns the CodeModel object for this item."), helpcontext(0x0000ecea)]+/
	override HRESULT get_FileCodeModel(/+[out, retval]+/ dte.FileCodeModel * ppFileCodeModel)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000076), helpstring("Causes the item to be saved to storage."), helpcontext(0x0000ecfb)]+/
	override HRESULT Save(/+[optional, defaultvalue("")]+/ BSTR FileName)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000077), propget, helpstring("Returns the Document object for this item."), helpcontext(0x0000ecfc)]+/
	override HRESULT get_Document(/+[out, retval]+/ dte.Document * ppDocument)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000078), propget, helpstring("If the project item is the root of a sub-project, then returns the Project object for the sub-project."), helpcontext(0x0000ecfd)]+/
	override HRESULT get_SubProject(/+[out, retval]+/ dte.Project * ppProject)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000079), propget, helpstring("Returns the project that hosts this ProjectItem object."), helpcontext(0x0000ed1b)]+/
	override HRESULT get_ContainingProject(/+[out, retval]+/ dte.Project * ppProject)
	{
		mixin(LogCallMix);
		*ppProject = addref(mExtProject);
		return S_OK;
	}

	/+[id(0x0000007a), helpstring("Removes the item from the project and it's storage."), helpcontext(0x0000ecfe)]+/
	override HRESULT Delete()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	//////////////////////////////////////////////////////////////
	__gshared ComTypeInfoHolder mTypeHolder;
	static void shared_static_this_typeHolder()
	{
		static class _ComTypeInfoHolder : ComTypeInfoHolder
		{
			override int GetIDsOfNames(
									   /* [size_is][in] */ in LPOLESTR *rgszNames,
									   /* [in] */ in UINT cNames,
									   /* [size_is][out] */ MEMBERID *pMemId)
			{
				//mixin(LogCallMix);
				if (cNames == 1 && to_string(*rgszNames) == "Name")
				{
					*pMemId = 1;
					return S_OK;
				}
				return returnError(E_NOTIMPL);
			}
		}
		mTypeHolder = newCom!_ComTypeInfoHolder;
		addref(mTypeHolder);
	}
	static void shared_static_dtor_typeHolder()
	{
		mTypeHolder = release(mTypeHolder);
	}

	override ComTypeInfoHolder getTypeHolder () { return mTypeHolder; }

private:
	ExtProject mExtProject;
	ExtProjectItems mParent;
	CHierNode mNode;
	bool mDirty;
};

class EmptyEnumerator : DComObject, IEnumVARIANT
{
	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IEnumVARIANT) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	HRESULT Next(in ULONG celt,
				 /+[out, size_is(celt), length_is(*pCeltFetched)]+/ VARIANT * rgVar,
				 /+[out]+/ ULONG * pCeltFetched)
	{
		if(pCeltFetched)
			*pCeltFetched = 0;
		return S_FALSE;
	}
	HRESULT Skip(in ULONG celt)
	{
		return S_OK;
	}
	HRESULT Reset()
	{
		return S_OK;
	}
	HRESULT Clone(/+[out]+/ IEnumVARIANT * ppEnum)
	{
		*ppEnum = addref(this);
		return S_OK;
	}
}

class ProjectItemsEnumerator : DComObject, IEnumVARIANT
{
	this(ExtProjectItems item, CHierContainer node)
	{
		mItem = item;
		mNode = node;
		mCurrent = mNode.GetHead();
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IEnumVARIANT) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	HRESULT Next(in ULONG celt,
				 /+[out, size_is(celt), length_is(*pCeltFetched)]+/ VARIANT * rgVar,
				 /+[out]+/ ULONG * pCeltFetched)
	{
		if(!rgVar)
			return E_INVALIDARG;

		ULONG c = 0;
		for( ; mCurrent && c < celt; c++)
		{
			rgVar[c].vt = VT_UNKNOWN;
			rgVar[c].punkVal = addref(newCom!ExtProjectItem(mItem.mExtProject, mItem, mCurrent));
			mCurrent = mCurrent.GetNext();
		}
		if(pCeltFetched)
			*pCeltFetched = c;
		return c >= celt ? S_OK : S_FALSE;
	}
	HRESULT Skip(in ULONG celt)
	{
		foreach(_; 0 .. celt)
		{
			if(!mCurrent)
				return S_FALSE;
			mCurrent = mCurrent.GetNext();
		}
		return S_OK;
	}
	HRESULT Reset()
	{
		mCurrent = mNode.GetHead();
		return S_OK;
	}
	HRESULT Clone(/+[out]+/ IEnumVARIANT * ppEnum)
	{
		*ppEnum = addref(newCom!ProjectItemsEnumerator(mItem, mNode));
		return S_OK;
	}

	ExtProjectItems mItem;
	CHierContainer mNode;
	CHierNode mCurrent;
}

class ProjectRootEnumerator : DComObject, IEnumVARIANT
{
	this(ExtProject prj)
	{
		mProject = prj;
		mDone = false;
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		if(queryInterface!(IEnumVARIANT) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	HRESULT Next(in ULONG celt,
				 /+[out, size_is(celt), length_is(*pCeltFetched)]+/ VARIANT * rgVar,
				 /+[out]+/ ULONG * pCeltFetched)
	{
		if(!rgVar)
			return E_INVALIDARG;

		ULONG fetched = 0;
		if(celt > 0 && !mDone)
		{
			rgVar.vt = VT_UNKNOWN;
			rgVar.punkVal = addref(mProject);
			mDone = true;
			fetched = 1;
		}
		if(pCeltFetched)
			*pCeltFetched = fetched;
		return fetched >= celt ? S_OK : S_FALSE;
	}
	HRESULT Skip(in ULONG celt)
	{
		if(celt > 0)
			mDone = true;
		return !mDone ? S_OK : S_FALSE;
	}
	HRESULT Reset()
	{
		mDone = false;
		return S_OK;
	}
	HRESULT Clone(/+[out]+/ IEnumVARIANT * ppEnum)
	{
		*ppEnum = addref(newCom!ProjectRootEnumerator(mProject));
		return S_OK;
	}

	ExtProject mProject;
	bool mDone;
}

class ExtProjectItems : DisposingDispatchObject, dte.ProjectItems
{
	this(ExtProject prj, ExtProjectItems parent, CHierNode node)
	{
		mExtProject = prj;
		mParent = parent;
		mNode = node;
	}

	__gshared ComTypeInfoHolder mTypeHolder;

	override ComTypeInfoHolder getTypeHolder () { return mTypeHolder; }

	override void Dispose()
	{
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(dte.ProjectItems) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override int Item(
		/* [in] */ in VARIANT index,
		/* [retval][out] */ dte.ProjectItem *lppcReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int get_Parent(
		/* [retval][out] */ IDispatch* lppptReturn)
	{
		mixin(LogCallMix);
		*lppptReturn = addref(mParent);
		return S_OK;
	}

	override int get_Count(
		/* [retval][out] */ int *lplReturn)
	{
		logCall("%s.get_Count(lplReturn=%s)", this, lplReturn);
		static if(HideProjectItems)
			*lplReturn = 0;
		else if(auto c = cast(CHierContainer) mNode)
			*lplReturn = c.GetCount();
		else
			*lplReturn = 0;
		return S_OK;
	}

	override int _NewEnum(
		/* [retval][out] */ IUnknown *lppiuReturn)
	{
		mixin(LogCallMix);
		static if(HideProjectItems)
			*lppiuReturn = addref(newCom!EmptyEnumerator());
		else if(auto c = cast(CHierContainer) mNode)
			*lppiuReturn = addref(newCom!ProjectItemsEnumerator(this, c));
		else
			*lppiuReturn = addref(newCom!EmptyEnumerator());
		return S_OK;
	}

	override int get_DTE(
		/* [retval][out] */ dte.DTE	*lppaReturn)
	{
		logCall("%s.get_DTE()", this);
		return GetDTE(lppaReturn);
	}

	override int get_Kind(
		/* [retval][out] */ BSTR *lpbstrFileName)
	{
		logCall("%s.get_Kind(lpbstrFileName=%s)", this, lpbstrFileName);
		return returnError(E_NOTIMPL);
	}

	override int AddFromFile(
		/* [in] */ in BSTR FileName,
		/* [retval][out] */ dte.ProjectItem *lppcReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int AddFromTemplate(
		/* [in] */ in BSTR FileName,
		/* [in] */ in BSTR Name,
		/* [retval][out] */ dte.ProjectItem *lppcReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int AddFromDirectory(
		/* [in] */ in BSTR Directory,
		/* [retval][out] */ dte.ProjectItem *lppcReturn)
	{
		logCall("AddFromDirectory(Directory=%s, lppcReturn=%s)", _toLog(Directory), _toLog(lppcReturn));
		return returnError(E_NOTIMPL);
	}

	override int get_ContainingProject(
		/* [retval][out] */ dte.Project* ppProject)
	{
		mixin(LogCallMix);
		*ppProject = addref(mExtProject);
		return S_OK;
	}

	override int AddFolder(
		BSTR Name,
		/* [defaultvalue] */ BSTR Kind,
		/* [retval][out] */ dte.ProjectItem *pProjectItem)
	{
		logCall("AddFolder(Kind=%s, pProjectItem=%s)", _toLog(Kind), _toLog(pProjectItem));
		return returnError(E_NOTIMPL);
	}

	override int AddFromFileCopy(
		BSTR FilePath,
		/* [retval][out] */ dte.ProjectItem *pProjectItem)
	{
		logCall("AddFromFileCopy(FilePath=%s, pProjectItem=%s)", _toLog(FilePath), _toLog(pProjectItem));
		return returnError(E_NOTIMPL);
	}

	override int Invoke(/* [in] */ in DISPID dispIdMember,
						/* [in] */ in IID* riid,
						/* [in] */ in LCID lcid,
						/* [in] */ in WORD wFlags,
						/* [out][in] */ DISPPARAMS *pDispParams,
						/* [out] */ VARIANT *pVarResult,
						/* [out] */ EXCEPINFO *pExcepInfo,
						/* [out] */ UINT *puArgErr)
	{
		mixin(LogCallMix);
		if (dispIdMember == -4)
		{
			pVarResult.vt = VT_UNKNOWN;
			return _NewEnum(&pVarResult.punkVal);
		}
		return super.Invoke(dispIdMember, riid, lcid, wFlags, pDispParams, pVarResult, pExcepInfo, puArgErr);
	}

	ExtProject mExtProject;
	ExtProjectItems mParent;
	CHierNode mNode;
};

class ExtProjectRootItems : ExtProjectItems
{
	this(ExtProject prj, ExtProjectItems parent, CHierNode node)
	{
		super(prj, parent, node);
	}

	override int _NewEnum(/* [retval][out] */ IUnknown *lppiuReturn)
	{
		mixin(LogCallMix);
		*lppiuReturn = addref(newCom!ProjectRootEnumerator(mExtProject));
		return S_OK;
	}
}

class ExtProperties : DisposingDispatchObject, dte.Properties
{
	this(ExtProject prj)
	{
		mProject = prj;
	}

	override void Dispose()
	{
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(dte.Properties) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT Item(in VARIANT index, dte.Property * lplppReturn)
	{
		mixin(LogCallMix);
		if(index.vt != VT_BSTR)
			return E_INVALIDARG;

		string prop = to_string(index.bstrVal);
		if(prop == "FullPath")
		{
			string fullpath = mProject.mProject.GetFilename();
			*lplppReturn = addref(newCom!(ExtProperty!string)(this, prop, fullpath));
			return S_OK;
		}
		if(prop == "ProjectDirectory")
		{
			string fullpath = dirName(mProject.mProject.GetFilename());
			*lplppReturn = addref(newCom!(ExtProperty!string)(this, prop, fullpath));
			return S_OK;
		}
		return returnError(S_FALSE);
	}

	/+[id(0x00000001), propget, restricted, hidden]+/
	override HRESULT get_Application(/+[out, retval]+/ IDispatch * lppidReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}
	/+[id(0x00000002), propget, helpstring("Returns the parent object."), helpcontext(0x0000eaf2)]+/
	override HRESULT get_Parent(/+[out, retval]+/ IDispatch * lppidReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}
	/+[id(0x00000028), propget, helpstring("Returns value indicating the count of objects in the collection."), helpcontext(0x0000eabb)]+/
	override HRESULT get_Count(/+[out, retval]+/ int* lplReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}
	/+[id(0xfffffffc), restricted]+/
	override HRESULT _NewEnum(/+[out, retval]+/ IUnknown * lppiuReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}
	/+[id(0x00000064), propget, helpstring("Returns the top-level extensibility object."), helpcontext(0x0000eac1)]+/
	override HRESULT get_DTE(/+[out, retval]+/ dte.DTE * lppaReturn)
	{
		logCall("%s.get_DTE()", this);
		return GetDTE(lppaReturn);
	}

	//////////////////////////////////////////////////////////////
	__gshared ComTypeInfoHolder mTypeHolder;
	static void shared_static_this_typeHolder()
	{
		static class _ComTypeInfoHolder : ComTypeInfoHolder
		{
			override int GetIDsOfNames(
									   /* [size_is][in] */ in LPOLESTR *rgszNames,
									   /* [in] */ in UINT cNames,
									   /* [size_is][out] */ MEMBERID *pMemId)
			{
				//mixin(LogCallMix);
				if (cNames == 1 && to_string(*rgszNames) == "Name")
				{
					*pMemId = 1;
					return S_OK;
				}
				return returnError(E_NOTIMPL);
			}
		}
		mTypeHolder = newCom!_ComTypeInfoHolder;
		addref(mTypeHolder);
	}
	static void shared_static_dtor_typeHolder()
	{
		mTypeHolder = release(mTypeHolder);
	}

	override ComTypeInfoHolder getTypeHolder () { return mTypeHolder; }

private:
	ExtProject mProject;
}

class ExtProperty(T) : DisposingDispatchObject, dte.Property
{
	this(ExtProperties props, string name, T value)
	{
		mProperties = props;
		mName = name;
		mValue = value;
	}

	override void Dispose()
	{
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(dte.Property) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override HRESULT get_Value(/+[out, retval]+/ VARIANT* lppvReturn)
	{
		mixin(LogCallMix);
		static if(is (T == string))
		{
			lppvReturn.vt = VT_BSTR;
			lppvReturn.bstrVal = allocBSTR(mValue);
		}
		else static if (is(T == int))
		{
			lppvReturn.vt = VT_INT;
			lppvReturn.intVal = mValue;
		}
		else
			static assert(false, "unsupported type in ExtProperty.Value");
		return S_OK;
	}

	/+[id(00000000), propput, helpstring("Sets/ returns the value of property returned by the Property object."), helpcontext(0x0000eb08)]+/
	override HRESULT put_Value(in VARIANT lppvSet)
	{
		mixin(LogCallMix);
		return returnError(S_FALSE);
	}

	/+[id(00000000), propputref, helpstring("Sets/ returns the value of property returned by the Property object."), helpcontext(0x0000eb08)]+/
	override HRESULT putref_Value(in VARIANT lppvReturn)
	{
		mixin(LogCallMix);
		return returnError(S_FALSE);
	}

	/+[id(0x00000003), propget, helpstring("Returns one element of a list."), helpcontext(0x0000ead6)]+/
	override HRESULT get_IndexedValue(in VARIANT Index1,
						 /+[ optional]+/ in VARIANT Index2,
						 /+[ optional]+/ in VARIANT Index3,
						 /+[ optional]+/ in VARIANT Index4,
						 /+[out, retval]+/ VARIANT* Val)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000003), propput, helpstring("Returns one element of a list."), helpcontext(0x0000ead6)]+/
	override HRESULT put_IndexedValue(in VARIANT Index1,
						 /+[ optional]+/ in VARIANT Index2,
						 /+[ optional]+/ in VARIANT Index3,
						 /+[ optional]+/ in VARIANT Index4,
						 in VARIANT Val)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000004), propget, helpstring("Returns a value representing the number of items in the list value."), helpcontext(0x0000eaea)]+/
	override HRESULT get_NumIndices(/+[out, retval]+/ short* lpiRetVal)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000001), propget, restricted, hidden]+/
	override HRESULT get_Application(/+[out, retval]+/ IDispatch * lppidReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000002), propget, restricted, hidden]+/
	override HRESULT get_Parent(/+[out, retval]+/ dte.Properties * lpppReturn)
	{
		mixin(LogCallMix);
		*lpppReturn = addref(mProperties);
		return S_OK;
	}

	/+[id(0x00000028), propget, helpstring("Returns the name of the object."), helpcontext(0x0000edbb)]+/
	override HRESULT get_Name(/+[out, retval]+/ BSTR* lpbstrReturn)
	{
		mixin(LogCallMix);
		*lpbstrReturn = allocBSTR(mName);
		return S_OK;
	}

	/+[id(0x0000002a), propget, helpstring("Returns the collection containing the object supporting this property."), helpcontext(0x0000eab1)]+/
	override HRESULT get_Collection(/+[out, retval]+/ dte.Properties * lpppReturn)
	{
		mixin(LogCallMix);
		*lpppReturn = addref(mProperties);
		return S_OK;
	}

	/+[id(0x0000002d), propget, helpstring("Sets/returns value of Property object when type of value is Object."), helpcontext(0x0000eaed)]+/
	override HRESULT get_Object(/+[out, retval]+/ IDispatch * lppunk)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x0000002d), propputref, helpstring("Sets/returns value of Property object when type of value is Object."), helpcontext(0x0000eaed)]+/
	override HRESULT putref_Object(/+[in]+/ IUnknown lppunk)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	/+[id(0x00000064), propget, helpstring("Returns the top-level extensibility object."), helpcontext(0x0000eac1)]+/
	override HRESULT get_DTE(/+[out, retval]+/ dte.DTE * lppaReturn)
	{
		logCall("%s.get_DTE()", this);
		return GetDTE(lppaReturn);
	}


	//////////////////////////////////////////////////////////////
	__gshared ComTypeInfoHolder mTypeHolder;
	static void shared_static_this_typeHolder()
	{
		static class _ComTypeInfoHolder : ComTypeInfoHolder
		{
			override int GetIDsOfNames(
									   /* [size_is][in] */ in LPOLESTR *rgszNames,
									   /* [in] */ in UINT cNames,
									   /* [size_is][out] */ MEMBERID *pMemId)
			{
				//mixin(LogCallMix);
				if (cNames == 1 && to_string(*rgszNames) == "Name")
				{
					*pMemId = 1;
					return S_OK;
				}
				return returnError(E_NOTIMPL);
			}
		}
		mTypeHolder = newCom!_ComTypeInfoHolder;
		addref(mTypeHolder);
	}
	static void shared_static_dtor_typeHolder()
	{
		mTypeHolder = release(mTypeHolder);
	}

	override ComTypeInfoHolder getTypeHolder () { return mTypeHolder; }

private:
	string mName;
	T mValue;
	ExtProperties mProperties;
}

class ExtProject : ExtProjectItem, dte.Project
{
	this(Project prj)
	{
		super(this, null, prj.GetProjectNode());
		mProject = prj;
		mProperties = newCom!ExtProperties(this);
	}

	override HRESULT QueryInterface(in IID* riid, void** pvObject)
	{
		//mixin(LogCallMix);

		if(queryInterface!(dte.Project) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	// DTE.Project
	override int get_Name(
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("%s.get_Name(lpbstrName=%s)", this, _toLog(lpbstrName));
		*lpbstrName = allocBSTR(mProject.GetCaption());
		return S_OK;
	}

	override int put_Name(
		/* [in] */ in BSTR bstrName)
	{
		logCall("%s.put_Name(bstrName=%s)", this, _toLog(bstrName));
		mProject.SetCaption(to_string(bstrName));
		return S_OK;
	}

	override int get_FileName(
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("%s.get_FileName(lpbstrName=%s)", this, _toLog(lpbstrName));
		*lpbstrName = allocBSTR(mProject.GetFilename());
		return S_OK;
	}

	override int get_IsDirty(
		/* [retval][out] */ VARIANT_BOOL *lpfReturn)
	{
		mixin(LogCallMix);
		return super.get_IsDirty(lpfReturn);
	}

	override int put_IsDirty(
		/* [in] */ in VARIANT_BOOL Dirty)
	{
		logCall("%s.put_IsDirty(Dirty=%s)", this, _toLog(Dirty));
		return super.put_IsDirty(Dirty);
	}

	override int get_Collection(
		/* [retval][out] */ dte.Projects *lppaReturn)
	{
		mixin(LogCallMix);
		dte2.DTE2 _dte = GetDTE();
		if(!_dte)
			return returnError(E_FAIL);
		scope(exit) release(_dte);

		IUnknown solution; // dte.Solution not derived from IUnknown?!
		if(_dte.get_Solution(cast(dte.Solution*)&solution) != S_OK || !solution)
			return returnError(E_FAIL);
		scope(exit) release(solution);

		dte._Solution _solution = qi_cast!(dte._Solution)(solution);
		if(!_solution)
			return returnError(E_FAIL);
		scope(exit) release(_solution);

		return _solution.get_Projects(lppaReturn);
	}

	override int SaveAs(
		/* [in] */ in BSTR NewFileName)
	{
		logCall("%s.SaveAs(NewFileName=%s)", this, _toLog(NewFileName));
		return returnError(E_NOTIMPL);
	}

	override int get_DTE(
		/* [retval][out] */ dte.DTE	*lppaReturn)
	{
		logCall("%s.get_DTE()", this);
		return GetDTE(lppaReturn);
	}

	override int get_Kind(
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("%s.get_Kind(lpbstrName=%s)", this, _toLog(lpbstrName));
		wstring s = GUID2wstring(g_projectFactoryCLSID);
		*lpbstrName = allocwBSTR(s);
		return S_OK;
	}

	override int get_ProjectItems(
		/* [retval][out] */ dte.ProjectItems* lppcReturn)
	{
		mixin(LogCallMix);
		*lppcReturn = addref(newCom!ExtProjectItems(this, null, mProject.GetProjectNode()));
		return S_OK;
	}

	override int get_Properties(
		/* [retval][out] */ dte.Properties *ppObject)
	{
		mixin(LogCallMix);
		*ppObject = addref(mProperties);
		return S_OK;
	}

	override int get_UniqueName(
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("%s.get_UniqueName(lpbstrName=%s)", this, _toLog(lpbstrName));

		if (!mProject)
			return returnError(E_FAIL);

		IVsSolution srpSolution = queryService!(IVsSolution);
		if(!srpSolution)
			return returnError(E_FAIL);

		IVsHierarchy pIVsHierarchy = mProject; // ->GetIVsHierarchy();

		int hr = srpSolution.GetUniqueNameOfProject(pIVsHierarchy, lpbstrName);
		srpSolution.Release();

		return hr;
	}

	override int get_Object(
		/* [retval][out] */ IDispatch* ProjectModel)
	{
		logCall("%s.get_Object(out ProjectModel=%s)", this, _toLog(&ProjectModel));
		*ProjectModel = addref(this); // (mProject);
		return S_OK;
	}

	override int get_Extender(
		/* [in] */ in BSTR ExtenderName,
		/* [retval][out] */ IDispatch *Extender)
	{
		logCall("%s.get_Extender(ExtenderName=%s)", this, _toLog(ExtenderName));
		return returnError(E_NOTIMPL);
	}

	override int get_ExtenderNames(
		/* [retval][out] */ VARIANT *ExtenderNames)
	{
		logCall("%s.get_ExtenderNames(ExtenderNames=%s)", this, _toLog(ExtenderNames));
		return returnError(E_NOTIMPL);
	}

	override int get_ExtenderCATID(
		/* [retval][out] */ BSTR *pRetval)
	{
		logCall("%s.get_ExtenderCATID(pRetval=%s)", this, _toLog(pRetval));
		return returnError(E_NOTIMPL);
	}

	override int get_FullName(
		/* [retval][out] */ BSTR *lpbstrName)
	{
		logCall("%s.get_FullName(lpbstrName=%s)", this, _toLog(lpbstrName));
		return get_FileName(lpbstrName);
	}

	override int get_Saved(
		/* [retval][out] */ VARIANT_BOOL *lpfReturn)
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}

	override int put_Saved(
		/* [in] */ in VARIANT_BOOL SavedFlag)
	{
		logCall("put_Saved(SavedFlag=%s)", _toLog(SavedFlag));
		return returnError(E_NOTIMPL);
	}

	override int get_ConfigurationManager(
		/* [retval][out] */ dte.ConfigurationManager* ppConfigurationManager)
	{
		mixin(LogCallMix);

		*ppConfigurationManager = mProject.getConfigurationManager();
		return S_OK;
	}

	override int get_Globals(
		/* [retval][out] */ dte.Globals* ppGlobals)
	{
		mixin(LogCallMix);

		HRESULT hr = S_OK;
		// hr = CheckEnabledItem(this, &IID__DTE, L"Globals");
		// IfFailRet(hr);

		// if don't already have m_srpGlobals, get it from shell
		IVsExtensibility3 ext = queryService!(dte.IVsExtensibility, IVsExtensibility3);
		if(!ext)
			return E_FAIL;
		scope(exit) release(ext);

		dte.Globals globals;
		VARIANT varIVsGlobalsCallback;
		varIVsGlobalsCallback.vt = VT_UNKNOWN;
		IVsHierarchy pIVsHierarchy = mProject;
		hr = mProject.QueryInterface(&IID_IUnknown, cast(void**)&varIVsGlobalsCallback.punkVal);
		if(!FAILED(hr))
		{
			//! TODO fix: returns failure
			hr = ext.GetGlobalsObject(varIVsGlobalsCallback, cast(IUnknown*) &globals);
			varIVsGlobalsCallback.punkVal.Release();
		}

		*ppGlobals = globals;
		return hr;
	}

	override int Save(
		/* [defaultvalue] */ BSTR FileName)
	{
		logCall("Save(FileName=%s)", _toLog(FileName));
		return returnError(E_NOTIMPL);
	}

	///////////////////////////////////////////
	extern(D)
	static bool searchNestedHierarchy(IVsHierarchy pHierarchy, VSITEMID item,
									  scope bool delegate (IVsHierarchy, VSITEMID, IVsHierarchy, VSITEMID) dg)
	{
		VARIANT var;
		if((pHierarchy.GetProperty(item, VSHPROPID_Container, &var) == S_OK &&
			((var.vt == VT_BOOL && var.boolVal) || (var.vt == VT_I4 && var.lVal))) ||
		   (pHierarchy.GetProperty(item, VSHPROPID_Expandable, &var) == S_OK &&
			((var.vt == VT_BOOL && var.boolVal) || (var.vt == VT_I4 && var.lVal))))
		{
			IVsHierarchy nestedHierarchy;
			VSITEMID itemidNested;
			if(pHierarchy.GetNestedHierarchy(item, &IVsHierarchy.iid, cast(void **)&nestedHierarchy, &itemidNested) == S_OK)
			{
				scope(exit) release(nestedHierarchy);
				if(dg(pHierarchy, item, nestedHierarchy, itemidNested))
					return true;
				if(searchNestedHierarchy(nestedHierarchy, itemidNested, dg))
					return true;
			}
			else if(pHierarchy.GetProperty(item, VSHPROPID_FirstChild, &var) == S_OK &&
					(var.vt == VT_INT_PTR || var.vt == VT_I4 || var.vt == VT_INT))
			{
				VSITEMID chid = var.lVal;
				while(chid != VSITEMID_NIL)
				{
					VARIANT name;
					pHierarchy.GetProperty(item, VSHPROPID_Name, &name);
					detachBSTR(name.bstrVal);

					if(searchNestedHierarchy(pHierarchy, chid, dg))
						return true;

					if(pHierarchy.GetProperty(chid, VSHPROPID_NextSibling, &var) != S_OK ||
					   (var.vt != VT_INT_PTR && var.vt != VT_I4 && var.vt != VT_INT))
						break;
					chid = var.lVal;
				}
			}
		}

		return false;
	}

	override int get_ParentProjectItem(
		/* [retval][out] */ dte.ProjectItem *ppParentProjectItem)
	{
		mixin(LogCallMix);
		*ppParentProjectItem = null;

		IVsSolution srpSolution = queryService!(IVsSolution);
		if(!srpSolution)
			return returnError(E_FAIL);

		int hr = E_UNEXPECTED;

		IVsHierarchy pIVsHierarchy = mProject; // ->GetIVsHierarchy();
		auto hierSolution = qi_cast!(IVsHierarchy)(srpSolution);
		if (hierSolution)
		{
			IVsHierarchy parentHier;
			VSITEMID parentItem;
			bool matchItem(IVsHierarchy hier, VSITEMID item, IVsHierarchy nestedHier, VSITEMID nestItem)
			{
				if (nestedHier == pIVsHierarchy)
				{
					parentHier = addref(hier);
					parentItem = item;
					return true;
				}
				return false;
			}

			if (searchNestedHierarchy(hierSolution, VSITEMID_ROOT, &matchItem))
			{
				VARIANT var;
				hr = parentHier.GetProperty(VSITEMID_ROOT, VSHPROPID_ExtObject, &var);
				if (hr == S_OK && var.vt == VT_DISPATCH && var.pdispVal)
				{
					*ppParentProjectItem = qi_cast!(dte.ProjectItem)(var.pdispVal);
					release(var.pdispVal);
				}
				else if (hr == S_OK)
					hr = E_UNEXPECTED;
			}
			release(parentHier);
			release(hierSolution);
		}
		release(srpSolution);

		return hr;
	}

	override int get_CodeModel(
		/* [retval][out] */ dte.CodeModel *ppCodeModel)
	{
		mixin(LogCallMix);
		*ppCodeModel = null;
		return S_OK; // returnError(E_NOTIMPL);
	}

	override int Delete()
	{
		mixin(LogCallMix);
		return returnError(E_NOTIMPL);
	}


	//////////////////////////////////////////////////////////////
	__gshared ComTypeInfoHolder mTypeHolder;
	static void shared_static_this_typeHolder()
	{
		static class _ComTypeInfoHolder : ComTypeInfoHolder
		{
			override int GetIDsOfNames(
				/* [size_is][in] */ in LPOLESTR *rgszNames,
				/* [in] */ in UINT cNames,
				/* [size_is][out] */ MEMBERID *pMemId)
			{
				//mixin(LogCallMix);
				if (cNames == 1 && to_string(*rgszNames) == "Name")
				{
					*pMemId = 1;
					return S_OK;
				}
				return returnError(E_NOTIMPL);
			}
		}
		mTypeHolder = newCom!_ComTypeInfoHolder;
		addref(mTypeHolder);
	}
	static void shared_static_dtor_typeHolder()
	{
		mTypeHolder = release(mTypeHolder);
	}

	override ComTypeInfoHolder getTypeHolder () { return mTypeHolder; }

	Project mProject;
	dte.Properties mProperties;
}

void automation_shared_static_this_typeHolder()
{
	ExtProjectItem.shared_static_this_typeHolder();
	ExtProperties.shared_static_this_typeHolder();
	ExtProperty!string.shared_static_this_typeHolder();
	ExtProperty!int.shared_static_this_typeHolder();
	ExtProject.shared_static_this_typeHolder();
}

void automation_shared_static_dtor_typeHolder()
{
	ExtProjectItem.shared_static_dtor_typeHolder();
	ExtProperties.shared_static_dtor_typeHolder();
	ExtProperty!string.shared_static_dtor_typeHolder();
	ExtProperty!int.shared_static_dtor_typeHolder();
	ExtProject.shared_static_dtor_typeHolder();
}
