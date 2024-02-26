// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt

module visuald.register;

import visuald.windows;
import sdk.win32.winreg;
import sdk.win32.winnls;

import std.string;
import std.conv;
import std.utf;
import std.path;
import std.file;
import std.datetime;
import std.array;

import stdext.string;
import stdext.registry;

import visuald.dpackage;
import visuald.propertypage;
import visuald.config;
import visuald.comutil;

// Registers COM objects normally and registers VS Packages to the specified VS registry hive under HKCU
extern(Windows)
HRESULT VSDllRegisterServerUser(const wchar* strRegRoot)
{
	return VSDllRegisterServerInternal(strRegRoot, true);
}

// Unregisters COM objects normally and unregisters VS Packages from the specified VS registry hive under HKCU
extern(Windows)
HRESULT VSDllUnregisterServerUser(const wchar* strRegRoot)
{
	return VSDllUnregisterServerInternal(strRegRoot, true);
}

// Registers COM objects normally and registers VS Packages to the specified VS registry hive
extern(Windows)
HRESULT VSDllRegisterServer(const wchar* strRegRoot)
{
	return VSDllRegisterServerInternal(strRegRoot, false);
}

// Unregisters COM objects normally and unregisters VS Packages from the specified VS registry hive
extern(Windows)
HRESULT VSDllUnregisterServer(const wchar* strRegRoot)
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

extern(Windows)
HRESULT WriteExtensionPackageDefinition(const wchar* args)
{
	wstring wargs = to_wstring(args);
	auto idx = indexOf(wargs, ' ');
	if(idx < 1)
		return E_FAIL;

	registryDump = "Windows Registry Editor Version 5.00\n"w;
	registryRoot = (wargs[0 .. idx] ~ "\0"w)[0 .. idx];
	string fname = to!string(wargs[idx + 1 .. $]);
	try
	{
		HRESULT rc = VSDllRegisterServerInternal(registryRoot.ptr, false);
		if(rc != S_OK)
			return rc;

		string dir = dirName(fname);
		if(!exists(dir))
			mkdirRecurse(dir);

		std.file.write(fname, (cast(wchar) 0xfeff) ~ registryDump); // add BOM
		return S_OK;
	}
	catch(Throwable e)
	{
		MessageBox(null, toUTF16z(e.msg), args, MB_OK);
	}
	return E_FAIL;
}

///////////////////////////////////////////////////////////////////////

wstring registryDump;
wstring registryRoot;

class RegistryException : Exception
{
	this(HRESULT hr)
	{
		super("Registry Error");
		result = hr;
	}

	HRESULT result;
}

enum RegHive { def, x64, x86 }

class RegKey
{
	this(HKEY root, wstring keyname, bool write = true, bool chkDump = true, RegHive hive = RegHive.def)
	{
		Create(root, keyname, write, chkDump, hive);
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

	static wstring registryName(wstring name)
	{
		if(name.length == 0)
			return "@"w;
		return  "\""w ~ escapeString(name) ~ "\""w;
	}

	void Create(HKEY root, wstring keyname, bool write, bool chkDump, RegHive hive)
	{
		DWORD sam = hive == RegHive.x64 ? KEY_WOW64_64KEY : hive == RegHive.x86 ? KEY_WOW64_32KEY : 0;
		HRESULT hr;
		if(write && chkDump && registryRoot.length && keyname.startsWith(registryRoot))
		{
			if (keyname.startsWith(registryRoot))
				registryDump ~= "\n[$RootKey$"w ~ keyname[registryRoot.length..$] ~ "]\n"w;
			else
				registryDump ~= "\n[\\"w ~ keyname ~ "]\n"w;
		}
		else if(write)
		{
			auto opt = REG_OPTION_NON_VOLATILE;
			hr = hrRegCreateKeyEx(root, keyname, 0, null, opt, sam | KEY_WRITE, null, &key, null);
			if(FAILED(hr))
				throw new RegistryException(hr);
		}
		else
		{
			hr = hrRegOpenKeyEx(root, keyname, REG_OPTION_OPEN_LINK, sam | KEY_READ, &key);
		}
	}

	void Set(wstring name, wstring value, bool escape = true)
	{
		if(!key && registryRoot.length)
		{
			if(escape)
				value = escapeString(value);
			registryDump ~= registryName(name) ~ "=\""w ~ value ~ "\"\n"w;
			return;
		}
		if(!key)
			throw new RegistryException(E_FAIL);

		HRESULT hr = RegCreateValue(key, name, value);
		if(FAILED(hr))
			throw new RegistryException(hr);
	}

	void Set(wstring name, uint value)
	{
		if(!key && registryRoot.length)
		{
			registryDump ~= registryName(name) ~ "=dword:"w;
			registryDump ~= to!wstring(format("%08x", value)) ~ "\n";
			return;
		}
		if(!key)
			throw new RegistryException(E_FAIL);

		HRESULT hr = RegCreateDwordValue(key, name, value);
		if(FAILED(hr))
			throw new RegistryException(hr);
	}

	void Set(wstring name, long value)
	{
		if(!key && registryRoot.length)
		{
			registryDump ~= registryName(name) ~ "=qword:"w;
			registryDump ~= to!wstring(to!string(value, 16) ~ "\n");
			return;
		}
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
		if(!key && registryRoot.length)
			return true; // ignore
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

		wchar[260] buf;
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
static const wstring regPathToolsDirsOld   = "\\ToolsOptionsPages\\Projects\\Visual D Directories"w;
static const wstring regPathToolsDirsDmd   = "\\ToolsOptionsPages\\Projects\\Visual D Settings\\DMD Directories"w;
static const wstring regPathToolsDirsGdc   = "\\ToolsOptionsPages\\Projects\\Visual D Settings\\GDC Directories"w;
static const wstring regPathToolsDirsLdc   = "\\ToolsOptionsPages\\Projects\\Visual D Settings\\LDC Directories"w;
static const wstring regPathToolsDirsCmd   = "\\ToolsOptionsPages\\Projects\\Visual D Settings\\Compile/Run/Debug/Dustmite"w;
static const wstring regPathToolsUpdate    = "\\ToolsOptionsPages\\Projects\\Visual D Settings\\Updates"w;
static const wstring regPathToolsDub       = "\\ToolsOptionsPages\\Projects\\Visual D Settings\\DUB Options"w;
static const wstring regPathMagoOptions    = "\\ToolsOptionsPages\\Debugger\\Mago"w;
static const wstring regPathMetricsExcpt   = "\\AD7Metrics\\Exception"w;
static const wstring regPathMetricsEE      = "\\AD7Metrics\\ExpressionEvaluator"w;

static const wstring vendorMicrosoftGuid   = "{994B45C4-E6E9-11D2-903F-00C04FA302A1}"w;
static const wstring guidCOMPlusNativeEng  = "{92EF0900-2251-11D2-B72E-0000F87572EF}"w;

static const GUID GUID_MaGoDebugger = uuid("{97348AC0-2B6B-4B99-A245-4C7E2C09D403}");

static const wstring[] regMiscProjects =
[
	// GUID                                       TemplateGroupIDs(VsTemplate)
	"{A2FE74E1-B743-11d0-AE1A-00A0C90FFFC3}"w, // misc (new item without project)
	"{3295daf3-837e-4482-ab9c-a945fa3e0cee}"w, // VC-Windows;WinRT-Common;VC-Native;VC-MFC
	"{887e6942-90cd-4266-8816-b74502858c07}"w, // VC-Windows;WinRT-Native-6.3;WinRT-Common
	"{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}"w, // VC
	"{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC943}"w, // VC-Windows;WinRT-Common;VC-Native <= used by our templates
	"{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC944}"w, // VC-Windows;WinRT-Common;VC-Managed
	"{8BC9CEBA-8B4A-11D0-8D11-00A0C91BC942}"w, // VC package addclass?
	"{8C3FFDCC-9A63-43F2-9A3E-C45FB2ABF450}"w, // VC-Windows;WinRT-Common;VC-Native
	"{dc073cad-303e-4838-9969-278c87bd53eb}"w, // VC-Windows;WinRT-Native-Phone-6.3;WinRT-Common
	"{F8BBB05E-FBD0-4B36-8C17-0B3F79AD4F01}"w, // VC-Android
	"{fae12128-4bbf-454a-b96c-e83e7ad6a783}"w, // VC-Windows;CodeSharing-Native;WinRT-Common
	"{fe0b9df8-a7c2-4687-a235-316c1aca78d3}"w, // VC-Windows;WinRT-Native-UAP;WinRT-Common
];

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

float guessVSVersion(wstring registrationRoot)
{
	auto idx = lastIndexOf(registrationRoot, '\\');
	if(idx < 0 || idx >= registrationRoot.length)
		return 0;
	wstring txt = registrationRoot[idx + 1 .. $];
	// parse integer part only, the remainder is unused anyway
	int ver = 0;
	for (++idx; idx < registrationRoot.length && std.ascii.isDigit(registrationRoot[idx]); ++idx)
		ver = ver * 10 + registrationRoot[idx] - '0';
	return ver;
}

void updateConfigurationChanged(HKEY keyRoot, wstring registrationRoot)
{
	float ver = guessVSVersion(registrationRoot);
	//MessageBoxA(null, text("version: ", ver, "\nregkey: ", to!string(registrationRoot)).ptr, to!string(registrationRoot).ptr, MB_OK);
	if(ver >= 11)
	{
		scope RegKey keyRegRoot = new RegKey(keyRoot, registrationRoot, true, false);

		// avoid: Function type does not match previously declared function with the same mangled name
		// which is an ambiguity between sdk.win32 and core.sys.windows
		version(LDC)
			import core.sys.windows.winbase : FILETIME, GetSystemTimeAsFileTime;
		FILETIME fileTime;
		GetSystemTimeAsFileTime(&fileTime);
		ULARGE_INTEGER ul;
		ul.HighPart = fileTime.dwHighDateTime;
		ul.LowPart = fileTime.dwLowDateTime;
		ulong tempHNSecs = ul.QuadPart;

		keyRegRoot.Set("ConfigurationChanged", tempHNSecs);
	}
}

void fixVS2012Shellx64Debugger(HKEY keyRoot, wstring registrationRoot)
{
	float ver = guessVSVersion(registrationRoot);
	//MessageBoxA(null, text("version: ", ver, "\nregkey: ", to!string(registrationRoot)).ptr, to!string(registrationRoot).ptr, MB_OK);
	if(ver >= 11 && ver < 14)
	{
		scope RegKey keyDebugger = new RegKey(keyRoot, registrationRoot ~ "\\Debugger"w);
		keyDebugger.Set("msvsmon-pseudo_remote"w, r"$ShellFolder$\Common7\Packages\Debugger\X64\msvsmon.exe"w, false);
	}
}

bool generateGeneralXML(string originalXML, string insertXML, string newXML)
{
	try
	{
		if (!std.file.exists(originalXML))
		{
			// if english (LCID 1033) not installed, try the system language
			auto id = GetSystemDefaultLangID();
			auto basedir = dirName(dirName(originalXML));
			auto filename = baseName(originalXML);
			originalXML = buildPath(basedir, to!string(id), filename);
			if (!std.file.exists(originalXML))
				foreach (string name; dirEntries(basedir, SpanMode.depth))
					if (icmp(baseName(name), filename) == 0)
					{
						originalXML = name;
						break;
					}
		}

		string oxml = cast(string) std.file.read(originalXML);
		string ixml = cast(string) std.file.read(insertXML);

		auto pos = oxml.indexOf(`<DynamicEnumProperty Name="PlatformToolset"`);
		if (pos >= 0)
		{
			// insert before next tag after "PlatformToolset"
			auto p = oxml[pos+1..$].indexOf('<');
			if (p < 0)
				return false;
			pos += 1 + p;
		}
		else
		{
			// insert before end tag
			pos = oxml.indexOf(`</Rule>`);
			if (pos < 0)
				return false;
		}
		string nxml = oxml[0..pos] ~ ixml ~ oxml[pos..$];
		std.file.write(newXML, nxml);
		return true;
	}
	catch(Exception e)
	{
	}
	return false;
}

HRESULT VSDllUnregisterServerInternal(in wchar* pszRegRoot, in bool useRanu)
{
	HKEY keyRoot = useRanu ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
	wstring registrationRoot = GetRegistrationRoot(pszRegRoot, useRanu);

	HRESULT hr = S_OK;
	float ver = guessVSVersion(registrationRoot);
	if (ver < 14)
	{
		wstring packageGuid = GUID2wstring(g_packageCLSID);
		wstring languageGuid = GUID2wstring(g_languageCLSID);
		wstring wizardGuid = GUID2wstring(g_ProjectItemWizardCLSID);
		wstring vdhelperGuid = GUID2wstring(g_VisualDHelperCLSID);
		wstring vchelperGuid = GUID2wstring(g_VisualCHelperCLSID);

		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\Packages\\"w ~ packageGuid);
		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ languageGuid);
		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ wizardGuid);
		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ vdhelperGuid);
		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ vchelperGuid);

		foreach (wstring fileExt; g_languageFileExtensions)
			hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathFileExts ~ "\\"w ~ fileExt);

		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\Services\\"w ~ languageGuid);
		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\InstalledProducts\\"w ~ g_packageName);

		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathLServices ~ "\\"w ~ g_languageName);
		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathCodeExpansions ~ "\\"w ~ g_languageName);

		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathPrjTemplates ~ "\\"w ~ packageGuid);
		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathProjects ~ "\\"w ~ GUID2wstring(g_projectFactoryCLSID));
		foreach (reg; regMiscProjects)
			hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathProjects ~ "\\"w ~ reg ~ "\\AddItemTemplates\\TemplateDirs\\"w ~ packageGuid);

		hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ regPathToolsOptions);

		foreach(guid; guids_propertyPages)
			hr |= RegDeleteRecursive(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ GUID2wstring(*guid));

		hr |= RegDeleteRecursive(HKEY_CLASSES_ROOT, "CLSID\\"w ~ GUID2wstring(g_unmarshalEnumOutCLSID));
		static if(is(typeof(g_unmarshalTargetInfoCLSID)))
			hr |= RegDeleteRecursive(HKEY_CLASSES_ROOT, "CLSID\\"w ~ GUID2wstring(g_unmarshalTargetInfoCLSID));

		scope RegKey keyToolMenu = new RegKey(keyRoot, registrationRoot ~ "\\Menus"w);
		keyToolMenu.Delete(packageGuid);
	}

	updateConfigurationChanged(keyRoot, registrationRoot);
	return hr;
}

HRESULT VSDllRegisterServerInternal(in wchar* pszRegRoot, in bool useRanu)
{
	HKEY    keyRoot = useRanu ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
	wstring registrationRoot = GetRegistrationRoot(pszRegRoot, useRanu);
	wstring dllPath = GetDLLName(g_hInst);
	wstring instPath = dirName(dllPath);
	wstring templatePath = GetTemplatePath(instPath);
	wstring vdextPath = instPath ~ "\\vdextensions.dll"w;

	float ver = guessVSVersion(registrationRoot);
	if (ver >= 17)
		dllPath = buildPath(instPath, "x64"w, baseName(dllPath)); // 32-bit DLL used to register 64-bit DLL

	wstring dbuildPath;
	if (ver == 12)
		dbuildPath = instPath ~ "\\msbuild\\dbuild.12.0.dll"w;
	else if (ver == 14)
		dbuildPath = instPath ~ "\\msbuild\\dbuild.14.0.dll"w;
	else if (ver == 15)
		dbuildPath = instPath ~ "\\msbuild\\dbuild.15.0.dll"w;
	else if (ver == 16)
		dbuildPath = instPath ~ "\\msbuild\\dbuild.16.0.dll"w;
	else if (ver == 17)
		dbuildPath = instPath ~ "\\msbuild\\dbuild.17.0.dll"w;

	wstring vdext15Path;
	if (ver >= 15)
		vdext15Path = instPath ~ "\\vdext15.dll"w;

	try
	{
		wstring packageGuid = GUID2wstring(g_packageCLSID);
		wstring languageGuid = GUID2wstring(g_languageCLSID);
		wstring debugLangGuid = GUID2wstring(g_debuggerLanguage);
		wstring exprEvalGuid = GUID2wstring(g_expressionEvaluator);
		wstring wizardGuid = GUID2wstring(g_ProjectItemWizardCLSID);
		wstring vdhelperGuid = GUID2wstring(g_VisualDHelperCLSID);
		wstring vdhelper15Guid = GUID2wstring(g_VisualDHelper15CLSID);
		wstring vchelperGuid = GUID2wstring(g_VisualCHelperCLSID);

		// package
		scope RegKey keyPackage = new RegKey(keyRoot, registrationRoot ~ "\\Packages\\"w ~ packageGuid);
		keyPackage.Set(null, g_packageName);
		keyPackage.Set("InprocServer32"w, dllPath);
		keyPackage.Set("About"w, g_packageName);
		keyPackage.Set("CompanyName"w, g_packageCompany);
		keyPackage.Set("ProductName"w, g_packageName);
		keyPackage.Set("ProductVersion"w, toUTF16(ver < 10 ? plk_version : g_packageVersion));
		keyPackage.Set("MinEdition"w, "Standard");
		keyPackage.Set("ID"w, 1);

		ptrdiff_t bspos = dllPath.length - 1;	while (bspos >= 0 && dllPath[bspos] != '\\') bspos--;
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

		// VDExtensions
		if (vdextPath)
		{
			scope RegKey keyHelperCLSID = new RegKey(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ vdhelperGuid);
			keyHelperCLSID.Set("InprocServer32"w, "mscoree.dll");
			keyHelperCLSID.Set("ThreadingModel"w, "Both"w);
			keyHelperCLSID.Set(null, "vdextensions.VisualDHelper"w);
			keyHelperCLSID.Set("Class"w, "vdextensions.VisualDHelper"w);
			keyHelperCLSID.Set("CodeBase"w, vdextPath);
		}

		// VDExtensions
		version(vdext15)
		if (vdext15Path)
		{
			scope RegKey keyHelperCLSID = new RegKey(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ vdhelper15Guid);
			keyHelperCLSID.Set("InprocServer32"w, "mscoree.dll");
			keyHelperCLSID.Set("ThreadingModel"w, "Both"w);
			keyHelperCLSID.Set(null, "vdextensions.VisualDHelper15"w);
			keyHelperCLSID.Set("Class"w, "vdextensions.VisualDHelper15"w);
			keyHelperCLSID.Set("CodeBase"w, vdext15Path);
		}

		// dbuild extension
		if (dbuildPath)
		{
			scope RegKey keyHelperCLSID = new RegKey(keyRoot, registrationRoot ~ "\\CLSID\\"w ~ vchelperGuid);
			keyHelperCLSID.Set("InprocServer32"w, "mscoree.dll");
			keyHelperCLSID.Set("ThreadingModel"w, "Both"w);
			keyHelperCLSID.Set(null, "vdextensions.VisualCHelper"w);
			keyHelperCLSID.Set("Class"w, "vdextensions.VisualCHelper"w);
			keyHelperCLSID.Set("CodeBase"w, dbuildPath);
		}

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
		scope RegKey keyColorizer = new RegKey(keyRoot, langserv ~ "\\EditorToolsOptions\\Editor"w);
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

		// project
		wstring tmplprojectdir = ver < 10 ? "\\Projects_vs9"w : "\\Projects"w;

		if (ver < 15) // registered in vsixmanifest
		{
			scope RegKey keyPrjTempl = new RegKey(keyRoot, registrationRoot ~ regPathPrjTemplates ~ "\\"w ~ packageGuid ~ "\\/1");
			keyPrjTempl.Set(null, g_languageName);
			keyPrjTempl.Set("DeveloperActivity"w, g_languageName);
			keyPrjTempl.Set("SortPriority"w, 20);
			keyPrjTempl.Set("TemplatesDir"w, templatePath ~ tmplprojectdir);
			keyPrjTempl.Set("Folder"w, "{152CDB9D-B85A-4513-A171-245CE5C61FCC}"w); // other languages
		}

		wstring projects = registrationRoot ~ "\\Projects\\"w ~ GUID2wstring(g_projectFactoryCLSID);
		scope RegKey keyProject = new RegKey(keyRoot, projects);
		keyProject.Set(null, "DProjectFactory"w);
		keyProject.Set("DisplayName"w, g_languageName);
		wstring starFiles = "*."w ~ join(g_projectFileExtensions, ",*."w);
		keyProject.Set("DisplayProjectFileExtensions"w, g_languageName ~ " Project Files ("w ~ starFiles ~ ");"w ~ starFiles);
		keyProject.Set("Package"w, packageGuid);
		keyProject.Set("DefaultProjectExtension"w, g_defaultProjectFileExtension);
		keyProject.Set("PossibleProjectExtensions"w, join(g_projectFileExtensions, ";"w));
		if (ver < 15) // registered in vsixmanifest
			keyProject.Set("ProjectTemplatesDir"w, templatePath ~ tmplprojectdir);
		keyProject.Set("Language(VsTemplate)"w, g_languageName);
		keyProject.Set("ItemTemplatesDir"w, templatePath ~ "\\Items"w);

		// file templates
		scope RegKey keyProject1 = new RegKey(keyRoot, projects ~ "\\AddItemTemplates\\TemplateDirs\\"w ~ packageGuid ~ "\\/1"w);
		keyProject1.Set(null, g_languageName);
		keyProject1.Set("TemplatesDir"w, templatePath ~ "\\Items"w);
		keyProject1.Set("SortPriority"w, 25);

		// new items in VC Projects
		foreach (reg; regMiscProjects)
		{
			wstring strkey = registrationRoot ~ regPathProjects ~ "\\"w ~ reg ~ "\\AddItemTemplates\\TemplateDirs\\"w ~ packageGuid ~ "\\/1"w;
			scope RegKey keyProject2 = new RegKey(keyRoot, strkey);
			keyProject2.Set(null, g_languageName);
			keyProject2.Set("TemplatesDir"w, templatePath ~ "\\VCItems"w);
			keyProject2.Set("SortPriority"w, 25);
		}

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
		keyToolMenu.Set(packageGuid, ",2001,20"); // CTMENU,version

		// Visual D settings
		scope RegKey keyToolOpts = new RegKey(keyRoot, registrationRoot ~ regPathToolsOptions);
		keyToolOpts.Set(null, "Visual D Settings");
		keyToolOpts.Set("Package"w, packageGuid);
		keyToolOpts.Set("Page"w, GUID2wstring(g_ToolsProperty2Page));

		// remove old page
		RegDeleteRecursive(keyRoot, registrationRoot ~ regPathToolsDirsOld);

		scope RegKey keyToolOptsDmd = new RegKey(keyRoot, registrationRoot ~ regPathToolsDirsDmd);
		keyToolOptsDmd.Set(null, "DMD Directories");
		keyToolOptsDmd.Set("Package"w, packageGuid);
		keyToolOptsDmd.Set("Page"w, GUID2wstring(g_DmdDirPropertyPage));
		keyToolOptsDmd.Set("Sort"w, 1);

		scope RegKey keyToolOptsGdc = new RegKey(keyRoot, registrationRoot ~ regPathToolsDirsGdc);
		keyToolOptsGdc.Set(null, "GDC Directories");
		keyToolOptsGdc.Set("Package"w, packageGuid);
		keyToolOptsGdc.Set("Page"w, GUID2wstring(g_GdcDirPropertyPage));
		keyToolOptsGdc.Set("Sort"w, 10);

		scope RegKey keyToolOptsLdc = new RegKey(keyRoot, registrationRoot ~ regPathToolsDirsLdc);
		keyToolOptsLdc.Set(null, "LDC Directories");
		keyToolOptsLdc.Set("Package"w, packageGuid);
		keyToolOptsLdc.Set("Page"w, GUID2wstring(g_LdcDirPropertyPage));
		keyToolOptsLdc.Set("Sort"w, 20);

		scope RegKey keyToolOptsCmd = new RegKey(keyRoot, registrationRoot ~ regPathToolsDirsCmd);
		keyToolOptsLdc.Set(null, "Compile/Run/Debug/Dustmite");
		keyToolOptsLdc.Set("Package"w, packageGuid);
		keyToolOptsLdc.Set("Page"w, GUID2wstring(g_CmdLinePropertyPage));
		keyToolOptsLdc.Set("Sort"w, 40);

		scope RegKey keyToolOptsUpdate = new RegKey(keyRoot, registrationRoot ~ regPathToolsUpdate);
		keyToolOptsLdc.Set(null, "Updates");
		keyToolOptsLdc.Set("Package"w, packageGuid);
		keyToolOptsLdc.Set("Page"w, GUID2wstring(g_UpdatePropertyPage));
		keyToolOptsLdc.Set("Sort"w, 50);

static if(hasDubSupport)
{
		scope RegKey keyToolOptsDub = new RegKey(keyRoot, registrationRoot ~ regPathToolsDub);
		keyToolOptsDub.Set(null, "DUB Options");
		keyToolOptsDub.Set("Package"w, packageGuid);
		keyToolOptsDub.Set("Page"w, GUID2wstring(g_DubPropertyPage));
		keyToolOptsDub.Set("Sort"w, 30);
}

		// remove "SkipLoading" entry from user settings
		scope RegKey userKeyPackage = new RegKey(HKEY_CURRENT_USER, registrationRoot ~ "\\Packages\\"w ~ packageGuid);
		userKeyPackage.Delete("SkipLoading");

		// remove Text Editor FontsAndColors Cache to add new Colors provided by Visual D
		RegDeleteRecursive(HKEY_CURRENT_USER, registrationRoot ~ "\\FontAndColors\\Cache"); // \\{A27B4E24-A735-4D1D-B8E7-9716E1E3D8E0}");

		fixVS2012Shellx64Debugger(keyRoot, registrationRoot);

		registerMago(pszRegRoot, useRanu);

		// global registry keys for marshalled objects
		void registerMarshalObject(ref const GUID iid)
		{
			scope RegKey keyMarshal1 = new RegKey(HKEY_CLASSES_ROOT, "CLSID\\"w ~ GUID2wstring(iid) ~ "\\InprocServer32"w);
			keyMarshal1.Set(null, dllPath);
			keyMarshal1.Set("ThreadingModel"w, "Both"w);
			scope RegKey keyMarshal2 = new RegKey(HKEY_CLASSES_ROOT, "CLSID\\"w ~ GUID2wstring(iid) ~ "\\InprocHandler32"w);
			keyMarshal2.Set(null, dllPath);
		}
		try
		{
			registerMarshalObject(g_unmarshalEnumOutCLSID);
			static if(is(typeof(g_unmarshalTargetInfoCLSID)))
				registerMarshalObject(g_unmarshalTargetInfoCLSID);

			updateConfigurationChanged(keyRoot, registrationRoot);
		}
		catch(Exception)
		{
			// silently ignore errors if not running as admin
		}
	}
	catch(RegistryException e)
	{
		return e.result;
	}
	return S_OK;
}

HRESULT registerMago(in wchar* pszRegRoot, in bool useRanu)
{
	HKEY    keyRoot = useRanu ? HKEY_CURRENT_USER : HKEY_LOCAL_MACHINE;
	wstring registrationRoot = GetRegistrationRoot(pszRegRoot, useRanu);

	// package
	scope RegKey keyProduct = new RegKey(keyRoot, registrationRoot ~ "\\InstalledProducts\\Mago"w);
	keyProduct.Set(null, "Mago Native Debug Engine"w);
	keyProduct.Set("PID"w, "1.0.0");
	keyProduct.Set("ProductDetails"w, "A debug engine dedicated to debugging applications written in the D programming language."
				   ~ " See the project website at http://www.dsource.org/projects/mago_debugger for more information."
				   ~ " Copyright (c) 2010-2014 Aldo J. Nunez"w);

	wstring magoGuid = GUID2wstring(GUID_MaGoDebugger);
	scope RegKey keyAD7 = new RegKey(keyRoot, registrationRoot ~ "\\AD7Metrics\\Engine\\"w ~ magoGuid);
	keyAD7.Set("CLSID"w, magoGuid);
	keyAD7.Set("Name"w, "Mago Native");
	keyAD7.Set("ENC"w, 0);
	keyAD7.Set("Disassembly"w, 1);
	keyAD7.Set("Exceptions"w, 1);
	keyAD7.Set("AlwaysLoadLocal"w, 1);

	// TODO: register exceptions

	wstring languageGuid = GUID2wstring(g_languageCLSID);
	wstring vendorGuid = GUID2wstring(g_vendorCLSID);

	wstring eeKeyStr = registrationRoot ~ "\\AD7Metrics\\ExpressionEvaluator\\"w ~ languageGuid ~ "\\"w ~ vendorGuid;
	scope RegKey keyEE = new RegKey(keyRoot, eeKeyStr);
	keyEE.Set("Language"w, "D"w);
	keyEE.Set("Name"w, "D"w);

	// needed to avoid "D does not support conditional breakpoints", see
	// https://github.com/Microsoft/ConcordExtensibilitySamples/issues/18
	scope RegKey keyEEEngine = new RegKey(keyRoot, eeKeyStr ~ "\\Engine"w);
	keyEE.Set("0"w, "{449EC4CC-30D2-4032-9256-EE18EB41B62B}"w); // COMPlusOnlyEng
	keyEE.Set("1"w, "{92EF0900-2251-11D2-B72E-0000F87572EF}"w); // COMPlusNativeEng
	keyEE.Set("2"w, "{3B476D35-A401-11D2-AAD4-00C04F990171}"w); // NativeOnlyEng

	scope RegKey keyCV = new RegKey(keyRoot, registrationRoot ~ "\\Debugger\\CodeView Compilers\\68:*"w);
	keyEE.Set("LanguageID"w, languageGuid);
	keyEE.Set("VendorID"w, vendorGuid);

	// mago property page
	wstring packageGuid = GUID2wstring(g_packageCLSID);
	scope RegKey keyPropPage = new RegKey(keyRoot, registrationRoot ~ regPathMagoOptions);
	keyPropPage.Set("Package"w, packageGuid);
	keyPropPage.Set("Page"w, GUID2wstring(g_MagoPropertyPage));

	void registerException(wstring keyName, uint code = 0)
	{
		scope RegKey keyExcp = new RegKey(keyRoot, keyName);
		keyPropPage.Set("Code"w, code);
		keyPropPage.Set("State"w, 3);
	}
	wstring[] Dexceptions =
	[
		"core.exception.AssertError",
		"core.exception.FinalizeError",
		"core.exception.HiddenFuncError",
		"core.exception.OutOfMemoryError",
		"core.exception.RangeError",
		"core.exception.SwitchError",
		"core.exception.UnicodeException",
		"core.sync.exception.SyncException",
		"core.thread.FiberException",
		"core.thread.ThreadException",
		"object.Error",
		"object.Exception",
		"std.base64.Base64CharException",
		"std.base64.Base64Exception",
		"std.boxer.UnboxException",
		"std.concurrency.LinkTerminated",
		"std.concurrency.MailboxFull",
		"std.concurrency.MessageMismatch",
		"std.concurrency.OwnerTerminated",
		"std.conv.ConvError",
		"std.conv.ConvOverflowError",
		"std.dateparse.DateParseError",
		"std.demangle.MangleException",
		"std.encoding.EncodingException",
		"std.encoding.UnrecognizedEncodingException",
		"std.exception.ErrnoException",
		"std.file.FileException",
		"std.format.FormatError",
		"std.json.JSONException",
		"std.loader.ExeModuleException",
		"std.math.NotImplemented",
		"std.regexp.RegExpException",
		"std.socket.AddressException",
		"std.socket.HostException",
		"std.socket.SocketAcceptException",
		"std.socket.SocketException",
		"std.stdio.StdioException",
		"std.stream.OpenException",
		"std.stream.ReadException",
		"std.stream.SeekException",
		"std.stream.StreamException",
		"std.stream.StreamFileException",
		"std.stream.WriteException",
		"std.typecons.NotImplementedError",
		"std.uri.URIerror",
		"std.utf.UtfError",
		"std.utf.UtfException",
		"std.variant.VariantException",
		"std.windows.registry.RegistryException",
		"std.windows.registry.Win32Exception",
		"std.xml.CDataException",
		"std.xml.CheckException",
		"std.xml.CommentException",
		"std.xml.DecodeException",
		"std.xml.InvalidTypeException",
		"std.xml.PIException",
		"std.xml.TagException",
		"std.xml.TextException",
		"std.xml.XIException",
		"std.xml.XMLException",
		"std.zip.ZipException",
		"std.zlib.ZlibException",
	];
	registerException(registrationRoot ~ r"\AD7Metrics\Exception\{3B476D35-A401-11D2-AAD4-00C04F990171}\Win32Exception\D Exception", 0xE0440001);
	registerException(registrationRoot ~ r"\AD7Metrics\Exception\" ~ magoGuid ~ r"\D Exceptions");
	wstring dexroot = registrationRoot ~ r"\AD7Metrics\Exception\"w ~ magoGuid ~ "\\D Exceptions\\";
	foreach (ex; Dexceptions)
		registerException(dexroot ~ ex);

	return S_OK;
}

wstring GetDLLName(HINSTANCE inst)
{
	//get dll path
	wchar[MAX_PATH+1] dllPath;
	DWORD dwLen = GetModuleFileNameW(inst, dllPath.ptr, MAX_PATH);
	if (dwLen == 0)
		throw new RegistryException(HRESULT_FROM_WIN32(GetLastError()));
	if (dwLen == MAX_PATH)
		throw new RegistryException(HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER));

	return to_wstring(dllPath.ptr);
}

wstring GetTemplatePath(wstring instpath)
{
	string path = toUTF8(instpath);
	debug path = dirName(dirName(path)) ~ "\\visuald";
	path = path ~ "\\Templates";
	return toUTF16(path);
}

