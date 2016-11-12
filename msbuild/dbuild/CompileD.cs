using System;
using System.Collections.Generic;
using System.Xaml;
//using System.Threading.Tasks;
using Microsoft.Build.Framework;
//using Microsoft.Build.Utilities;
//using Microsoft.Build.Tasks;
using Microsoft.Build.Tasks.Xaml;
using Microsoft.Build.CPPTasks;
using System.IO;
using XamlTypes = Microsoft.Build.Framework.XamlTypes;
using System.Collections;
using System.Resources;
using System.Reflection;

namespace dbuild
{
    public class CompileD : Microsoft.Build.CPPTasks.TrackedVCToolTask
    {
        public CompileD()
        : base(new ResourceManager("dbuild.Strings", Assembly.GetExecutingAssembly()))
        {
            MinimalRebuildFromTracking = true;
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
            get;
            set;
        }

        public string CommandLineTemplate
        {
            get;
            set;
        }

        public bool ShowCommandLine
        {
            get;
            set;
        }

        public string Xaml
        {
            get;
            set;
        }

        public string PackageName
        {
            get;
            set;
        }

        public string Parameters
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

        protected override string[] ReadTLogNames
        {
            get { return new string[1] { _compiler + ".read.1.tlog" }; }
        }

        protected override string[] WriteTLogNames
        {
            get { return new string[1] { _compiler + ".write.1.tlog" }; }
        }

        protected override string CommandTLogName
        {
            get { return _compiler + ".command.1.tlog"; }
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

#if TOOLS_V14
        public 
#else
        protected
#endif
        override string SourcesPropertyName
        {
            get { return "Sources"; }
        }

        protected override ITaskItem[] TrackedInputFiles
        {
            get { return Sources; } //  return new ITaskItem[1] { new TaskItem(this.Source) };
        }

        /// <summary>
        /// The list of switches in the order they should appear, if set.
        /// </summary>
        private Dictionary<String, Object> parameterValues = new Dictionary<string, object>();

        private bool parseParameters(XamlTypes.Rule rule)
        {
            Dictionary<string, string> strOptions = new Dictionary<string, string>();
            string[] paras = Parameters.Split('|');
            foreach (string p in paras)
            {
                int pos = p.IndexOf('=');
                if (pos >= 0)
                {
                    string name = p.Substring(0, pos);
                    string value = p.Substring(pos + 1);
                    strOptions[name] = value;
                    switchOrderList.Add(name);
                }
            }

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
                        parameterValues[property.Name] = Int64.Parse(val);
                    }
                    else
                        parameterValues[property.Name] = val;
                }
            }
            return true;
        }

        public override bool Execute()
        {
            if (!String.IsNullOrEmpty(TrackerLogDirectory))
                TrackFileAccess = true;

            object rootObject = XamlServices.Load(new StreamReader(Xaml));
            XamlTypes.ProjectSchemaDefinitions schemas = rootObject as XamlTypes.ProjectSchemaDefinitions;
            if (schemas != null)
            {
                foreach (XamlTypes.IProjectSchemaNode node in schemas.Nodes)
                {
                    XamlTypes.Rule rule = node as XamlTypes.Rule;
                    if (rule != null)
                    {
                        parseParameters(rule);
                        CommandLineGenerator generator = new CommandLineGenerator(rule, parameterValues);
                        generator.CommandLineTemplate = this.CommandLineTemplate;
                        generator.AdditionalOptions = AdditionalOptions;

                        CommandLine = generator.GenerateCommandLine();
                        return base.Execute();
                    }
                }
            }
            return false;
        }

        protected override int ExecuteTool(string pathToTool, string responseFileCommands, string commandLineCommands)
        {
            responseFileCommands = responseFileCommands.Replace("[PackageName]", PackageName);
            commandLineCommands = commandLineCommands.Replace("[PackageName]", PackageName);
            string src = "";
            foreach (var item in Sources)
                src += " " + item.ToString();
            if (ShowCommandLine)
                Log.LogMessage(MessageImportance.High, pathToTool + " " + responseFileCommands + " " + commandLineCommands);
            else
                Log.LogMessage(MessageImportance.High, "Compiling" + src);
            return base.ExecuteTool(pathToTool, responseFileCommands, commandLineCommands);
        }

        string CommandLine;

        protected override string GenerateCommandLineCommands(VCToolTask.CommandLineFormat format
#if TOOLS_V14
                                                              , VCToolTask.EscapeFormat escapeFormat
#endif
        ) {
            string str = base.GenerateResponseFileCommands(format
#if TOOLS_V14
                , escapeFormat
#endif
                );
            if (!this.TrackFileAccess)
                str = str.Replace("\\\"", "\"").Replace("\\\\\"", "\\\"");
            str += " " + CommandLine;

            string src = "";
            foreach (var item in Sources)
                src += " " + item.ToString();
            if (!String.IsNullOrEmpty(src))
            {
                if (format == VCToolTask.CommandLineFormat.ForTracking)
                    str += " " + src.ToUpper();
                else
                    str += " " + src;
            }
            return str;
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
                        if (bReader.ReadUInt16() == 23117) //check the MZ signature
                        {
                            fStream.Seek(0x3A, System.IO.SeekOrigin.Current); //seek to e_lfanew.
                            fStream.Seek(bReader.ReadUInt32(), System.IO.SeekOrigin.Begin); //seek to the start of the NT header.
                            if (bReader.ReadUInt32() == 17744) //check the PE\0\0 signature.
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
                /* TODO: Any exception handling you want to do, personally I just take 0 as a sign of failure */
            }
            // if architecture returns 0, there has been an error.
            return architecture;
        }

    }

}
