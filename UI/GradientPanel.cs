using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace Calypso.UI
{
    /// <summary>
    /// A panel that paints a vertical-streak ambient gradient derived from the
    /// bottom 2 rows of an image's 4x4 color grid. Each column of the grid
    /// becomes a vertical band blurred horizontally, complementing the gallery's
    /// horizontal bands.
    /// </summary>
    internal sealed class GradientPanel : Panel
    {
        private const float Opacity    = 0.20f;
        private const int   BlurPasses = 3;

        private Color[]? _strip = null;  // one color per pixel column

        public GradientPanel()
        {
            SetStyle(
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.AllPaintingInWmPaint  |
                ControlStyles.UserPaint,
                true);
            BackColor = Color.Transparent;
        }

        protected override void OnControlAdded(ControlEventArgs e)
        {
            base.OnControlAdded(e);
            // Keep any child TableLayoutPanel transparent so the gradient shows through
            if (e.Control is TableLayoutPanel tlp)
                tlp.BackColor = Color.Transparent;
        }

        public void SetColors(string? colorGrid)
        {
            if (colorGrid == null)
            {
                _strip = null;
                Invalidate();
                return;
            }

            // Bottom 2 rows → 8 colors (4 cols × 2 rows)
            Color[] src = ColorGrid.BottomTwoRows(colorGrid);

            // Average each column pair into 4 colors
            var cols = new Color[ColorGrid.Cols];
            for (int c = 0; c < ColorGrid.Cols; c++)
            {
                int r = (src[c].R + src[ColorGrid.Cols + c].R) / 2;
                int g = (src[c].G + src[ColorGrid.Cols + c].G) / 2;
                int b = (src[c].B + src[ColorGrid.Cols + c].B) / 2;
                cols[c] = Color.FromArgb(r, g, b);
            }

            // Expand to one-color-per-pixel-column by interpolating between the 4 key points
            int w = Math.Max(1, Width);
            var raw = new Color[w];
            for (int px = 0; px < w; px++)
            {
                float t    = (float)px / (w - 1) * (ColorGrid.Cols - 1);
                int   lo   = Math.Clamp((int)t,     0, ColorGrid.Cols - 1);
                int   hi   = Math.Clamp(lo + 1,     0, ColorGrid.Cols - 1);
                float frac = t - lo;
                raw[px] = Blend(cols[lo], cols[hi], frac);
            }

            // Horizontal box blur (vertical streaks stay sharp, horizontal transitions soften)
            int radius = Math.Max(4, w / 8);
            for (int pass = 0; pass < BlurPasses; pass++)
                raw = BoxBlur(raw, radius);

            // Blend with background
            var bg = Theme.Background;
            _strip = new Color[w];
            for (int px = 0; px < w; px++)
                _strip[px] = Blend(bg, raw[px], Opacity);

            Invalidate();
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            // Strip is width-dependent — invalidate so it gets rebuilt on next paint
            _strip = null;
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.Clear(Theme.Background);

            if (_strip == null || _strip.Length < 2) return;

            int w = ClientSize.Width;
            int h = ClientSize.Height;

            // Sample a small number of evenly-spaced key colors from the strip
            // and hand them to a single ColorBlend — one smooth pass across the full width.
            const int Keys = 8;
            var blend = new ColorBlend(Keys);
            blend.Positions = new float[Keys];
            blend.Colors    = new Color[Keys];
            for (int i = 0; i < Keys; i++)
            {
                float t = (float)i / (Keys - 1);
                blend.Positions[i] = t;
                int px = Math.Clamp((int)(t * (_strip.Length - 1)), 0, _strip.Length - 1);
                blend.Colors[i] = _strip[px];
            }

            using var brush = new LinearGradientBrush(
                new Rectangle(0, 0, Math.Max(w, 1), h),
                Color.Black, Color.Black,          // overridden by InterpolationColors
                LinearGradientMode.Horizontal);
            brush.InterpolationColors = blend;
            g.FillRectangle(brush, 0, 0, w, h);
        }

        // ── helpers ───────────────────────────────────────────────────────

        private static Color Blend(Color a, Color b, float t) =>
            Color.FromArgb(
                (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t),
                (int)(a.B + (b.B - a.B) * t));

        private static Color[] BoxBlur(Color[] src, int radius)
        {
            int len = src.Length;
            var dst = new Color[len];
            for (int i = 0; i < len; i++)
            {
                int lo = Math.Max(0, i - radius);
                int hi = Math.Min(len - 1, i + radius);
                int count = hi - lo + 1;
                int r = 0, g = 0, b = 0;
                for (int j = lo; j <= hi; j++) { r += src[j].R; g += src[j].G; b += src[j].B; }
                dst[i] = Color.FromArgb(r / count, g / count, b / count);
            }
            return dst;
        }
    }
}
