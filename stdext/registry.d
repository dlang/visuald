module stdext.registry;

import stdext.com;

import sdk.win32.winreg;
import sdk.port.base;

enum { SECURE_ACCESS = ~(WRITE_DAC | WRITE_OWNER | GENERIC_ALL | ACCESS_SYSTEM_SECURITY) }

/*---------------------------------------------------------
Registry helpers
-----------------------------------------------------------*/
HRESULT RegQueryValue(HKEY root, in wstring keyname, in wstring valuename, ref wstring value)
{
	HKEY key;
	HRESULT hr = hrRegOpenKeyEx(root, keyname, 0, KEY_READ, &key);
	if(FAILED(hr))
		return hr;
	scope(exit) RegCloseKey(key);

	wchar[260] buf;
	DWORD cnt = 260 * wchar.sizeof;
	wchar* szName = _toUTF16zw(valuename);
	DWORD type;
	hr = RegQueryValueExW(key, szName, null, &type, cast(ubyte*) buf.ptr, &cnt);
	if(hr == S_OK && cnt > 0)
		value = to_wstring(buf.ptr);
	if(hr != ERROR_MORE_DATA)
		return HRESULT_FROM_WIN32(hr);
	if (type != REG_SZ)
		return ERROR_DATATYPE_MISMATCH;

	scope wchar[] pbuf = new wchar[cnt/2 + 1];
	hr = RegQueryValueExW(key, szName, null, &type, cast(ubyte*) pbuf.ptr, &cnt);
	if(hr == S_OK)
		value = to_wstring(pbuf.ptr);
	return HRESULT_FROM_WIN32(hr);
}

HRESULT RegCreateValue(HKEY key, in wstring name, in wstring value)
{
	wstring szName = name ~ cast(wchar)0;
	wstring szValue = value ~ cast(wchar)0;
	DWORD dwDataSize = value is null ? 0 : cast(DWORD) (wchar.sizeof * (value.length+1));
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
	LONG lRetCode = RegSetValueExW(key, szName.ptr, 0, REG_BINARY, cast(ubyte*)data.ptr, cast(DWORD) data.length);
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
	if (!FAILED(hr))
	{
		LONG lRetCode = RegQueryInfoKeyW(key, null, null, null, &subKeys, &maxKeyLen, 
										 null, null, null, null, null, null);
		if (ERROR_SUCCESS != lRetCode)
		{
			hr = HRESULT_FROM_WIN32(lRetCode);
		}
		else if (subKeys > 0)
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
	}
fail:
	wstring szPath = path ~ cast(wchar)0;
	LONG lRetCode = RegDeleteKeyW(keyRoot, szPath.ptr);
	if (SUCCEEDED(hr) && (ERROR_SUCCESS != lRetCode))
		hr = HRESULT_FROM_WIN32(lRetCode);
	if (key) RegCloseKey(key);
	return hr;
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
