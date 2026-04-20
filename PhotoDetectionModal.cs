using Calypso.UI;
using System.Drawing.Imaging;

namespace Calypso
{
    internal class PhotoDetectionModal : Form
    {
        private PictureBox _pictureBox;
        private Label      _scoreLabel;
        private Button     _okButton;

        public static void Run()
        {
            var lib = DB.appdata?.ActiveLibrary;
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
                var result = modal.ShowDialog();
                if (result != DialogResult.OK) return;
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
            this.ClientSize      = new Size(600, 560);
            this.KeyPreview      = true;
            this.KeyDown        += (_, e) => { if (e.KeyCode == Keys.Enter) AcceptOk(); };

            _pictureBox = new PictureBox
            {
                SizeMode  = PictureBoxSizeMode.Zoom,
                Size      = new Size(560, 460),
                Location  = new Point(20, 20),
                BackColor = Theme.Background
            };

            _scoreLabel = new Label
            {
                AutoSize  = false,
                Size      = new Size(560, 24),
                Location  = new Point(20, 490),
                ForeColor = Theme.Foreground,
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleCenter,
                Font      = new Font(Font.FontFamily, 10, FontStyle.Bold)
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
            _okButton.Location = new Point((ClientSize.Width - _okButton.Width) / 2, 524);
            _okButton.Click   += (_, _) => AcceptOk();

            this.Controls.AddRange(new Control[] { _pictureBox, _scoreLabel, _okButton });
        }

        private void LoadImage(ImageData img)
        {
            System.Threading.Tasks.Task.Run(() =>
            {
                try
                {
                    var bmp   = Util.LoadImage(img.Filepath);
                    float score = PhotoDetector.Score(bmp);
                    string label = score >= 0.66f ? "Photo" : score >= 0.33f ? "Uncertain" : "Not a photo";

                    this.BeginInvoke(() =>
                    {
                        _pictureBox.Image?.Dispose();
                        _pictureBox.Image = bmp;
                        _scoreLabel.Text  = $"{label}  —  score: {score:F2}  |  {Path.GetFileName(img.Filepath)}";
                        _scoreLabel.ForeColor = score >= 0.66f ? Color.LightGreen
                                              : score >= 0.33f ? Color.Orange
                                              : Color.IndianRed;
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
