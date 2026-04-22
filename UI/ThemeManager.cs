using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Calypso.UI
{
    internal enum ThemeMode { Dark, Light, System }

    internal static class Theme
    {
        public static Color Background    { get; private set; } = Color.FromArgb(28,  28,  28);
        public static Color Surface       { get; private set; } = Color.FromArgb(38,  38,  38);
        public static Color SurfaceRaised { get; private set; } = Color.FromArgb(48,  48,  48);
        public static Color Border        { get; private set; } = Color.FromArgb(60,  60,  60);
        public static Color Foreground    { get; private set; } = Color.FromArgb(220, 220, 220);
        public static Color ForegroundDim { get; private set; } = Color.FromArgb(150, 150, 150);
        public static Color Accent        { get; private set; } = Color.FromArgb(0,   120, 215);
        public static Color AccentOverlay { get; private set; } = Color.FromArgb(40,  0,   120, 215);
        public static bool  IsDark        { get; private set; } = true;

        internal static void ApplyDark()
        {
            Background    = Color.FromArgb(28,  28,  28);
            Surface       = Color.FromArgb(38,  38,  38);
            SurfaceRaised = Color.FromArgb(48,  48,  48);
            Border        = Color.FromArgb(60,  60,  60);
            Foreground    = Color.FromArgb(220, 220, 220);
            ForegroundDim = Color.FromArgb(150, 150, 150);
            Accent        = Color.FromArgb(0,   120, 215);
            AccentOverlay = Color.FromArgb(40,  0,   120, 215);
            IsDark        = true;
        }

        internal static void ApplyLight()
        {
            Background    = Color.FromArgb(245, 245, 245);
            Surface       = Color.FromArgb(255, 255, 255);
            SurfaceRaised = Color.FromArgb(230, 230, 230);
            Border        = Color.FromArgb(200, 200, 200);
            Foreground    = Color.FromArgb(20,  20,  20);
            ForegroundDim = Color.FromArgb(100, 100, 100);
            Accent        = Color.FromArgb(0,   120, 215);
            AccentOverlay = Color.FromArgb(40,  0,   120, 215);
            IsDark        = false;
        }
    }

    internal static class ThemeManager
    {
        public static ThemeMode CurrentMode { get; private set; } = ThemeMode.Dark;

        public static void SetTheme(ThemeMode mode)
        {
            CurrentMode = mode;

            bool dark = mode == ThemeMode.Dark ||
                        (mode == ThemeMode.System && SystemPrefersDark());

            if (dark) Theme.ApplyDark();
            else      Theme.ApplyLight();

            foreach (Form f in Application.OpenForms)
            {
                Apply(f);
                f.BackColor = Theme.Background;
                f.ForeColor = Theme.Foreground;
                SetImmersiveDarkMode(f.Handle, dark);
                f.Invalidate(true);
            }

            // re-theme any floating context menus registered with us
            foreach (var cms in _contextMenus)
                ApplyContextMenu(cms);
        }

        private static readonly List<ContextMenuStrip> _contextMenus = new();

        public static void ApplyContextMenu(ContextMenuStrip cms)
        {
            if (!_contextMenus.Contains(cms)) _contextMenus.Add(cms);
            cms.BackColor = Theme.Surface;
            cms.ForeColor = Theme.Foreground;
            cms.Renderer  = new ThemedMenuRenderer();
            ApplyMenuItems(cms.Items);
        }

        public static void Apply(Control root)
        {
            ApplyControl(root);
            foreach (Control child in root.Controls)
                Apply(child);
        }

        private static void ApplyControl(Control c)
        {
            switch (c)
            {
                case MenuStrip ms:
                    ms.BackColor = Theme.Surface;
                    ms.ForeColor = Theme.Foreground;
                    ms.Renderer  = new ThemedMenuRenderer();
                    ApplyMenuItems(ms.Items);
                    break;

                case StatusStrip ss:
                    ss.BackColor   = Theme.Surface;
                    ss.ForeColor   = Theme.Foreground;
                    ss.Renderer    = new ThemedMenuRenderer();
                    foreach (ToolStripItem item in ss.Items)
                    {
                        item.BackColor = Theme.Surface;
                        item.ForeColor = Theme.Foreground;
                    }
                    break;

                case ToolStrip ts:
                    ts.BackColor = Theme.Surface;
                    ts.ForeColor = Theme.Foreground;
                    ts.Renderer  = new ThemedMenuRenderer();
                    break;

                case TreeView tv:
                    tv.BackColor   = Theme.Background;
                    tv.ForeColor   = Theme.Foreground;
                    tv.BorderStyle = BorderStyle.None;
                    if (tv.IsHandleCreated) ApplyScrollbarTheme(tv.Handle);
                    else tv.HandleCreated += (s, _) => ApplyScrollbarTheme(((Control)s!).Handle);
                    break;

                case TextBox tb:
                    tb.BackColor   = Theme.SurfaceRaised;
                    tb.ForeColor   = Theme.Foreground;
                    tb.BorderStyle = BorderStyle.FixedSingle;
                    break;

                case ComboBox cb:
                    cb.BackColor = Theme.SurfaceRaised;
                    cb.ForeColor = Theme.Foreground;
                    cb.FlatStyle = FlatStyle.Flat;
                    break;

                case CheckBox chk:
                    chk.BackColor             = Color.Transparent;
                    chk.ForeColor             = Theme.Foreground;
                    chk.UseVisualStyleBackColor = false;
                    break;

                case Button btn:
                    btn.BackColor                    = Theme.SurfaceRaised;
                    btn.ForeColor                    = Theme.Foreground;
                    btn.FlatStyle                    = FlatStyle.Flat;
                    btn.FlatAppearance.BorderColor   = Theme.Border;
                    break;

                case SplitContainer sc:
                    sc.BackColor        = Theme.Background;
                    sc.ForeColor        = Theme.Foreground;
                    sc.Panel1.BackColor = Theme.Background;
                    sc.Panel2.BackColor = Theme.Background;
                    break;

                case TableLayoutPanel tlp:
                    tlp.BackColor       = Theme.Surface;
                    tlp.ForeColor       = Theme.Foreground;
                    tlp.CellBorderStyle = TableLayoutPanelCellBorderStyle.None;
                    break;

                case PictureBox pb:
                    pb.BackColor = Theme.Background;
                    break;

                case Panel p:
                    p.BackColor   = Theme.Background;
                    p.ForeColor   = Theme.Foreground;
                    p.BorderStyle = BorderStyle.None;
                    break;

                case Label lbl:
                    lbl.BackColor = Color.Transparent;
                    lbl.ForeColor = Theme.Foreground;
                    break;

                case VirtualGalleryPanel vgp:
                    vgp.BackColor = Theme.Background;
                    break;
            }
        }

        private static void ApplyMenuItems(ToolStripItemCollection items)
        {
            foreach (ToolStripItem item in items)
            {
                item.BackColor = Theme.Surface;
                item.ForeColor = Theme.Foreground;
                if (item is ToolStripMenuItem mi)
                    ApplyMenuItems(mi.DropDownItems);
            }
        }

        // ── system theme detection ────────────────────────────────────────

        private static bool SystemPrefersDark()
        {
            try
            {
                using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                return (int)(key?.GetValue("AppsUseLightTheme") ?? 1) == 0;
            }
            catch { return false; }
        }

        // ── DWM dark mode for title bar + scrollbars ──────────────────────

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

        internal static void SetImmersiveDarkMode(IntPtr hwnd, bool dark)
        {
            int value = dark ? 1 : 0;
            DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref value, sizeof(int));
        }

        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        private static extern int SetWindowTheme(IntPtr hwnd, string pszSubAppName, string? pszSubIdList);

        internal static void ApplyScrollbarTheme(IntPtr hwnd)
        {
            SetWindowTheme(hwnd, Theme.IsDark ? "DarkMode_Explorer" : "Explorer", null);
        }
    }

    // ── menu renderer ─────────────────────────────────────────────────────

    internal sealed class ThemedMenuRenderer : ToolStripProfessionalRenderer
    {
        public ThemedMenuRenderer() : base(new ThemedColorTable()) { }

        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            var rect = new Rectangle(Point.Empty, e.Item.Size);
            Color fill = e.Item.Selected ? Theme.SurfaceRaised : Theme.Surface;
            using var brush = new SolidBrush(fill);
            e.Graphics.FillRectangle(brush, rect);
        }

        protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
        {
            using var brush = new SolidBrush(Theme.Surface);
            e.Graphics.FillRectangle(brush, e.AffectedBounds);
        }

        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            // suppress the default highlight line drawn at the top of StatusStrip
        }

        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            int y = e.Item.Height / 2;
            using var pen = new Pen(Theme.Border);
            e.Graphics.DrawLine(pen, 4, y, e.Item.Width - 4, y);
        }

        protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
        {
            var rect = new Rectangle(2, 1, e.Item.Height - 4, e.Item.Height - 4);
            using var pen = new Pen(Theme.Accent, 2);
            e.Graphics.DrawRectangle(pen, rect);
            if (e.Item is ToolStripMenuItem { Checked: true })
            {
                using var brush = new SolidBrush(Theme.Accent);
                e.Graphics.FillRectangle(brush, Rectangle.Inflate(rect, -3, -3));
            }
        }
    }

    internal sealed class ThemedColorTable : ProfessionalColorTable
    {
        public override Color MenuItemSelected              => Theme.SurfaceRaised;
        public override Color MenuItemBorder                => Theme.Border;
        public override Color MenuBorder                    => Theme.Border;
        public override Color MenuStripGradientBegin        => Theme.Surface;
        public override Color MenuStripGradientEnd          => Theme.Surface;
        public override Color MenuItemSelectedGradientBegin => Theme.SurfaceRaised;
        public override Color MenuItemSelectedGradientEnd   => Theme.SurfaceRaised;
        public override Color MenuItemPressedGradientBegin  => Theme.Background;
        public override Color MenuItemPressedGradientEnd    => Theme.Background;
        public override Color ToolStripDropDownBackground   => Theme.Surface;
        public override Color ImageMarginGradientBegin      => Theme.Surface;
        public override Color ImageMarginGradientMiddle     => Theme.Surface;
        public override Color ImageMarginGradientEnd        => Theme.Surface;
        public override Color SeparatorDark                 => Theme.Border;
        public override Color SeparatorLight                => Theme.Border;
        public override Color StatusStripGradientBegin      => Theme.Surface;
        public override Color StatusStripGradientEnd        => Theme.Surface;
        public override Color CheckBackground               => Theme.Accent;
        public override Color CheckSelectedBackground       => Theme.Accent;
        public override Color CheckPressedBackground        => Theme.Accent;
    }
}
