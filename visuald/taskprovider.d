// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2017 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.taskprovider;

import visuald.logutil;
import visuald.comutil;
import visuald.hierutil;
import visuald.dpackage;

import sdk.vsi.vsshell;
import sdk.vsi.vsshell80;
import sdk.win32.winerror;

import std.string;
import std.conv;
import std.utf;
import std.ascii;
import std.uni;

class TaskProvider : DisposingComObject, IVsTaskProvider, IVsTaskListEvents
{
	VSTASKPRIORITY[string] mTokens;
	CommentTaskItem[] mTasks;
	bool mInErrorList;

	this(bool errlist)
	{
		mInErrorList = errlist;
		RefreshTokens();
	}

	override void Dispose()
	{

	}
	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsTaskProvider) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsTaskListEvents) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

    override HRESULT EnumTaskItems(/+[out]+/ IVsEnumTaskItems *ppEnum)
	{
		mixin(LogCallMix);
		*ppEnum = newCom!TaskItemsEnum(mTasks);
		addref(*ppEnum);
		return S_OK;
	}

	override HRESULT get_ImageList(/+[out,retval]+/ HANDLE *phImageList)
	{
		mixin(LogCallMix);
		*phImageList = null;
		return E_NOTIMPL;
	}

	override HRESULT get_SubcategoryList(const ULONG cbstr, BSTR *rgbstr, ULONG *pcActual)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}
	override HRESULT get_ReRegistrationKey(BSTR *pbstrKey)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}
    override HRESULT OnTaskListFinalRelease(IVsTaskList pTaskList)
	{
		mixin(LogCallMix);
		return E_NOTIMPL;
	}

	// IVsTaskListEvents
	override HRESULT OnCommentTaskInfoChanged()
	{
		RefreshTokens();
		return S_OK;
	}


	VSTASKPRIORITY getPriority(string txt)
	{
		size_t pos;
		while(pos < txt.length)
		{
			auto nextpos = pos;
			dchar ch = decode(txt, nextpos);
			if (!std.uni.isAlpha(ch) && !std.ascii.isDigit(ch) && ch != '_' && ch != '@')
				break;
			pos = nextpos;
		}
		string tok = txt[0..pos];
		if (auto pprio = tok in mTokens)
			return *pprio;
		return TP_NORMAL;
	}

	void updateTaskItems(string filename, string tasks)
	{
		size_t pos = 0;
		string[] tsks = splitLines(tasks);
		bool modified = false;
		foreach(t; tsks)
		{
			auto idx = indexOf(t, ':');
			if(idx > 0)
			{
				string[] num = split(t[0..idx], ",");
				if(num.length >= 2)
				{
					try
					{
						int line = parse!int(num[0]);
						int col = parse!int(num[1]);
						string txt = t[idx+1 .. $];
						VSTASKPRIORITY prio = getPriority(txt);

						while (pos < mTasks.length && mTasks[pos].mFile != filename)
							pos++;
						if (pos == mTasks.length)
						{
							auto task = newCom!CommentTaskItem(txt, prio, filename, line, col);
							task.mError = mInErrorList;
							mTasks ~= task;
							modified = true;
						}
						else if (mTasks[pos].mLine != line || mTasks[pos].mColumn != col ||
								 mTasks[pos].mText != txt || mTasks[pos].mPriority != prio)
						{
							mTasks[pos].mLine = line;
							mTasks[pos].mColumn = col;
							mTasks[pos].mText = txt.replace("\a", "\n");
							mTasks[pos].mPriority = prio;
							modified = true;
						}
						pos++;
					}
					catch(ConvException)
					{
					}
				}
			}
		}
		while (pos < mTasks.length && mTasks[pos].mFile != filename)
			pos++;
		if (pos < mTasks.length)
		{
			for (size_t q = pos; q < mTasks.length; q++)
			if (mTasks[q].mFile != filename)
				mTasks[pos++] = mTasks[q];
			mTasks.length = pos;
			modified = true;
		}
		if (modified)
		{
			if (mInErrorList)
				Package.RefreshErrorList();
			else
				Package.RefreshTaskList();
		}
	}

	// Retrieves token settings as defined by user in Tools -> Options -> Environment -> Task List.
	void RefreshTokens()
	{
		auto taskInfo = queryService!(IVsTaskList, IVsCommentTaskInfo);
		if (taskInfo is null)
			return;
		scope(exit) release(taskInfo);

		IVsEnumCommentTaskTokens enumTokens;
		if (FAILED(taskInfo.get_EnumTokens(&enumTokens)))
			return;
		scope(exit) release(enumTokens);

		VSTASKPRIORITY[string] tokens;

		IVsCommentTaskToken token;
		uint fetched;
		// DevDiv bug 1135485: EnumCommentTaskTokens.Next returns E_FAIL instead of S_FALSE
		while(enumTokens.Next(1, &token, &fetched) == S_OK && fetched > 0)
		{
			scope(exit) release(token);
			BSTR text;
			VSTASKPRIORITY priority;
			if(token.get_Text(&text) == S_OK)
			{
				string txt = detachBSTR(text);
				if (token.get_Priority(&priority) == S_OK)
				{
					tokens[txt] = priority;
				}
			}
		}

		if (mTokens != tokens)
		{
			mTokens = tokens;

			auto langsvc = Package.GetLanguageService();
			langsvc.vdServerClient.ConfigureCommentTasks(tokens.keys());
		}
	}
}

class CommentTaskItem : DComObject, IVsTaskItem, IVsErrorItem
{
	string mFile;
	int mLine, mColumn;
	string mText;
	VSTASKPRIORITY mPriority;
	bool mChecked;
	bool mError;

	this(string txt, VSTASKPRIORITY prio, string file, int line, int col)
	{
		mText = txt;
		mPriority = prio;
		mFile = file;
		mLine = line;
		mColumn = col;
	}
	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsTaskItem) (this, riid, pvObject))
			return S_OK;
		if(queryInterface!(IVsErrorItem) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

    override HRESULT get_Priority(VSTASKPRIORITY *ptpPriority)
	{
		*ptpPriority = mPriority;
		return S_OK;
	}
    override HRESULT put_Priority(const VSTASKPRIORITY tpPriority)
	{
		mPriority = tpPriority;
		return S_OK;
	}

	override HRESULT get_Category(/+[out, retval]+/ VSTASKCATEGORY *pCat)
	{
		*pCat = mError ? CAT_CODESENSE : CAT_COMMENTS;
		return S_OK;
	}

	override HRESULT get_SubcategoryIndex(/+[out, retval]+/int *pIndex)
	{
		*pIndex = 0;
		return E_NOTIMPL;
	}

	override HRESULT get_ImageListIndex(/+[out,retval]+/ int *pIndex)
	{
		*pIndex = mError ? BMP_SQUIGGLE : BMP_COMMENT;
		return S_OK;
	}

    override HRESULT   get_Checked(/+[out,retval]+/BOOL *pfChecked)
	{
		*pfChecked = mChecked;
		return S_OK;
	}
    override HRESULT put_Checked(const BOOL fChecked)
	{
		mChecked = fChecked != 0;
		return S_OK;
	}
    override HRESULT get_Text(/+[out,retval]+/ BSTR *pbstrName)
	{
		*pbstrName = allocBSTR(mText);
		return S_OK;
	}
    override HRESULT put_Text (const BSTR bstrName)
	{
		return E_NOTIMPL;
	}

	override HRESULT get_Document(/+[out,retval]+/ BSTR *pbstrMkDocument)
	{
		*pbstrMkDocument = allocBSTR(mFile);
		return S_OK;
	}

	override HRESULT get_Line(/+[out,retval]+/ int *piLine)
	{
		*piLine = mLine - 1; // 0 based
		return S_OK;
	}

	override HRESULT get_Column(/+[out, retval]+/ int *piCol)
	{
		*piCol = mColumn - 1;
		return S_OK;
	}

	override HRESULT get_CanDelete(/+[out, retval]+/BOOL *pfCanDelete)
	{
		*pfCanDelete = FALSE;
		return S_OK;
	}
	override HRESULT get_IsReadOnly(const VSTASKFIELD field, BOOL *pfReadOnly)
	{
		switch(field)
		{
			case FLD_PRIORITY:
			case FLD_CHECKED:
				*pfReadOnly = false;
				break;
			default:
				*pfReadOnly = true;
				break;
		}
		return S_OK;
	}

	override HRESULT get_HasHelp(BOOL *pfHasHelp)
	{
		*pfHasHelp = FALSE;
		return S_OK;
	}

	// Actions
	override HRESULT NavigateTo()
	{
		return OpenFileInSolution(mFile, mLine - 1, mColumn - 1);
	}
    override HRESULT NavigateToHelp()
	{
		return E_NOTIMPL;
	}

	// Notifications
    override HRESULT OnFilterTask(const BOOL fVisible)
	{
		return E_NOTIMPL;
	}

    override HRESULT OnDeleteTask()
	{
		return E_NOTIMPL;
	}

	// IVsErrorItem
    HRESULT GetHierarchy(/+[out]+/ IVsHierarchy * ppProject)
	{
		*ppProject = getProjectForSourceFile(mFile);
		return S_OK;
	}

    // Returns the category of this item: error, warning, or informational message.
    HRESULT GetCategory(/+[out]+/ VSERRORCATEGORY* pCategory)
	{
		if (!mError)
			*pCategory = EC_MESSAGE;
		else if (mText.startsWith ("Deprecation:"))
			*pCategory = EC_MESSAGE;
		else if (mText.startsWith ("Info:"))
			*pCategory = EC_MESSAGE;
		else if (mText.startsWith ("Warning:"))
			*pCategory = EC_WARNING;
		else
			*pCategory = EC_ERROR;
		return S_OK;
	}
}

class TaskItemsEnum : DComObject, IVsEnumTaskItems
{
	CommentTaskItem[] mItems;
	int mPos;

	this(CommentTaskItem[] items)
	{
		mItems = items;
		mPos = 0;
	}

	override HRESULT QueryInterface(const IID* riid, void** pvObject)
	{
		if(queryInterface!(IVsEnumTaskItems) (this, riid, pvObject))
			return S_OK;
		return super.QueryInterface(riid, pvObject);
	}

	override int Next(const ULONG celt, IVsTaskItem *rgelt, ULONG *pceltFetched)
	{
		if(mPos + celt > mItems.length)
			return E_FAIL;

		for(int i = 0; i < celt; i++)
			rgelt[i] = addref(mItems[mPos + i]);

		mPos += celt;
		if(pceltFetched)
			*pceltFetched = celt;

		return S_OK;
	}

	override int Skip(const ULONG celt)
	{
		mPos += celt;
		return S_OK;
	}

	override int Reset()
	{
		mPos = 0;
		return S_OK;
	}

	override int Clone(IVsEnumTaskItems *ppenum)
	{
		auto clone = newCom!TaskItemsEnum(mItems);
		mPos = clone.mPos;
		*ppenum = addref(clone);
		return S_OK;
	}
}
