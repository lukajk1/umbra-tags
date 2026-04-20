using Calypso.UI;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace Calypso
{
    internal class ImportWizardModal : Form
    {
        private static readonly string[] SupportedExtensions =
            { ".jpg", ".jpeg", ".jfif", ".png", ".bmp", ".gif", ".webp" };

        private static string DownloadsPath =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");

        // ── controls ──────────────────────────────────────────────────────
        private PictureBox pictureBox;
        private Label labelFilename;
        private Label labelDescription;
        private Label labelProgress;
        private Button buttonYes;
        private Button buttonNo;
        private Button buttonNoDelete;

        // ── state ─────────────────────────────────────────────────────────
        private readonly Queue<string> _queue;
        private string _current = string.Empty;
        private int _total;
        private int _processed;

        public static void RunFromDownloads()
        {
            var files = new Queue<string>();
            foreach (string f in Directory.GetFiles(DownloadsPath))
            {
                string ext = Path.GetExtension(f).ToLower();
                if (Array.IndexOf(SupportedExtensions, ext) >= 0)
                    files.Enqueue(f);
            }

            if (files.Count == 0)
            {
                MessageBox.Show("No compatible images found in Downloads.",
                    "Import Wizard", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            using var wizard = new ImportWizardModal(files);
            wizard.ShowDialog();
        }

        private ImportWizardModal(Queue<string> queue)
        {
            _queue   = queue;
            _total   = queue.Count;
            _processed = 0;

            BuildUI();
            ThemeManager.Apply(this);
            this.BackColor = Theme.Background;
            this.ForeColor = Theme.Foreground;
            ThemeManager.SetImmersiveDarkMode(this.Handle, Theme.IsDark);

            Advance();
        }

        private void BuildUI()
        {
            this.Text            = "Import Wizard";
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.StartPosition   = FormStartPosition.CenterScreen;
            this.MinimizeBox     = false;
            this.MaximizeBox     = false;
            this.ShowIcon        = false;
            this.ClientSize      = new Size(420, 520);
            this.KeyPreview      = true;
            this.KeyDown        += (_, e) =>
            {
                if (e.KeyCode == Keys.Escape) Close();
            };

            pictureBox = new PictureBox
            {
                SizeMode  = PictureBoxSizeMode.Zoom,
                Size      = new Size(380, 300),
                Location  = new Point(20, 20),
                BackColor = Theme.Background
            };

            labelFilename = new Label
            {
                AutoSize  = false,
                Size      = new Size(380, 22),
                Location  = new Point(20, 330),
                Font      = new Font(Font.FontFamily, 10, FontStyle.Bold),
                ForeColor = Theme.Foreground,
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleLeft
            };

            labelDescription = new Label
            {
                AutoSize  = false,
                Size      = new Size(380, 20),
                Location  = new Point(20, 354),
                ForeColor = Theme.ForegroundDim,
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleLeft
            };

            labelProgress = new Label
            {
                AutoSize  = false,
                Size      = new Size(380, 20),
                Location  = new Point(20, 376),
                ForeColor = Theme.ForegroundDim,
                BackColor = Color.Transparent,
                TextAlign = ContentAlignment.MiddleLeft
            };

            int btnY  = 420;
            int btnW  = 110;
            int btnH  = 36;
            int gap   = 15;
            int totalW = btnW * 3 + gap * 2;
            int startX = (ClientSize.Width - totalW) / 2;

            buttonNoDelete = MakeButton("No && Delete", startX, btnY, btnW, btnH);
            buttonNo       = MakeButton("No",           startX + btnW + gap, btnY, btnW, btnH);
            buttonYes      = MakeButton("Yes",          startX + (btnW + gap) * 2, btnY, btnW, btnH, Theme.Accent);

            buttonYes.Click      += ButtonYes_Click;
            buttonNo.Click       += ButtonNo_Click;
            buttonNoDelete.Click += ButtonNoDelete_Click;

            this.Controls.AddRange(new Control[]
                { pictureBox, labelFilename, labelDescription, labelProgress,
                  buttonYes, buttonNo, buttonNoDelete });
        }

        private Button MakeButton(string text, int x, int y, int w, int h, Color? back = null)
        {
            return new Button
            {
                Text      = text,
                Location  = new Point(x, y),
                Size      = new Size(w, h),
                FlatStyle = FlatStyle.Flat,
                BackColor = back ?? Theme.SurfaceRaised,
                ForeColor = Theme.Foreground,
                FlatAppearance = { BorderColor = Theme.Border }
            };
        }

        // ── navigation ────────────────────────────────────────────────────

        private void Advance()
        {
            DisposeCurrentImage();

            if (_queue.Count == 0)
            {
                Close();
                return;
            }

            _current = _queue.Dequeue();
            _processed++;

            labelFilename.Text    = Path.GetFileName(_current);
            labelProgress.Text    = $"{_processed} of {_total}";
            labelDescription.Text = "--";
            pictureBox.Image      = null;

            LoadImageAsync(_current);
        }

        private void LoadImageAsync(string path)
        {
            string captured = path;
            System.Threading.Tasks.Task.Run(() =>
            {
                try
                {
                    var bmp = Util.LoadImage(captured);
                    long bytes = new FileInfo(captured).Length;
                    string size = bytes >= 1024 * 1024
                        ? $"{bytes / (1024.0 * 1024.0):F1} MB"
                        : $"{bytes / 1024.0:F1} KB";
                    string desc = $"{bmp.Width} x {bmp.Height}  ·  {size}";

                    this.BeginInvoke(() =>
                    {
                        if (_current != captured) { bmp.Dispose(); return; }
                        pictureBox.Image?.Dispose();
                        pictureBox.Image      = bmp;
                        labelDescription.Text = desc;
                    });
                }
                catch { }
            });
        }

        // ── button handlers ───────────────────────────────────────────────

        private void ButtonYes_Click(object? sender, EventArgs e)
        {
            // AddFilesToLibrary shows the duplicate modal synchronously if needed,
            // so it blocks here until resolved before we advance.
            var added = DB.AddFilesToLibrary(new[] { _current });
            if (added.Count > 0 && PreferencesManager.Prefs.DeleteSourceOnDragIn)
                try { if (File.Exists(_current)) File.Delete(_current); } catch { }
            Advance();
        }

        private void ButtonNo_Click(object? sender, EventArgs e)
        {
            Advance();
        }

        private void ButtonNoDelete_Click(object? sender, EventArgs e)
        {
            try { if (File.Exists(_current)) File.Delete(_current); } catch { }
            Advance();
        }

        // ── cleanup ───────────────────────────────────────────────────────

        private void DisposeCurrentImage()
        {
            if (pictureBox?.Image != null)
            {
                pictureBox.Image.Dispose();
                pictureBox.Image = null;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) DisposeCurrentImage();
            base.Dispose(disposing);
        }
    }
}
