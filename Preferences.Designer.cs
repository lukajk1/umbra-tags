namespace Calypso
{
    partial class Preferences
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
            checkboxDeleteSourceOnDragIn = new CheckBox();
            checkboxShowFilenames = new CheckBox();
            button2 = new Button();
            SuspendLayout();
            // 
            // checkboxDeleteSourceOnDragIn
            // 
            checkboxDeleteSourceOnDragIn.AutoSize = true;
            checkboxDeleteSourceOnDragIn.Location = new Point(125, 97);
            checkboxDeleteSourceOnDragIn.Name = "checkboxDeleteSourceOnDragIn";
            checkboxDeleteSourceOnDragIn.Size = new Size(236, 19);
            checkboxDeleteSourceOnDragIn.TabIndex = 0;
            checkboxDeleteSourceOnDragIn.Text = "Delete Original image when dragging in";
            checkboxDeleteSourceOnDragIn.UseVisualStyleBackColor = true;
            // 
            // checkboxShowFilenames
            // 
            checkboxShowFilenames.AutoSize = true;
            checkboxShowFilenames.Location = new Point(125, 132);
            checkboxShowFilenames.Name = "checkboxShowFilenames";
            checkboxShowFilenames.Size = new Size(163, 19);
            checkboxShowFilenames.TabIndex = 1;
            checkboxShowFilenames.Text = "Show Filenames in Gallery";
            checkboxShowFilenames.UseVisualStyleBackColor = true;
            // 
            // button2
            // 
            button2.Location = new Point(699, 406);
            button2.Name = "button2";
            button2.Size = new Size(75, 23);
            button2.TabIndex = 3;
            button2.Text = "Apply";
            button2.UseVisualStyleBackColor = true;
            button2.Click += buttonApply_Click;
            // 
            // Preferences
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(800, 450);
            Controls.Add(button2);
            Controls.Add(checkboxShowFilenames);
            Controls.Add(checkboxDeleteSourceOnDragIn);
            Name = "Preferences";
            ShowIcon = false;
            Text = "Preferences";
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private CheckBox checkboxDeleteSourceOnDragIn;
        private CheckBox checkboxShowFilenames;
        private Button button2;
    }
}