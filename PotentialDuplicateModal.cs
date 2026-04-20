using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Calypso
{
    public enum DuplicateAction { Cancel, ImportAnyway, Replace }

    public partial class PotentialDuplicateModal : Form
    {
        public DuplicateAction Action { get; private set; } = DuplicateAction.Cancel;

        public PotentialDuplicateModal(string incomingPath, string existingPath)
        {
            InitializeComponent();

            var img1 = Util.LoadImage(incomingPath);
            var img2 = Util.LoadImage(existingPath);

            pictureBox1.Image = img1;
            pictureBox2.Image = img2;
            pictureBox1.SizeMode = PictureBoxSizeMode.Zoom;
            pictureBox2.SizeMode = PictureBoxSizeMode.Zoom;

            filename1.Text = Truncate(Path.GetFileName(incomingPath));
            filename2.Text = Truncate(Path.GetFileName(existingPath));
            res1.Text = $"{FileSize(incomingPath)}, {img1.Width} x {img1.Height}";
            res2.Text = $"{FileSize(existingPath)}, {img2.Width} x {img2.Height}";
        }

        private static string Truncate(string s, int max = 30) =>
            s.Length > max ? s[..max] + "…" : s;

        private static string FileSize(string path)
        {
            long bytes = new FileInfo(path).Length;
            return bytes >= 1024 * 1024
                ? $"{bytes / (1024.0 * 1024.0):F1} MB"
                : $"{bytes / 1024.0:F1} KB";
        }

        private void buttonImportAnyway_Click(object sender, EventArgs e)
        {
            Action = DuplicateAction.ImportAnyway;
            Close();
        }

        private void buttonReplace_Click(object sender, EventArgs e)
        {
            Action = DuplicateAction.Replace;
            Close();
        }

        private void buttonCancel_Click(object sender, EventArgs e)
        {
            Action = DuplicateAction.Cancel;
            Close();
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            pictureBox1.Image?.Dispose();
            pictureBox2.Image?.Dispose();
            base.OnFormClosed(e);
        }
    }
}
