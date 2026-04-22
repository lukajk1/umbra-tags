using Calypso.UI;
using System;
using System.IO;
using System.Windows.Forms;

namespace Calypso
{
    internal partial class ResizeWizard : Form
    {
        private readonly ImageData _img;
        private readonly int _origW;
        private readonly int _origH;
        private bool _updatingFields = false;

        public ResizeWizard(ImageData img)
        {
            _img = img;

            using var bmp = Util.LoadImage(img.Filepath);
            _origW = bmp.Width;
            _origH = bmp.Height;

            InitializeComponent();
            ThemeManager.Apply(this);
            this.BackColor = Theme.Background;
            this.ForeColor = Theme.Foreground;
            this.HandleCreated += (_, _) => ThemeManager.SetImmersiveDarkMode(Handle, Theme.IsDark);

            this.StartPosition   = FormStartPosition.CenterParent;
            this.Text            = "Resize Image";
            this.FormBorderStyle = FormBorderStyle.FixedDialog;
            this.MinimizeBox     = false;
            this.MaximizeBox     = false;

            labelCurrent.Text = $"Current size:  {_origW} × {_origH} px";

            nudWidth.Value  = _origW;
            nudHeight.Value = _origH;

            nudWidth.ValueChanged  += NudWidth_Changed;
            nudHeight.ValueChanged += NudHeight_Changed;
            trackScale.ValueChanged += TrackScale_Changed;

            btnOK.Click     += BtnOK_Click;
            btnCancel.Click += (_, _) => Close();

            btn10.Click += (_, _) => ApplyPercent(10);
            btn25.Click += (_, _) => ApplyPercent(25);
            btn50.Click += (_, _) => ApplyPercent(50);
            btn75.Click += (_, _) => ApplyPercent(75);

            UpdateOutputLabel();
        }

        // ── slider → fields ───────────────────────────────────────────────

        private void TrackScale_Changed(object? sender, EventArgs e)
        {
            if (_updatingFields) return;
            ApplyPercent(trackScale.Value);
        }

        // ── preset buttons ────────────────────────────────────────────────

        private void ApplyPercent(int pct)
        {
            _updatingFields = true;
            nudWidth.Value  = Math.Max(1, (int)(_origW * pct / 100.0));
            nudHeight.Value = Math.Max(1, (int)(_origH * pct / 100.0));
            trackScale.Value = Math.Clamp(pct, trackScale.Minimum, trackScale.Maximum);
            _updatingFields = false;
            UpdateOutputLabel();
        }

        // ── fields → each other + slider ──────────────────────────────────

        private void NudWidth_Changed(object? sender, EventArgs e)
        {
            if (_updatingFields) return;
            _updatingFields = true;
            double ratio     = (double)nudWidth.Value / _origW;
            nudHeight.Value  = Math.Max(1, (int)(_origH * ratio));
            trackScale.Value = Math.Clamp((int)(ratio * 100), trackScale.Minimum, trackScale.Maximum);
            _updatingFields  = false;
            UpdateOutputLabel();
        }

        private void NudHeight_Changed(object? sender, EventArgs e)
        {
            if (_updatingFields) return;
            _updatingFields = true;
            double ratio     = (double)nudHeight.Value / _origH;
            nudWidth.Value   = Math.Max(1, (int)(_origW * ratio));
            trackScale.Value = Math.Clamp((int)(ratio * 100), trackScale.Minimum, trackScale.Maximum);
            _updatingFields  = false;
            UpdateOutputLabel();
        }

        // ── label ─────────────────────────────────────────────────────────

        private void UpdateOutputLabel()
        {
            int pct = trackScale.Value;
            labelScale.Text  = $"{pct}%";
            labelOutput.Text = $"Output size:  {(int)nudWidth.Value} × {(int)nudHeight.Value} px";
        }

        // ── OK ────────────────────────────────────────────────────────────

        private void BtnOK_Click(object? sender, EventArgs e)
        {
            int newW = (int)nudWidth.Value;
            int newH = (int)nudHeight.Value;

            if (newW == _origW && newH == _origH) { Close(); return; }

            try
            {
                Util.ResizeImage(_img, newW, newH);
                DB.GenTagDictAndSaveLibrary();
                ImageInfoPanel.Refresh();

                string name    = Path.GetFileNameWithoutExtension(_img.Filename);
                string shortName = name.Length > 20 ? name[..20] + "…" : name;
                Toast.Show($"Resized {shortName} to {newW}×{newH}");
            }
            catch (Exception ex)
            {
                Util.ShowErrorDialog($"Resize failed: {ex.Message}");
            }

            Close();
        }
    }
}
