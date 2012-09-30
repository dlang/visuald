// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.register;

import visuald.windows;
import sdk.win32.winreg;

import std.string;
import std.conv;
import std.utf;
import std.path;
import std.datetime;

import visuald.dpackage;
import visuald.dllmain;
import visuald.propertypage;
import visuald.config;
import visuald.comutil;

enum { SECURE_ACCESS = ~(WRITE_DAC | WRITE_OWNER | GENERIC_ALL | ACCESS_SYSTEM_SECURITY) }

// Registers COM objects normally and registers VS Packages to the specified VS registry hive under HKCU
extern(Windows)
HRESULT VSDllRegisterServerUser(in wchar* strRegRoot)
{
	return VSDllRegisterServerInternal(strRegRoot, true);
}

// Unregisters COM objects normally and unregisters VS Packages from the specified VS registry hive under HKCU
extern(Windows)
HRESULT VSDllUnregisterServerUser(in wchar* strRegRoot)
{
	return VSDllUnregisterServerInternal(strRegRoot, true);
}

// Registers COM objects normally and registers VS Packages to the specified VS registry hive
extern(Windows)
HRESULT VSDllRegisterServer(in wchar* strRegRoot)
{
	return VSDllRegisterServerInternal(strRegRoot, false);
}

// Unregisters COM objects normally and unregisters VS Packages from the specified VS registry hive
extern(Windows)
HRESULT VSDllUnregisterServer(in wchar* strRegRoot)
{
	return VSDllUnregisterServerInternal(strRegRoot, false);
}

// Registers COM objects normally and registers VS Packages to the default VS registry hive
extern(Windows)
HRESULT DllRegisterServer()
{
	return VSDllRegisterServer(null);
}

// Unregisters COM objects normally and unregisters VS Packages from the default VS registry hive
extern(Windows)
HRESULT DllUnregisterServer()
{
	return VSDllUnregisterServer(null);
}

///////////////////////////////////////////////////////////////////////

class RegistryException : Exception
{
	this(HRESULT hr)
	{
		super("Registry Error");
		result = hr;
	}

	HRESULT result;
}

class RegKey
{
	this(HKEY root, wstring keyname, bool write = true)
	{
		Create(root, keyname, write);
	}

	~this()
	{
		Close();
	}

	void Close()
	{
		if(key)
		{
			RegCloseKey(key);
			key = null;
		}
	}

	void Create(HKEY root, wstring keyname, bool write = true)
	{
		HRESULT hr;
		if(write)
		{
			hr = hrRegCreateKeyEx(root, keyname, 0, null, REG_OPTION_NON_VOLATILE, KEY_WRITE, null, &key, null);
			if(FAILED(hr))
				throw new RegistryException(hr);
		}
		else
			hr = hrRegOpenKeyEx(root, keyname, 0, KEY_READ, &key);
	}

	void Set(wstring name, wstring value)
	{
		if(!key)
			throw new RegistryException(E_FAIL);
			
		HRESULT hr = RegCreateValue(key, name, value);
		if(FAILED(hr))
			throw new RegistryException(hr);
	}

	void Set(wstring name, uint value)
	{
		if(!key)
			throw new RegistryException(E_FAIL);

		HRESULT hr = RegCreateDwordValue(key, name, value);
		if(FAILED(hr))
			throw new RegistryException(hr);
	}

	void Set(wstring name, long value)
	{
		if(!key)
			throw new RegistryException(E_FAIL);

		HRESULT hr = RegCreateQwordValue(key, name, value);
		if(FAILED(hr))
			throw new RegistryException(hr);
	}

	void Set(wstring name, void[] data)
	{
		if(!key)
			throw new RegistryException(E_FAIL);
		
		HRESULT hr = RegCreateBinaryValue(key, name, data);
		if(FAILED(hr))
			throw new RegistryException(hr);
	}
	
	bool Delete(wstring name)
	{
		if(!key)
			return false;
		wchar* szName = _toUTF16zw(name);
		HRESULT hr = RegDeleteValue(key, szName);
		return SUCCEEDED(hr);
	}
	
	wstring GetString(wstring name, wstring def = "")
	{
		if(!key)
			return def;
		
		wchar buf[260];
		DWORD cnt = 260 * wchar.sizeof;
		wchar* szName = _toUTF16zw(name);
		DWORD type;
		int hr = RegQueryValueExW(key, szName, null, &type, cast(ubyte*) buf.ptr, &cnt);
		if(hr == S_OK && cnt > 0)
			return to_wstring(buf.ptr);
		if(hr != ERROR_MORE_DATA || type != REG_SZ)
			return def;

		scope wchar[] pbuf = new wchar[cnt/2 + 1];
		RegQueryValueExW(key, szName, null, &type, cast(ubyte*) pbuf.ptr, &cnt);
		return to_wstring(pbuf.ptr);
	}

	DWORD GetDWORD(wstring name, DWORD def = 0)
	{
		if(!key)
			return def;
		
		DWORD dw, type, cnt = dw.sizeof;
		wchar* szName = _toUTF16zw(name);
		int hr = RegQueryValueExW(key, szName, null, &type, cast(ubyte*) &dw, &cnt);
		if(hr != S_OK || type != REG_DWORD)
			return def;
		return dw;
	}
	
	void[] GetBinary(wstring name)
	{
		if(!key)
			return null;
		
		wchar* szName = _toUTF16zw(name);
		DWORD type, cnt = 0;
		int hr = RegQueryValueExW(key, szName, null, &type, cast(ubyte*) &type, &cnt);
		if(hr != ERROR_MORE_DATA || type != REG_BINARY)
			return null;
		
		ubyte[] data = new ubyte[cnt];
		hr = RegQueryValueExW(key, szName, null, &type, data.ptr, &cnt);
		if(hr != S_OK)
			return null;
		return data;
	}
	
	HKEY key;
}

///////////////////////////////////////////////////////////////////////
// convention: no trailing "\" for keys

static const wstring regPathConfigDefault  = "Software\\Microsoft\\VisualStudio\\9.0"w;

static const wstring regPathFileExts       = "\\Languages\\File Extensions"w;
static const wstring regPathLServices      = "\\Languages\\Language Services"w;
static const wstring regPathCodeExpansions = "\\Languages\\CodeExpansions"w;
static const wstring regPathPrjTemplates   = "\\NewProjectTemplates\\TemplateDirs"w;
static const wstring regPathProjects       = "\\Projects"w;
static const wstring regPathToolsOptions   = "\\ToolsOptionsPages\\Projects\\Visual D Settings"w;
static const wstring regPathToolsDirs      = "\\ToolsOptionsPages\\Projects\\Visual D Directories"w;
static const wstring regMiscFiles          = regPathProjects ~ "\\{A2FE74E1-B743-11d0-AE1A-00A0C90FFFC3}"w;
static const wstring regPathMetricsExcpt   = "\\AD7Metrics\\Exception"w;
static const wstring regPathMetricsEE      = "\\AD7Metrics\\ExpressionEvaluator"w;

static const wstring vendorMicrosoftGuid   = "{994B45C4-E6E9-11D2-903F-00C04FA302A1}"w;
static const wstring guidCOMPlusNativeEng  = "{92EF0900-2251-11D2-B72E-0000F87572EF}"w;

///////////////////////////////////////////////////////////////////////
//  Registration
///////////////////////////////////////////////////////////////////////

wstring GetRegistrationRoot(in wchar* pszRegRoot, bool useRanu)
{
	wstring szRegistrationRoot;

	// figure out registration root, append "Configuration" in the case of RANU
	if (pszRegRoot is null)
		szRegistrationRoot = regPathConfigDefault;
	else
		szRegistrationRoot = to_wstring(pszRegRoot);
	if(useRanu)
	{
		scope RegKey keyConfig = new RegKey(HKEY_CURRENT_USER, szRegistrationRoot ~ "_Config"w, false);
		if(keyConfig.key)
			szRegistrationRoot ~= "_Config"w; // VS2010
		else
			szRegistrationRoot ~= "\\Configuration"w;
	}
	return szRegistrationRoot;
}

int guessVSVersion(wstring registrationRoot)
{
	auto idx = lastIndexOf(registrationRoot, '\\');
	if(idx < 0)
		return 0;
	wstring txt = registrationRoot[idx + 1 .. $];
	return parse!int(txt);
}

void updateConfigurationChanged(HKEY keyRoot, wstring registrationRoot)
{
	if(guessVSVersion(registrationRoot) >= 11)
	{
		scope RegKey keyRegRoot = new RegKey(keyRoot, registrationRoot);

		FILETIME fileTime;
		GetSystemTimeAsFileTime(&fileTime);
		ULARGE_INTEGER ul;
		ul.HighPart = fileTime.dwHighDateTime;
		ul.LowPart = fileTime.dwLowDateTime;
		ulong tempHNSecs = ul.QuadPart;

		keyRegRoot.Set("ConfigurationChanged", tempHNSecs);
	}
}

HRESULT VSDllUnregisterServerInternal(in wchar* pszRegRoot, in bool useRanu)
{
	HKEY keyRoot = useRanu ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
	wstring registrationRoot = GetRegistrationRoot(pszRegRoot, useRanu);

	wstring packageGuid = GUID2wstring(g_packageCLSID);
	wstring languageGuid = GUID2wstring(g_languageCLSID);
	wstring wizardGuid = GUID2wstring(g_ProjectItemWizardCLSID);

	HRESULT hr = S_OK;
	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\Packages\\"w ~ packageGuid);
	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ languageGuid);
	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ wizardGuid);

	foreach (wstring fileExt; g_languageFileExtensions)
		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathFileExts ~ "\\"w ~ fileExt);

	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\Services\\"w ~ languageGuid);
	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\InstalledProducts\\"w ~ g_packageName);

	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathLServices ~ "\\"w ~ g_languageName);
	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathCodeExpansions ~ "\\"w ~ g_languageName);

	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathPrjTemplates ~ "\\"w ~ packageGuid);
	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathProjects ~ "\\"w ~ GUID2wstring(g_projectFactoryCLSID));
	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regMiscFiles ~ "\\AddItemTemplates\\TemplateDirs\\"w ~ packageGuid);

	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathToolsOptions);

	foreach(guid; guids_propertyPages)
		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ GUID2wstring(*guid));

	hr |= RegDeleteRecursive(HKEY_CLASSES_ROOT, "CLSID\\"w ~ GUID2wstring(g_unmarshalCLSID));

	scope RegKey keyToolMenu = new RegKey(keyRoot, registrationRoot ~ "\\Menus"w);
	keyToolMenu.Delete(packageGuid);

	updateConfigurationChanged(keyRoot, registrationRoot);
	return hr;
}

HRESULT VSDllRegisterServerInternal(in wchar* pszRegRoot, in bool useRanu)
{
	HKEY    keyRoot = useRanu ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
	wstring registrationRoot = GetRegistrationRoot(pszRegRoot, useRanu);
	wstring dllPath = GetDLLName(g_hInst);
	wstring templatePath = GetTemplatePath(dllPath);

	try
	{
		wstring packageGuid = GUID2wstring(g_packageCLSID);
		wstring languageGuid = GUID2wstring(g_languageCLSID);
		wstring debugLangGuid = GUID2wstring(g_debuggerLanguage);
		wstring exprEvalGuid = GUID2wstring(g_expressionEvaluator);
		wstring wizardGuid = GUID2wstring(g_ProjectItemWizardCLSID);

		// package
		scope RegKey keyPackage = new RegKey(keyRoot, registrationRoot ~ "\\Packages\\"w ~ packageGuid);
		keyPackage.Set(null, g_packageName);
		keyPackage.Set("InprocServer32"w, dllPath);
		keyPackage.Set("About"w, g_packageName);
		keyPackage.Set("CompanyName"w, g_packageCompany);
		keyPackage.Set("ProductName"w, g_packageName);
		keyPackage.Set("ProductVersion"w, toUTF16(g_packageVersion));
		keyPackage.Set("MinEdition"w, "Standard");
		keyPackage.Set("ID"w, 1);

		int bspos = dllPath.length - 1;	while (bspos >= 0 && dllPath[bspos] != '\\') bspos--;
		scope RegKey keySatellite = new RegKey(keyRoot, registrationRoot ~ "\\Packages\\"w ~ packageGuid ~ "\\SatelliteDll"w);
		keySatellite.Set("Path"w, dllPath[0 .. bspos+1]);
		keySatellite.Set("DllName"w, ".."w ~ dllPath[bspos .. $]);

		scope RegKey keyCLSID = new RegKey(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ languageGuid);
		keyCLSID.Set("InprocServer32"w, dllPath);
		keyCLSID.Set("ThreadingModel"w, "Free"w); // Appartment?

		// Wizards
		scope RegKey keyWizardCLSID = new RegKey(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ wizardGuid);
		keyWizardCLSID.Set("InprocServer32"w, dllPath);
		keyWizardCLSID.Set("ThreadingModel"w, "Appartment"w);

		// file extensions
		wstring fileExtensions;
		foreach (wstring fileExt; g_languageFileExtensions)
		{
			scope RegKey keyExt = new RegKey(keyRoot, registrationRoot ~ regPathFileExts ~ "\\"w ~ fileExt);
			keyExt.Set(null, languageGuid);
			keyExt.Set("Name"w, g_languageName);
			fileExtensions ~= fileExt ~ ";"w;
		}

		// language service
		wstring langserv = registrationRoot ~ regPathLServices ~ "\\"w ~ g_languageName;
		scope RegKey keyLang = new RegKey(keyRoot, langserv);
		keyLang.Set(null, languageGuid);
		keyLang.Set("Package"w, packageGuid);
		keyLang.Set("Extensions"w, fileExtensions);
		keyLang.Set("LangResId"w, 0);
		foreach (ref const(LanguageProperty) prop; g_languageProperties)
			keyLang.Set(prop.name, prop.value);
		
		// colorizer settings
		scope RegKey keyColorizer = new RegKey(keyRoot, langserv ~ "\\EditorToolsOptions\\Colorizer"w);
		keyColorizer.Set("Package"w, packageGuid);
		keyColorizer.Set("Page"w, GUID2wstring(g_ColorizerPropertyPage));
		
		// intellisense settings
		scope RegKey keyIntellisense = new RegKey(keyRoot, langserv ~ "\\EditorToolsOptions\\Intellisense"w);
		keyIntellisense.Set("Package"w, packageGuid);
		keyIntellisense.Set("Page"w, GUID2wstring(g_IntellisensePropertyPage));

		scope RegKey keyService = new RegKey(keyRoot, registrationRoot ~ "\\Services\\"w ~ languageGuid);
		keyService.Set(null, packageGuid);
		keyService.Set("Name"w, g_languageName);
		
		scope RegKey keyProduct = new RegKey(keyRoot, registrationRoot ~ "\\InstalledProducts\\"w ~ g_packageName);
		keyProduct.Set("Package"w, packageGuid);
		keyProduct.Set("UseInterface"w, 1);

		// snippets
		wstring codeExp = registrationRoot ~ regPathCodeExpansions ~ "\\"w ~ g_languageName;
		scope RegKey keyCodeExp = new RegKey(keyRoot, codeExp);
		keyCodeExp.Set(null, languageGuid);
		keyCodeExp.Set("DisplayName"w, "131"w); // ???
		keyCodeExp.Set("IndexPath"w, templatePath ~ "\\CodeSnippets\\SnippetsIndex.xml"w);
		keyCodeExp.Set("LangStringId"w, g_languageName);
		keyCodeExp.Set("Package"w, packageGuid);
		keyCodeExp.Set("ShowRoots"w, 0);

		wstring snippets = templatePath ~ "\\CodeSnippets\\Snippets\\;%MyDocs%\\Code Snippets\\" ~ g_languageName ~ "\\My Code Snippets\\"w;
		scope RegKey keyCodeExp1 = new RegKey(keyRoot, codeExp ~ "\\ForceCreateDirs"w);
		keyCodeExp1.Set(g_languageName, snippets);

		scope RegKey keyCodeExp2 = new RegKey(keyRoot, codeExp ~ "\\Paths"w);
		keyCodeExp2.Set(g_languageName, snippets);

		scope RegKey keyPrjTempl = new RegKey(keyRoot, registrationRoot ~ regPathPrjTemplates ~ "\\"w ~ packageGuid ~ "\\/1");
		keyPrjTempl.Set(null, g_languageName);
		keyPrjTempl.Set("DeveloperActivity"w, g_languageName);
		keyPrjTempl.Set("SortPriority"w, 20);
		keyPrjTempl.Set("TemplatesDir"w, templatePath ~ "\\Projects"w);
		keyPrjTempl.Set("Folder"w, "{152CDB9D-B85A-4513-A171-245CE5C61FCC}"w); // other languages

		// project
		wstring projects = registrationRoot ~ "\\Projects\\"w ~ GUID2wstring(g_projectFactoryCLSID);
		scope RegKey keyProject = new RegKey(keyRoot, projects);
		keyProject.Set(null, "DProjectFactory"w);
		keyProject.Set("DisplayName"w, g_languageName);
		keyProject.Set("DisplayProjectFileExtensions"w, g_languageName ~ " Project Files (*."w ~ g_projectFileExtensions ~ ");*."w ~ g_projectFileExtensions);
		keyProject.Set("Package"w, packageGuid);
		keyProject.Set("DefaultProjectExtension"w, g_projectFileExtensions);
		keyProject.Set("PossibleProjectExtensions"w, g_projectFileExtensions);
		keyProject.Set("ProjectTemplatesDir"w, templatePath ~ "\\Projects"w);
		keyProject.Set("Language(VsTemplate)"w, g_languageName);
		keyProject.Set("ItemTemplatesDir"w, templatePath ~ "\\Items"w);

		// file templates
		scope RegKey keyProject1 = new RegKey(keyRoot, projects ~ "\\AddItemTemplates\\TemplateDirs\\"w ~ packageGuid ~ "\\/1"w);
		keyProject1.Set(null, g_languageName);
		keyProject1.Set("TemplatesDir"w, templatePath ~ "\\Items"w);
		keyProject1.Set("SortPriority"w, 25);

		// Miscellaneous Files Project
		scope RegKey keyProject2 = new RegKey(keyRoot, registrationRoot ~ regMiscFiles ~ "\\AddItemTemplates\\TemplateDirs\\"w ~ packageGuid ~ "\\/1"w);
		keyProject2.Set(null, g_languageName);
		keyProject2.Set("TemplatesDir"w, templatePath ~ "\\Items"w);
		keyProject2.Set("SortPriority"w, 25);

		// property pages
		foreach(guid; guids_propertyPages)
		{
			scope RegKey keyProp = new RegKey(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ GUID2wstring(*guid));
			keyProp.Set("InprocServer32"w, dllPath);
			keyProp.Set("ThreadingModel"w, "Appartment"w);
		}

version(none){
		// expression evaluator
		scope RegKey keyLangDebug = new RegKey(keyRoot, langserv ~ "\\Debugger Languages\\"w ~ debugLangGuid);
		keyLangDebug.Set(null, g_languageName);
		
		scope RegKey keyLangException = new RegKey(keyRoot, registrationRoot ~ regPathMetricsExcpt ~ "\\"w ~ debugLangGuid ~ "\\D Exceptions");

		wstring langEE = registrationRoot ~ regPathMetricsEE ~ "\\"w ~ debugLangGuid ~ "\\"w ~ vendorMicrosoftGuid;
		scope RegKey keyLangEE = new RegKey(keyRoot, langEE);
		keyLangEE.Set("CLSID"w, exprEvalGuid);
		keyLangEE.Set("Language"w, g_languageName);
		keyLangEE.Set("Name"w, "D EE"w);
			
		scope RegKey keyEngine = new RegKey(keyRoot, langEE ~ "\\Engine");
		keyEngine.Set("0"w, guidCOMPlusNativeEng);
}

		// menu
		scope RegKey keyToolMenu = new RegKey(keyRoot, registrationRoot ~ "\\Menus"w);
		keyToolMenu.Set(packageGuid, ",2001,12"); // CTMENU,version
		
		// Visual D settings
		scope RegKey keyToolOpts = new RegKey(keyRoot, registrationRoot ~ regPathToolsOptions);
		keyToolOpts.Set(null, "Visual D Settings");
		keyToolOpts.Set("Package"w, packageGuid);
		keyToolOpts.Set("Page"w, GUID2wstring(g_ToolsProperty2Page));

		if(keyToolOpts.GetString("ExeSearchPath"w).length == 0)
			keyToolOpts.Set("ExeSearchPath"w, "$(DMDInstallDir)windows\\bin\n$(WindowsSdkDir)\\bin"w);
		if(keyToolOpts.GetString("IncSearchPath"w).length == 0)
			keyToolOpts.Set("IncSearchPath"w, "$(WindowsSdkDir)\\include;$(DevEnvDir)..\\..\\VC\\include"w);

		scope RegKey keyToolOpts2 = new RegKey(keyRoot, registrationRoot ~ regPathToolsDirs);
		keyToolOpts2.Set(null, "Visual D Directories");
		keyToolOpts2.Set("Package"w, packageGuid);
		keyToolOpts2.Set("Page"w, GUID2wstring(g_ToolsPropertyPage));

		// remove "SkipLoading" entry from user settings
		scope RegKey userKeyPackage = new RegKey(HKEY_CURRENT_USER, registrationRoot ~ "\\Packages\\"w ~ packageGuid);
		userKeyPackage.Delete("SkipLoading");

		// remove Text Editor FontsAndColors Cache to add new Colors provided by Visual D
		RegDeleteRecursive(HKEY_CURRENT_USER, registrationRoot ~ "\\FontAndColors\\Cache\\{A27B4E24-A735-4D1D-B8E7-9716E1E3D8E0}");

		// global registry keys for marshalled objects
		scope RegKey keyMarshal1 = new RegKey(HKEY_CLASSES_ROOT, "CLSID\\"w ~ GUID2wstring(g_unmarshalCLSID) ~ "\\InprocServer32"w);
		keyMarshal1.Set("InprocServer32"w, dllPath);
		keyMarshal1.Set("ThreadingModel"w, "Appartment"w);

		scope RegKey keyMarshal2 = new RegKey(HKEY_CLASSES_ROOT, "CLSID\\"w ~ GUID2wstring(g_unmarshalCLSID) ~ "\\InprocHandler32"w);
		keyMarshal2.Set(null, dllPath);

		updateConfigurationChanged(keyRoot, registrationRoot);
	}
	catch(RegistryException e)
	{
		return e.result;
	}
	return S_OK;
}

/*---------------------------------------------------------
  Registry helpers
-----------------------------------------------------------*/
HRESULT RegCreateValue(HKEY key, in wstring name, in wstring value)
{
	wstring szName = name ~ cast(wchar)0;
	wstring szValue = value ~ cast(wchar)0;
	DWORD dwDataSize = value is null ? 0 : wchar.sizeof * (value.length+1);
	LONG lRetCode = RegSetValueExW(key, szName.ptr, 0, REG_SZ, cast(ubyte*)(szValue.ptr), dwDataSize);
	return HRESULT_FROM_WIN32(lRetCode);
}

HRESULT RegCreateDwordValue(HKEY key, in wstring name, in DWORD value)
{
	wstring szName = name ~ cast(wchar)0;
	LONG lRetCode = RegSetValueExW(key, szName.ptr, 0, REG_DWORD, cast(ubyte*)(&value), value.sizeof);
	return HRESULT_FROM_WIN32(lRetCode);
}

HRESULT RegCreateQwordValue(HKEY key, in wstring name, in long value)
{
	wstring szName = name ~ cast(wchar)0;
	LONG lRetCode = RegSetValueExW(key, szName.ptr, 0, REG_QWORD, cast(ubyte*)(&value), value.sizeof);
	return HRESULT_FROM_WIN32(lRetCode);
}

HRESULT RegCreateBinaryValue(HKEY key, in wstring name, in void[] data)
{
	wstring szName = name ~ cast(wchar)0;
	LONG lRetCode = RegSetValueExW(key, szName.ptr, 0, REG_BINARY, cast(ubyte*)data.ptr, data.length);
	return HRESULT_FROM_WIN32(lRetCode);
}

HRESULT RegDeleteRecursive(HKEY keyRoot, wstring path)
{
	HRESULT hr;
	HKEY    key;
	ULONG   subKeys    = 0;
	ULONG   maxKeyLen  = 0;
	ULONG   currentKey = 0;
	wstring[] keyNames;

	hr = hrRegOpenKeyEx(keyRoot, path, 0, (KEY_READ & SECURE_ACCESS), &key);
	if (FAILED(hr)) goto fail;

	LONG lRetCode = RegQueryInfoKeyW(key, null, null, null, &subKeys, &maxKeyLen, 
	                                 null, null, null, null, null, null);
	if (ERROR_SUCCESS != lRetCode)
	{
		hr = HRESULT_FROM_WIN32(lRetCode);
		goto fail;
	}
	if (subKeys > 0)
	{
		wchar[] keyName = new wchar[maxKeyLen+1];
		for (currentKey = 0; currentKey < subKeys; currentKey++)
		{
			ULONG keyLen = maxKeyLen+1;
			lRetCode = RegEnumKeyExW(key, currentKey, keyName.ptr, &keyLen, null, null, null, null);
			if (ERROR_SUCCESS == lRetCode)
				keyNames ~= to_wstring(keyName.ptr, keyLen);
		}
		foreach(wstring subkey; keyNames)
			RegDeleteRecursive(key, subkey);
	}

fail:
	wstring szPath = path ~ cast(wchar)0;
	lRetCode = RegDeleteKeyW(keyRoot, szPath.ptr);
	if (SUCCEEDED(hr) && (ERROR_SUCCESS != lRetCode))
		hr = HRESULT_FROM_WIN32(lRetCode);
	if (key) RegCloseKey(key);
	return hr;
}

wstring GetDLLName(HINSTANCE inst)
{
	//get dll path
	wchar dllPath[MAX_PATH+1];
	DWORD dwLen = GetModuleFileNameW(inst, dllPath.ptr, MAX_PATH);
	if (dwLen == 0)
		throw new RegistryException(HRESULT_FROM_WIN32(GetLastError()));
	if (dwLen == MAX_PATH)
		throw new RegistryException(HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER));

	return to_wstring(dllPath.ptr);
}
 
wstring GetTemplatePath(wstring dllpath)
{
	string path = toUTF8(dllpath);
	path = dirName(path);
	debug path = dirName(dirName(path)) ~ "\\visuald";
	path = path ~ "\\Templates";
	return toUTF16(path);
}

HRESULT hrRegOpenKeyEx(HKEY root, wstring regPath, int reserved, REGSAM samDesired, HKEY* phkResult)
{
	wchar* szRegPath = _toUTF16zw(regPath);
	LONG lRes = RegOpenKeyExW(root, szRegPath, 0, samDesired, phkResult);
	return HRESULT_FROM_WIN32(lRes);
}

HRESULT hrRegCreateKeyEx(HKEY keySub, wstring regPath, int reserved, wstring classname, DWORD opt, DWORD samDesired, 
			 SECURITY_ATTRIBUTES* security, HKEY* key, DWORD* disposition)
{
	wchar* szRegPath = _toUTF16zw(regPath);
	wchar* szClassname = _toUTF16zw(classname);
	LONG lRes = RegCreateKeyExW(keySub, szRegPath, 0, szClassname, opt, samDesired, security, key, disposition);
	return HRESULT_FROM_WIN32(lRes);
}
