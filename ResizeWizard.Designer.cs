namespace Calypso
{
    partial class ResizeWizard
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && components != null) components.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            labelCurrent  = new System.Windows.Forms.Label();
            labelOutput   = new System.Windows.Forms.Label();
            labelW        = new System.Windows.Forms.Label();
            labelH        = new System.Windows.Forms.Label();
            nudWidth      = new System.Windows.Forms.NumericUpDown();
            nudHeight     = new System.Windows.Forms.NumericUpDown();
            btn10         = new System.Windows.Forms.Button();
            btn25         = new System.Windows.Forms.Button();
            btn50         = new System.Windows.Forms.Button();
            btn75         = new System.Windows.Forms.Button();
            btnOK         = new System.Windows.Forms.Button();
            btnCancel     = new System.Windows.Forms.Button();
            labelPresets  = new System.Windows.Forms.Label();
            trackScale    = new System.Windows.Forms.TrackBar();
            labelScale    = new System.Windows.Forms.Label();

            ((System.ComponentModel.ISupportInitialize)nudWidth).BeginInit();
            ((System.ComponentModel.ISupportInitialize)nudHeight).BeginInit();
            ((System.ComponentModel.ISupportInitialize)trackScale).BeginInit();
            SuspendLayout();

            // labelCurrent
            labelCurrent.AutoSize = true;
            labelCurrent.Location = new System.Drawing.Point(16, 16);

            // labelPresets
            labelPresets.AutoSize = true;
            labelPresets.Location = new System.Drawing.Point(16, 48);
            labelPresets.Text     = "Presets:";

            // btn10
            btn10.Text      = "10%";
            btn10.Location  = new System.Drawing.Point(16, 68);
            btn10.Size      = new System.Drawing.Size(52, 26);
            btn10.FlatStyle = System.Windows.Forms.FlatStyle.Flat;

            // btn25
            btn25.Text      = "25%";
            btn25.Location  = new System.Drawing.Point(74, 68);
            btn25.Size      = new System.Drawing.Size(52, 26);
            btn25.FlatStyle = System.Windows.Forms.FlatStyle.Flat;

            // btn50
            btn50.Text      = "50%";
            btn50.Location  = new System.Drawing.Point(132, 68);
            btn50.Size      = new System.Drawing.Size(52, 26);
            btn50.FlatStyle = System.Windows.Forms.FlatStyle.Flat;

            // btn75
            btn75.Text      = "75%";
            btn75.Location  = new System.Drawing.Point(190, 68);
            btn75.Size      = new System.Drawing.Size(52, 26);
            btn75.FlatStyle = System.Windows.Forms.FlatStyle.Flat;

            // trackScale
            trackScale.Location    = new System.Drawing.Point(12, 104);
            trackScale.Size        = new System.Drawing.Size(260, 45);
            trackScale.Minimum     = 1;
            trackScale.Maximum     = 100;
            trackScale.Value       = 100;
            trackScale.TickFrequency = 10;
            trackScale.SmallChange = 1;
            trackScale.LargeChange = 10;

            // labelScale
            labelScale.AutoSize = true;
            labelScale.Location = new System.Drawing.Point(16, 152);
            labelScale.Text     = "100%";

            // labelW
            labelW.AutoSize = true;
            labelW.Text     = "Width:";
            labelW.Location = new System.Drawing.Point(16, 178);

            // nudWidth
            nudWidth.Location = new System.Drawing.Point(70, 174);
            nudWidth.Size     = new System.Drawing.Size(90, 23);
            nudWidth.Minimum  = 1;
            nudWidth.Maximum  = 99999;

            // labelH
            labelH.AutoSize = true;
            labelH.Text     = "Height:";
            labelH.Location = new System.Drawing.Point(16, 210);

            // nudHeight
            nudHeight.Location = new System.Drawing.Point(70, 206);
            nudHeight.Size     = new System.Drawing.Size(90, 23);
            nudHeight.Minimum  = 1;
            nudHeight.Maximum  = 99999;

            // labelOutput
            labelOutput.AutoSize = true;
            labelOutput.Location = new System.Drawing.Point(16, 244);
            labelOutput.Text     = "Output size:  — × — px";

            // btnOK
            btnOK.Text      = "OK";
            btnOK.Location  = new System.Drawing.Point(100, 278);
            btnOK.Size      = new System.Drawing.Size(80, 28);
            btnOK.FlatStyle = System.Windows.Forms.FlatStyle.Flat;

            // btnCancel
            btnCancel.Text      = "Cancel";
            btnCancel.Location  = new System.Drawing.Point(188, 278);
            btnCancel.Size      = new System.Drawing.Size(80, 28);
            btnCancel.FlatStyle = System.Windows.Forms.FlatStyle.Flat;

            // Form
            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode       = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize          = new System.Drawing.Size(284, 322);
            Controls.AddRange(new System.Windows.Forms.Control[]
            {
                labelCurrent, labelPresets,
                btn10, btn25, btn50, btn75,
                trackScale, labelScale,
                labelW, nudWidth, labelH, nudHeight,
                labelOutput, btnOK, btnCancel
            });

            ((System.ComponentModel.ISupportInitialize)nudWidth).EndInit();
            ((System.ComponentModel.ISupportInitialize)nudHeight).EndInit();
            ((System.ComponentModel.ISupportInitialize)trackScale).EndInit();
            ResumeLayout(false);
            PerformLayout();
        }

        private System.Windows.Forms.Label            labelCurrent;
        private System.Windows.Forms.Label            labelOutput;
        private System.Windows.Forms.Label            labelW;
        private System.Windows.Forms.Label            labelH;
        private System.Windows.Forms.Label            labelPresets;
        private System.Windows.Forms.Label            labelScale;
        private System.Windows.Forms.NumericUpDown    nudWidth;
        private System.Windows.Forms.NumericUpDown    nudHeight;
        private System.Windows.Forms.TrackBar         trackScale;
        private System.Windows.Forms.Button           btn10;
        private System.Windows.Forms.Button           btn25;
        private System.Windows.Forms.Button           btn50;
        private System.Windows.Forms.Button           btn75;
        private System.Windows.Forms.Button           btnOK;
        private System.Windows.Forms.Button           btnCancel;
    }
}
