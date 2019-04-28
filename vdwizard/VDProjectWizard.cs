using System;
using System.Collections.Generic;
using EnvDTE;
using Microsoft.VisualStudio.TemplateWizard;
using System.Windows.Forms;
using VisualDWizard;
using System.Drawing;

namespace VisualDWizard
{
    abstract public class ProjectWizard : IWizard
    {
        private DTE _dte;

        protected WizardDialog dlg;
        protected bool isVDProject;
        protected string _solutionDir;
        protected string _templateDir;

        public void BeforeOpeningFile(ProjectItem projectItem) { }
        public void ProjectItemFinishedGenerating(ProjectItem projectItem) { }
        public void RunFinished() { }

        public abstract void beforeOpenDialog();

        public void RunStarted(object automationObject, Dictionary<string, string> replacementsDictionary, WizardRunKind runKind, object[] customParams)
        {
            _dte = (DTE)automationObject;

            /* The solution directory will be this directories parent
               when the Type attribute of the VSTemplate element is ProjectGroup */
            _solutionDir = System.IO.Path.GetDirectoryName(replacementsDictionary["$destinationdirectory$"]);

            // customParams[0] is a default custom param that contains the physical location of the template that is currently being applied
            _templateDir = System.IO.Path.GetDirectoryName(customParams[0] as string);

            // Display a form to the user. The form collects   
            // input for the custom message.  
            dlg = new WizardDialog();
            beforeOpenDialog();
            var res = dlg.ShowDialog();
            if (res == DialogResult.Cancel)
                throw new WizardBackoutException();
            if (res != DialogResult.OK)
                throw new WizardCancelledException();

            bool mainInCpp = dlg.mainInCpp.Checked && dlg.prjTypeConsole.Checked;
            // for vcxproj
            if (dlg.prjTypeWindows.Checked)
            {
                replacementsDictionary.Add("$subsystem$", "Windows"); // for vcxproj
                replacementsDictionary.Add("$subsys$", "2"); // for visualdproj
            }
            else
            {
                replacementsDictionary.Add("$subsystem$", "Console");
                replacementsDictionary.Add("$subsys$", "1");
            }

            if (dlg.prjTypeDLL.Checked)
            {
                replacementsDictionary.Add("$apptype$", "DynamicLibrary"); // for main.d
                replacementsDictionary.Add("$configtype$", "DynamicLibrary"); // for vcxproj
                replacementsDictionary.Add("$outputtype$", "2"); // for visualdproj
                replacementsDictionary.Add("$outputext$", "dll");
            }
            else if (dlg.prjTypeLib.Checked)
            {
                replacementsDictionary.Add("$apptype$", "StaticLibrary");
                replacementsDictionary.Add("$configtype$", "StaticLibrary");
                replacementsDictionary.Add("$outputtype$", "1");
                replacementsDictionary.Add("$outputext$", "lib");
            }
            else
            {
                string app = dlg.prjTypeWindows.Checked ? "WindowsApp" : 
                             mainInCpp ? "ConsoleAppMainInCpp" : "ConsoleApp";
                replacementsDictionary.Add("$apptype$", app);
                replacementsDictionary.Add("$configtype$", "Application");
                replacementsDictionary.Add("$outputtype$", "0");
                replacementsDictionary.Add("$outputext$", "exe");
            }

            replacementsDictionary.Add("$mainInCpp$", mainInCpp ? "1" : "0");
            replacementsDictionary.Add("$addStdafxH$", dlg.precompiledHeaders.Checked || mainInCpp ? "1" : "0");
            replacementsDictionary.Add("$addStdafxCpp$", dlg.precompiledHeaders.Checked ? "1" : "0");
            replacementsDictionary.Add("$PrecompiledHeader$", dlg.precompiledHeaders.Checked ? "Use" : "NotUsing");

            replacementsDictionary.Add("$x86mscoff$", dlg.platformx86OMF.Checked ? "0" : "1");

            int numCompiler = 0;
            if (dlg.compilerDMD.Checked)
                numCompiler++;
            if (dlg.compilerLDC.Checked)
                numCompiler++;
            if (dlg.compilerGDC.Checked)
                numCompiler++;

            if (numCompiler <= 1)
            {
                int compiler = dlg.compilerLDC.Checked ? 2 : dlg.compilerGDC.Checked ? 1 : 0;
                AddConfigReplacements(replacementsDictionary, 1, compiler, "");
            }
            else
            {
                numCompiler = 0;
                if (dlg.compilerDMD.Checked)
                    AddConfigReplacements(replacementsDictionary, ++numCompiler, 0, " DMD");
                if (dlg.compilerLDC.Checked)
                    AddConfigReplacements(replacementsDictionary, ++numCompiler, 2, " LDC");
                if (dlg.compilerGDC.Checked)
                    AddConfigReplacements(replacementsDictionary, ++numCompiler, 1, " GDC");
            }

            while (numCompiler++ <= 3)
            {
                string idxs = numCompiler.ToString();
                replacementsDictionary.Add("$platformx86_" + idxs + "$", "0");
                replacementsDictionary.Add("$platformx64_" + idxs + "$", "0");
            }
        }

        public bool ShouldAddProjectItem(string filePath) { return true; }

        static string[] compilerName = { "DMD", "GDC", "LDC" };

        public void AddConfigReplacements(Dictionary<string, string> replacementsDictionary, int idx, int compiler, string suffix)
        {
            string idxs = idx.ToString();
            replacementsDictionary.Add("$dcompiler_" + idxs + "$", compiler.ToString());
            replacementsDictionary.Add("$dcompilername_" + idxs + "$", compilerName[compiler]);

            // VS expects "Debug" configuration in .vcxproj, otherwise it doesn't show 
            //  project files before reload
            if (!dlg.platformx86OMF.Visible && idx == 1)
                suffix = "";
            replacementsDictionary.Add("$configsuffix_" + idxs + "$", suffix);

            replacementsDictionary.Add("$platformx86_" + idxs + "$", dlg.platformX86.Checked ? "1" : "0");
            replacementsDictionary.Add("$platformx64_" + idxs + "$", dlg.platformX64.Checked ? "1" : "0");
        }

        public void CopyToProject(Project project, string fname)
        {
            string projectDir = System.IO.Path.GetDirectoryName(project.FileName);
            string srcFile = System.IO.Path.Combine(_templateDir, fname);
            string destFile = System.IO.Path.Combine(projectDir, fname);
            System.IO.File.Copy(srcFile, destFile);
            //return project.ProjectItems.AddFromFile(fname);
        }

        public void ProjectFinishedGenerating(Project project)
        {
            bool mainInCpp = dlg.mainInCpp.Checked && dlg.prjTypeConsole.Checked;
            if (mainInCpp)
                CopyToProject(project, "main.cpp");
            if (mainInCpp || dlg.precompiledHeaders.Checked)
                CopyToProject(project, "stdafx.h");
            if (dlg.precompiledHeaders.Checked)
                CopyToProject(project, "stdafx.cpp");
        }

    }

    public class VDProjectWizard : ProjectWizard
    {
        public override void beforeOpenDialog()
        {
            dlg.pictureBox1.Image = new Bitmap(VisualDWizard.Properties.Resources.vd_logo);
            dlg.label2.Text = "This project will use Visual D\'s custom project type designed";
            dlg.label3.Text = "for the D programming language.";
            dlg.cppOptionsGroup.Visible = false;
        }
    }

    public class VCProjectWizard : ProjectWizard
    {
        public override void beforeOpenDialog()
        {
            dlg.compilerGDC.Enabled = false;
            dlg.compilerGDC.Visible = false;
            dlg.platformx86OMF.Visible = false;
        }
    }
}
