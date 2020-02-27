using System;
using System.Collections.Generic;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using System.Collections;
using System.Globalization;
using System.Text;
using System.IO;

namespace dbuild
{
	/// //////////////////////////////////////////////////////////////////
	/// happens to be identical to CPPTasks.ToolSwitchType
	public enum DToolSwitchType
	{
		Boolean,
		Integer,
		String,
		StringArray,
		File,
		Directory,
		ITaskItem,
		ITaskItemArray,
		AlwaysAppend,
		StringPathArray,
	}

	public interface IToolSwitchProvider
	{
		void SetProperty(string name, string displayName, string description, string switchValue,
						 DToolSwitchType type, object value,
						 bool multipleValues = false, bool required = false, string separator = null);
		object GetProperty(string name);
	}

	[Flags]
	public enum EscapeFormat
	{
		Default = 0,
		EscapeTrailingSlash = 1
	}
	public enum CommandLineFormat
	{
		ForBuildLog = 0,
		ForTracking = 1
	}

	public class CompileDOptions
	{
		public ArrayList switchOrderList = new ArrayList();
		private IToolSwitchProvider provider;
		private string _compiler = "dmd";

		public CompileDOptions(IToolSwitchProvider provider)
		{
			this.provider = provider;

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
			this.switchOrderList.Add("LowMem");
			this.switchOrderList.Add("DebugCode");
			this.switchOrderList.Add("DebugInfo");
			this.switchOrderList.Add("DebugFull");
			this.switchOrderList.Add("DebugMixin");
			this.switchOrderList.Add("BoundsCheck");
			this.switchOrderList.Add("CPUArchitecture");
			this.switchOrderList.Add("PerformSyntaxCheckOnly");

			this.switchOrderList.Add("BetterC");
			this.switchOrderList.Add("CppStandard");
			this.switchOrderList.Add("DIP25");
			this.switchOrderList.Add("DIP1000");
			this.switchOrderList.Add("DIP1008");
			this.switchOrderList.Add("DIP1021");
			this.switchOrderList.Add("RevertImport");
			this.switchOrderList.Add("PreviewDtorFields");
			this.switchOrderList.Add("PreviewIntPromote");
			this.switchOrderList.Add("PreviewFixAliasThis");
			this.switchOrderList.Add("PreviewRvalueRefParam");
			this.switchOrderList.Add("PreviewNoSharedAccess");
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
			this.switchOrderList.Add("CppHeaderFile");
			this.switchOrderList.Add("JSONFile");

			this.switchOrderList.Add("AdditionalOptions");

			this.switchOrderList.Add("Sources");
		}

		public string AdditionalOptions { get; set; }

		public ITaskItem[] Sources
		{
			get
			{
				return GetTaskItemsProperty("Sources");
			}
			set
			{
				SetTaskItemsProperty("Sources", value);
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
				SetStringArray("ImportPaths", true, "Import Paths",
                               "Where to look for imports. (-I[path]).", "-I", value);
            }
        }

        public string[] StringImportPaths
        {
            get { return GetStringArray("StringImportPaths"); }
            set
            {
				SetStringArray("StringImportPaths", true, "String Import Paths",
                               "Where to look for string imports. (-J[path]).", "-J", value);
            }
        }

        public string[] VersionIdentifiers
        {
            get { return GetStringArray("VersionIdentifiers"); }
            set
            {
				SetStringArray("VersionIdentifiers", false, "Version Identifiers",
                               "Compile in version code identified by ident/&gt;= level.", "-version=", value);
            }
        }

        public string[] DebugIdentifiers
        {
            get { return GetStringArray("DebugIdentifiers"); }
            set
            {
				SetStringArray("DebugIdentifiers", false, "Debug Identifiers",
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
				return GetIntProperty("MinCoverage");
            }
            set
            {
				SetIntProperty("MinCoverage", "Minimum Code Coverage",
							   "Require at least nnn% code coverage. (-cov=nnn)",
							   "-cov=", ValidateInteger(0, 100, value));
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

        public bool LowMem
        {
            get { return GetBoolProperty("LowMem"); }
            set
            {
				SetBoolProperty("LowMem", "Low Memory Usage",
                                "Use garbage collector to reduce memory needed by the compiler (-lowmem)",
                                "-lowmem", value);
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
                    new string[2] { "VS", "-g" },  // -gc removed, but kept for compatibility
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

		public bool DIP1021
		{
			get { return GetBoolProperty("DIP1021"); }
			set
			{
				SetBoolProperty("DIP1021", "DIP1021",
								"implement DIP1021: mutable function arguments (-preview=dip1021)",
								"-preview=dip1021", value);
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

		public bool PreviewRvalueRefParam
		{
			get { return GetBoolProperty("PreviewRvalueRefParam"); }
			set
			{
				SetBoolProperty("PreviewRvalueRefParam", "Preview rvaluerefparam",
								"enable rvalue arguments to ref parameters (-preview=rvaluerefparam)",
								"-preview=rvaluerefparam", value);
			}
		}

		public bool PreviewNoSharedAccess
		{
			get { return GetBoolProperty("PreviewNoSharedAccess"); }
			set
			{
				SetBoolProperty("PreviewNoSharedAccess", "Preview nosharedaccess",
								"disable access to shared memory objects (-preview=nosharedaccess)",
								"-preview=nosharedaccess", value);
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

        public string CppStandard
        {
            get { return GetStringProperty("CppStandard"); }
            set
            {
                string[][] switchMap = new string[5][]
                {
                    new string[2] { "default", "" },
                    new string[2] { "cpp98", "-extern-std=c++98" },
                    new string[2] { "cpp11", "-extern-std=c++11" },
                    new string[2] { "cpp14", "-extern-std=c++14" },
                    new string[2] { "cpp17", "-extern-std=c++17" }
                };

				SetEnumProperty("CppStandard", "C++ Language Standard",
                                "set C++ name mangling compatibility (-extern-std=)",
                                switchMap, value);
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

		public string CppHeaderFile
		{
			get { return GetStringProperty("CppHeaderFile"); }
			set
			{
				SetFileProperty("CppHeaderFile", "C++ Header File",
								"Write C++ 'header' to this file. (-HCf=[file])",
								"-HCf=", value);
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
		public string Compiler
		{
			get { return _compiler; }
			set { _compiler = value; }
		}

		public string ToolName
		{
			get { return _compiler + ".exe"; }
		}

		public string TrackerLogDirectory
		{
			get;
			set;
		}

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

		//////////////////////////////////////////////////////////////////
		private int ValidateInteger(int min, int max, int value)
		{
			if (value < min)
				value = min;
			if (value > max)
				value = max;
			return value;
		}

		protected string ReadSwitchMap(string propertyName, string[][] switchMap, string value)
		{
			if (switchMap != null)
			{
				for (int index = 0; index < switchMap.Length; ++index)
				{
					if (string.Equals(switchMap[index][0], value, StringComparison.CurrentCultureIgnoreCase))
						return switchMap[index][1];
				}
			}
			return string.Empty;
		}

		protected static string EnsureTrailingSlash(string directoryName)
		{
			if (!string.IsNullOrEmpty(directoryName))
			{
				char ch = directoryName[directoryName.Length - 1];
				if ((int)ch != (int)Path.DirectorySeparatorChar && (int)ch != (int)Path.AltDirectorySeparatorChar)
					directoryName += Path.DirectorySeparatorChar.ToString();
			}
			return directoryName;
		}

		//////////////////////////////////////////////////////////////////
		public bool GetBoolProperty(string name)
		{
			object val = provider.GetProperty(name);
			return val != null ? (bool)val : false;
		}

		public void SetBoolProperty(string name, string displayName, string description, string switchValue, bool value)
		{
			provider.SetProperty(name, displayName, description, switchValue, DToolSwitchType.Boolean, value);
		}

		public int GetIntProperty(string name)
		{
			object val = provider.GetProperty(name);
			return val != null ? (int)val : 0;
		}

		public void SetIntProperty(string name, string displayName, string description,
								   string switchValue, int value)
		{
			provider.SetProperty(name, displayName, description, switchValue, DToolSwitchType.Integer, value);
		}

		public string GetStringProperty(string name)
		{
			object val = provider.GetProperty(name);
			return val != null ? (string)val : null;
		}

		public void SetFileProperty(string name, string displayName, string description,
									string switchValue, string value)
		{
			provider.SetProperty(name, displayName, description, switchValue, DToolSwitchType.File, value);
		}

		public void SetDirectoryProperty(string name, string displayName, string description,
										 string switchValue, string value)
		{
			provider.SetProperty(name, displayName, description, switchValue, DToolSwitchType.Directory, EnsureTrailingSlash(value));
		}

		public void SetEnumProperty(string name, string displayName, string description,
									string[][] switchMap, string value)
		{
			string switchValue = ReadSwitchMap(name, switchMap, value);
			provider.SetProperty(name, displayName, description, switchValue, DToolSwitchType.Directory, value, true);
		}

		public string[] GetStringArray(string name)
		{
			object val = provider.GetProperty(name);
			return val != null ? (string[])val : null;
		}

		public void SetStringArray(string name, bool paths, string displayName, string description,
								   string switchValue, string[] value)
		{
			DToolSwitchType type = paths ? DToolSwitchType.StringPathArray : DToolSwitchType.StringArray;
			provider.SetProperty(name, displayName, description, switchValue, type, value);
		}

		public ITaskItem[] GetTaskItemsProperty(string name)
		{
			object val = provider.GetProperty(name);
			return val != null ? (ITaskItem[])val : null;
		}

		public void SetTaskItemsProperty(string name, ITaskItem[] value)
		{
			provider.SetProperty(name, string.Empty, string.Empty, string.Empty, DToolSwitchType.ITaskItemArray, value, false, true, " ");
		}

	}

	public class DToolSwitch
	{
		public string Name;
		public string FalseSuffix;
		public string TrueSuffix;
		public string Separator;
		public bool BooleanValue = true;
		public string Value;
		public string SwitchValue;
		public string ReverseSwitchValue;
		public string Description;
		public string DisplayName;
		public DToolSwitchType Type;
		public bool Required;
		public int Number;
		public string[] StringList;
		public ITaskItem TaskItem;
		public ITaskItem[] TaskItemArray;
		public bool MultipleValues;

		public DToolSwitch()
		{
		}
		public DToolSwitch(DToolSwitchType toolType)
		{
			Type = toolType;
		}

		public void SetValue(object val)
		{
			switch (Type)
			{
				case DToolSwitchType.Boolean: BooleanValue = (bool)val; break;
				case DToolSwitchType.Integer: Number = (int)val; break;
				case DToolSwitchType.File:
				case DToolSwitchType.Directory:
				case DToolSwitchType.String: Value = (string)val; break;
				case DToolSwitchType.StringPathArray:
				case DToolSwitchType.StringArray: StringList = (string[])val; break;
				case DToolSwitchType.ITaskItem: TaskItem = (ITaskItem)val; break;
				case DToolSwitchType.ITaskItemArray: TaskItemArray = (ITaskItem[])val; break;
			}
		}

		public object GetValue()
		{
			switch (Type)
			{
				case DToolSwitchType.Boolean: return BooleanValue;
				case DToolSwitchType.Integer: return Number;
				case DToolSwitchType.File:
				case DToolSwitchType.Directory:
				case DToolSwitchType.String: return Value;
				case DToolSwitchType.StringPathArray:
				case DToolSwitchType.StringArray: return StringList;
				case DToolSwitchType.ITaskItem: return TaskItem;
				case DToolSwitchType.ITaskItemArray: return TaskItemArray;
			}
			return null;
		}
	}

	public class CompileDOpt : IToolSwitchProvider
	{
		private Dictionary<string, DToolSwitch> activeToolSwitchesValues = new Dictionary<string, DToolSwitch>();
		private Dictionary<string, DToolSwitch> activeToolSwitches = new Dictionary<string, DToolSwitch>((IEqualityComparer<string>)StringComparer.OrdinalIgnoreCase);
		CompileDOptions opts;

		public string Compiler { get { return opts.Compiler; } set { opts.Compiler = value; } }
		public string ToolExe { get; set; }
		public string AdditionalOptions { get { return opts.AdditionalOptions; } set { opts.AdditionalOptions = value; } }
		public virtual ITaskItem[] Sources { get { return opts.Sources; } set { opts.Sources = value; } }

		public CompileDOpt()
		{
			opts = new CompileDOptions(this);
		}

		//////////////////////////////////////////////////////////////////
		public void SetProperty(string name, string displayName, string description, string switchValue,
		                        DToolSwitchType type, object value,
								bool multipleValues = false, bool required = false, string separator = null)
		{
			activeToolSwitches.Remove(name);
			DToolSwitch toolSwitch = new DToolSwitch(type);
			toolSwitch.DisplayName = displayName;
			toolSwitch.Description = description;
			toolSwitch.SwitchValue = switchValue;
			toolSwitch.Name = name;
			toolSwitch.SetValue(value);
			toolSwitch.MultipleValues = multipleValues;
			toolSwitch.Required = required;
			toolSwitch.Separator = separator;
			activeToolSwitches.Add(name, toolSwitch);
			AddActiveSwitchToolValue(toolSwitch);
		}

		public object GetProperty(string name)
		{
			if (IsPropertySet(name))
			{
				return activeToolSwitches[name].GetValue();
			}
			return null;
		}

		protected void AddActiveSwitchToolValue(DToolSwitch switchToAdd)
		{
			if (switchToAdd.Type != DToolSwitchType.Boolean || switchToAdd.BooleanValue)
			{
				if (string.IsNullOrEmpty(switchToAdd.SwitchValue))
					return;
				activeToolSwitchesValues.Add(switchToAdd.SwitchValue, switchToAdd);
			}
			else
			{
				if (string.IsNullOrEmpty(switchToAdd.ReverseSwitchValue))
					return;
				activeToolSwitchesValues.Add(switchToAdd.ReverseSwitchValue, switchToAdd);
			}
		}

		protected bool IsPropertySet(string propertyName)
		{
			if (!string.IsNullOrEmpty(propertyName))
				return this.activeToolSwitches.ContainsKey(propertyName);
			return false;
		}

		// emulate what's happening in VCToolTask
		public string GenerateCommandLineCommands()
		{
			// must be outside of response file
			string cmd = null;
			if (opts.LowMem)
				cmd = " -lowmem";
			return cmd;
		}

		public string GenerateResponseFileCommands(CommandLineFormat format, EscapeFormat escapeFormat)
		{
			bool hadAdditionalOpts = false;
			CommandLineBuilder commandLineBuilder = new CommandLineBuilder(true);
			foreach (string switchOrder in opts.switchOrderList)
			{
				if (IsPropertySet(switchOrder))
				{
					DToolSwitch activeToolSwitch = this.activeToolSwitches[switchOrder];
					// no dependencies between switches defined
					this.GenerateCommandsAccordingToType(commandLineBuilder, activeToolSwitch, format, escapeFormat);
				}
				else if (string.Equals(switchOrder, "additionaloptions", StringComparison.OrdinalIgnoreCase))
				{
					if (!string.IsNullOrEmpty(this.AdditionalOptions))
						commandLineBuilder.AppendSwitch(Environment.ExpandEnvironmentVariables(this.AdditionalOptions));
					hadAdditionalOpts = true;
				}
			}
			if (!hadAdditionalOpts && !string.IsNullOrEmpty(this.AdditionalOptions))
				commandLineBuilder.AppendSwitch(Environment.ExpandEnvironmentVariables(this.AdditionalOptions));
			return commandLineBuilder.ToString();
		}

		protected void GenerateCommandsAccordingToType(CommandLineBuilder builder, DToolSwitch toolSwitch,
													   CommandLineFormat format, EscapeFormat escapeFormat)
		{
			switch (toolSwitch.Type)
			{
				case DToolSwitchType.Boolean:
					this.EmitBooleanSwitch(builder, toolSwitch);
					break;
				case DToolSwitchType.Integer:
					this.EmitIntegerSwitch(builder, toolSwitch);
					break;
				case DToolSwitchType.String:
					this.EmitStringSwitch(builder, toolSwitch);
					break;
				case DToolSwitchType.StringArray:
					EmitStringArraySwitch(builder, toolSwitch, CommandLineFormat.ForBuildLog, EscapeFormat.Default);
					break;
				case DToolSwitchType.File:
					EmitFileSwitch(builder, toolSwitch, format);
					break;
				case DToolSwitchType.Directory:
					EmitDirectorySwitch(builder, toolSwitch, format);
					break;
				case DToolSwitchType.ITaskItem:
					EmitTaskItemSwitch(builder, toolSwitch);
					break;
				case DToolSwitchType.ITaskItemArray:
					EmitTaskItemArraySwitch(builder, toolSwitch, format);
					break;
				case DToolSwitchType.StringPathArray:
					EmitStringArraySwitch(builder, toolSwitch, format, escapeFormat);
					break;
				default:
					// ErrorUtilities.VerifyThrow(false, "InternalError");
					break;
			}
		}

		private static void EmitTaskItemArraySwitch(CommandLineBuilder builder, DToolSwitch toolSwitch, CommandLineFormat format)
		{
			if (string.IsNullOrEmpty(toolSwitch.Separator))
			{
				foreach (ITaskItem taskItem in toolSwitch.TaskItemArray)
					builder.AppendSwitchIfNotNull(toolSwitch.SwitchValue, Environment.ExpandEnvironmentVariables(taskItem.ItemSpec));
			}
			else
			{
				ITaskItem[] parameters = new ITaskItem[toolSwitch.TaskItemArray.Length];
				for (int index = 0; index < toolSwitch.TaskItemArray.Length; ++index)
				{
					parameters[index] = (ITaskItem)new TaskItem(Environment.ExpandEnvironmentVariables(toolSwitch.TaskItemArray[index].ItemSpec));
					if (format == CommandLineFormat.ForTracking)
						parameters[index].ItemSpec = parameters[index].ItemSpec.ToUpperInvariant();
				}
				builder.AppendSwitchIfNotNull(toolSwitch.SwitchValue, parameters, toolSwitch.Separator);
			}
		}

		private static void EmitTaskItemSwitch(CommandLineBuilder builder, DToolSwitch toolSwitch)
		{
			if (string.IsNullOrEmpty(toolSwitch.TaskItem.ItemSpec))
				return;
			builder.AppendFileNameIfNotNull(Environment.ExpandEnvironmentVariables(toolSwitch.TaskItem.ItemSpec + toolSwitch.Separator));
		}

		private static void EmitDirectorySwitch(CommandLineBuilder builder, DToolSwitch toolSwitch, CommandLineFormat format)
		{
			if (string.IsNullOrEmpty(toolSwitch.SwitchValue))
				return;
			if (format == CommandLineFormat.ForBuildLog)
				builder.AppendSwitch(toolSwitch.SwitchValue + toolSwitch.Separator);
			else
				builder.AppendSwitch(toolSwitch.SwitchValue.ToUpperInvariant() + toolSwitch.Separator);
		}

		private static void EmitFileSwitch(CommandLineBuilder builder, DToolSwitch toolSwitch, CommandLineFormat format)
		{
			if (string.IsNullOrEmpty(toolSwitch.Value))
				return;
			string parameter = Environment.ExpandEnvironmentVariables(toolSwitch.Value).Trim();
			if (format == CommandLineFormat.ForTracking)
				parameter = parameter.ToUpperInvariant();
			if (!parameter.StartsWith("\"", StringComparison.Ordinal))
			{
				string str = "\"" + parameter;
				parameter = !str.EndsWith("\\", StringComparison.Ordinal) || str.EndsWith("\\\\", StringComparison.Ordinal) ? str + "\"" : str + "\\\"";
			}
			builder.AppendSwitchUnquotedIfNotNull(toolSwitch.SwitchValue + toolSwitch.Separator, parameter);
		}

		private void EmitIntegerSwitch(CommandLineBuilder builder, DToolSwitch toolSwitch)
		{
			string num = toolSwitch.Number.ToString((IFormatProvider)CultureInfo.InvariantCulture) + GetEffectiveArgumentsValues(toolSwitch);
			if (!string.IsNullOrEmpty(toolSwitch.Separator))
				builder.AppendSwitch(toolSwitch.SwitchValue + toolSwitch.Separator + num);
			else
				builder.AppendSwitch(toolSwitch.SwitchValue + num);
		}

		private static void EmitStringArraySwitch(CommandLineBuilder builder, DToolSwitch toolSwitch,
												  CommandLineFormat format, EscapeFormat escapeFormat)
		{
			string[] parameters = new string[toolSwitch.StringList.Length];
			char[] anyOf = new char[11] { ' ', '|', '<', '>', ',', ';', '-', '\r', '\n', '\t', '\f' };
			for (int index = 0; index < toolSwitch.StringList.Length; ++index)
			{
				string str = !toolSwitch.StringList[index].StartsWith("\"", StringComparison.Ordinal) || !toolSwitch.StringList[index].EndsWith("\"", StringComparison.Ordinal) ? Environment.ExpandEnvironmentVariables(toolSwitch.StringList[index]) : Environment.ExpandEnvironmentVariables(toolSwitch.StringList[index].Substring(1, toolSwitch.StringList[index].Length - 2));
				if (!string.IsNullOrEmpty(str))
				{
					if (format == CommandLineFormat.ForTracking)
						str = str.ToUpperInvariant();
					if (escapeFormat.HasFlag((Enum)EscapeFormat.EscapeTrailingSlash) && 
						str.IndexOfAny(anyOf) == -1 && 
						(str.EndsWith("\\", StringComparison.Ordinal) && !str.EndsWith("\\\\", StringComparison.Ordinal)))
						str += "\\";
					parameters[index] = str;
				}
			}
			if (string.IsNullOrEmpty(toolSwitch.Separator))
			{
				foreach (string parameter in parameters)
					builder.AppendSwitchIfNotNull(toolSwitch.SwitchValue, parameter);
			}
			else
				builder.AppendSwitchIfNotNull(toolSwitch.SwitchValue, parameters, toolSwitch.Separator);
		}

		private void EmitStringSwitch(CommandLineBuilder builder, DToolSwitch toolSwitch)
		{
			string switchName = string.Empty + toolSwitch.SwitchValue + toolSwitch.Separator;
			StringBuilder stringBuilder = new StringBuilder(GetEffectiveArgumentsValues(toolSwitch));
			string str1 = toolSwitch.Value;
			if (!toolSwitch.MultipleValues)
			{
				string str2 = str1.Trim();
				if (!str2.StartsWith("\"", StringComparison.Ordinal))
				{
					string str3 = "\"" + str2;
					str2 = !str3.EndsWith("\\", StringComparison.Ordinal) || str3.EndsWith("\\\\", StringComparison.Ordinal) ? str3 + "\"" : str3 + "\\\"";
				}
				stringBuilder.Insert(0, str2);
			}
			if (switchName.Length == 0 && stringBuilder.ToString().Length == 0)
				return;
			builder.AppendSwitchUnquotedIfNotNull(switchName, stringBuilder.ToString());
		}

		private void EmitBooleanSwitch(CommandLineBuilder builder, DToolSwitch toolSwitch)
		{
			if (toolSwitch.BooleanValue)
			{
				if (string.IsNullOrEmpty(toolSwitch.SwitchValue))
					return;
				StringBuilder stringBuilder = new StringBuilder(GetEffectiveArgumentsValues(toolSwitch));
				stringBuilder.Insert(0, toolSwitch.Separator);
				stringBuilder.Insert(0, toolSwitch.TrueSuffix);
				stringBuilder.Insert(0, toolSwitch.SwitchValue);
				builder.AppendSwitch(stringBuilder.ToString());
			}
			else
				this.EmitReversibleBooleanSwitch(builder, toolSwitch);
		}

		private void EmitReversibleBooleanSwitch(CommandLineBuilder builder, DToolSwitch toolSwitch)
		{
			if (string.IsNullOrEmpty(toolSwitch.ReverseSwitchValue))
				return;
			string str = toolSwitch.BooleanValue ? toolSwitch.TrueSuffix : toolSwitch.FalseSuffix;
			StringBuilder stringBuilder = new StringBuilder(GetEffectiveArgumentsValues(toolSwitch));
			stringBuilder.Insert(0, str);
			stringBuilder.Insert(0, toolSwitch.Separator);
			stringBuilder.Insert(0, toolSwitch.TrueSuffix);
			stringBuilder.Insert(0, toolSwitch.ReverseSwitchValue);
			builder.AppendSwitch(stringBuilder.ToString());
		}

		protected string GetEffectiveArgumentsValues(DToolSwitch property)
		{
			StringBuilder stringBuilder = new StringBuilder();
			CommandLineBuilder commandLineBuilder = new CommandLineBuilder();
			commandLineBuilder.AppendSwitchUnquotedIfNotNull("", stringBuilder.ToString());
			return commandLineBuilder.ToString();
		}

		public void applyParameters(Dictionary<string, object> parameterValues)
		{
			var myType = typeof(CompileDOptions);
			foreach (string s in opts.switchOrderList)
			{
				var prop = myType.GetProperty(s);
				object val;
				if (prop != null && parameterValues.TryGetValue(s, out val))
				{
					prop.SetValue(opts, val, null);
				}
			}
		}

		public string GenCmdLine(Dictionary<string, object> parameters)
		{
			applyParameters(parameters);

			string commandLineCommands = GenerateCommandLineCommands();
			string responseFileCommands = GenerateResponseFileCommands(CommandLineFormat.ForBuildLog, EscapeFormat.Default);
			if (!string.IsNullOrEmpty(commandLineCommands))
				return commandLineCommands + " " + responseFileCommands;
			return responseFileCommands;
		}
	}
}
