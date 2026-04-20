namespace Calypso
{
    partial class ImportWizard
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
            pictureBox1 = new PictureBox();
            filename = new Label();
            details = new Label();
            button1 = new Button();
            label3 = new Label();
            button2 = new Button();
            button3 = new Button();
            ((System.ComponentModel.ISupportInitialize)pictureBox1).BeginInit();
            SuspendLayout();
            // 
            // pictureBox1
            // 
            pictureBox1.Anchor = AnchorStyles.Top;
            pictureBox1.Location = new Point(34, 12);
            pictureBox1.Name = "pictureBox1";
            pictureBox1.Size = new Size(186, 270);
            pictureBox1.TabIndex = 0;
            pictureBox1.TabStop = false;
            // 
            // filename
            // 
            filename.AutoSize = true;
            filename.Location = new Point(253, 73);
            filename.Name = "filename";
            filename.Size = new Size(53, 15);
            filename.TabIndex = 1;
            filename.Text = "filename";
            // 
            // details
            // 
            details.AutoSize = true;
            details.Location = new Point(253, 100);
            details.Name = "details";
            details.Size = new Size(41, 15);
            details.TabIndex = 2;
            details.Text = "details";
            // 
            // button1
            // 
            button1.Location = new Point(253, 382);
            button1.Name = "button1";
            button1.Size = new Size(75, 23);
            button1.TabIndex = 3;
            button1.Text = "Yes";
            button1.UseVisualStyleBackColor = true;
            // 
            // label3
            // 
            label3.AutoSize = true;
            label3.Location = new Point(145, 322);
            label3.Name = "label3";
            label3.Size = new Size(48, 15);
            label3.TabIndex = 4;
            label3.Text = "Import?";
            // 
            // button2
            // 
            button2.Location = new Point(52, 382);
            button2.Name = "button2";
            button2.Size = new Size(114, 23);
            button2.TabIndex = 5;
            button2.Text = "No and Delete";
            button2.UseVisualStyleBackColor = true;
            // 
            // button3
            // 
            button3.Location = new Point(172, 382);
            button3.Name = "button3";
            button3.Size = new Size(75, 23);
            button3.TabIndex = 6;
            button3.Text = "No";
            button3.UseVisualStyleBackColor = true;
            // 
            // ImportWizard
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(488, 428);
            Controls.Add(button3);
            Controls.Add(button2);
            Controls.Add(label3);
            Controls.Add(button1);
            Controls.Add(details);
            Controls.Add(filename);
            Controls.Add(pictureBox1);
            Name = "ImportWizard";
            ShowIcon = false;
            Text = "Import Wizard";
            ((System.ComponentModel.ISupportInitialize)pictureBox1).EndInit();
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private PictureBox pictureBox1;
        private Label filename;
        private Label details;
        private Button button1;
        private Label label3;
        private Button button2;
        private Button button3;
    }
}