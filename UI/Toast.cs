using Calypso.UI;
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace Calypso
{
    /// <summary>
    /// A small in-app toast notification that appears anchored to the bottom-center
    /// of the main window, displays for a few seconds, then fades out.
    /// </summary>
    internal sealed class Toast : Form
    {
        private const int PadX        = 20;
        private const int PadY        = 10;
        private const int CornerRadius = 10;
        private const int DisplayMs   = 2500;
        private const int FadeStepMs  = 30;
        private const float FadeStep  = 0.06f;

        private readonly System.Windows.Forms.Timer _holdTimer  = new();
        private readonly System.Windows.Forms.Timer _fadeTimer  = new();

        private Toast(string message)
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar   = false;
            TopMost         = true;
            BackColor       = Color.Magenta;          // key color for transparency
            TransparencyKey = Color.Magenta;
            Opacity         = 0.95;
            StartPosition   = FormStartPosition.Manual;

            SetStyle(
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.AllPaintingInWmPaint  |
                ControlStyles.UserPaint,
                true);

            // Measure text
            using var font = new Font("Segoe UI", 10f);
            var textSize   = TextRenderer.MeasureText(message, font);
            int w = textSize.Width  + PadX * 2;
            int h = textSize.Height + PadY * 2;
            ClientSize = new Size(w, h);

            // Position: bottom-center of main window client area
            var owner = MainWindow.i;
            var ownerPt = owner.PointToScreen(new Point(
                (owner.ClientSize.Width  - w) / 2,
                owner.ClientSize.Height  - h - 40));
            Location = ownerPt;

            // Paint
            Paint += (_, e) =>
            {
                var g    = e.Graphics;
                g.SmoothingMode = SmoothingMode.AntiAlias;

                var rect = new Rectangle(0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
                using var bgBrush  = new SolidBrush(Color.FromArgb(30, 30, 30));
                g.FillRectangle(bgBrush, rect);

                using var borderPen = new Pen(Color.FromArgb(70, 70, 70));
                g.DrawRectangle(borderPen, rect);

                using var textBrush = new SolidBrush(Color.FromArgb(220, 220, 220));
                using var f = new Font("Segoe UI", 10f);
                var sf = new StringFormat
                {
                    Alignment     = StringAlignment.Center,
                    LineAlignment = StringAlignment.Center
                };
                g.DrawString(message, f, textBrush, new RectangleF(0, 0, ClientSize.Width, ClientSize.Height), sf);
            };

            // Hold timer — start fading after DisplayMs
            _holdTimer.Interval = DisplayMs;
            _holdTimer.Tick += (_, _) =>
            {
                _holdTimer.Stop();
                _fadeTimer.Start();
            };

            // Fade timer
            _fadeTimer.Interval = FadeStepMs;
            _fadeTimer.Tick += (_, _) =>
            {
                Opacity -= FadeStep;
                if (Opacity <= 0)
                {
                    _fadeTimer.Stop();
                    Close();
                }
            };
        }

        /// <summary>Show a toast on the main window. Safe to call from any thread.</summary>
        public static void Show(string message)
        {
            var owner = MainWindow.i;
            if (owner == null || owner.IsDisposed) return;

            if (owner.InvokeRequired)
            {
                owner.BeginInvoke(() => Show(message));
                return;
            }

            var toast = new Toast(message);
            toast._holdTimer.Start();
            toast.Show(owner);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _holdTimer.Dispose();
                _fadeTimer.Dispose();
            }
            base.Dispose(disposing);
        }

        // ── rounded rect helpers ──────────────────────────────────────────

        private static void FillRoundedRect(Graphics g, Brush brush, Rectangle r, int radius)
        {
            using var path = RoundedRectPath(r, radius);
            g.FillPath(brush, path);
        }

        private static void DrawRoundedRect(Graphics g, Pen pen, Rectangle r, int radius)
        {
            using var path = RoundedRectPath(r, radius);
            g.DrawPath(pen, path);
        }

        private static GraphicsPath RoundedRectPath(Rectangle r, int radius)
        {
            int d    = radius * 2;
            var path = new GraphicsPath();
            path.AddArc(r.X,             r.Y,              d, d, 180, 90);
            path.AddArc(r.Right - d,     r.Y,              d, d, 270, 90);
            path.AddArc(r.Right - d,     r.Bottom - d,     d, d,   0, 90);
            path.AddArc(r.X,             r.Bottom - d,     d, d,  90, 90);
            path.CloseFigure();
            return path;
        }
    }
}
