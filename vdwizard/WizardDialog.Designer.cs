namespace VisualDWizard
{
    partial class WizardDialog
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(WizardDialog));
            this.panel1 = new System.Windows.Forms.Panel();
            this.pictureBox1 = new System.Windows.Forms.PictureBox();
            this.label3 = new System.Windows.Forms.Label();
            this.label2 = new System.Windows.Forms.Label();
            this.label1 = new System.Windows.Forms.Label();
            this.prjTypeConsole = new System.Windows.Forms.RadioButton();
            this.prjTypeWindows = new System.Windows.Forms.RadioButton();
            this.prjTypeDLL = new System.Windows.Forms.RadioButton();
            this.groupBox1 = new System.Windows.Forms.GroupBox();
            this.prjTypeLib = new System.Windows.Forms.RadioButton();
            this.groupBox2 = new System.Windows.Forms.GroupBox();
            this.compilerGDC = new System.Windows.Forms.CheckBox();
            this.compilerLDC = new System.Windows.Forms.CheckBox();
            this.compilerDMD = new System.Windows.Forms.CheckBox();
            this.addUnittest = new System.Windows.Forms.CheckBox();
            this.button1 = new System.Windows.Forms.Button();
            this.button2 = new System.Windows.Forms.Button();
            this.groupBox3 = new System.Windows.Forms.GroupBox();
            this.platformx86OMF = new System.Windows.Forms.CheckBox();
            this.platformX64 = new System.Windows.Forms.CheckBox();
            this.platformX86 = new System.Windows.Forms.CheckBox();
            this.button3 = new System.Windows.Forms.Button();
            this.Warning1 = new System.Windows.Forms.Label();
            this.Warning2 = new System.Windows.Forms.Label();
            this.panel1.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox1)).BeginInit();
            this.groupBox1.SuspendLayout();
            this.groupBox2.SuspendLayout();
            this.groupBox3.SuspendLayout();
            this.SuspendLayout();
            // 
            // panel1
            // 
            this.panel1.BackColor = System.Drawing.SystemColors.ControlLightLight;
            this.panel1.Controls.Add(this.pictureBox1);
            this.panel1.Controls.Add(this.label3);
            this.panel1.Controls.Add(this.label2);
            this.panel1.Controls.Add(this.label1);
            this.panel1.Location = new System.Drawing.Point(6, 5);
            this.panel1.Name = "panel1";
            this.panel1.Size = new System.Drawing.Size(515, 113);
            this.panel1.TabIndex = 0;
            // 
            // pictureBox1
            // 
            this.pictureBox1.Image = ((System.Drawing.Image)(resources.GetObject("pictureBox1.Image")));
            this.pictureBox1.Location = new System.Drawing.Point(8, 12);
            this.pictureBox1.Name = "pictureBox1";
            this.pictureBox1.Size = new System.Drawing.Size(81, 82);
            this.pictureBox1.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            this.pictureBox1.TabIndex = 3;
            this.pictureBox1.TabStop = false;
            // 
            // label3
            // 
            this.label3.AutoSize = true;
            this.label3.Location = new System.Drawing.Point(107, 76);
            this.label3.Name = "label3";
            this.label3.Size = new System.Drawing.Size(234, 13);
            this.label3.TabIndex = 2;
            this.label3.Text = "D and C/C++ files to coexist in the same project.";
            // 
            // label2
            // 
            this.label2.AutoSize = true;
            this.label2.Location = new System.Drawing.Point(107, 60);
            this.label2.Name = "label2";
            this.label2.Size = new System.Drawing.Size(332, 13);
            this.label2.TabIndex = 1;
            this.label2.Text = "This project will be based on Visual C++ .vcxproj files that allows both";
            // 
            // label1
            // 
            this.label1.AutoSize = true;
            this.label1.Font = new System.Drawing.Font("Microsoft Sans Serif", 11.25F, System.Drawing.FontStyle.Bold, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.label1.Location = new System.Drawing.Point(107, 26);
            this.label1.Name = "label1";
            this.label1.Size = new System.Drawing.Size(261, 18);
            this.label1.TabIndex = 0;
            this.label1.Text = "Welcome to the D Project Wizard";
            // 
            // prjTypeConsole
            // 
            this.prjTypeConsole.AutoSize = true;
            this.prjTypeConsole.Location = new System.Drawing.Point(24, 28);
            this.prjTypeConsole.Name = "prjTypeConsole";
            this.prjTypeConsole.Size = new System.Drawing.Size(118, 17);
            this.prjTypeConsole.TabIndex = 1;
            this.prjTypeConsole.TabStop = true;
            this.prjTypeConsole.Text = "Console Application";
            this.prjTypeConsole.UseVisualStyleBackColor = true;
            // 
            // prjTypeWindows
            // 
            this.prjTypeWindows.AutoSize = true;
            this.prjTypeWindows.Location = new System.Drawing.Point(24, 51);
            this.prjTypeWindows.Name = "prjTypeWindows";
            this.prjTypeWindows.Size = new System.Drawing.Size(124, 17);
            this.prjTypeWindows.TabIndex = 2;
            this.prjTypeWindows.TabStop = true;
            this.prjTypeWindows.Text = "Windows Application";
            this.prjTypeWindows.UseVisualStyleBackColor = true;
            // 
            // prjTypeDLL
            // 
            this.prjTypeDLL.AutoSize = true;
            this.prjTypeDLL.Location = new System.Drawing.Point(24, 74);
            this.prjTypeDLL.Name = "prjTypeDLL";
            this.prjTypeDLL.Size = new System.Drawing.Size(129, 17);
            this.prjTypeDLL.TabIndex = 3;
            this.prjTypeDLL.TabStop = true;
            this.prjTypeDLL.Text = "Dynamic Library (DLL)";
            this.prjTypeDLL.UseVisualStyleBackColor = true;
            // 
            // groupBox1
            // 
            this.groupBox1.Controls.Add(this.prjTypeLib);
            this.groupBox1.Controls.Add(this.prjTypeConsole);
            this.groupBox1.Controls.Add(this.prjTypeDLL);
            this.groupBox1.Controls.Add(this.prjTypeWindows);
            this.groupBox1.Location = new System.Drawing.Point(12, 134);
            this.groupBox1.Name = "groupBox1";
            this.groupBox1.Size = new System.Drawing.Size(259, 138);
            this.groupBox1.TabIndex = 5;
            this.groupBox1.TabStop = false;
            this.groupBox1.Text = "Project Type";
            // 
            // prjTypeLib
            // 
            this.prjTypeLib.AutoSize = true;
            this.prjTypeLib.Location = new System.Drawing.Point(24, 97);
            this.prjTypeLib.Name = "prjTypeLib";
            this.prjTypeLib.Size = new System.Drawing.Size(111, 17);
            this.prjTypeLib.TabIndex = 4;
            this.prjTypeLib.TabStop = true;
            this.prjTypeLib.Text = "Static Library (LIB)";
            this.prjTypeLib.UseVisualStyleBackColor = true;
            // 
            // groupBox2
            // 
            this.groupBox2.Controls.Add(this.compilerGDC);
            this.groupBox2.Controls.Add(this.compilerLDC);
            this.groupBox2.Controls.Add(this.compilerDMD);
            this.groupBox2.Location = new System.Drawing.Point(277, 134);
            this.groupBox2.Name = "groupBox2";
            this.groupBox2.Size = new System.Drawing.Size(241, 138);
            this.groupBox2.TabIndex = 6;
            this.groupBox2.TabStop = false;
            this.groupBox2.Text = "Compiler Configurations";
            // 
            // compilerGDC
            // 
            this.compilerGDC.AutoSize = true;
            this.compilerGDC.Location = new System.Drawing.Point(24, 75);
            this.compilerGDC.Name = "compilerGDC";
            this.compilerGDC.Size = new System.Drawing.Size(161, 17);
            this.compilerGDC.TabIndex = 10;
            this.compilerGDC.Text = "GDC (gcc based D compiler)";
            this.compilerGDC.UseVisualStyleBackColor = true;
            this.compilerGDC.CheckedChanged += new System.EventHandler(this.compiler_CheckedChanged);
            // 
            // compilerLDC
            // 
            this.compilerLDC.AutoSize = true;
            this.compilerLDC.Location = new System.Drawing.Point(24, 51);
            this.compilerLDC.Name = "compilerLDC";
            this.compilerLDC.Size = new System.Drawing.Size(169, 17);
            this.compilerLDC.TabIndex = 9;
            this.compilerLDC.Text = "LDC (LLVM based D compiler)";
            this.compilerLDC.UseVisualStyleBackColor = true;
            this.compilerLDC.CheckedChanged += new System.EventHandler(this.compiler_CheckedChanged);
            // 
            // compilerDMD
            // 
            this.compilerDMD.AutoSize = true;
            this.compilerDMD.Location = new System.Drawing.Point(24, 28);
            this.compilerDMD.Name = "compilerDMD";
            this.compilerDMD.Size = new System.Drawing.Size(158, 17);
            this.compilerDMD.TabIndex = 8;
            this.compilerDMD.Text = "DMD (reference D compiler)";
            this.compilerDMD.UseVisualStyleBackColor = true;
            this.compilerDMD.CheckedChanged += new System.EventHandler(this.compiler_CheckedChanged);
            // 
            // addUnittest
            // 
            this.addUnittest.AutoSize = true;
            this.addUnittest.Location = new System.Drawing.Point(36, 341);
            this.addUnittest.Name = "addUnittest";
            this.addUnittest.Size = new System.Drawing.Size(145, 17);
            this.addUnittest.TabIndex = 11;
            this.addUnittest.Text = "add unittest configuration";
            this.addUnittest.UseVisualStyleBackColor = true;
            // 
            // button1
            // 
            this.button1.DialogResult = System.Windows.Forms.DialogResult.Abort;
            this.button1.Location = new System.Drawing.Point(443, 353);
            this.button1.Name = "button1";
            this.button1.Size = new System.Drawing.Size(75, 23);
            this.button1.TabIndex = 14;
            this.button1.Text = "Cancel";
            this.button1.UseVisualStyleBackColor = true;
            // 
            // button2
            // 
            this.button2.DialogResult = System.Windows.Forms.DialogResult.OK;
            this.button2.Location = new System.Drawing.Point(362, 353);
            this.button2.Name = "button2";
            this.button2.Size = new System.Drawing.Size(75, 23);
            this.button2.TabIndex = 13;
            this.button2.Text = "Finish";
            this.button2.UseVisualStyleBackColor = true;
            // 
            // groupBox3
            // 
            this.groupBox3.Controls.Add(this.platformx86OMF);
            this.groupBox3.Controls.Add(this.platformX64);
            this.groupBox3.Controls.Add(this.platformX86);
            this.groupBox3.Location = new System.Drawing.Point(14, 278);
            this.groupBox3.Name = "groupBox3";
            this.groupBox3.Size = new System.Drawing.Size(257, 57);
            this.groupBox3.TabIndex = 10;
            this.groupBox3.TabStop = false;
            this.groupBox3.Text = "Platforms";
            // 
            // platformx86OMF
            // 
            this.platformx86OMF.AutoSize = true;
            this.platformx86OMF.Location = new System.Drawing.Point(148, 25);
            this.platformx86OMF.Name = "platformx86OMF";
            this.platformx86OMF.Size = new System.Drawing.Size(104, 17);
            this.platformx86OMF.TabIndex = 7;
            this.platformx86OMF.Text = "use OMF for x86";
            this.platformx86OMF.UseVisualStyleBackColor = true;
            // 
            // platformX64
            // 
            this.platformX64.AutoSize = true;
            this.platformX64.Location = new System.Drawing.Point(22, 25);
            this.platformX64.Name = "platformX64";
            this.platformX64.Size = new System.Drawing.Size(43, 17);
            this.platformX64.TabIndex = 5;
            this.platformX64.Text = "x64";
            this.platformX64.UseVisualStyleBackColor = true;
            this.platformX64.CheckedChanged += new System.EventHandler(this.platform_CheckedChanged);
            // 
            // platformX86
            // 
            this.platformX86.AutoSize = true;
            this.platformX86.Location = new System.Drawing.Point(88, 25);
            this.platformX86.Name = "platformX86";
            this.platformX86.Size = new System.Drawing.Size(43, 17);
            this.platformX86.TabIndex = 6;
            this.platformX86.Text = "x86";
            this.platformX86.UseVisualStyleBackColor = true;
            this.platformX86.CheckedChanged += new System.EventHandler(this.platform_CheckedChanged);
            // 
            // button3
            // 
            this.button3.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            this.button3.Location = new System.Drawing.Point(281, 353);
            this.button3.Name = "button3";
            this.button3.Size = new System.Drawing.Size(75, 23);
            this.button3.TabIndex = 12;
            this.button3.Text = "Back...";
            this.button3.UseVisualStyleBackColor = true;
            // 
            // Warning1
            // 
            this.Warning1.AutoSize = true;
            this.Warning1.ForeColor = System.Drawing.Color.Red;
            this.Warning1.Location = new System.Drawing.Point(278, 292);
            this.Warning1.Name = "Warning1";
            this.Warning1.Size = new System.Drawing.Size(241, 13);
            this.Warning1.TabIndex = 15;
            this.Warning1.Text = "Warning: without platform x86 you need to unload";
            // 
            // Warning2
            // 
            this.Warning2.AutoSize = true;
            this.Warning2.ForeColor = System.Drawing.Color.Red;
            this.Warning2.Location = new System.Drawing.Point(286, 311);
            this.Warning2.Name = "Warning2";
            this.Warning2.Size = new System.Drawing.Size(225, 13);
            this.Warning2.TabIndex = 16;
            this.Warning2.Text = "and reload the project once to see source files";
            // 
            // WizardDialog
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(530, 383);
            this.Controls.Add(this.Warning2);
            this.Controls.Add(this.Warning1);
            this.Controls.Add(this.button3);
            this.Controls.Add(this.groupBox3);
            this.Controls.Add(this.button2);
            this.Controls.Add(this.button1);
            this.Controls.Add(this.addUnittest);
            this.Controls.Add(this.groupBox2);
            this.Controls.Add(this.groupBox1);
            this.Controls.Add(this.panel1);
            this.Name = "WizardDialog";
            this.ShowInTaskbar = false;
            this.SizeGripStyle = System.Windows.Forms.SizeGripStyle.Hide;
            this.Text = "Visual D Project Wizard";
            this.panel1.ResumeLayout(false);
            this.panel1.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pictureBox1)).EndInit();
            this.groupBox1.ResumeLayout(false);
            this.groupBox1.PerformLayout();
            this.groupBox2.ResumeLayout(false);
            this.groupBox2.PerformLayout();
            this.groupBox3.ResumeLayout(false);
            this.groupBox3.PerformLayout();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.Panel panel1;
        private System.Windows.Forms.Label label1;
        private System.Windows.Forms.GroupBox groupBox1;
        private System.Windows.Forms.GroupBox groupBox2;
        private System.Windows.Forms.Button button1;
        private System.Windows.Forms.Button button2;
        private System.Windows.Forms.GroupBox groupBox3;
        private System.Windows.Forms.Button button3;
        public System.Windows.Forms.RadioButton prjTypeConsole;
        public System.Windows.Forms.RadioButton prjTypeWindows;
        public System.Windows.Forms.RadioButton prjTypeDLL;
        public System.Windows.Forms.RadioButton prjTypeLib;
        public System.Windows.Forms.CheckBox addUnittest;
        public System.Windows.Forms.CheckBox compilerGDC;
        public System.Windows.Forms.CheckBox compilerLDC;
        public System.Windows.Forms.CheckBox compilerDMD;
        public System.Windows.Forms.CheckBox platformX64;
        public System.Windows.Forms.CheckBox platformX86;
        public System.Windows.Forms.PictureBox pictureBox1;
        public System.Windows.Forms.CheckBox platformx86OMF;
        private System.Windows.Forms.Label Warning1;
        private System.Windows.Forms.Label Warning2;
        public System.Windows.Forms.Label label2;
        public System.Windows.Forms.Label label3;
    }
}