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
using System.Collections.Generic;
using System;
using System.Xaml;
using XamlTypes = Microsoft.Build.Framework.XamlTypes;
using System.IO;
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
        void GetDCompileOptions(IVsHierarchy proj, uint itemid, out string impPath, out string stringImpPath,
                                out string versionids, out string debugids, out uint flags);
        void GetDCommandLine(IVsHierarchy proj, uint itemid, out string cmdline);
    }

    [ComVisible(true), Guid(IID.VisualCHelper)]
    [ClassInterface(ClassInterfaceType.None)]
    public partial class VisualCHelper : IVisualCHelper
    {
        ///////////////////////////////////////////////////////////////////////
        static int ConfigureFlags(bool unittestOn, bool debugOn, bool x64, bool cov, bool doc, bool nobounds, bool gdc,
                                  int versionLevel, int debugLevel, bool noDeprecated, bool deprecateInfo,
                                  bool ldc, bool warnings, bool warnAsError)
        {
            return (unittestOn ? 1 : 0)
                | (debugOn ? 2 : 0)
                | (x64 ? 4 : 0)
                | (cov ? 8 : 0)
                | (doc ? 16 : 0)
                | (nobounds ? 32 : 0)
                | (gdc ? 64 : 0)
                | (noDeprecated ? 128 : 0)
                | (deprecateInfo ? 0x40000000 : 0)
                | ((versionLevel & 0xff) << 8)
                | ((debugLevel & 0xff) << 16)
                | (ldc ? 0x4000000 : 0)
                | (warnings ? 0x10000000 : 0)
                | (warnAsError ? 0x20000000 : 0);
        }


        public const uint _VSITEMID_ROOT = 4294967294;

        // throws COMException if not found
        static void GetVCToolProps(IVsHierarchy proj, uint itemid,
                                   out VCFileConfiguration fcfg,
                                   out VCConfiguration cfg,
                                   out System.Reflection.IReflect vcrefl,
                                   out IVCRulePropertyStorage vcprop)
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
            var cfgmgr = envproj.ConfigurationManager;
            var activecfg = cfgmgr.ActiveConfiguration;
            var activename = activecfg.ConfigurationName + "|" + activecfg.PlatformName;

            fcfg = null;
            cfg = null;
            var vcfile = envitem != null ? envitem.Object as Microsoft.VisualStudio.VCProjectEngine.VCFile : null;
            if (vcfile != null)
            {
                var vcfconfigs = vcfile.FileConfigurations as IVCCollection;
                for (int c = 1; c <= vcfconfigs.Count; c++)
                {
                    var vcfcfg = vcfconfigs.Item(c);
                    fcfg = vcfcfg as Microsoft.VisualStudio.VCProjectEngine.VCFileConfiguration;
                    if (fcfg.Name == activename)
                        break;
                    else
                        fcfg = null;
                }
                if (fcfg == null)
                    throw new COMException();

                var vcftool = fcfg.Tool; // as Microsoft.VisualStudio.Project.VisualC.VCProjectEngine.VCToolBase;
                vcprop = vcftool as Microsoft.VisualStudio.VCProjectEngine.IVCRulePropertyStorage;
                if (vcftool != null && vcprop != null && vcfile.ItemType == "DCompile")
                {
                    vcrefl = vcftool as System.Reflection.IReflect;
                    if (vcrefl != null)
                        return;
                }
            }

            var vcproj = envproj.Object as Microsoft.VisualStudio.VCProjectEngine.VCProject; // Project.VisualC.VCProjectEngine.VCProjectShim;
            if (vcproj == null)
                throw new COMException();

            var vcconfigs = vcproj.Configurations as IVCCollection;
            for (int c = 1; c <= vcconfigs.Count; c++)
            {
                var vccfg = vcconfigs.Item(c);
                cfg = vccfg as Microsoft.VisualStudio.VCProjectEngine.VCConfiguration;
                if (cfg.Name == activename)
                    break;
                else
                    cfg = null;
            }
            if (cfg == null)
                throw new COMException();

            var tools = cfg.FileTools as IVCCollection;
            for (int f = 1; f <= tools.Count; f++)
            {
                var vctool = tools.Item(f);
                vcrefl = vctool as System.Reflection.IReflect;
                var prop = vctool as Microsoft.VisualStudio.VCProjectEngine.IVCRulePropertyStorage;
                if (prop != null)
                {
                    // read C# property dynamically to avoid dependency on Microsoft.VisualStudio.Project.VisualC.VCProjectEngine
                    var type = vctool.GetType();
                    var itprop = type.GetProperty("ItemType");
                    if (itprop != null)
                    {
                        object val = itprop.GetValue(vctool);
                        if (val != null && val.Equals("DCompile"))
                        {
                            vcprop = prop;
                            return;
                        }
                    }
                }
            }
            throw new COMException();
        }

        public delegate string EvalFun(string value);

        public void GetDCommandLine(IVsHierarchy proj, uint itemid, out string cmdline)
        {
            Microsoft.VisualStudio.VCProjectEngine.VCFileConfiguration fcfg;
            Microsoft.VisualStudio.VCProjectEngine.VCConfiguration cfg;
            System.Reflection.IReflect vcrefl;
            Microsoft.VisualStudio.VCProjectEngine.IVCRulePropertyStorage vcprop;
            GetVCToolProps(proj, itemid, out fcfg, out cfg, out vcrefl, out vcprop);

            EvalFun eval = (string s) => { return fcfg != null ? fcfg.Evaluate(s) : cfg.Evaluate(s); };

            string compiler = eval("$(DCompiler)");
            bool ldc = compiler == "LDC";

            string assemblyFolder = System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
            string xmlFileName = System.IO.Path.Combine(assemblyFolder, compiler + ".xml");

            var cd = new dbuild.CompileDOpt();
            cd.Compiler = compiler;
            cd.ToolExe = eval(ldc ? "$(LDCBinDir)ldmd2.exe" : "$(DMDBinDir)dmd.exe");
            cd.AdditionalOptions = vcprop.GetEvaluatedPropertyValue("AdditionalOptions");
            var strOptions = getParametersFromFakeProperties(vcprop, vcrefl.GetProperties(0));
            var parameters = parseParameters(xmlFileName, strOptions);
            cmdline = cd.ToolExe + " " + cd.GenCmdLine(parameters);
        }

        public void GetDCompileOptions(IVsHierarchy proj, uint itemid,
                                out string impPath, out string stringImpPath,
                                out string versionids, out string debugids, out uint flags)
        {
            Microsoft.VisualStudio.VCProjectEngine.VCFileConfiguration fcfg;
            Microsoft.VisualStudio.VCProjectEngine.VCConfiguration cfg;
            System.Reflection.IReflect vcrefl;
            Microsoft.VisualStudio.VCProjectEngine.IVCRulePropertyStorage vcprop;
            GetVCToolProps(proj, itemid, out fcfg, out cfg, out vcrefl, out vcprop);

            EvalFun eval = (string s) => { return fcfg != null ? fcfg.Evaluate(s) : cfg.Evaluate(s); };

            string platform = eval("$(PlatformName)");
            string compiler = eval("$(DCompiler)");
            bool ldc = compiler == "LDC";

            impPath = vcprop.GetEvaluatedPropertyValue("ImportPaths");
            stringImpPath = vcprop.GetEvaluatedPropertyValue("StringImportPaths");
            versionids = vcprop.GetEvaluatedPropertyValue("VersionIdentifiers");
            debugids = vcprop.GetEvaluatedPropertyValue("DebugIdentifiers");

            bool unittestOn = vcprop.GetEvaluatedPropertyValue("Unittest") == "true";
            bool debugOn = vcprop.GetEvaluatedPropertyValue("DebugCode") == "Debug";
            bool x64 = platform == "x64";
            bool cov = vcprop.GetEvaluatedPropertyValue("Coverage") == "true";
            bool doc = vcprop.GetEvaluatedPropertyValue("DocDir") != "" || vcprop.GetEvaluatedPropertyValue("DocFile") != "";
            bool nobounds = vcprop.GetEvaluatedPropertyValue("BoundsCheck") == "On";
            bool noDeprecated = vcprop.GetEvaluatedPropertyValue("Deprecations") != "Allow";
            bool deprecatedInfo = vcprop.GetEvaluatedPropertyValue("Deprecations") == "Info";
            bool warnings = vcprop.GetEvaluatedPropertyValue("Warnings") != "None";
            bool warnAsError = vcprop.GetEvaluatedPropertyValue("Warnings") == "Error";
            bool gdc = false;
            int versionLevel = 0;
            int debugLevel = 0;
            flags = (uint)ConfigureFlags(unittestOn, debugOn, x64, cov, doc, nobounds, gdc,
                                         versionLevel, debugLevel, noDeprecated, deprecatedInfo,
                                         ldc, warnings, warnAsError);
        }


        private static Dictionary<string, string> getParametersFromFakeProperties(IVCRulePropertyStorage vcfprop,
                                                                                  System.Reflection.PropertyInfo[] props)
        {
            var parameters = new Dictionary<string, string>();
            foreach(var p in props)
            {
                var val = vcfprop.GetEvaluatedPropertyValue(p.Name);
                if (!string.IsNullOrEmpty(val))
                    parameters[p.Name] = val;
            }
            return parameters;
        }

        private static Dictionary<string, object> parseParameters(XamlTypes.Rule rule,
                                                                  Dictionary<string, string> strOptions)
        {
            Dictionary<string, object> parameterValues = new Dictionary<string, object>();

            foreach (XamlTypes.BaseProperty property in rule.Properties)
            {
                string val;
                if (strOptions.TryGetValue(property.Name, out val))
                {
                    XamlTypes.BoolProperty boolProperty = property as XamlTypes.BoolProperty;
                    XamlTypes.DynamicEnumProperty dynamicEnumProperty = property as XamlTypes.DynamicEnumProperty;
                    XamlTypes.EnumProperty enumProperty = property as XamlTypes.EnumProperty;
                    XamlTypes.IntProperty intProperty = property as XamlTypes.IntProperty;
                    XamlTypes.StringProperty stringProperty = property as XamlTypes.StringProperty;
                    XamlTypes.StringListProperty stringListProperty = property as XamlTypes.StringListProperty;

                    if (stringListProperty != null)
                    {
                        string[] values = val.Split(';');
                        parameterValues[property.Name] = values;
                    }
                    else if (boolProperty != null)
                    {
                        parameterValues[property.Name] = string.Compare(val, "true", StringComparison.OrdinalIgnoreCase) == 0;
                    }
                    else if (intProperty != null)
                    {
                        parameterValues[property.Name] = Int32.Parse(val);
                    }
                    else
                        parameterValues[property.Name] = val;
                }
            }
            return parameterValues;
        }

        Dictionary<string, object> cacheXaml = new Dictionary<string, object>();

        private Dictionary<string, object> parseParameters(string xaml, Dictionary<string, string> strOptions)
        {
            object rootObject;
            if (!cacheXaml.TryGetValue(xaml, out rootObject))
            {
                rootObject = XamlServices.Load(new StreamReader(xaml));
                cacheXaml.Add(xaml, rootObject);
            }
            XamlTypes.ProjectSchemaDefinitions schemas = rootObject as XamlTypes.ProjectSchemaDefinitions;
            if (schemas != null)
            {
                foreach (XamlTypes.IProjectSchemaNode node in schemas.Nodes)
                {
                    XamlTypes.Rule rule = node as XamlTypes.Rule;
                    if (rule != null)
                    {
                        return parseParameters(rule, strOptions);
                    }
                }
            }
            return null;
        }

    }
}
