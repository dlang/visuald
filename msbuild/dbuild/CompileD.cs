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

    }

}
