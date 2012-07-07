// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2010-2012 by Rainer Schuetze, All Rights Reserved
//
// License for redistribution is given by the Artistic License 2.0
// see file LICENSE for further details

module visuald.getmsobj;

import visuald.register;
import visuald.hierutil;
import visuald.fileutil;
import visuald.windows;

import stdext.httpget;
import stdext.path;
import sdk.win32.winreg;

import std.path;
import std.conv;
import std.file;
import core.stdc.stdlib;

// for msobj80.dll
// http://download.microsoft.com/download/2/E/9/2E911956-F90F-4BFB-8231-E292A7B6F287/GRMSDK_EN_DVD.iso
// FL_msobj71_dll_1_60033_x86_ln.3643236F_FC70_11D3_A536_0090278A1BB8
// in vc_stdx86.cab 

// for msobj100.dll
//
// http://download.microsoft.com/download/1/E/5/1E5F1C0A-0D5B-426A-A603-1798B951DDAE/VS2010Express1.iso
// FL_msobj71_dll_1_60033_x86_ln.3643236F_FC70_11D3_A536_0090278A1BB8
// in vs_setup.cab
// in lxpvc.exe (msi)
// or
// http://download.microsoft.com/download/4/0/E/40EFE5F6-C7A5-48F7-8402-F3497FABF888/X16-42555VS2010ProTrial1.iso
// FL_msobj71_dll_1_60033_x86_ln.3643236F_FC70_11D3_A536_0090278A1BB8
// in cab14.cab

HRESULT VerifyMSObjectParser(wstring winstallDir)
{
	debug UtilMessageBox("VerifyMSObj(dir=" ~ to!string(winstallDir) ~ ")", MB_OK, "Visual D Installer");

	if(!winstallDir.length)
		return S_FALSE;
	string installDir = to!string(winstallDir);

	HRESULT checkMSObj(string ver, string url, ulong cab_start, ulong cab_length)
	{
		debug UtilMessageBox("checkMSObj(ver=" ~ ver ~ ")", MB_OK, "Visual D Installer");

		string mspdb = "mspdb" ~ ver ~ ".dll";
		string absmspdb = buildPath(installDir, mspdb);
		if(exists(absmspdb))
		{
			debug UtilMessageBox(absmspdb ~ " exists", MB_OK, "Visual D Installer");

			string msobj = "msobj" ~ ver ~ ".dll";
			string absmsobj = buildPath(installDir, msobj);
			if(exists(absmsobj))
				return S_OK;

			int res = UtilMessageBox("The file " ~ msobj ~ "\n"
									 "is missing in your Visual Studio installation.\n"
									 "Would you like to download it from the Windows 7 SDK?",
									 MB_YESNO, "Visual Studio Shell detected");
			if(res == IDYES)
			{
				string tmp_cab = buildPath(tempDir(), "vd_install_from_w7sdk.cab");
				for (;;)
				{
					try
					{
						auto length = httpget("download.microsoft.com", 80, url, tmp_cab, cab_start, cab_length);
						if(length != cab_length)
							throw new Exception("Unexpected file length");
					}
					catch(Exception e)
					{
						res = UtilMessageBox("Error while downloading:\n" ~ e.msg ~ "\n",
											 MB_ABORTRETRYIGNORE, "Visual D Installer");
						if(res == IDABORT)
							return E_ABORT;
						if(res == IDIGNORE)
							return S_OK;
					}
					break;
				}
				string srcfile = "FL_msobj71_dll_1_60033_x86_ln.3643236F_FC70_11D3_A536_0090278A1BB8";
				string cmd = "expand " ~ shortFilename(tmp_cab) ~ " -f:" ~ srcfile ~ " " ~ shortFilename(installDir);

				for(;;)
				{
					string logfile = tmp_cab ~ ".expand_log";
					//scope(exit) if (exists(logfile)) remove(logfile);
					std.file.write(logfile, cmd);
					if(system((cmd ~ " >> " ~ logfile ~ " 2>&1").ptr) != 0)
					{
						string output = readText(logfile);
						res = UtilMessageBox("Error while expanding:\n" ~ cmd ~ "\n" ~ output,
											 MB_ABORTRETRYIGNORE, "Visual D Installer");
						if(res == IDABORT)
							return E_ABORT;
						if(res == IDIGNORE)
							return S_OK;
					}
					break;
				}
				try
				{
					rename(buildPath(installDir, srcfile), absmsobj);
				}
				catch(Exception e)
				{
					UtilMessageBox("Error while renaming:\n" ~ e.msg, MB_OK, "Visual D Installer");
					return S_FALSE;
				}
			}
		}
		return S_OK;
	}

	HRESULT hr;
	hr = checkMSObj("80", "/download/2/E/9/2E911956-F90F-4BFB-8231-E292A7B6F287/GRMSDK_EN_DVD.iso",
					0x59b07000, 0x29524dc);
	if(hr == S_OK)
		hr = checkMSObj("100", "/download/4/0/E/40EFE5F6-C7A5-48F7-8402-F3497FABF888/X16-42555VS2010ProTrial1.iso",
						0x1b03000, 14_039_060);
	return hr;
}
