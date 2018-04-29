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

        protected WizardDialog inputForm;
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
            inputForm = new WizardDialog();
            beforeOpenDialog();
            var res = inputForm.ShowDialog();
            if (res == DialogResult.Cancel)
                throw new WizardBackoutException();
            if (res != DialogResult.OK)
                throw new WizardCancelledException();

            if (inputForm.prjTypeConsole.Checked)
                replacementsDictionary.Add("$subsystem$", "Console");
            else if (inputForm.prjTypeWindows.Checked)
                replacementsDictionary.Add("$subsystem$", "Windows");
            else if (inputForm.prjTypeDLL.Checked)
                replacementsDictionary.Add("$subsystem$", "DynamicLibrary");
            else if (inputForm.prjTypeLib.Checked)
                replacementsDictionary.Add("$subsystem$", "StaticLibrary");

            replacementsDictionary.Add("$platformx86$", inputForm.platformX86.Checked ? "1" : "0");
            replacementsDictionary.Add("$platformx64$", inputForm.platformX64.Checked ? "1" : "0");
            replacementsDictionary.Add("$x86mscoff$", inputForm.platformx86OMF.Checked ? "0" : "1");

            AddConfigReplacements(replacementsDictionary);
        }

        public bool ShouldAddProjectItem(string filePath) { return true; }

        public void AddConfigReplacements(Dictionary<string, string> replacementsDictionary)
        {
            int numCompiler = 0;
            int selectCompiler = 0;
            if (inputForm.compilerDMD.Checked)
            {
                numCompiler++;
                selectCompiler += 1;
                replacementsDictionary.Add("$dcompiler" + numCompiler.ToString() + "$", "DMD");
            }
            if (inputForm.compilerLDC.Checked)
            {
                numCompiler++;
                selectCompiler += 2;
                replacementsDictionary.Add("$dcompiler" + numCompiler.ToString() + "$", "LDC");
            }
            if (inputForm.compilerGDC.Checked)
            {
                numCompiler++;
                selectCompiler += 4;
                replacementsDictionary.Add("$dcompiler" + numCompiler.ToString() + "$", "GDC");
            }

            replacementsDictionary.Add("$numCompiler$", numCompiler.ToString());
            if (numCompiler <= 1)
            {
                // only one selected
                replacementsDictionary.Add("$configsuffix1$", "");
                replacementsDictionary.Add("$configsuffix2$", "");
                replacementsDictionary.Add("$configsuffix3$", "");
            }
            else
            {
                int testCompiler = 0;
                if ((selectCompiler & (1 << testCompiler++)) != 0)
                    replacementsDictionary.Add("$configsuffix1$", " DMD");
                else if ((selectCompiler & (1 << testCompiler++)) != 0)
                    replacementsDictionary.Add("$configsuffix1$", " LDC");
                else if ((selectCompiler & (1 << testCompiler++)) != 0)
                    replacementsDictionary.Add("$configsuffix1$", " GDC");

                if ((selectCompiler & (1 << testCompiler++)) != 0)
                    replacementsDictionary.Add("$configsuffix2$", testCompiler == 2 ? " LDC" : " GDC");
                else if ((selectCompiler & (1 << testCompiler++)) != 0)
                    replacementsDictionary.Add("$configsuffix2$", " GDC");
                else
                    replacementsDictionary.Add("$configsuffix2$", "");

                if ((selectCompiler & (1 << testCompiler++)) != 0)
                    replacementsDictionary.Add("$configsuffix3$", " GDC");
                else
                    replacementsDictionary.Add("$configsuffix3$", "");
            }

        }
    }

    public class VDProjectWizard : ProjectWizard
    {
        public override void beforeOpenDialog()
        {
            inputForm.pictureBox1.Image = new Bitmap(VisualDWizard.Properties.Resources.vd_logo);
        }
    }

    public class VCProjectWizard : ProjectWizard
    {
        public override void beforeOpenDialog()
        {
            inputForm.compilerGDC.Enabled = false;
            inputForm.compilerGDC.Visible = false;
            inputForm.platformx86OMF.Visible = false;
        }
    }
}
