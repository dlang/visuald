using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace VisualDWizard
{
    public partial class WizardDialog : Form
    {
        public WizardDialog()
        {
            InitializeComponent();
            platformX86.CheckState = CheckState.Checked;
            platformX64.CheckState = CheckState.Checked;
            compilerDMD.CheckState = CheckState.Checked;
            prjTypeConsole.Select();
            Warning1.Visible = false;
            Warning2.Visible = false;

            ToolTip toolTip = new ToolTip();
            toolTip.SetToolTip(platformx86OMF, "Digital Mars OMF object files, only available with DMD");
            toolTip.SetToolTip(compilerGDC, "only available with DMD");

            CenterToScreen();
        }

        private void platform_CheckedChanged(object sender, EventArgs e)
        {
            if (!platformX64.Checked && !platformX86.Checked)
                platformX64.Checked = true;
            platformx86OMF.Enabled = platformX86.Checked && compilerGDC.Enabled;
            Warning1.Visible = !platformX86.Checked && !compilerGDC.Enabled;
            Warning2.Visible = !platformX86.Checked && !compilerGDC.Enabled;
        }

        private void compiler_CheckedChanged(object sender, EventArgs e)
        {
            if (!compilerDMD.Checked && !compilerLDC.Checked && !compilerGDC.Checked)
                compilerDMD.Checked = true;
        }

        private void prjTypeConsole_CheckedChanged(object sender, EventArgs e)
        {
            mainInCpp.Enabled = prjTypeConsole.Checked;
        }
    }
}
