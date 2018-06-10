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

        public void BeforeOpeningFile(ProjectItem projectItem) { }
        public void ProjectFinishedGenerating(Project project) { }
        public void ProjectItemFinishedGenerating(ProjectItem projectItem) { }
        public void RunFinished() { }

        public abstract void beforeOpenDialog();

        public void RunStarted(object automationObject, Dictionary<string, string> replacementsDictionary, WizardRunKind runKind, object[] customParams)
        {
            _dte = (DTE)automationObject;

            // Display a form to the user. The form collects   
            // input for the custom message.  
            dlg = new WizardDialog();
            beforeOpenDialog();
            var res = dlg.ShowDialog();
            if (res == DialogResult.Cancel)
                throw new WizardBackoutException();
            if (res != DialogResult.OK)
                throw new WizardCancelledException();

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
                replacementsDictionary.Add("$apptype$", dlg.prjTypeWindows.Checked ? "WindowsApp" : "ConsoleApp");
                replacementsDictionary.Add("$configtype$", "Application");
                replacementsDictionary.Add("$outputtype$", "0");
                replacementsDictionary.Add("$outputext$", "exe");
            }


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
                    AddConfigReplacements(replacementsDictionary, ++numCompiler, 0, " LDC");
                if (dlg.compilerGDC.Checked)
                    AddConfigReplacements(replacementsDictionary, ++numCompiler, 0, " GDC");
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

            replacementsDictionary.Add("$configsuffix_" + idxs + "$", suffix);

            replacementsDictionary.Add("$platformx86_" + idxs + "$", dlg.platformX86.Checked ? "1" : "0");
            replacementsDictionary.Add("$platformx64_" + idxs + "$", dlg.platformX64.Checked ? "1" : "0");
        }
    }

    public class VDProjectWizard : ProjectWizard
    {
        public override void beforeOpenDialog()
        {
            dlg.pictureBox1.Image = new Bitmap(VisualDWizard.Properties.Resources.vd_logo);
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
