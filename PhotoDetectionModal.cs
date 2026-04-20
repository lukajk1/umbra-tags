using Calypso.UI;

namespace Calypso
{
    internal class PhotoDetectionModal : Form
    {
        private PictureBox _pictureBox;
        private Label      _verdictLabel;
        private Label      _breakdownLabel;
        private Button     _okButton;

        public static void Run()
        {
            var lib = DB.ActiveLibrary;
            if (lib == null || lib.filenameDict.Count == 0)
            {
                MessageBox.Show("No active library.", "Photo Detection",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var images = lib.filenameDict.Values
                .Where(img => !img.IsArchived && File.Exists(img.Filepath))
                .ToList();

            if (images.Count == 0)
            {
                MessageBox.Show("No images found.", "Photo Detection",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            foreach (var img in images)
            {
                using var modal = new PhotoDetectionModal(img);
                if (modal.ShowDialog() != DialogResult.OK) return;
            }
        }

        private PhotoDetectionModal(ImageData img)
        {
            BuildUI();
            ThemeManager.Apply(this);
            this.BackColor = Theme.Background;
            this.ForeColor = Theme.Foreground;
            ThemeManager.SetImmersiveDarkMode(this.Handle, Theme.IsDark);
            LoadImage(img);
        }

        private void BuildUI()
        {
            this.Text            = "Photo Detection";
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.StartPosition   = FormStartPosition.CenterScreen;
            this.MinimizeBox     = false;
            this.MaximizeBox     = false;
            this.ShowIcon        = false;
            this.ClientSize      = new Size(620, 620);
            this.KeyPreview      = true;
            this.KeyDown        += (_, e) => { if (e.KeyCode == Keys.Enter) AcceptOk(); };

            _pictureBox = new PictureBox
            {
                SizeMode  = PictureBoxSizeMode.Zoom,
                Size      = new Size(580, 440),
                Location  = new Point(20, 20),
                BackColor = Theme.Background
            };

            _verdictLabel = new Label
            {
                AutoSize  = false,
                Size      = new Size(580, 26),
                Location  = new Point(20, 470),
                ForeColor = Theme.Foreground,
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleCenter,
                Font      = new Font(Font.FontFamily, 11, FontStyle.Bold)
            };

            _breakdownLabel = new Label
            {
                AutoSize  = false,
                Size      = new Size(580, 60),
                Location  = new Point(20, 500),
                ForeColor = Theme.ForegroundDim,
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleCenter,
                Font      = new Font(Font.FontFamily, 8.5f)
            };

            _okButton = new Button
            {
                Text      = "OK",
                Size      = new Size(80, 30),
                FlatStyle = FlatStyle.Flat,
                BackColor = Theme.Accent,
                ForeColor = Theme.Foreground,
                FlatAppearance = { BorderColor = Theme.Border }
            };
            _okButton.Location = new Point((ClientSize.Width - _okButton.Width) / 2, 574);
            _okButton.Click   += (_, _) => AcceptOk();

            this.Controls.AddRange(new Control[]
                { _pictureBox, _verdictLabel, _breakdownLabel, _okButton });
        }

        private void LoadImage(ImageData img)
        {
            System.Threading.Tasks.Task.Run(() =>
            {
                try
                {
                    var bmp = Util.LoadImage(img.Filepath);
                    var bd  = PhotoDetector.Breakdown(bmp, img.Filepath);

                    string verdict = bd.Total >= 0.66f ? "Photo"
                                   : bd.Total >= 0.33f ? "Uncertain"
                                   : "Not a photo";

                    string exifStr = bd.Exif >= 1f ? "EXIF ✓" : bd.Exif > 0f ? $"EXIF ~{bd.Exif:F2}" : "no EXIF";

                    string breakdown =
                        $"{Path.GetFileName(img.Filepath)}    total: {bd.Total:F2}\n" +
                        $"{exifStr}   entropy: {bd.HueEntropy:F2}   lap: {bd.LaplacianVariance:F2}" +
                        $"   edge: {bd.EdgeSoftness:F2}   colors: {bd.ColorDiversity:F2}   sat↓: {1f - bd.SaturationPenalty:F2}";

                    this.BeginInvoke(() =>
                    {
                        _pictureBox.Image?.Dispose();
                        _pictureBox.Image    = bmp;
                        _verdictLabel.Text   = verdict;
                        _verdictLabel.ForeColor = bd.Total >= 0.66f ? Color.LightGreen
                                               : bd.Total >= 0.33f ? Color.Orange
                                               : Color.IndianRed;
                        _breakdownLabel.Text = breakdown;
                    });
                }
                catch { }
            });
        }

        private void AcceptOk() => DialogResult = DialogResult.OK;

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _pictureBox?.Image?.Dispose();
                _pictureBox?.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
