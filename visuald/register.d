module register;

import std.c.windows.windows;
import std.c.windows.com;
import std.string;
import std.conv;
import std.utf;
import std.path;

import dpackage;
import dllmain;
import propertypage;
import config;
import comutil;

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

extern(Windows)
DWORD GetModuleFileNameW(in HMODULE hModule, wchar* lpFilename, DWORD nSize);

extern(Windows)
LONG RegOpenKeyExW(in HKEY hKey, in wchar* lpSubKey, in DWORD ulOptions, in REGSAM samDesired, HKEY* phkResult);

extern(Windows)
LONG RegCreateKeyExW(in HKEY hKey, in wchar* lpSubKey, DWORD Reserved, in wchar* lpClass, in DWORD dwOptions,
                     in REGSAM samDesired, in SECURITY_ATTRIBUTES* lpSecurityAttributes, HKEY* phkResult, DWORD* lpdwDisposition);

extern(Windows)
LONG RegSetValueExW(in HKEY hKey, in wchar* lpValueName, DWORD reserved, DWORD dwType, in ubyte* data, DWORD nSize);

extern(Windows)
LONG RegQueryValueW(in HKEY hKey, in wchar* lpSubKey, wchar* lpValue, LONG *lpcbValue);

extern(Windows)
LONG RegQueryValueExW(in HKEY hkey, in wchar* lpValueName, in int Reserved, DWORD* type, void *lpData, LONG *pcbData);

enum { SECURE_ACCESS = ~(WRITE_DAC | WRITE_OWNER | GENERIC_ALL | ACCESS_SYSTEM_SECURITY) }

extern(Windows)
LONG RegQueryInfoKeyW(in HKEY hKey, wchar* lpClass, DWORD* lpcClass, DWORD* lpReserved,
                      DWORD* lpcSubKeys, DWORD* lpcMaxSubKeyLen, DWORD* lpcMaxClassLen,
                      DWORD* lpcValues, DWORD* lpcMaxValueNameLen, DWORD* lpcMaxValueLen,
                      DWORD* lpcbSecurityDescriptor, FILETIME* lpftLastWriteTime);

extern(Windows)
LONG RegEnumKeyW(in HKEY hKey, in DWORD dwIndex, wchar* lpName, in DWORD cchName);

extern(Windows)
LONG RegEnumKeyExW(in HKEY hKey, in DWORD dwIndex, wchar* lpName, DWORD* lpcName,
                   DWORD* lpReserved, wchar* lpClass, DWORD* lpcClass, FILETIME* lpftLastWriteTime);

extern(Windows)
LONG RegDeleteKeyW(in HKEY hKey, in wchar* lpSubKey);

enum { ERROR_INSUFFICIENT_BUFFER = 122 }

HRESULT HRESULT_FROM_WIN32(ulong x)
{
	enum { FACILITY_WIN32 = 7 };
	return cast(HRESULT)(x) <= 0 ? cast(HRESULT)(x) 
	                             : cast(HRESULT) (((x) & 0x0000FFFF) | (FACILITY_WIN32 << 16) | 0x80000000);
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
			hr = hrRegCreateKeyEx(root, keyname, 0, null, REG_OPTION_NON_VOLATILE, KEY_WRITE, null, &key, null);
		else
			hr = hrRegOpenKeyEx(root, keyname, 0, KEY_READ, &key);
		if(FAILED(hr))
			throw new RegistryException(hr);
	}

	void Set(wstring name, wstring value)
	{
		HRESULT hr = RegCreateValue(key, name, value);
		if(FAILED(hr))
			throw new RegistryException(hr);
	}

	void Set(wstring name, uint value)
	{
		HRESULT hr = RegCreateDwordValue(key, name, value);
		if(FAILED(hr))
			throw new RegistryException(hr);
	}

	wstring GetString(wstring name)
	{
		wchar buf[260];
		LONG cnt = 260 * wchar.sizeof;
		wstring szName = name ~ cast(wchar)0;
		DWORD type;
		int hr = RegQueryValueExW(key, szName.ptr, 0, &type, buf, &cnt);
		if(hr == S_OK && cnt > 0)
			return to_wstring(buf);
		if(hr != ERROR_MORE_DATA || type != REG_SZ)
			return ""w;

		scope wchar[] pbuf = new wchar[cnt/2 + 1];
		RegQueryValueExW(key, szName.ptr, 0, &type, pbuf.ptr, &cnt);
		return to_wstring(pbuf.ptr);
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
static const wstring regMiscFiles          = regPathProjects ~ "\\{A2FE74E1-B743-11d0-AE1A-00A0C90FFFC3}"w;

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
		szRegistrationRoot ~= "\\Configuration"w;

	return szRegistrationRoot;
}

HRESULT VSDllUnregisterServerInternal(in wchar* pszRegRoot, in bool useRanu)
{
	HKEY keyRoot = useRanu ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
	wstring registrationRoot = GetRegistrationRoot(pszRegRoot, useRanu);

	wstring packageGuid = GUID2wstring(g_packageCLSID);
	wstring languageGuid = GUID2wstring(g_languageCLSID);

	HRESULT hr = S_OK;
	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\Packages\\"w ~ packageGuid);
	hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ languageGuid);

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

	return hr;
}

HRESULT VSDllRegisterServerInternal(in wchar* pszRegRoot, in bool useRanu)
{
	HKEY    keyRoot = useRanu ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
	wstring registrationRoot = GetRegistrationRoot(pszRegRoot, useRanu);
	wstring dllPath = GetModuleFileName(g_hInst);
	wstring templatePath = GetTemplatePath(dllPath);

	try
	{
		wstring packageGuid = GUID2wstring(g_packageCLSID);
		wstring languageGuid = GUID2wstring(g_languageCLSID);

		scope RegKey keyPackage = new RegKey(keyRoot, registrationRoot ~ "\\Packages\\"w ~ packageGuid);
		keyPackage.Set(null, g_packageName);
		keyPackage.Set("InprocServer32"w, dllPath);
		keyPackage.Set("About"w, g_packageName);
		keyPackage.Set("CompanyName"w, g_packageCompany);
		keyPackage.Set("ProductName"w, g_packageName);
		keyPackage.Set("ProductVersion"w, g_packageVersion);
		keyPackage.Set("MinEdition"w, "Standard");
		keyPackage.Set("ID"w, 1);

		int bspos = dllPath.length - 1;	while (bspos >= 0 && dllPath[bspos] != '\\') bspos--;
		scope RegKey keySatellite = new RegKey(keyRoot, registrationRoot ~ "\\Packages\\"w ~ packageGuid ~ "\\SatelliteDll"w);
		keySatellite.Set("Path"w, dllPath[0 .. bspos+1]);
		keySatellite.Set("DllName"w, ".."w ~ dllPath[bspos .. $]);

		scope RegKey keyCLSID = new RegKey(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ languageGuid);
		keyCLSID.Set("InprocServer32"w, dllPath);
		keyCLSID.Set("ThreadingModel"w, "Free"w); // Appartment?

		wstring fileExtensions;
		foreach (wstring fileExt; g_languageFileExtensions)
		{
			scope RegKey keyExt = new RegKey(keyRoot, registrationRoot ~ regPathFileExts ~ "\\"w ~ fileExt);
			keyExt.Set(null, languageGuid);
			keyExt.Set("Name"w, g_languageName);
			fileExtensions ~= fileExt ~ ";"w;
		}

		scope RegKey keyLang = new RegKey(keyRoot, registrationRoot ~ regPathLServices ~ "\\"w ~ g_languageName);
		keyLang.Set(null, languageGuid);
		keyLang.Set("Package"w, packageGuid);
		keyLang.Set("Extensions"w, fileExtensions);
		keyLang.Set("LangResId"w, 0);
		foreach (ref LanguageProperty prop; g_languageProperties)
			keyLang.Set(prop.name, prop.value);
		
		scope RegKey keyService = new RegKey(keyRoot, registrationRoot ~ "\\Services\\"w ~ languageGuid);
		keyService.Set(null, packageGuid);
		keyService.Set("Name"w, g_languageName);
		
		scope RegKey keyProduct = new RegKey(keyRoot, registrationRoot ~ "\\InstalledProducts\\"w ~ g_packageName);
		keyProduct.Set("Package"w, packageGuid);
		keyProduct.Set("UseInterface"w, 1);

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

		scope RegKey keyProject1 = new RegKey(keyRoot, projects ~ "\\AddItemTemplates\\TemplateDirs\\"w ~ packageGuid ~ "\\/1"w);
		keyProject1.Set(null, g_languageName);
		keyProject1.Set("TemplatesDir"w, templatePath ~ "\\Items"w);
		keyProject1.Set("SortPriority"w, 25);

		// Miscellaneous Files Project
		scope RegKey keyProject2 = new RegKey(keyRoot, registrationRoot ~ regMiscFiles ~ "\\AddItemTemplates\\TemplateDirs\\"w ~ packageGuid ~ "\\/1"w);
		keyProject1.Set(null, g_languageName);
		keyProject1.Set("TemplatesDir"w, templatePath ~ "\\Items"w);
		keyProject1.Set("SortPriority"w, 25);

		foreach(guid; guids_propertyPages)
		{
			scope RegKey keyProp = new RegKey(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ GUID2wstring(*guid));
			keyProp.Set("InprocServer32"w, dllPath);
			keyProp.Set("ThreadingModel"w, "Appartment"w);
		}

		scope RegKey keyToolOpts = new RegKey(keyRoot, registrationRoot ~ regPathToolsOptions);
		keyToolOpts.Set(null, "Visual D Settings");
		keyToolOpts.Set("Package"w, packageGuid);
		keyToolOpts.Set("Page"w, GUID2wstring(g_ToolsPropertyPage));
		if(keyToolOpts.GetString("ExeSearchPath"w).length == 0)
			keyToolOpts.Set("ExeSearchPath"w, "$(DMDInstallDir)windows\\bin\n$(WindowsSdkDir)\\bin"w);
		if(keyToolOpts.GetString("IncSearchPath"w).length == 0)
			keyToolOpts.Set("IncSearchPath"w, "$(WindowsSdkDir)\\include;$(DevEnvDir)..\\..\\VC\\include"w);

		scope RegKey keyMarshal1 = new RegKey(HKEY_CLASSES_ROOT, "CLSID\\"w ~ GUID2wstring(g_unmarshalCLSID) ~ "\\InprocServer32"w);
		keyMarshal1.Set("InprocServer32"w, dllPath);
		keyMarshal1.Set("ThreadingModel"w, "Appartment"w);

		scope RegKey keyMarshal2 = new RegKey(HKEY_CLASSES_ROOT, "CLSID\\"w ~ GUID2wstring(g_unmarshalCLSID) ~ "\\InprocHandler32"w);
		keyMarshal2.Set(null, dllPath);
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
HRESULT RegCreateValue(in HKEY key, in wstring name, in wstring value)
{
	wstring szName = name ~ cast(wchar)0;
	wstring szValue = value ~ cast(wchar)0;
	DWORD dwDataSize = value is null ? 0 : wchar.sizeof * (value.length+1);
	LONG lRetCode = RegSetValueExW(key, szName.ptr, 0, REG_SZ, cast(ubyte*)(szValue.ptr), dwDataSize);
	return HRESULT_FROM_WIN32(lRetCode);
}

HRESULT RegCreateDwordValue(in HKEY key, in wstring name, in DWORD value)
{
	wstring szName = name ~ cast(wchar)0;
	LONG lRetCode = RegSetValueExW(key, szName.ptr, 0, REG_DWORD, cast(ubyte*)(&value), value.sizeof);
	return HRESULT_FROM_WIN32(lRetCode);
}

HRESULT RegDeleteRecursive(in HKEY keyRoot, wstring path)
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

wstring GetModuleFileName(HINSTANCE inst)
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
	path = getDirName(path);
	debug path = getDirName(getDirName(path)) ~ "\\visuald";
	path = path ~ "\\Templates";
	return toUTF16(path);
}

HRESULT hrRegOpenKeyEx(in HKEY root, wstring regPath, int reserved, REGSAM samDesired, HKEY* phkResult)
{
	wstring szRegPath = regPath ~ cast(wchar)0;
	LONG lRes = RegOpenKeyExW(root, szRegPath.ptr, 0, samDesired, phkResult);
	return HRESULT_FROM_WIN32(lRes);
}

HRESULT hrRegCreateKeyEx(in HKEY keySub, wstring regPath, int reserved, wstring classname, DWORD opt, DWORD samDesired, 
			 SECURITY_ATTRIBUTES* security, HKEY* key, DWORD* disposition)
{
	wstring szRegPath = regPath ~ cast(wchar)0;
	wstring szClassname = classname ~ cast(wchar)0;
	LONG lRes = RegCreateKeyExW(keySub, szRegPath.ptr, 0, szClassname.ptr, opt, samDesired, security, key, disposition);
	return HRESULT_FROM_WIN32(lRes);
}
