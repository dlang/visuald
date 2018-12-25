using Microsoft.Build.CPPTasks;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;

#if TOOLS_V14 || TOOLS_V15

namespace dbuild
{
    using TasksPerPackage = Dictionary<string, List<List<ITaskItem>>>;

    // A tool used to run multiple CompileD tasks in parallel.
    // Heavily inspired from Microsoft.Build.CPPTasks.MultiToolTask but with the support
    // for Package compilation model.
    public class MultiToolTaskVisualD : MultiToolTask
    {
        // array list contains either ITaskItems or ArrayLists of ITaskItems
        protected TasksPerPackage tasksPerPackage;

        // packageIndex, used to generate separate package names when compiling with "File" compilation model
        protected int packageIndex = 0;

        protected ITaskItem[] trackedInputFiles;


        [Required]
        public string CompilationModel { get; set; }

        protected override bool MaintainCompositeRootingMarkers { get { return true; } }

        protected override ITaskItem[] TrackedInputFiles
        {
            get
            {
                if (trackedInputFiles == null)
                    return Sources;
                return trackedInputFiles;
            }
        }

        public MultiToolTaskVisualD()
        {
        }

        public override bool Execute()
        {
            Type taskType;
            if (!PrepareTaskAssembly(out taskType))
                return false;

            if (!VerifyTrackerLogDirectory(Sources))
                return false;

            if (cts.IsCancellationRequested)
                return false;

            int workItemCount = 0;
            try
            {
                workItemCount = PrepareTasksPerPackage(Sources);
            }
            catch(ArgumentException)
            {
                return false;
            }

            TrackCommandLines = false;
            ComputeOutOfDateSourcesPerPackage();
            sourcesToCommandLines = MapSourcesToCommandLines();

            if (cts.IsCancellationRequested)
                return false;

            string[] envVariables = PrepareEnvironmentVariables();

            var workItems = new Dictionary<string, MultiToolTaskWorkItem>(workItemCount);
            if (!PrepareWorkItems(taskType, envVariables, ref workItems))
                return false;
            
            if (cts.IsCancellationRequested)
                return false;

            InitializeTaskScheduler();

            AddWorkItemsToTaskScheduler(workItems);
            UpdateSourcesCompiled(workItems);

            if (cts.IsCancellationRequested)
                return false;

            if (SchedulerVerbose)
            {
                Log.LogMessageFromResources("MultiTool.AddDone", ToolExe, taskScheduler.Count);
            }

            int errCode = ProcessTasks();
            return errCode == 0;
        }

        protected bool PrepareTaskAssembly(out Type taskType)
        {
            taskType = null;
            Assembly assembly = string.IsNullOrEmpty(TaskAssemblyName) ?
                                typeof(MultiToolTask).Assembly :
                                Assembly.LoadFrom(TaskAssemblyName);
            if (assembly == null)
            {
                Log.LogErrorWithCodeFromResources("General.InvalidValue",
                                                  TaskAssemblyName.GetType().Name,
                                                  GetType().Name);
                return false;
            }
            taskType = assembly.GetType(TaskName);
            if (taskType == null)
            {
                Log.LogErrorWithCodeFromResources("General.InvalidValue",
                                                  TaskName.GetType().Name,
                                                  GetType().Name);
                return false;
            }
            object obj = Activator.CreateInstance(taskType);
            if (new TrackedVCToolTaskInterfaceHelper(obj, taskType) == null)
            {
                Log.LogErrorWithCodeFromResources("General.InvalidValue",
                                                  TaskName.GetType().Name,
                                                  GetType().Name);
                return false;
            }
            if (SchedulerVerbose)
            {
                Log.LogMessageFromResources("MultiTool.TaskFound", TaskName);
            }
            if (string.IsNullOrEmpty(ToolExe))
            {
                ToolExe = (obj as ToolTask).ToolExe;
            }
            var pathToTool = ComputePathToTool(ToolPath, ToolExe);
            if (!string.IsNullOrEmpty(pathToTool))
            {
                ToolPath = Path.GetDirectoryName(pathToTool);
                ToolExe = Path.GetFileName(pathToTool);
            }
            if (SchedulerVerbose)
            {
                Log.LogMessageFromResources("MultiTool.BuildingWith", ToolExe);
            }
            return true;
        }

        protected bool VerifyTrackerLogDirectory(ITaskItem[] sources)
        {
            foreach(var source in sources)
            {
                string metadata = source.GetMetadata("TrackerLogDirectory");
                if (string.IsNullOrEmpty(TrackerLogDirectory) && !string.IsNullOrEmpty(metadata))
                {
                    TrackerLogDirectory = Path.GetFullPath(metadata);
                }
                else if (!string.IsNullOrEmpty(TrackerLogDirectory) &&
                         !string.IsNullOrEmpty(metadata) &&
                         string.Compare(TrackerLogDirectory,
                                        Path.GetFullPath(metadata),
                                        StringComparison.OrdinalIgnoreCase) != 0)
                {
                    Log.LogErrorWithCodeFromResources("MultiTool.SameTrackerLogDirectory",
                                                      TrackerLogDirectory,
                                                      Path.GetFullPath(metadata));
                    return false;
                }
            }
            return true;
        }

        protected int PrepareTasksPerPackage(ITaskItem[] sources)
        {
            tasksPerPackage = new TasksPerPackage();
            int compilationPackageCount = 0;
            foreach(var source in sources)
            {
                string package = GetPackageName(source);

                List<List<ITaskItem>> taskItemsPerPackage;
                if (!tasksPerPackage.TryGetValue(package, out taskItemsPerPackage))
                {
                    taskItemsPerPackage = new List<List<ITaskItem>>();
                    tasksPerPackage.Add(package, taskItemsPerPackage);
                }
                bool added = false;
                foreach(var itemList in taskItemsPerPackage)
                {
                    if (itemList.Count > 0)
                    {
                        var firstItemInList = itemList[0];
                        if (CanTaskItemsBeCompiledTogether(firstItemInList, source))
                        {
                            itemList.Add(source);
                            added = true;
                            break;
                        }
                        else
                        {
                            if (!CanTaskItemsBeCompiledSeparately(firstItemInList, source))
                            {
                                throw new ArgumentException("Task items cannot be compiled separately, " +
                                    "check log for a more descriptive error message");
                            }
                        }
                    }
                }
                if (!added)
                {
                    var itemList = new List<ITaskItem>();
                    itemList.Add(source);
                    taskItemsPerPackage.Add(itemList);
                    ++compilationPackageCount;
                }
            }
            return compilationPackageCount;
        }

        protected string GetPackageName(ITaskItem source)
        {
            if (string.Compare(CompilationModel, "Package", StringComparison.OrdinalIgnoreCase) == 0)
            {
                string package = source.GetMetadata("PackageName");
                if (package == null)
                    package = "";

                return package;
            }
            else
            {
                // in case the compilation is not by 'package' (it should be by 'file')
                // give each task item (file) a separate package name
                string package = packageIndex.ToString();
                ++packageIndex;
                return package;
            }
        }

        protected bool CanTaskItemsBeCompiledTogether(ITaskItem lhs, ITaskItem rhs)
        {
            if (!(lhs is ITaskItem2) || !(rhs is ITaskItem2))
                return false;

            var customMetadataLhs = ((ITaskItem2)lhs).CloneCustomMetadataEscaped() as IDictionary<string, string>;
            var customMetadataRhs = ((ITaskItem2)rhs).CloneCustomMetadataEscaped() as IDictionary<string, string>;

            if (customMetadataLhs == null || customMetadataRhs == null)
                return false;

            if (customMetadataLhs.Count != customMetadataRhs.Count)
            {
                string msg = "files " + lhs.ItemSpec + " and " + rhs.ItemSpec +
                    " to be compiled together but they will not be because their metadata count differs " +
                    "(" + customMetadataLhs.Count.ToString() + " vs " + customMetadataRhs.Count.ToString() + ")";
                Log.LogMessageFromResources("InvalidType", msg);
                return false;
            }

            foreach(var metaData in customMetadataLhs)
            {
                // ignore PackageName metadata, it is already filtered out
                if (string.Compare(metaData.Key, "PackageName") == 0)
                    continue;

                string valueRhs;
                if (!customMetadataRhs.TryGetValue(metaData.Key, out valueRhs))
                {
                    string msg = "files " + lhs.ItemSpec + " and " + rhs.ItemSpec +
                        " to be compiled together but they will not be because the second file misses the metadata " +
                        metaData.Key;
                    Log.LogMessageFromResources("InvalidType", msg);
                    return false;
                }

                if (string.Compare(metaData.Value,
                                   valueRhs,
                                   StringComparison.OrdinalIgnoreCase) != 0)
                {
                    string msg = "files " + lhs.ItemSpec + " and " + rhs.ItemSpec +
                        " to be compiled together but they will not be because their metadata value " +
                        metaData.Key + " differs " +
                        "(" + metaData.Value + " vs " + valueRhs + ")";
                    Log.LogMessageFromResources("InvalidType", msg);
                    return false;
                }
            }
            return true;
        }

        protected bool CanTaskItemsBeCompiledSeparately(ITaskItem lhs, ITaskItem rhs)
        {
            // task items can be compiled separately if they do not write to the same object file
            var objFileLhs = lhs.GetMetadata("ObjectFileName");
            var objFileRhs = rhs.GetMetadata("ObjectFileName");
            if (!string.IsNullOrEmpty(objFileLhs) && !string.IsNullOrEmpty(objFileRhs))
            {
                if (string.Compare(objFileLhs, objFileRhs, StringComparison.OrdinalIgnoreCase) == 0)
                {
                    string msg = "different object file names for files " +
                        lhs.ItemSpec + " and " + rhs.ItemSpec +
                        " as they will be compiled separately (problematic object file name is " +
                        objFileLhs + ")";
                    Log.LogErrorWithCodeFromResources("InvalidType", msg);
                    return false;
                }
            }
            return true;
        }

        protected void ComputeOutOfDateSourcesPerPackage()
        {
            // backup sources compiled
            var srcsCompiled = new List<ITaskItem>();
            if (SourcesCompiled != null)
                srcsCompiled.AddRange(SourcesCompiled);

            foreach (var package in tasksPerPackage)
            {
                foreach (var taskItems in package.Value)
                {
                    trackedInputFiles = taskItems.ToArray();
                    ComputeOutOfDateSources();
                    if (SourcesCompiled != null)
                        srcsCompiled.AddRange(SourcesCompiled);
                }
            }
            SourcesCompiled = srcsCompiled.ToArray();
            trackedInputFiles = null;
        }

        private TrackedVCToolTaskInterfaceHelper CreateTask(Type taskType,
                                                            List<ITaskItem> taskItems,
                                                            string currentDirectory,
                                                            string[] environmentVariables)
        {
            var interfaceHelper = new TrackedVCToolTaskInterfaceHelper(Activator.CreateInstance(taskType), taskType);
            PopulateTaskFromSourceItems(taskType, taskItems, interfaceHelper);
            SetTaskDefaults(interfaceHelper);
            interfaceHelper.EffectiveWorkingDirectory = currentDirectory;
            interfaceHelper.EnvironmentVariables = environmentVariables;
            interfaceHelper.PostBuildTrackingCleanup = false;
            return interfaceHelper;
        }

        private string GenerateCommandLine(TrackedVCToolTaskInterfaceHelper task,
                                           ref System.Text.StringBuilder strBuilder,
                                           List<ITaskItem> taskItems,
                                           string currentDirectory)
        {
            var interfaceHelper2 = task; // is this needed?

            var cmdLineWithoutSwitches = interfaceHelper2.GenerateCommandLineExceptSwitches(new string[1]
                    { SourcesPropertyName }, CommandLineFormat.ForTracking, EscapeFormat.Default);

            strBuilder.Clear();
            foreach (var item in taskItems)
            {
                strBuilder.Append(Path.Combine(currentDirectory, item.ItemSpec).ToUpperInvariant());
                strBuilder.Append(" ");
            }

            string cmdLine = interfaceHelper2.ApplyPrecompareCommandFilter(cmdLineWithoutSwitches) +
                " " + strBuilder.ToString();

            return cmdLine;
        }

        private bool UpdateDependencies(bool toBeCompiled,
                                        ref Dictionary<string, MultiToolTaskWorkItem> workItems,
                                        string sources,
                                        string multiToolTaskDep)
        {
            if (toBeCompiled)
            {
                var enumerator = workItems.Values.GetEnumerator();
                try
                {
                    while (enumerator.MoveNext())
                    {
                        var current = enumerator.Current;
                        if (!current.ShouldAdd && current.Dependency == sources)
                        {
                            current.ShouldAdd = true;
                        }
                    }
                }
                finally { ((IDisposable)enumerator).Dispose(); }
            }

            MultiToolTaskWorkItem workItem = default(MultiToolTaskWorkItem);
            if (!toBeCompiled &&
                workItems.TryGetValue(multiToolTaskDep, out workItem) &&
                workItem.ShouldAdd)
            {
                toBeCompiled = true;
            }
            return toBeCompiled;
        }

        private void CheckCommandLineOutOfDate(bool minimalRebuldFromTracking,
                                               List<ITaskItem> taskItems,
                                               string sources,
                                               TrackedVCToolTaskInterfaceHelper task,
                                               string cmdLine,
                                               ref bool toBeCompiled,
                                               ref bool outOfDateCommandLine)
        {
            if ((SourcesCompiled != null && minimalRebuldFromTracking) &&
                SourcesCompiled.Intersect(taskItems.ToArray()).Count() != taskItems.Count)
            {
                string existingCmdLine = null;
                sourcesToCommandLines.TryGetValue(sources, out existingCmdLine);
                if (existingCmdLine != null)
                {
                    existingCmdLine = task.ApplyPrecompareCommandFilter(existingCmdLine);
                }
                if (existingCmdLine == null || !cmdLine.Equals(existingCmdLine, StringComparison.Ordinal))
                {
                    if (existingCmdLine != null && SchedulerVerbose)
                    {
                        Log.LogMessageFromResources("MultiTool.SourceNotMatchCommand", sources);
                    }
                    sourcesToCommandLines[sources] = cmdLine;
                    toBeCompiled = true;
                    outOfDateCommandLine = true;
                }
            }
            else
            {
                if (SchedulerVerbose)
                {
                    Log.LogMessageFromResources("MultiTool.SourceOutOfDate", sources);
                }
                sourcesToCommandLines[sources] = cmdLine;
                toBeCompiled = true;
            }
        }

        protected bool PrepareWorkItems(Type taskType,
                                        string[] environmentVariables,
                                        ref Dictionary<string, MultiToolTaskWorkItem> workItems)
        {
            string currentDirectory = Environment.CurrentDirectory;
            var strBuilder = new StringBuilder();

            foreach(var package in tasksPerPackage)
            {
                foreach(var taskItems in package.Value)
                {
                    if (taskItems.Count > 0)
                    {
                        var task = CreateTask(taskType, taskItems, currentDirectory, environmentVariables);
                        var cmdLine = GenerateCommandLine(task, ref strBuilder, taskItems, currentDirectory);

                        bool toBeCompiled = false;
                        bool outOfDateCommandLine = false;
                        string sources = FileTracker.FormatRootingMarker(taskItems.ToArray(), null);
                        bool minimalRebuldFromTracking = true;
                        if (!bool.TryParse(taskItems[0].GetMetadata("MinimalRebuildFromTracking"), out minimalRebuldFromTracking))
                        {
                            minimalRebuldFromTracking = true;
                        }

                        CheckCommandLineOutOfDate(minimalRebuldFromTracking, taskItems, sources, task,
                                                  cmdLine, ref toBeCompiled, ref outOfDateCommandLine);

                        string multiToolTaskDep = taskItems[0].GetMetadata("MultiToolTaskDependency");
                        // Update dependencies of the existing work items
                        toBeCompiled = UpdateDependencies(toBeCompiled, ref workItems, sources, multiToolTaskDep);

                        // Create WorkItem
                        var workItemToAdd = new MultiToolTaskWorkItem
                        {
                            Sourcekey = sources,
                            Dependency = multiToolTaskDep,
                            ShouldAdd = toBeCompiled,
                            Task = task,
                            OutOfDateCommandLine = outOfDateCommandLine
                        };
                        workItems.Add(sources, workItemToAdd);
                        if (cts.IsCancellationRequested)
                            return false;
                    }
                }
            }
            return true;
        }

        protected void InitializeTaskScheduler()
        {
            int processorCount = 0;
            if (!string.IsNullOrEmpty(SemaphoreProcCount) &&
                int.TryParse(SemaphoreProcCount, out processorCount))
            {
                var taskDependencySchedulerSetting = default(TaskDependencyScheduler.TaskDependencySchedulerSetting);
                taskDependencySchedulerSetting.ThreadingModel = "MultipleProcessor";
                taskDependencySchedulerSetting.SemaphoreName = "VC++Semaphore";
                taskDependencySchedulerSetting.ProcessorCount = processorCount;
                taskScheduler = new TaskDependencyScheduler(taskDependencySchedulerSetting);
            }
            else
            {
                taskScheduler = new TaskDependencyScheduler();
            }
        }

        protected string[] PrepareEnvironmentVariables()
        {
            var envVars = new List<string>();
            envVars.Add("TRACKER_ADDPIDTOTOOLCHAIN=1");
            foreach(var envVarName in EnvironmentVariablesToSet)
            {
                var envVarValue = Environment.GetEnvironmentVariable(envVarName);
                if (!string.IsNullOrEmpty(envVarValue))
                {
                    envVars.Add(envVarName + "=" + envVarValue);
                }
            }
            return envVars.ToArray();
        }

        protected void AddWorkItemsToTaskScheduler(Dictionary<string, MultiToolTaskWorkItem> workItems)
        {
            var enumerator = workItems.Values.GetEnumerator();
            try
            {
                while (enumerator.MoveNext())
                {
                    var current = enumerator.Current;
                    if (current.ShouldAdd)
                    {
                        taskScheduler.Add(current.Sourcekey, current.Task, current.Dependency);
                        if (SchedulerVerbose)
                        {
                            if (string.IsNullOrEmpty(current.Dependency))
                            {
                                Log.LogMessageFromResources("MultiTool.AddSource", current.Sourcekey);
                            }
                            else
                            {
                                Log.LogMessageFromResources("MultiTool.AddSourceWithDep",
                                                            current.Sourcekey, current.Dependency);
                            }
                        }
                    }
                }
            }
            finally
            {
                ((IDisposable)enumerator).Dispose();
            }
        }

        protected void UpdateSourcesCompiled(Dictionary<string, MultiToolTaskWorkItem> workItems)
        {
            if (workItems.Any((KeyValuePair<string, MultiToolTaskWorkItem> p) => p.Value.OutOfDateCommandLine))
            {
                var srcCompiled = new List<ITaskItem>(SourcesCompiled);
                foreach(var item in from p in workItems where p.Value.OutOfDateCommandLine select p)
                {
                    srcCompiled.Add(new TaskItem(item.Value.Sourcekey));
                }
                SourcesCompiled = srcCompiled.ToArray();
            }
        }

        protected int ProcessTasks()
        {
            int errCode = -1;
            if (taskScheduler.Count > 0)
            {
                string readTLogFName = TaskName + ".read.1.tlog";
                string writeTLogFName = TaskName + ".write.1.tlog";
                string readTLog = Path.Combine(TrackerIntermediateDirectory, readTLogFName);
                string writeTLog = Path.Combine(TrackerIntermediateDirectory, writeTLogFName);
                if (!File.Exists(readTLog))
                {
                    using (File.Create(readTLog)) { }
                }
                if (!File.Exists(writeTLog))
                {
                    using (File.Create(writeTLog)) { }
                }

                try
                {
                    BuildEngine3.Yield();
                    if (taskScheduler.Run(cts, Log, SchedulerVerbose))
                    {
                        errCode = 0;
                    }
                }
                finally
                {
                    BuildEngine3.Reacquire();

                }
                if (!cts.IsCancellationRequested)
                {
                    _FinishBuild(0);
                }
            }
            else
            {
                errCode = 0;
            }
            return errCode;
        }

        protected int PopulateTaskFromSourceItems(Type taskType, List<ITaskItem> sources,
                                                  TrackedVCToolTaskInterfaceHelper schedulingTask)
        {
            int propertiesSet = 0;
            PropertyInfo[] properties = taskType.GetProperties();
            foreach(var propertyInfo in properties)
            {
                string propertyName = propertyInfo.Name;
                if (!string.IsNullOrEmpty(propertyName))
                {
                    if (string.Compare(schedulingTask.SourcesPropertyName,
                                       propertyName,
                                       StringComparison.OrdinalIgnoreCase) == 0)
                    {
                        if (propertyInfo.PropertyType == typeof(ITaskItem))
                        {
                            if (sources.Count == 1)
                            {
                                propertyInfo.SetValue(schedulingTask.Instance, sources[0]);
                            }
                            else
                            {
                                throw new InvalidCastException("Unable to cast " + 
                                    propertyInfo.PropertyType.ToString() +
                                    " to ITaskItem[].");
                            }
                        }
                        else if (propertyInfo.PropertyType == typeof(ITaskItem[]))
                        {
                            propertyInfo.SetValue(schedulingTask.Instance, sources.ToArray());
                        }
                        ++propertiesSet;
                    }
                    else
                    {
                        string metadata = sources[0].GetMetadata(propertyName);
                        if (!string.IsNullOrEmpty(metadata))
                        {
                            if (propertyInfo.PropertyType == typeof(bool))
                            {
                                propertyInfo.SetValue(schedulingTask.Instance, bool.Parse(metadata));
                            }
                            else if (propertyInfo.PropertyType == typeof(int))
                            {
                                propertyInfo.SetValue(schedulingTask.Instance, int.Parse(metadata));
                            }
                            else if(propertyInfo.PropertyType == typeof(string))
                            {
                                propertyInfo.SetValue(schedulingTask.Instance, metadata);
                            }
                            else if(propertyInfo.PropertyType == typeof(string[]))
                            {
                                string[] stringArrayValue = (from v
                                                             in metadata.Split(StringArraySplitter,
                                                                               StringSplitOptions.RemoveEmptyEntries)
                                                             select v.Trim())
                                                             .ToArray();
                                propertyInfo.SetValue(schedulingTask.Instance, stringArrayValue);
                            }
                            else
                            {
                                throw new InvalidCastException("Unable to cast " + 
                                    propertyInfo.PropertyType.ToString() +
                                    " to bool, int, string or string[].");
                            }
                            ++propertiesSet;
                        }
                    }
                }
                else
                {
                    continue;
                }
            }
            return propertiesSet;
        }

        public override void Cancel()
        {
            cts.Cancel();
            _FinishBuild(0);
        }

        static string _FormatRootingMarker(string sources)
        {
            string[] splitSources = sources.Split('|');
            List<string> stringList = new List<string>(splitSources.Length);
            foreach (string source in splitSources)
                stringList.Add(Path.GetFullPath(source).ToUpperInvariant());
            stringList.Sort((IComparer<string>)StringComparer.OrdinalIgnoreCase);
            return string.Join("|", (IEnumerable<string>)stringList);
        }

        // to replace super.FinishBuild
        protected int _FinishBuild(int exitCode)
        {
            if (PostBuildTrackingCleanup)
                exitCode = PostExecuteTool(exitCode);
            if (sourcesToCommandLines != null)
            {
                foreach (var allTask in taskScheduler.GetAllTasks())
                    // original causes PathTooLongException for long list of files used as ITaskItem.itemSpec
                    //sourcesToCommandLines.Remove(FileTracker.FormatRootingMarker((ITaskItem)new TaskItem(allTask.Key)));
                    sourcesToCommandLines.Remove(_FormatRootingMarker(allTask.Key));
                WriteSourcesToCommandLinesTable(sourcesToCommandLines);
            }
            return exitCode;
        }

        protected override int PostExecuteTool(int exitCode)
        {
            // need to call PostExecuteTool per package
            // backup sources compiled
            var srcsCompiled = new List<ITaskItem>();
            if (SourcesCompiled != null)
                srcsCompiled.AddRange(SourcesCompiled);

            foreach (var package in tasksPerPackage)
            {
                foreach (var taskItems in package.Value)
                {
                    SourcesCompiled = Enumerable.Intersect(srcsCompiled, taskItems).ToArray();
                    trackedInputFiles = taskItems.ToArray();
                    exitCode = base.PostExecuteTool(exitCode);
                }
            }
            // restore
            trackedInputFiles = null;
            SourcesCompiled = srcsCompiled.ToArray();
            return exitCode;
        }
    }
}

#endif //TOOLS_V14 || TOOLS_V15