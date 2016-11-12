// This file is part of Visual D
//
// Visual D integrates the D programming language into Visual Studio
// Copyright (c) 2016 by Rainer Schuetze, All Rights Reserved
//
// Distributed under the Boost Software License, Version 1.0.
// See accompanying file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt

using System.Runtime.InteropServices; // DllImport

using Microsoft.VisualStudio.Shell.Interop;
using Microsoft.VisualStudio.VCProjectEngine;
//using Microsoft.VisualStudio.Project.VisualC.VCProjectEngine.VCCustomBuildRuleShim;

namespace vdextensions
{
    public class IID
    {
        public const string IVisualCHelper = "002a2de9-8bb6-484d-9911-7e4ad4084715";
        public const string VisualCHelper = "002a2de9-8bb6-484d-AA11-7e4ad4084715";
    }

    [ComVisible(true), Guid(IID.IVisualCHelper)]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IVisualCHelper
    {
        void GetDCompileOptions(IVsHierarchy proj, uint itemid, out string cmd, out string impPath, out string stringImpPath,
                                out string versionids, out string debugids, out uint flags);
    }

    [ComVisible(true), Guid(IID.VisualCHelper)]
    [ClassInterface(ClassInterfaceType.None)]
    public partial class VisualCHelper : IVisualCHelper
    {
        ///////////////////////////////////////////////////////////////////////
        static int ConfigureFlags(bool unittestOn, bool debugOn, bool x64, bool cov, bool doc, bool nobounds, bool gdc,
                                  int versionLevel, int debugLevel, bool noDeprecated, bool ldc)
        {
            return (unittestOn ? 1 : 0)
                | (debugOn ? 2 : 0)
                | (x64 ? 4 : 0)
                | (cov ? 8 : 0)
                | (doc ? 16 : 0)
                | (nobounds ? 32 : 0)
                | (gdc ? 64 : 0)
                | (noDeprecated ? 128 : 0)
                | ((versionLevel & 0xff) << 8)
                | ((debugLevel & 0xff) << 16)
                | (ldc ? 0x4000000 : 0);
        }


        public const uint _VSITEMID_ROOT = 4294967294;

        public void GetDCompileOptions(IVsHierarchy proj, uint itemid,
                                       out string cmdline, out string impPath, out string stringImpPath,
                                       out string versionids, out string debugids, out uint flags)
        {
            object ext;
            if (proj.GetProperty(itemid, (int)__VSHPROPID.VSHPROPID_ExtObject, out ext) != 0)
                throw new COMException();

            object projext;
            if (proj.GetProperty(_VSITEMID_ROOT, (int)__VSHPROPID.VSHPROPID_ExtObject, out projext) != 0)
                throw new COMException();

            var envproj = projext as EnvDTE.Project;
            if (envproj == null)
                throw new COMException();

            var envitem = ext as EnvDTE.ProjectItem;
            if (envitem == null)
                throw new COMException();

            var cfgmgr = envproj.ConfigurationManager;
            var activecfg = cfgmgr.ActiveConfiguration;
            var name = activecfg.ConfigurationName + "|" + activecfg.PlatformName;

            var vcfile = envitem.Object as Microsoft.VisualStudio.VCProjectEngine.VCFile;
            if (vcfile != null)
            {
                //var vcpfile = envitem.Object as Microsoft.VisualStudio.Project.VisualC.VCProjectEngine.VCProjectFileShim;
                //var envproj = envitem.ContainingProject as EnvDTE.Project;
                //if (envproj == null)
                //    throw new COMException();

                Microsoft.VisualStudio.VCProjectEngine.VCFileConfiguration fcfg = null;
                var vcfconfigs = vcfile.FileConfigurations as IVCCollection;
                for (int c = 1; c <= vcfconfigs.Count; c++)
                {
                    var vcfcfg = vcfconfigs.Item(c);
                    fcfg = vcfcfg as Microsoft.VisualStudio.VCProjectEngine.VCFileConfiguration;
                    if (fcfg.Name == name)
                        break;
                    else
                        fcfg = null;
                }
                if (fcfg == null)
                    throw new COMException();

                var vcftool = fcfg.Tool as Microsoft.VisualStudio.Project.VisualC.VCProjectEngine.VCToolBase;
                var vcfprop = vcftool as Microsoft.VisualStudio.VCProjectEngine.IVCRulePropertyStorage;
                if (vcftool != null && vcfprop != null && vcftool.ItemType == "DCompile")
                {
                    bool fldc = fcfg.Evaluate("$(DCompiler)") == "LDC";
                    string foutdir = fcfg.Evaluate("$(OutDir)");
                    string fintdir = fcfg.Evaluate("$(IntDir)");

                    var style = Microsoft.VisualStudio.Project.VisualC.VCProjectEngine.CommandLineOptionStyle.cmdLineForBuild;
                    cmdline = ""; // vcftool.GetCommandLineOptions(envitem, true, style);
                    //string compilerexe = vcfprop.GetEvaluatedPropertyValue("CompilerExe");
                    //cmdline = compilerexe + " " + cmdline;
                    impPath = vcfprop.GetEvaluatedPropertyValue("ImportPaths");
                    stringImpPath = vcfprop.GetEvaluatedPropertyValue("StringImportPaths");
                    versionids = vcfprop.GetEvaluatedPropertyValue("VersionIdentifiers");
                    debugids = vcfprop.GetEvaluatedPropertyValue("DebugIdentifiers");

                    bool unittestOn = vcfprop.GetEvaluatedPropertyValue("Unittest") == "true";
                    bool debugOn = vcfprop.GetEvaluatedPropertyValue("DebugCode") == "Debug";
                    bool x64 = activecfg.PlatformName == "x64";
                    bool cov = vcfprop.GetEvaluatedPropertyValue("Coverage") == "true";
                    bool doc = vcfprop.GetEvaluatedPropertyValue("DocDir") != "" || vcfprop.GetEvaluatedPropertyValue("DocFile") != "";
                    bool nobounds = vcfprop.GetEvaluatedPropertyValue("BoundsCheck") == "On";
                    bool noDeprecated = vcfprop.GetEvaluatedPropertyValue("Deprecations") == "Error";
                    bool gdc = false;
                    int versionLevel = 0;
                    int debugLevel = 0;
                    flags = (uint)ConfigureFlags(unittestOn, debugOn, x64, cov, doc, nobounds, gdc,
                                                 versionLevel, debugLevel, noDeprecated, fldc);
                    return;
                }
            }

            var vcproj = envproj.Object as Microsoft.VisualStudio.VCProjectEngine.VCProject; // Project.VisualC.VCProjectEngine.VCProjectShim;
            if (vcproj == null)
                throw new COMException();
           
            Microsoft.VisualStudio.VCProjectEngine.VCConfiguration cfg = null;
            var vcconfigs = vcproj.Configurations as IVCCollection;
            for (int c = 1; c <= vcconfigs.Count; c++)
            {
                var vccfg = vcconfigs.Item(c);
                cfg = vccfg as Microsoft.VisualStudio.VCProjectEngine.VCConfiguration;
                if (cfg.Name == name)
                    break;
                else
                    cfg = null;
            }
            if (cfg == null)
                throw new COMException();

            bool ldc = false;
            string outdir;
            string intdir;
            var tools = cfg.FileTools as IVCCollection;
            for (int f = 1; f <= tools.Count; f++)
            {
                var obj = tools.Item(f);
                var vctool = obj as Microsoft.VisualStudio.Project.VisualC.VCProjectEngine.VCToolBase;
                if (vctool != null && vctool.ItemType == "ConfigurationGeneral")
                {
                    var vcprop = vctool as Microsoft.VisualStudio.VCProjectEngine.IVCRulePropertyStorage;
                    if (vcprop != null)
                    {
                        try
                        {
                            ldc = vcprop.GetEvaluatedPropertyValue("DCompiler") == "LDC";
                            outdir = vcprop.GetEvaluatedPropertyValue("OutDir");
                            intdir = vcprop.GetEvaluatedPropertyValue("IntDir");
                        }
                        catch
                        {
                        }
                    }
                }
                if (vctool != null && vctool.ItemType == "DCompile")
                {
                    var vcprop = vctool as Microsoft.VisualStudio.VCProjectEngine.IVCRulePropertyStorage;
                    if (vcprop != null)
                    {
                        var style = Microsoft.VisualStudio.Project.VisualC.VCProjectEngine.CommandLineOptionStyle.cmdLineForBuild;
                        cmdline = ""; // vctool.GetCommandLineOptions(envitem.Object, true, style);
                        string outfile;
                        var rc = vctool.GetPrimaryOutputFromTool(envitem, false, out outfile);
                        string compilerexe = vcprop.GetEvaluatedPropertyValue("CompilerExe");
                        cmdline = compilerexe + " " + cmdline;
                        impPath = vcprop.GetEvaluatedPropertyValue("ImportPaths");
                        stringImpPath = vcprop.GetEvaluatedPropertyValue("StringImportPaths");
                        versionids = vcprop.GetEvaluatedPropertyValue("VersionIdentifiers");
                        debugids = vcprop.GetEvaluatedPropertyValue("DebugIdentifiers");

                        bool unittestOn = vcprop.GetEvaluatedPropertyValue("Unittest") == "true";
                        bool debugOn = vcprop.GetEvaluatedPropertyValue("DebugCode") == "Debug";
                        bool x64 = activecfg.PlatformName == "x64";
                        bool cov = vcprop.GetEvaluatedPropertyValue("Coverage") == "true";
                        bool doc = vcprop.GetEvaluatedPropertyValue("DocDir") != "" || vcprop.GetEvaluatedPropertyValue("DocFile") != "";
                        bool nobounds = vcprop.GetEvaluatedPropertyValue("BoundsCheck") == "On";
                        bool noDeprecated = vcprop.GetEvaluatedPropertyValue("Deprecations") == "Error";
                        bool gdc = false;
                        int versionLevel = 0;
                        int debugLevel = 0;
                        flags = (uint)ConfigureFlags(unittestOn, debugOn, x64, cov, doc, nobounds, gdc,
                                                     versionLevel, debugLevel, noDeprecated, ldc);

                        return;
                    }
                }
                //var cltool = obj as VCCLCompilerTool;
                //var vcrule = obj as Microsoft.VisualStudio.Project.VisualC.VCProjectEngine.VCCustomBuildRuleShim;
                //var vcbtool = obj as VCCustomBuildTool;
                //                    var tool = obj as IVCToolImpl;
                //                    var custom = obj as IVCCustomBuildRuleProperties;
                // n = obj.ToolsName;
            }
            throw new COMException();
        }

    }
}
