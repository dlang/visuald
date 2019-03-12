using System;
using System.Collections.Generic;
using Microsoft.Build.Framework;
using Microsoft.Build.CPPTasks;
using System.Collections;
using System.Resources;
using System.Reflection;
using System.Text;

namespace dbuild
{
    public class CompileD : TrackedVCToolTask
    {
        public CompileD()
        : base(new ResourceManager("dbuild.Strings", Assembly.GetExecutingAssembly()))
        {
            MinimalRebuildFromTracking = true;

            this.switchOrderList.Add("DoNotLink");
            this.switchOrderList.Add("CodeGeneration");

            this.switchOrderList.Add("ImportPaths");
            this.switchOrderList.Add("StringImportPaths");
            this.switchOrderList.Add("VersionIdentifiers");
            this.switchOrderList.Add("DebugIdentifiers");
            this.switchOrderList.Add("ObjectFileName");
            this.switchOrderList.Add("PreserveSourcePath");
            this.switchOrderList.Add("CRuntimeLibrary");

            this.switchOrderList.Add("Profile");
            this.switchOrderList.Add("ProfileGC");
            this.switchOrderList.Add("Coverage");
            this.switchOrderList.Add("MinCoverage");
            this.switchOrderList.Add("Unittest");
            this.switchOrderList.Add("Optimizer");
            this.switchOrderList.Add("Inliner");
            this.switchOrderList.Add("StackFrame");
            this.switchOrderList.Add("StackStomp");
            this.switchOrderList.Add("AllInst");
            this.switchOrderList.Add("Main");
            this.switchOrderList.Add("DebugCode");
            this.switchOrderList.Add("DebugInfo");
            this.switchOrderList.Add("DebugFull");
            this.switchOrderList.Add("DebugMixin");
            this.switchOrderList.Add("BoundsCheck");
            this.switchOrderList.Add("CPUArchitecture");
            this.switchOrderList.Add("PerformSyntaxCheckOnly");

            this.switchOrderList.Add("BetterC");
            this.switchOrderList.Add("DIP25");
            this.switchOrderList.Add("DIP1000");
            this.switchOrderList.Add("DIP1008");
            this.switchOrderList.Add("RevertImport");
            this.switchOrderList.Add("PreviewDtorFields");
            this.switchOrderList.Add("PreviewIntPromote");
            this.switchOrderList.Add("PreviewFixAliasThis");
            this.switchOrderList.Add("PreviewMarkdown");
            this.switchOrderList.Add("TransitionVMarkdown");
            this.switchOrderList.Add("TransitionField");
            this.switchOrderList.Add("TransitionCheckImports");
            this.switchOrderList.Add("TransitionComplex");

            this.switchOrderList.Add("Warnings");
            this.switchOrderList.Add("Deprecations");
            this.switchOrderList.Add("Verbose");
            this.switchOrderList.Add("ShowTLS");
            this.switchOrderList.Add("ShowGC");
            this.switchOrderList.Add("IgnorePragma");
            this.switchOrderList.Add("ShowDependencies");

            this.switchOrderList.Add("DocDir");
            this.switchOrderList.Add("DocFile");
            this.switchOrderList.Add("DepFile");
            this.switchOrderList.Add("HeaderDir");
            this.switchOrderList.Add("HeaderFile");
            this.switchOrderList.Add("JSONFile");

            this.switchOrderList.Add("AdditionalOptions");

            this.switchOrderList.Add("Sources");
        }

        private ArrayList switchOrderList = new ArrayList();
        private string _compiler = "dmd";

        public string Compiler
        {
            get { return _compiler; }
            set { _compiler = value; }
        }

        protected override string ToolName
        {
            get { return _compiler + ".exe"; }
        }

        [Required]
        public virtual ITaskItem[] Sources
        {
            get
            {
                if (base.IsPropertySet("Sources"))
                {
                    return base.ActiveToolSwitches["Sources"].TaskItemArray;
                }
                return null;
            }
            set
            {
                base.ActiveToolSwitches.Remove("Sources");
                ToolSwitch toolSwitch = new ToolSwitch(ToolSwitchType.ITaskItemArray);
                toolSwitch.Separator = " ";
                toolSwitch.Required = true;
                toolSwitch.ArgumentRelationList = new ArrayList();
                toolSwitch.TaskItemArray = value;
                base.ActiveToolSwitches.Add("Sources", toolSwitch);
                base.AddActiveSwitchToolValue(toolSwitch);
            }
        }

        // Hidden
        public bool DoNotLink
        {
            get { return GetBoolProperty("DoNotLink"); }
            set
            {
                SetBoolProperty("DoNotLink", "Do Not Link",
                                "Compile only. Do not link (-c)",
                                "-c", value);
            }
        }

        public string CodeGeneration
        {
            get { return GetStringProperty("CodeGeneration"); }
            set
            {
                string[][] switchMap = new string[3][]
                {
                    new string[2] { "32BitsMS-COFF", "-m32mscoff" },
                    new string[2] { "32Bits", "-m32" },
                    new string[2] { "64Bits", "-m64" }
                };

                SetEnumProperty("CodeGeneration", "Code Generation",
                                "Generate 32 or 64 bit code.",
                                switchMap, value);
            }
        }

        // General
        public string[] ImportPaths
        {
            get { return GetStringArray("ImportPaths"); }
            set
            {
                SetStringArray("ImportPaths", GetToolSwitchTypeForStringPathArray(), "Import Paths",
                               "Where to look for imports. (-I[path]).", "-I", value);
            }
        }

        public string[] StringImportPaths
        {
            get { return GetStringArray("StringImportPaths"); }
            set
            {
                SetStringArray("StringImportPaths", GetToolSwitchTypeForStringPathArray(), "String Import Paths",
                               "Where to look for string imports. (-J[path]).", "-J", value);
            }
        }

        public string[] VersionIdentifiers
        {
            get { return GetStringArray("VersionIdentifiers"); }
            set
            {
                SetStringArray("VersionIdentifiers", ToolSwitchType.StringArray, "Version Identifiers",
                               "Compile in version code identified by ident/&gt;= level.", "-version=", value);
            }
        }

        public string[] DebugIdentifiers
        {
            get { return GetStringArray("DebugIdentifiers"); }
            set
            {
                SetStringArray("DebugIdentifiers", ToolSwitchType.StringArray, "Debug Identifiers",
                               "Compile in debug code identified by ident/&lt;= level.", "-debug=", value);
            }
        }

        public string ObjectFileName
        {
            get { return GetStringProperty("ObjectFileName"); }
            set
            {
                SetFileProperty("ObjectFileName", "Object File Name",
                    "Specifies the name of the output object file. Leave empty to auto generate a name according to the compilation model. Use [PackageName] to add the folder name with special characters replaced.",
                    "-of", value);
            }
        }

        public bool PreserveSourcePath
        {
            get { return GetBoolProperty("PreserveSourcePath"); }
            set
            {
                SetBoolProperty("PreserveSourcePath", "Preserve source path",
                                "Preserve source path for output files. (-op)",
                                "-op", value);
            }
        }
 
        public string CRuntimeLibrary
        {
            get { return GetStringProperty("CRuntimeLibrary"); }
            set
            {
                string[][] switchMap = new string[5][]
                {
                    new string[2] { "None", "-mscrtlib=" },
                    new string[2] { "MultiThreaded", "" },
                    new string[2] { "MultiThreadedDebug", "-mscrtlib=libcmtd" },
                    new string[2] { "MultiThreadedDll", "-mscrtlib=msvcrt" },
                    new string[2] { "MultiThreadedDebugDll", "-mscrtlib=msvcrtd" }
                };

                SetEnumProperty("CRuntimeLibrary", "C Runtime Library",
                                "Link against the static/dynamic debug/release C runtime library.",
                                switchMap, value);
            }
        }

        // Code generation
        public bool Profile
        {
            get { return GetBoolProperty("Profile"); }
            set
            {
                SetBoolProperty("Profile", "Enable Profiling",
                                "Profile runtime performance of generated code. (-profile)",
                                "-profile", value);
            }
        }

        public bool ProfileGC
        {
            get { return GetBoolProperty("ProfileGC"); }
            set
            {
                SetBoolProperty("ProfileGC", "Enable GC Profiling",
                                "Profile runtime allocations. (-profile=gc)",
                                "-profile=gc", value);
            }
        }

        public bool Coverage
        {
            get { return GetBoolProperty("Coverage"); }
            set
            {
                SetBoolProperty("Coverage", "Enable Code Coverage",
                                "Do code coverage analysis. (-cov)",
                                "-cov", value);
            }
        }

        public int MinCoverage
        {
            get
            {
                if (base.IsPropertySet("MinCoverage"))
                {
                    return base.ActiveToolSwitches["MinCoverage"].Number;
                }
                return 0;

            }
            set
            {
                base.ActiveToolSwitches.Remove("MinCoverage");
                ToolSwitch toolSwitch = new ToolSwitch(ToolSwitchType.Integer);
                toolSwitch.DisplayName = "Minimum Code Coverage";
                toolSwitch.Description = "Require at least nnn% code coverage. (-cov=nnn)";
                toolSwitch.ArgumentRelationList = new ArrayList();
                if (base.ValidateInteger("MinCoverage", 0, 100, value))
                {
                    toolSwitch.IsValid = true;
                }
                else
                {
                    toolSwitch.IsValid = false;
                }

                toolSwitch.SwitchValue = "-cov=";
                toolSwitch.Name = "MinCoverage";
                toolSwitch.Number = value;
                base.ActiveToolSwitches.Add("MinCoverage", toolSwitch);
                base.AddActiveSwitchToolValue(toolSwitch);
            }
        }

        public bool Unittest
        {
            get { return GetBoolProperty("Unittest"); }
            set
            {
                SetBoolProperty("Unittest", "Enable Unittests",
                                "Compile in unit tests (-unittest)",
                                "-unittest", value);
            }
        }

        public bool Optimizer
        {
            get { return GetBoolProperty("Optimizer"); }
            set
            {
                SetBoolProperty("Optimizer", "Optimizations",
                                "run optimizer (-O)",
                                "-O", value);
            }
        }

        public bool Inliner
        {
            get { return GetBoolProperty("Inliner"); }
            set
            {
                SetBoolProperty("Inliner", "Inlining",
                                "Do function inlining (-inline)",
                                "-inline", value);
            }
        }

        public bool StackFrame
        {
            get { return GetBoolProperty("StackFrame"); }
            set
            {
                SetBoolProperty("StackFrame", "Stack Frames",
                                "Always emit stack frame (-gs)",
                                "-gs", value);
            }
        }

        public bool StackStomp
        {
            get { return GetBoolProperty("StackStomp"); }
            set
            {
                SetBoolProperty("StackStomp", "Stack Stomp",
                                "Add stack stomp code (-gx)",
                                "-gx", value);
            }
        }

        public bool AllInst
        {
            get { return GetBoolProperty("AllInst"); }
            set
            {
                SetBoolProperty("AllInst", "All Template Instantiations",
                                "Generate code for all template instantiations (-allinst)",
                                "-allinst", value);
            }
        }

        public bool BetterC
        {
            get { return GetBoolProperty("BetterC"); }
            set
            {
                SetBoolProperty("BetterC", "Better C",
                                "Omit generating some runtime information and helper functions (-betterC)",
                                "-betterC", value);
            }
        }

        public bool Main
        {
            get { return GetBoolProperty("Main"); }
            set
            {
                SetBoolProperty("Main", "Add Main",
                                "Add default main() (e.g. for unittesting) (-main)",
                                "-main", value);
            }
        }

        public string DebugCode
        {
            get { return GetStringProperty("DebugCode"); }
            set
            {
                string[][] switchMap = new string[3][]
                {
                    new string[2] { "Default", "" },
                    new string[2] { "Debug", "-debug" },
                    new string[2] { "Release", "-release" }
                };

                SetEnumProperty("DebugCode", "Debug Code",
                                "Compile in debug code. (-debug, -release)",
                                switchMap, value);
            }
        }

        public string DebugInfo
        {
            get { return GetStringProperty("DebugInfo"); }
            set
            {
                string[][] switchMap = new string[3][]
                {
                    new string[2] { "None", "" },
                    new string[2] { "VS", "-gc" },
                    new string[2] { "Mago", "-g" }
                };

                SetEnumProperty("DebugInfo", "Debug Info",
                                "Generate debug information. (-gc, -g)",
                                switchMap, value);
            }
        }

        public bool DebugFull
        {
            get { return GetBoolProperty("DebugFull"); }
            set
            {
                SetBoolProperty("DebugFull", "Full Debug Info",
                                "Emit debug info for all referenced types (-gf)",
                                "-gf", value);
            }
        }

		public string DebugMixin
		{
			get { return GetStringProperty("DebugMixin"); }
			set
			{
				SetFileProperty("DebugMixin", "Debug Mixin File",
								"Expand and save mixins to specified file. (-mixin=[file])",
								"-mixin=", value);
			}
		}

		public string CPUArchitecture
		{
			get { return GetStringProperty("CPUArchitecture"); }
			set
			{
				string[][] switchMap = new string[4][]
				{
					new string[2] { "baseline", "" },
					new string[2] { "avx", "-mcpu=avx" },
					new string[2] { "avx2", "-mcpu=avx2" },
					new string[2] { "native", "-mcpu=native" }
				};

				SetEnumProperty("CPUArchitecture", "CPU Architecture",
								"generate instructions for architecture. (-mcpu=)",
								switchMap, value);
			}
		}

		public string BoundsCheck
        {
            get { return GetStringProperty("BoundsCheck"); }
            set
            {
                string[][] switchMap = new string[3][]
                {
                    new string[2] { "Off", "-boundscheck=off" },
                    new string[2] { "SafeOnly", "-boundscheck=safeonly" },
                    new string[2] { "On", "-boundscheck=on" }
                };

                SetEnumProperty("BoundsCheck", "Bounds Checking",
                                "Enable array bounds checking. (-boundscheck=off/safeonly/on)",
                                switchMap, value);
            }
        }

        public bool PerformSyntaxCheckOnly
        {
            get { return GetBoolProperty("PerformSyntaxCheckOnly"); }
            set
            {
                SetBoolProperty("PerformSyntaxCheckOnly", "Perform Syntax Check Only",
                                "Performs a syntax check only (-o-)",
                                "-o-", value);
            }
        }

        // Language
        public bool DIP25
        {
            get { return GetBoolProperty("DIP25"); }
            set
            {
                SetBoolProperty("DIP25", "DIP25",
                                "implement DIP25: sealed pointers (-dip25)",
                                "-dip25", value);
            }
        }

        public bool DIP1000
        {
            get { return GetBoolProperty("DIP1000"); }
            set
            {
                SetBoolProperty("DIP1000", "DIP1000",
                                "implement DIP1000: scoped pointers (-dip1000)",
                                "-dip1000", value);
            }
        }

        public bool DIP1008
        {
            get { return GetBoolProperty("DIP1008"); }
            set
            {
                SetBoolProperty("DIP1008", "DIP1008",
                                "implement DIP1008: reference counted exceptions (-dip1008)",
                                "-dip1008", value);
            }
        }

        public bool RevertImport
        {
            get { return GetBoolProperty("RevertImport"); }
            set
            {
                SetBoolProperty("RevertImport", "Revert import",
								"revert to single phase name lookup (-revert=import)",
                                "-revert=import", value);
            }
        }

        public bool PreviewDtorFields
		{
            get { return GetBoolProperty("PreviewDtorFields"); }
            set
            {
                SetBoolProperty("PreviewDtorFields", "Preview dtorfields",
								"destruct fields of partially constructed objects (-preview=dtorfields)",
                                "-preview=dtorfields", value);
            }
        }

        public bool PreviewIntPromote
        {
            get { return GetBoolProperty("PreviewIntPromote"); }
            set
            {
                SetBoolProperty("PreviewIntPromote", "Preview intpromote",
								"fix integral promotions for unary + - ~ operators (-preview=intpromote)",
								"-preview=intpromote", value);
            }
        }

        public bool PreviewFixAliasThis
		{
            get { return GetBoolProperty("PreviewFixAliasThis"); }
            set
            {
                SetBoolProperty("PreviewFixAliasThis", "Preview fixAliasThis",
								"when a symbol is resolved, check alias this scope before upper scopes (-preview=fixAliasThis)",
								"-preview=fixAliasThis", value);
            }
        }

        public bool PreviewMarkdown
		{
            get { return GetBoolProperty("PreviewMarkdown"); }
            set
            {
                SetBoolProperty("PreviewMarkdown", "Enable Markdown",
								"Enable Markdown replacements in Ddoc (-preview=markdown)",
								"-preview=markdown", value);
            }
        }

        public bool TransitionVMarkdown
        {
            get { return GetBoolProperty("TransitionVMarkdown"); }
            set
            {
                SetBoolProperty("TransitionVMarkdown", "List Markdown Usage",
                                "List instances of Markdown replacements in Ddoc (-transition=vmarkdown)",
                                "-transition=vmarkdown", value);
            }
        }

        public bool TransitionField
        {
            get { return GetBoolProperty("TransitionField"); }
            set
            {
                SetBoolProperty("TransitionField", "List non-mutable fields",
                                "List all non-mutable fields which occupy an object instance (-transition=field)",
                                "-transition=field", value);
            }
        }

        public bool TransitionCheckImports
        {
            get { return GetBoolProperty("TransitionCheckImports"); }
            set
            {
                SetBoolProperty("TransitionCheckImports", "Show import anomalies",
                                "Give deprecation messages about import anomalies (-transition=checkimports)",
                                "-transition=checkimports", value);
            }
        }

        public bool TransitionComplex
        {
            get { return GetBoolProperty("TransitionComplex"); }
            set
            {
                SetBoolProperty("TransitionComplex", "Show usage of complex types",
                                "Give deprecation messages about all usages of complex or imaginary types (-transition=complex)",
                                "-transition=complex", value);
            }
        }

        // Messages
        public string Warnings
        {
            get { return GetStringProperty("Warnings"); }
            set
            {
                string[][] switchMap = new string[3][]
                {
                    new string[2] { "None", "" },
                    new string[2] { "Info", "-wi" },
                    new string[2] { "Error", "-w" }
                };

                SetEnumProperty("Warnings", "Warnings",
                                "Enable display of warnings. (-w, -wi)",
                                switchMap, value);
            }
        }

        public string Deprecations
        {
            get { return GetStringProperty("Deprecations"); }
            set
            {
                string[][] switchMap = new string[3][]
                {
                    new string[2] { "Info", "-dw" },
                    new string[2] { "Error", "-de" },
                    new string[2] { "Allow", "-d" }
                };

                SetEnumProperty("Deprecations", "Enable deprecated features",
                                "Enable display of deprecated features. (-dw, -de, -d)",
                                switchMap, value);
            }
        }

        public bool Verbose
        {
            get { return GetBoolProperty("Verbose"); }
            set
            {
                SetBoolProperty("Verbose", "Verbose",
                                "Print out what the compiler is currently doing (-v)",
                                "-v", value);
            }
        }

        public bool ShowTLS
        {
            get { return GetBoolProperty("ShowTLS"); }
            set
            {
                SetBoolProperty("ShowTLS", "Show TLS variables",
                                "List all variables going into thread local storage (-vtls)",
                                "-vtls", value);
            }
        }

        public bool ShowGC
        {
            get { return GetBoolProperty("ShowGC"); }
            set
            {
                SetBoolProperty("ShowGC", "Show GC allocations",
                                "List all gc allocations including hidden ones. (-vgc)",
                                "-vgc", value);
            }
        }

        public bool IgnorePragma
        {
            get { return GetBoolProperty("IgnorePragma"); }
            set
            {
                SetBoolProperty("IgnorePragma", "Ignore unsupported pragmas",
                                "Ignore unsupported pragmas. (-ignore)",
                                "-ignore", value);
            }
        }

        public bool ShowDependencies
        {
            get { return GetBoolProperty("ShowDependencies"); }
            set
            {
                SetBoolProperty("ShowDependencies", "Print module dependencies",
                                "Print module dependencies (imports/file/version/debug/lib). (-deps)",
                                "-deps", value);
            }
        }

        // Documentation
        public string DocDir
        {
            get { return GetStringProperty("DocDir"); }
            set
            {
                SetFileProperty("DocDir", "Documentation Directory",
                                "Write documentation file(s) to this directory. (-Dd[dir])",
                                "-Dd", value);
            }
        }

        public string DocFile
        {
            get { return GetStringProperty("DocFile"); }
            set
            {
                SetFileProperty("DocFile", "Documentation File",
                                "Write documentation to this file. (-Df[file])",
                                "-Df", value);
            }
        }

        public string DepFile
        {
            get { return GetStringProperty("DepFile"); }
            set
            {
                SetFileProperty("DepFile", "Dependencies File",
                                "Write module dependencies to filename (only imports). (-deps=[file])",
                                "-deps=", value);
            }
        }

        public string HeaderDir
        {
            get { return GetStringProperty("HeaderDir"); }
            set
            {
                SetFileProperty("HeaderDir", "Header Directory",
                                "Write 'header' file(s) to this directory. (-Hd[dir])",
                                "-Hd", value);
            }
        }

        public string HeaderFile
        {
            get { return GetStringProperty("HeaderFile"); }
            set
            {
                SetFileProperty("HeaderFile", "Header File",
                                "Write 'header' to this file. (-Hf[file])",
                                "-Hf", value);
            }
        }

        public string JSONFile
        {
            get { return GetStringProperty("JSONFile"); }
            set
            {
                SetFileProperty("JSONFile", "JSON Browse File",
                                "Write browse information to this JSON file. (-Xf[file])",
                                "-Xf", value);
            }
        }

        // Other properties
        public bool ShowCommandLine
        {
            get;
            set;
        }

        public string PackageName
        {
            get;
            set;
        }

        public string TrackerLogDirectory
        {
            get;
            set;
        }

        [Output]
        public string PackageNameOut
        {
            get { return PackageName; }
        }

        protected override ArrayList SwitchOrderList
        {
            get { return this.switchOrderList; }
        }

        private string TLogPrefix
        {
            get { return _compiler == "LDC" ? "ldmd2-ldc2" : "dmd"; }
        }

        protected override string[] ReadTLogNames
        {
            get { return new string[1] { TLogPrefix + ".read.1.tlog" }; }
        }

        protected override string[] WriteTLogNames
        {
            get { return new string[1] { TLogPrefix + ".write.1.tlog" }; }
        }

        protected override string CommandTLogName
        {
            get { return "dcompile.command.1.tlog"; }
        }

        protected override string TrackerIntermediateDirectory
        {
            get
            {
                if (this.TrackerLogDirectory != null)
                    return this.TrackerLogDirectory;
                return string.Empty;
            }
        }

        protected override bool MaintainCompositeRootingMarkers
        {
            get
            {
                return true;
            }
        }

        private bool GetBoolProperty(string name)
        {
            if (base.IsPropertySet(name))
            {
                return base.ActiveToolSwitches[name].BooleanValue;
            }
            return false;
        }

        private void SetBoolProperty(string name,
                                     string displayName,
                                     string description,
                                     string switchValue,
                                     bool value)
        {
            base.ActiveToolSwitches.Remove(name);
            ToolSwitch toolSwitch = new ToolSwitch(ToolSwitchType.Boolean);
            toolSwitch.DisplayName = displayName;
            toolSwitch.Description = description;
            toolSwitch.ArgumentRelationList = new ArrayList();
            toolSwitch.SwitchValue = switchValue;
            toolSwitch.Name = name;
            toolSwitch.BooleanValue = value;
            base.ActiveToolSwitches.Add(name, toolSwitch);
            base.AddActiveSwitchToolValue(toolSwitch);
        }

        private string GetStringProperty(string name)
        {
            if (base.IsPropertySet(name))
            {
                return base.ActiveToolSwitches[name].Value;
            }
            return null;
        }

        private void SetFileProperty(string name,
                                     string displayName,
                                     string description,
                                     string switchValue,
                                     string value)
        {
            base.ActiveToolSwitches.Remove(name);
            ToolSwitch toolSwitch = new ToolSwitch(ToolSwitchType.File);
            toolSwitch.DisplayName = displayName;
            toolSwitch.Description = description;
            toolSwitch.ArgumentRelationList = new ArrayList();
            toolSwitch.SwitchValue = switchValue;
            toolSwitch.Name = name;
            toolSwitch.Value = value;
            base.ActiveToolSwitches.Add(name, toolSwitch);
            base.AddActiveSwitchToolValue(toolSwitch);
        }

        private void SetDirectoryProperty(string name,
                                          string displayName,
                                          string description,
                                          string switchValue,
                                          string value)
        {
            base.ActiveToolSwitches.Remove(name);
            ToolSwitch toolSwitch = new ToolSwitch(ToolSwitchType.Directory);
            toolSwitch.DisplayName = displayName;
            toolSwitch.Description = description;
            toolSwitch.ArgumentRelationList = new ArrayList();
            toolSwitch.SwitchValue = switchValue;
            toolSwitch.Name = name;
            toolSwitch.Value = VCToolTask.EnsureTrailingSlash(value);
            base.ActiveToolSwitches.Add(name, toolSwitch);
            base.AddActiveSwitchToolValue(toolSwitch);
        }

        private void SetEnumProperty(string name,
                                     string displayName,
                                     string description,
                                     string[][] switchMap,
                                     string value)
            {
                base.ActiveToolSwitches.Remove(name);
                ToolSwitch toolSwitch = new ToolSwitch(ToolSwitchType.String);
                toolSwitch.DisplayName = displayName;
                toolSwitch.Description = description;
                toolSwitch.ArgumentRelationList = new ArrayList();
                toolSwitch.SwitchValue = base.ReadSwitchMap(name, switchMap, value);
                toolSwitch.Name = name;
                toolSwitch.Value = value;
                toolSwitch.MultipleValues = true;
                base.ActiveToolSwitches.Add(name, toolSwitch);
                base.AddActiveSwitchToolValue(toolSwitch);
            }

        private string[] GetStringArray(string name)
        {
            if (base.IsPropertySet(name))
            {
                return base.ActiveToolSwitches[name].StringList;
            }
            return null;
        }

        private void SetStringArray(string name,
                                    ToolSwitchType type,
                                    string displayName,
                                    string description,
                                    string switchValue,
                                    string[] value)
        {
            base.ActiveToolSwitches.Remove(name);
            ToolSwitch toolSwitch = new ToolSwitch(type);
            toolSwitch.DisplayName = displayName;
            toolSwitch.Description = description;
            toolSwitch.ArgumentRelationList = new ArrayList();
            toolSwitch.SwitchValue = switchValue;
            toolSwitch.Name = name;
            toolSwitch.StringList = value;
            base.ActiveToolSwitches.Add(name, toolSwitch);
            base.AddActiveSwitchToolValue(toolSwitch);
        }

        private ToolSwitchType GetToolSwitchTypeForStringPathArray()
        {
            // dynamically decide whether ToolSwitchType.StringPathArray exists
            // (not declared in Microsoft.Build.CPPTasks.Common, Version=12.0.0.0, but still seems to work)
            var type = typeof(ToolSwitchType);
            var enums = type.GetEnumNames();
            if (enums.Length >= 10)
                return (ToolSwitchType)9; // ToolSwitchType.StringPathArray;
            return ToolSwitchType.StringArray;
        }

        // use the default implementation of SourcesPropertyName, it returns "Sources"

        protected override ITaskItem[] TrackedInputFiles
        {
            get { return Sources; } //  return new ITaskItem[1] { new TaskItem(this.Source) };
        }

        private void applyParameters(Dictionary<string, object> parameterValues)
        {
            var myType = typeof(CompileD);
            foreach (string s in switchOrderList)
            {
                var prop = myType.GetProperty(s);
                object val;
                if (prop != null && parameterValues.TryGetValue(s, out val))
                {
                    prop.SetValue(this, val, null);
                }
            }
        }

        public string GenCmdLine(Dictionary<string, object> parameters)
        {
            applyParameters(parameters);
            return GenerateCommandLineExceptSwitches(new string[0]);
        }

        public override bool Execute()
        {
            if (!String.IsNullOrEmpty(TrackerLogDirectory))
                TrackFileAccess = true;

            return base.Execute();
        }

        protected override int ExecuteTool(string pathToTool, string responseFileCommands, string commandLineCommands)
        {
            responseFileCommands = responseFileCommands.Replace("[PackageName]", PackageName);
            commandLineCommands = commandLineCommands.Replace("[PackageName]", PackageName);

            string src = "";
            foreach (var item in Sources)
                src += " " + item.ToString();
            if (ShowCommandLine)
                Log.LogMessage(MessageImportance.High, pathToTool + " " + commandLineCommands + " " + responseFileCommands);
            else
                Log.LogMessage(MessageImportance.High, "Compiling" + src);

            return base.ExecuteTool(pathToTool, responseFileCommands, commandLineCommands);
        }

        private System.DateTime _nextToolTypeCheck = new System.DateTime(1900, 1, 1);
        private Microsoft.Build.Utilities.ExecutableType? _ToolType = new Microsoft.Build.Utilities.ExecutableType?();

        protected override Microsoft.Build.Utilities.ExecutableType? ToolType
        {
            get
            {
                if (_nextToolTypeCheck <= DateTime.Now)
                {
                    _nextToolTypeCheck = DateTime.Now.AddSeconds(5);
                    ushort arch = GetPEArchitecture(ToolExe);
                    if (arch == 0x10B)
                        _ToolType = Microsoft.Build.Utilities.ExecutableType.Native32Bit;
                    else if (arch == 0x20B)
                        _ToolType = Microsoft.Build.Utilities.ExecutableType.Native64Bit;
                    else
                        _ToolType = new Microsoft.Build.Utilities.ExecutableType?();
                }
                return _ToolType;
            }
        }

        protected static ushort GetPEArchitecture(string pFilePath)
        {
            ushort architecture = 0;
            try
            {
                using (System.IO.FileStream fStream = new System.IO.FileStream(pFilePath, System.IO.FileMode.Open, System.IO.FileAccess.Read))
                {
                    using (System.IO.BinaryReader bReader = new System.IO.BinaryReader(fStream))
                    {
                        if (bReader.ReadUInt16() == 0x5A4D) //check the MZ signature
                        {
                            fStream.Seek(0x3A, System.IO.SeekOrigin.Current); //seek to e_lfanew.
                            fStream.Seek(bReader.ReadUInt32(), System.IO.SeekOrigin.Begin); //seek to the start of the NT header.
                            if (bReader.ReadUInt32() == 0x4550) //check the PE\0\0 signature.
                            {
                                fStream.Seek(20, System.IO.SeekOrigin.Current); //seek past the file header,
                                architecture = bReader.ReadUInt16(); //read the magic number of the optional header.
                            }
                        }
                    }
                }
            }
            catch (Exception)
            {
            }
            // if architecture returns 0, there has been an error.
            return architecture;
        }

        protected override Encoding ResponseFileEncoding
        {
            get
            {
                return new UTF8Encoding(false);
            }
        }


    }

}
