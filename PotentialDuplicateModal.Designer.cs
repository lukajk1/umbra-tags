namespace Calypso
{
    partial class PotentialDuplicateModal
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
            label1 = new Label();
            pictureBox1 = new PictureBox();
            pictureBox2 = new PictureBox();
            button2 = new Button();
            button3 = new Button();
            button4 = new Button();
            filename1 = new Label();
            filename2 = new Label();
            res2 = new Label();
            res1 = new Label();
            ((System.ComponentModel.ISupportInitialize)pictureBox1).BeginInit();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).BeginInit();
            SuspendLayout();
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new Point(12, 346);
            label1.Name = "label1";
            label1.Size = new Size(271, 15);
            label1.TabIndex = 0;
            label1.Text = "Potential duplicate image found. Select an option:";
            // 
            // pictureBox1
            // 
            pictureBox1.Location = new Point(12, 12);
            pictureBox1.Name = "pictureBox1";
            pictureBox1.Size = new Size(192, 246);
            pictureBox1.TabIndex = 1;
            pictureBox1.TabStop = false;
            // 
            // pictureBox2
            // 
            pictureBox2.Location = new Point(272, 12);
            pictureBox2.Name = "pictureBox2";
            pictureBox2.Size = new Size(192, 246);
            pictureBox2.TabIndex = 2;
            pictureBox2.TabStop = false;
            // 
            // button2
            // 
            button2.Location = new Point(144, 380);
            button2.Name = "button2";
            button2.Size = new Size(178, 23);
            button2.TabIndex = 4;
            button2.Text = "Replace the Image";
            button2.UseVisualStyleBackColor = true;
            button2.Click += buttonReplace_Click;
            // 
            // button3
            // 
            button3.Location = new Point(144, 439);
            button3.Name = "button3";
            button3.Size = new Size(178, 23);
            button3.TabIndex = 5;
            button3.Text = "Cancel";
            button3.UseVisualStyleBackColor = true;
            button3.Click += buttonCancel_Click;
            // 
            // button4
            // 
            button4.Location = new Point(144, 409);
            button4.Name = "button4";
            button4.Size = new Size(178, 23);
            button4.TabIndex = 6;
            button4.Text = "Keep Both";
            button4.UseVisualStyleBackColor = true;
            button4.Click += buttonImportAnyway_Click;
            // 
            // filename1
            // 
            filename1.Location = new Point(12, 275);
            filename1.Name = "filename1";
            filename1.Size = new Size(192, 23);
            filename1.TabIndex = 7;
            filename1.Text = "filename 1";
            // 
            // filename2
            // 
            filename2.Location = new Point(272, 275);
            filename2.Name = "filename2";
            filename2.Size = new Size(192, 23);
            filename2.TabIndex = 8;
            filename2.Text = "filename 2";
            // 
            // res2
            // 
            res2.Location = new Point(272, 298);
            res2.Name = "res2";
            res2.Size = new Size(192, 23);
            res2.TabIndex = 9;
            res2.Text = "resolution:";
            // 
            // res1
            // 
            res1.Location = new Point(12, 298);
            res1.Name = "res1";
            res1.Size = new Size(192, 23);
            res1.TabIndex = 10;
            res1.Text = "resolution:";
            // 
            // PotentialDuplicateModal
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(479, 490);
            Controls.Add(res1);
            Controls.Add(res2);
            Controls.Add(filename2);
            Controls.Add(filename1);
            Controls.Add(button4);
            Controls.Add(button3);
            Controls.Add(button2);
            Controls.Add(pictureBox2);
            Controls.Add(pictureBox1);
            Controls.Add(label1);
            Name = "PotentialDuplicateModal";
            ShowIcon = false;
            Text = "Potential Duplicate Found";
            ((System.ComponentModel.ISupportInitialize)pictureBox1).EndInit();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).EndInit();
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private Label label1;
        private PictureBox pictureBox1;
        private PictureBox pictureBox2;
        private Button button2;
        private Button button3;
        private Button button4;
        private Label filename1;
        private Label filename2;
        private Label res2;
        private Label res1;
    }
}