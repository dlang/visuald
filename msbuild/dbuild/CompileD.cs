using System;
using Microsoft.Build.Framework;
using Microsoft.Build.CPPTasks;
using System.Collections;
using System.Resources;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.IO;

namespace dbuild
{
	public class CompileD : TrackedVCToolTask, IToolSwitchProvider
	{
		CompileDOptions opts;

		public CompileD()
		: base(new ResourceManager("dbuild.Strings", Assembly.GetExecutingAssembly()))
		{
			opts = new CompileDOptions(this);
			MinimalRebuildFromTracking = true;
		}

		public new string AdditionalOptions
		{
			get { return base.AdditionalOptions; }
			set { base.AdditionalOptions = value; opts.AdditionalOptions = value; }
		}

		public string Compiler { get { return opts.Compiler; } set { opts.Compiler = value; } }
		protected override string ToolName { get { return opts.ToolName; } }
		public string TrackerLogDirectory { get { return opts.TrackerLogDirectory; } set { opts.TrackerLogDirectory = value; } }

		// use the default implementation of SourcesPropertyName, it returns "Sources"
		[Required]
		public virtual ITaskItem[] Sources { get { return opts.Sources; } set { opts.Sources = value; } }

		public bool DoNotLink { get { return opts.DoNotLink; } set { opts.DoNotLink = value; } }
		public string CodeGeneration { get { return opts.CodeGeneration; } set { opts.CodeGeneration = value; } }
        public string[] ImportPaths { get { return opts.ImportPaths; } set { opts.ImportPaths = value; } }
        public string[] ImportCPaths { get { return opts.ImportCPaths; } set { opts.ImportCPaths = value; } }
        public string[] StringImportPaths { get { return opts.StringImportPaths; } set { opts.StringImportPaths = value; } }
		public string[] VersionIdentifiers { get { return opts.VersionIdentifiers; } set { opts.VersionIdentifiers = value; } }
		public string[] DebugIdentifiers { get { return opts.DebugIdentifiers; } set { opts.DebugIdentifiers = value; } }
		public string ObjectFileName { get { return opts.ObjectFileName; } set { opts.ObjectFileName = value; } }
		public bool PreserveSourcePath { get { return opts.PreserveSourcePath; } set { opts.PreserveSourcePath = value; } }
		public string CRuntimeLibrary { get { return opts.CRuntimeLibrary; } set { opts.CRuntimeLibrary = value; } }
		public bool Profile { get { return opts.Profile; } set { opts.Profile = value; } }
		public bool ProfileGC { get { return opts.ProfileGC; } set { opts.ProfileGC = value; } }
		public bool Coverage { get { return opts.Coverage; } set { opts.Coverage = value; } }
		public int MinCoverage { get { return opts.MinCoverage; } set { opts.MinCoverage = value; } }
		public bool Unittest { get { return opts.Unittest; } set { opts.Unittest = value; } }
		public bool Optimizer { get { return opts.Optimizer; } set { opts.Optimizer = value; } }
		public bool Inliner { get { return opts.Inliner; } set { opts.Inliner = value; } }
		public bool StackFrame { get { return opts.StackFrame; } set { opts.StackFrame = value; } }
		public bool StackStomp { get { return opts.StackStomp; } set { opts.StackStomp = value; } }
		public bool AllInst { get { return opts.AllInst; } set { opts.AllInst = value; } }
		public bool BetterC { get { return opts.BetterC; } set { opts.BetterC = value; } }
		public bool Main { get { return opts.Main; } set { opts.Main = value; } }
		public bool LowMem { get { return opts.LowMem; } set { opts.LowMem = value; } }
		public string DebugCode { get { return opts.DebugCode; } set { opts.DebugCode = value; } }
		public string DebugInfo { get { return opts.DebugInfo; } set { opts.DebugInfo = value; } }
		public bool DebugFull { get { return opts.DebugFull; } set { opts.DebugFull = value; } }
		public string DebugMixin { get { return opts.DebugMixin; } set { opts.DebugMixin = value; } }
		public string CPUArchitecture { get { return opts.CPUArchitecture; } set { opts.CPUArchitecture = value; } }
		public string BoundsCheck { get { return opts.BoundsCheck; } set { opts.BoundsCheck = value; } }
		public bool PerformSyntaxCheckOnly { get { return opts.PerformSyntaxCheckOnly; } set { opts.PerformSyntaxCheckOnly = value; } }
		public bool DIP25 { get { return opts.DIP25; } set { opts.DIP25 = value; } }
		public bool DIP1000 { get { return opts.DIP1000; } set { opts.DIP1000 = value; } }
		public bool DIP1008 { get { return opts.DIP1008; } set { opts.DIP1008 = value; } }
		public bool DIP1021 { get { return opts.DIP1021; } set { opts.DIP1021 = value; } }
		public bool RevertImport { get { return opts.RevertImport; } set { opts.RevertImport = value; } }
		public bool PreviewDtorFields { get { return opts.PreviewDtorFields; } set { opts.PreviewDtorFields = value; } }
		public bool PreviewIntPromote { get { return opts.PreviewIntPromote; } set { opts.PreviewIntPromote = value; } }
		public bool PreviewFixAliasThis { get { return opts.PreviewFixAliasThis; } set { opts.PreviewFixAliasThis = value; } }
		public bool PreviewRvalueRefParam { get { return opts.PreviewRvalueRefParam; } set { opts.PreviewRvalueRefParam = value; } }
		public bool PreviewNoSharedAccess { get { return opts.PreviewNoSharedAccess; } set { opts.PreviewNoSharedAccess = value; } }
		public bool PreviewMarkdown { get { return opts.PreviewMarkdown; } set { opts.PreviewMarkdown = value; } }
		public bool PreviewIn { get { return opts.PreviewIn; } set { opts.PreviewIn = value; } }
		public bool PreviewInclusiveInContracts { get { return opts.PreviewInclusiveInContracts; } set { opts.PreviewInclusiveInContracts = value; } }
		public bool PreviewShortenedMethods { get { return opts.PreviewShortenedMethods; } set { opts.PreviewShortenedMethods = value; } }
		public bool PreviewFixImmutableConv { get { return opts.PreviewFixImmutableConv; } set { opts.PreviewFixImmutableConv = value; } }
		public bool PreviewSystemVariables { get { return opts.PreviewSystemVariables; } set { opts.PreviewSystemVariables = value; } }
		public bool TransitionVMarkdown { get { return opts.TransitionVMarkdown; } set { opts.TransitionVMarkdown = value; } }
		public bool TransitionField { get { return opts.TransitionField; } set { opts.TransitionField = value; } }
		public bool TransitionCheckImports { get { return opts.TransitionCheckImports; } set { opts.TransitionCheckImports = value; } }
		public bool TransitionComplex { get { return opts.TransitionComplex; } set { opts.TransitionComplex = value; } }
		public string CppStandard { get { return opts.CppStandard; } set { opts.CppStandard = value; } }
		public string Warnings { get { return opts.Warnings; } set { opts.Warnings = value; } }
		public string Deprecations { get { return opts.Deprecations; } set { opts.Deprecations = value; } }
		public bool Verbose { get { return opts.Verbose; } set { opts.Verbose = value; } }
		public bool ShowTLS { get { return opts.ShowTLS; } set { opts.ShowTLS = value; } }
		public bool ShowGC { get { return opts.ShowGC; } set { opts.ShowGC = value; } }
		public bool IgnorePragma { get { return opts.IgnorePragma; } set { opts.IgnorePragma = value; } }
		public bool ShowDependencies { get { return opts.ShowDependencies; } set { opts.ShowDependencies = value; } }
		public string DocDir { get { return opts.DocDir; } set { opts.DocDir = value; } }
		public string DocFile { get { return opts.DocFile; } set { opts.DocFile = value; } }
		public string DepFile { get { return opts.DepFile; } set { opts.DepFile = value; } }
		public string HeaderDir { get { return opts.HeaderDir; } set { opts.HeaderDir = value; } }
		public string HeaderFile { get { return opts.HeaderFile; } set { opts.HeaderFile = value; } }
		public string CppHeaderFile { get { return opts.CppHeaderFile; } set { opts.CppHeaderFile = value; } }
		public string JSONFile { get { return opts.JSONFile; } set { opts.JSONFile = value; } }
		public bool ShowCommandLine { get { return opts.ShowCommandLine; } set { opts.ShowCommandLine = value; } }
		public string PackageName { get { return opts.PackageName; } set { opts.PackageName = value; } }

		// IToolSwitchProvider
		public void SetProperty(string name, string displayName, string description, string switchValue,
								DToolSwitchType dtype, object value,
								bool multipleValues = false, bool required = false, string separator = null)
		{
			var type = (ToolSwitchType)dtype;
			if (dtype == DToolSwitchType.StringPathArray)
				type = GetToolSwitchTypeForStringPathArray();

			base.ActiveToolSwitches.Remove(name);
			ToolSwitch toolSwitch = new ToolSwitch(type);
			toolSwitch.DisplayName = displayName;
			toolSwitch.Description = description;
			toolSwitch.SwitchValue = switchValue;
			toolSwitch.Name = name;

			switch (type)
			{
				case ToolSwitchType.Boolean: toolSwitch.BooleanValue = (bool)value; break;
				case ToolSwitchType.Integer: toolSwitch.Number = (int)value; break;
				case ToolSwitchType.File:
				case ToolSwitchType.Directory:
				case ToolSwitchType.String: toolSwitch.Value = (string)value; break;
				case (ToolSwitchType)9 /*ToolSwitchType.StringPathArray*/:
				case ToolSwitchType.StringArray: toolSwitch.StringList = (string[])value; break;
				case ToolSwitchType.ITaskItem: toolSwitch.TaskItem = (ITaskItem)value; break;
				case ToolSwitchType.ITaskItemArray: toolSwitch.TaskItemArray = (ITaskItem[])value; break;
			}

			toolSwitch.MultipleValues = multipleValues;
			toolSwitch.Required = required;
			toolSwitch.Separator = separator;
			base.ActiveToolSwitches.Add(name, toolSwitch);
			AddActiveSwitchToolValue(toolSwitch);
		}

		public object GetProperty(string name)
		{
			if (IsPropertySet(name))
			{
				var toolSwitch = base.ActiveToolSwitches[name];
				switch (toolSwitch.Type)
				{
					case ToolSwitchType.Boolean: return toolSwitch.BooleanValue;
					case ToolSwitchType.Integer: return toolSwitch.Number;
					case ToolSwitchType.File:
					case ToolSwitchType.Directory:
					case ToolSwitchType.String: return toolSwitch.Value;
					case (ToolSwitchType)9 /*ToolSwitchType.StringPathArray*/:
					case ToolSwitchType.StringArray: return toolSwitch.StringList;
					case ToolSwitchType.ITaskItem: return toolSwitch.TaskItem;
					case ToolSwitchType.ITaskItemArray: return toolSwitch.TaskItemArray;
				}
			}
			return null;
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

		[Output]
        public string PackageNameOut
        {
            get { return opts.PackageName; }
        }

        protected override ArrayList SwitchOrderList
        {
            get { return opts.switchOrderList; }
        }

        private string TLogPrefix
        {
            get { return Compiler == "LDC" ? "ldmd2-ldc2" : "dmd"; }
        }

        protected override string[] ReadTLogNames
        {
            get {
				return new string[2] {
					TLogPrefix + ".read.1.tlog",
					TLogPrefix + "-cl.read.1.tlog",
				};
			}
        }

        protected override string[] WriteTLogNames
        {
            get {
				return new string[2] {
					TLogPrefix + ".write.1.tlog",
					TLogPrefix + "-cl.write.1.tlog",
	            };
			}
        }

        protected override string CommandTLogName
        {
            get { return "dcompile.command.1.tlog"; }
        }

        protected override string TrackerIntermediateDirectory
        {
            get
            {
                if (opts.TrackerLogDirectory != null)
                    return opts.TrackerLogDirectory;
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

        protected override ITaskItem[] TrackedInputFiles
        {
            get { return Sources; } //  return new ITaskItem[1] { new TaskItem(this.Source) };
        }

#if TOOLS_V14 || TOOLS_V15 || TOOLS_V17
        protected override string GenerateCommandLineCommandsExceptSwitches(string[] switchesToRemove, VCToolTask.CommandLineFormat format = VCToolTask.CommandLineFormat.ForBuildLog, VCToolTask.EscapeFormat escapeFormat = VCToolTask.EscapeFormat.Default)
        {
            string cmd = base.GenerateCommandLineCommandsExceptSwitches(switchesToRemove, format, escapeFormat);
#else
        protected override string GenerateCommandLineCommands(VCToolTask.CommandLineFormat format = VCToolTask.CommandLineFormat.ForBuildLog)
        {
            string cmd = base.GenerateCommandLineCommands(format);
#endif
            // must be outside of response file
            if (opts.LowMem)
                if (string.IsNullOrEmpty(cmd))
                    cmd = " -lowmem";
                else
                    cmd += " -lowmem"; // must be outside of response file
            return cmd;
        }

        public override bool Execute()
        {
            if (!String.IsNullOrEmpty(TrackerLogDirectory))
                TrackFileAccess = true;

            return base.Execute();
        }

        protected override int ExecuteTool(string pathToTool, string responseFileCommands, string commandLineCommands)
        {
            responseFileCommands = responseFileCommands.Replace("[PackageName]", opts.PackageName);
            commandLineCommands = commandLineCommands.Replace("[PackageName]", opts.PackageName);

            string src = "";
            foreach (var item in Sources)
                src += " " + Path.GetFileName(item.ToString());
            if (opts.ShowCommandLine)
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

        [DllImport("Kernel32.dll")] static extern int GetACP();

        protected override Encoding ResponseFileEncoding
        {
            get
            {
                // DMD assumes filenames encoded in system default Windows ANSI code page
                if (Compiler == "LDC")
                    return new UTF8Encoding(false);
                else
                {
                    int cp = GetACP();
                    if (cp == 65001)
                        return new UTF8Encoding(false); // no BOM
                    return System.Text.Encoding.GetEncoding(cp);
                }
            }
        }


    }

}
