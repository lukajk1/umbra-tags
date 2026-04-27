using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Calypso.UI
{
    public sealed class VirtualGalleryPanel : ScrollableControl
    {
        // ── layout constants ──────────────────────────────────────────────
        private const int TilePadding = 28;   // gap between tiles (and outer margin)
        private const int LabelH     = 20;
        private const int ScrollStep = 60;

        // ── tile size ─────────────────────────────────────────────────────
        private int _tileSize = 150;
        public int TileSize
        {
            get => _tileSize;
            set
            {
                _tileSize = Math.Max(1, value);
                RecalcLayout();
                Invalidate();
            }
        }

        public bool ShowLabels { get; set; } = true;

        // ── data ──────────────────────────────────────────────────────────
        private readonly List<GalleryItem> _items = new();
        public IReadOnlyList<GalleryItem> Items => _items;

        // ── selection ─────────────────────────────────────────────────────
        private readonly HashSet<int> _selectedIndices = new();
        public IReadOnlySet<int> SelectedIndices => _selectedIndices;
        private int _lastClickedIndex = -1;

        // ── image loading ─────────────────────────────────────────────────
        private Bitmap?[] _bitmaps = Array.Empty<Bitmap?>();
        private CancellationTokenSource? _loadCts;

        // ── layout cache ──────────────────────────────────────────────────
        private int _cols = 1;
        private int _rows = 0;
        private int _cellW = 1;   // tile + padding
        private int _cellH = 1;
        private int _totalContentH = 0;

        // ── scrolling ─────────────────────────────────────────────────────
        private int _scrollY = 0;

        // ── drag-out ─────────────────────────────────────────────────────
        private Point _dragStartPt = Point.Empty;
        private int _dragStartIndex = -1;
        private const int DragThreshold = 17;
        public static bool IsDraggingOut { get; private set; }

        // ── box select ────────────────────────────────────────────────────
        private Point _boxAnchor   = Point.Empty;   // screen-space anchor
        private Point _boxCurrent  = Point.Empty;   // screen-space current
        private bool  _isBoxSelecting = false;
        private HashSet<int> _preBoxSelection = new();

        // ── colors ────────────────────────────────────────────────────────
        private static Color SelectionColor   => Color.FromArgb(191, 191, 191);
        private static Color SelectionOverlay => Color.FromArgb(40, 255, 255, 255);
        private static Color LabelForeground  => Theme.Foreground;

        // ── ambient gradient ──────────────────────────────────────────────
        private Color[]? _gradientStrip = null;   // one color per pixel column
        private int      _gradientScrollY = -1;   // scroll position when strip was last built
        private const float GradientOpacity = 0.15f;

        // ── events ────────────────────────────────────────────────────────
        public event EventHandler<GalleryItem>?        ItemDoubleClicked;
        public event EventHandler<GalleryClickEventArgs>? ItemClicked;
        public event EventHandler<GalleryItem[]>?      ItemsDraggedOut;
        public event EventHandler<string[]>?           FileDropped;
        public event EventHandler?                     SelectionChanged;

        // ── progress ─────────────────────────────────────────────────────
        private int _loadedCount = 0;
        public event EventHandler<float>? LoadProgressChanged;

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            ThemeManager.ApplyScrollbarTheme(Handle);
        }

        public VirtualGalleryPanel()
        {
            SetStyle(
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.AllPaintingInWmPaint  |
                ControlStyles.UserPaint             |
                ControlStyles.ResizeRedraw,
                true);
            BackColor = Theme.Background;
            AllowDrop  = true;
            TabStop    = true;
        }

        // Suppress default background erase so our OnPaint gradient isn't wiped first
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            // intentionally empty — OnPaint fills the background itself
        }

        // ══════════════════════════════════════════════════════════════════
        //  Public API
        // ══════════════════════════════════════════════════════════════════

        public void Populate(IEnumerable<ImageData> images)
        {
            _loadCts?.Cancel();
            _loadCts = new CancellationTokenSource();

            DisposeAllBitmaps();
            _items.Clear();
            _selectedIndices.Clear();
            _lastClickedIndex = -1;
            _scrollY = 0;

            foreach (var img in images)
                _items.Add(new GalleryItem(img));

            _bitmaps = new Bitmap?[_items.Count];
            _gradientStrip   = null;
            _gradientScrollY = -1;

            RecalcLayout();
            UpdateScrollbar();
            Invalidate();

            SelectionChanged?.Invoke(this, EventArgs.Empty);
            BeginLoadImages(_loadCts.Token);
        }

        public void InsertAtFront(IEnumerable<ImageData> images)
        {
            _loadCts?.Cancel();
            _loadCts = new CancellationTokenSource();

            var list = images.ToList();
            var newItems = list.Select(img => new GalleryItem(img)).ToList();

            _items.InsertRange(0, newItems);

            // shift existing bitmaps right, prepend nulls
            var oldBitmaps = _bitmaps;
            _bitmaps = new Bitmap?[_items.Count];
            Array.Copy(oldBitmaps, 0, _bitmaps, list.Count, oldBitmaps.Length);

            // shift selected indices
            var shifted = _selectedIndices.Select(i => i + list.Count).ToHashSet();
            _selectedIndices.Clear();
            foreach (var i in shifted) _selectedIndices.Add(i);
            if (_lastClickedIndex >= 0) _lastClickedIndex += list.Count;

            _scrollY = 0;
            RecalcLayout();
            UpdateScrollbar();
            Invalidate();

            BeginLoadImages(_loadCts.Token, startIndex: 0, count: list.Count);
        }

        public void RemoveItems(IEnumerable<GalleryItem> toRemove)
        {
            var set = new HashSet<GalleryItem>(toRemove);
            var indices = _items
                .Select((item, i) => (item, i))
                .Where(t => set.Contains(t.item))
                .Select(t => t.i)
                .OrderByDescending(i => i)
                .ToList();

            foreach (int i in indices)
            {
                _bitmaps[i]?.Dispose();
                _items.RemoveAt(i);
                var newBitmaps = new Bitmap?[_items.Count];
                Array.Copy(_bitmaps, 0, newBitmaps, 0, i);
                if (i < _bitmaps.Length - 1)
                    Array.Copy(_bitmaps, i + 1, newBitmaps, i, _bitmaps.Length - i - 1);
                _bitmaps = newBitmaps;
            }

            _selectedIndices.RemoveWhere(i => i >= _items.Count);
            if (_lastClickedIndex >= _items.Count) _lastClickedIndex = _items.Count - 1;

            RecalcLayout();
            UpdateScrollbar();
            Invalidate();
            SelectionChanged?.Invoke(this, EventArgs.Empty);
        }

        public List<GalleryItem> GetSelectedItems()
            => _selectedIndices.OrderBy(i => i).Select(i => _items[i]).ToList();

        public void ClearSelection()
        {
            _selectedIndices.Clear();
            Invalidate();
            SelectionChanged?.Invoke(this, EventArgs.Empty);
        }

        public void SelectAll()
        {
            _selectedIndices.Clear();
            for (int i = 0; i < _items.Count; i++) _selectedIndices.Add(i);
            Invalidate();
            SelectionChanged?.Invoke(this, EventArgs.Empty);
        }

        public int ColsPerRow => _cols;

        public void ScrollToTop()
        {
            SetScrollY(0);
            Invalidate();
        }

        // ══════════════════════════════════════════════════════════════════
        //  Layout
        // ══════════════════════════════════════════════════════════════════

        private void RecalcLayout()
        {
            int tileH = _tileSize + (ShowLabels ? LabelH : 0);
            _cellW = _tileSize + TilePadding;
            _cellH = tileH + TilePadding;

            int usable = Math.Max(1, ClientSize.Width - TilePadding);
            _cols = Math.Max(1, usable / _cellW);
            _rows = _items.Count == 0 ? 0 : (int)Math.Ceiling(_items.Count / (double)_cols);
            _totalContentH = _rows * _cellH + TilePadding;

            _scrollY = Math.Max(0, Math.Min(_scrollY, Math.Max(0, _totalContentH - ClientSize.Height)));
        }

        private Rectangle TileBounds(int index)
        {
            int col = index % _cols;
            int row = index / _cols;
            int x = TilePadding + col * _cellW;
            int y = TilePadding + row * _cellH - _scrollY;
            return new Rectangle(x, y, _tileSize, _tileSize);
        }

        private int HitTest(Point pt)
        {
            int adjustedY = pt.Y + _scrollY;
            int col = (pt.X - TilePadding) / _cellW;
            int row = (adjustedY - TilePadding) / _cellH;

            if (col < 0 || col >= _cols || row < 0) return -1;

            // check the click lands within the tile itself (not in the gap)
            int localX = (pt.X - TilePadding) - col * _cellW;
            int localY = (adjustedY - TilePadding) - row * _cellH;
            if (localX < 0 || localX >= _tileSize || localY < 0 || localY >= _tileSize + (ShowLabels ? LabelH : 0))
                return -1;

            int index = row * _cols + col;
            return index < _items.Count ? index : -1;
        }

        // ══════════════════════════════════════════════════════════════════
        //  Ambient gradient
        // ══════════════════════════════════════════════════════════════════

        private void RebuildGradientIfNeeded()
        {
            // Rebuild if scroll changed meaningfully or panel was repopulated
            if (_gradientStrip != null && Math.Abs(_gradientScrollY - _scrollY) < _cellH / 2)
                return;

            _gradientScrollY = _scrollY;
            int h = Math.Max(1, ClientSize.Height);

            // Collect visible rows — one average color per row
            int firstRow = Math.Max(0, (_scrollY - TilePadding) / _cellH);
            int lastRow  = Math.Min(_rows - 1, (_scrollY + ClientSize.Height + _cellH - 1) / _cellH);

            // Build list of (screenCenterY, avgColor) per tile row
            var rowColors = new List<(float cy, Color color)>();
            for (int row = firstRow; row <= lastRow; row++)
            {
                var colors = new List<Color>();
                for (int col = 0; col < _cols; col++)
                {
                    int index = row * _cols + col;
                    if (index >= _items.Count) break;
                    string? grid = _items[index].ImageData.ColorGrid;
                    if (grid == null) continue;
                    colors.Add(ColorGrid.AverageColor(grid));
                }
                if (colors.Count == 0) continue;

                // screen Y center of this tile row
                int tileY = TilePadding + row * _cellH - _scrollY;
                float cy = tileY + _tileSize / 2f;

                int r = 0, gg = 0, b = 0;
                foreach (var c in colors) { r += c.R; gg += c.G; b += c.B; }
                rowColors.Add((cy, Color.FromArgb(r / colors.Count, gg / colors.Count, b / colors.Count)));
            }

            if (rowColors.Count == 0)
            {
                _gradientStrip = null;
                return;
            }

            rowColors.Sort((a, b) => a.cy.CompareTo(b.cy));

            // Sample: for each pixel row, interpolate between nearest row centers
            var raw = new Color[h];
            for (int py = 0; py < h; py++)
            {
                int li = 0, ri = rowColors.Count - 1;
                for (int k = 0; k < rowColors.Count; k++)
                {
                    if (rowColors[k].cy <= py) li = k;
                    if (rowColors[k].cy >= py) { ri = k; break; }
                }

                Color ca = rowColors[li].color;
                Color cb = rowColors[ri].color;
                float t  = rowColors[li].cy == rowColors[ri].cy ? 0f
                    : Math.Clamp((py - rowColors[li].cy) / (rowColors[ri].cy - rowColors[li].cy), 0f, 1f);

                raw[py] = BlendColors(ca, cb, t);
            }

            // Box blur vertically (3 passes)
            int blurRadius = Math.Max(8, h / 12);
            for (int pass = 0; pass < 3; pass++)
                raw = BoxBlur(raw, blurRadius);

            // Blend with background at GradientOpacity
            var bg = Theme.Background;
            _gradientStrip = new Color[h];
            for (int py = 0; py < h; py++)
                _gradientStrip[py] = BlendColors(bg, raw[py], GradientOpacity);
        }

        private void DrawGradient(Graphics g)
        {
            if (_gradientStrip == null || _gradientStrip.Length < 2) return;

            int w = ClientSize.Width;
            int h = ClientSize.Height;

            int step = Math.Max(1, h / 64); // at most 64 horizontal bands
            for (int py = 0; py < h; py += step)
            {
                int segH     = Math.Min(step, h - py);
                int idxTop   = Math.Clamp(py,        0, _gradientStrip.Length - 1);
                int idxBot   = Math.Clamp(py + segH, 0, _gradientStrip.Length - 1);

                using var brush = new LinearGradientBrush(
                    new Rectangle(0, py, w, segH + 1),
                    _gradientStrip[idxTop],
                    _gradientStrip[idxBot],
                    LinearGradientMode.Vertical);
                g.FillRectangle(brush, 0, py, w, segH);
            }
        }

        private static Color AverageColorArray(Color[] cols)
        {
            int r = 0, g = 0, b = 0;
            foreach (var c in cols) { r += c.R; g += c.G; b += c.B; }
            return Color.FromArgb(r / cols.Length, g / cols.Length, b / cols.Length);
        }

        private static Color BlendColors(Color a, Color b, float t)
        {
            return Color.FromArgb(
                (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t),
                (int)(a.B + (b.B - a.B) * t));
        }

        private static Color[] BoxBlur(Color[] src, int radius)
        {
            int len = src.Length;
            var dst = new Color[len];
            for (int i = 0; i < len; i++)
            {
                int lo = Math.Max(0, i - radius);
                int hi = Math.Min(len - 1, i + radius);
                int count = hi - lo + 1;
                int r = 0, g2 = 0, b = 0;
                for (int j = lo; j <= hi; j++) { r += src[j].R; g2 += src[j].G; b += src[j].B; }
                dst[i] = Color.FromArgb(r / count, g2 / count, b / count);
            }
            return dst;
        }

        // ══════════════════════════════════════════════════════════════════
        //  Painting
        // ══════════════════════════════════════════════════════════════════

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.InterpolationMode = InterpolationMode.Bilinear;

            // ── background fill (always, since OnPaintBackground is suppressed) ──
            g.Clear(Theme.Background);

            // ── ambient gradient background ───────────────────────────────
            RebuildGradientIfNeeded();
            DrawGradient(g);

            int firstRow = Math.Max(0, (_scrollY - TilePadding) / _cellH);
            int lastRow  = Math.Min(_rows - 1, (_scrollY + ClientSize.Height + _cellH - 1) / _cellH);

            for (int row = firstRow; row <= lastRow; row++)
            {
                for (int col = 0; col < _cols; col++)
                {
                    int index = row * _cols + col;
                    if (index >= _items.Count) break;

                    var tb = TileBounds(index);
                    DrawTile(g, index, tb);
                }
            }

            if (_isBoxSelecting)
            {
                var r = GetBoxRect();
                if (r.Width > 2 && r.Height > 2)
                {
                    using var fillBrush = new SolidBrush(Color.FromArgb(40, 191, 191, 191));
                    g.FillRectangle(fillBrush, r);
                    using var borderPen = new Pen(Color.FromArgb(191, 191, 191), 1);
                    g.DrawRectangle(borderPen, r.X, r.Y, r.Width - 1, r.Height - 1);
                }
            }
        }

        private static Rectangle LetterboxRect(Rectangle cell, int imgW, int imgH)
        {
            if (imgW <= 0 || imgH <= 0) return cell;
            float scale = Math.Min((float)cell.Width / imgW, (float)cell.Height / imgH);
            int w = (int)(imgW * scale);
            int h = (int)(imgH * scale);
            return new Rectangle(cell.X + (cell.Width - w) / 2, cell.Y + (cell.Height - h) / 2, w, h);
        }

        private void DrawTile(Graphics g, int index, Rectangle tb)
        {
            bool selected = _selectedIndices.Contains(index);
            var bmp = _bitmaps[index];

            if (bmp != null)
            {
                var dest = LetterboxRect(tb, bmp.Width, bmp.Height);
                g.DrawImage(bmp, dest);
            }

            // selection overlay + border
            if (selected)
            {
                using var overlayBrush = new SolidBrush(SelectionOverlay);
                g.FillRectangle(overlayBrush, tb);
                using var pen = new Pen(SelectionColor, 2);
                g.DrawRectangle(pen, tb.X, tb.Y, tb.Width - 1, tb.Height - 1);
            }

            // video badge: ▶ centred on the tile
            if (_items[index].ImageData.IsVideo)
            {
                const int BadgeSize = 36;
                var badge = new Rectangle(tb.X + (tb.Width - BadgeSize) / 2, tb.Y + (tb.Height - BadgeSize) / 2, BadgeSize, BadgeSize);
                using var bgBrush = new SolidBrush(Color.FromArgb(160, 0, 0, 0));
                g.FillEllipse(bgBrush, badge);
                using var fgBrush = new SolidBrush(Color.FromArgb(220, 255, 255, 255));
                using var badgeFont = new Font("Segoe UI Symbol", BadgeSize * 0.45f, GraphicsUnit.Pixel);
                var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                g.DrawString("▶", badgeFont, fgBrush, badge, sf);
            }

            // label
            if (ShowLabels)
            {
                var labelRect = new Rectangle(tb.X, tb.Bottom, tb.Width, LabelH);
                using var labelBrush = new SolidBrush(LabelForeground);
                var fmt = new StringFormat
                {
                    Alignment     = StringAlignment.Center,
                    LineAlignment = StringAlignment.Center,
                    Trimming      = StringTrimming.EllipsisCharacter,
                    FormatFlags   = StringFormatFlags.NoWrap
                };
                g.DrawString(_items[index].ImageData.Filename, Font, labelBrush, labelRect, fmt);
            }
        }

        // ══════════════════════════════════════════════════════════════════
        //  Scrolling
        // ══════════════════════════════════════════════════════════════════

        private void UpdateScrollbar()
        {
            int maxScroll = Math.Max(0, _totalContentH - ClientSize.Height);
            if (maxScroll == 0)
            {
                AutoScrollMinSize = Size.Empty;
                _scrollY = 0;
                return;
            }
            AutoScrollMinSize = new Size(0, _totalContentH);
            VerticalScroll.SmallChange = ScrollStep;
            VerticalScroll.LargeChange = Math.Max(1, ClientSize.Height);
            // clamp and sync after layout changes
            _scrollY = Math.Min(_scrollY, maxScroll);
            SetScrollY(_scrollY);
        }

        private void SetScrollY(int value)
        {
            int maxScroll = Math.Max(0, _totalContentH - ClientSize.Height);
            _scrollY = Math.Max(0, Math.Min(value, maxScroll));
            if (VerticalScroll.Visible)
            {
                int clamped = Math.Min(_scrollY, VerticalScroll.Maximum - VerticalScroll.LargeChange + 1);
                if (clamped >= 0) VerticalScroll.Value = clamped;
            }
        }

        private const int WM_VSCROLL = 0x0115;
        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg == WM_VSCROLL)
            {
                _scrollY = Math.Max(0, Math.Min(VerticalScroll.Value, Math.Max(0, _totalContentH - ClientSize.Height)));
                Invalidate();
            }
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            if ((ModifierKeys & Keys.Control) == Keys.Control)
            {
                base.OnMouseWheel(e);
                return;
            }

            int delta = -(e.Delta / 120) * ScrollStep * 3;
            SetScrollY(_scrollY + delta);
            Invalidate();
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            RecalcLayout();
            UpdateScrollbar();
            Invalidate();
        }

        // ══════════════════════════════════════════════════════════════════
        //  Mouse: click / double-click / drag-out
        // ══════════════════════════════════════════════════════════════════

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            Focus();

            int index = HitTest(e.Location);
            if (index < 0)
            {
                if (e.Button == MouseButtons.Left)
                {
                    bool additive = (ModifierKeys & Keys.Control) == Keys.Control;
                    _preBoxSelection = additive ? new HashSet<int>(_selectedIndices) : new HashSet<int>();
                    if (!additive) { _selectedIndices.Clear(); Invalidate(); SelectionChanged?.Invoke(this, EventArgs.Empty); }
                    _boxAnchor    = e.Location;
                    _boxCurrent   = e.Location;
                    _isBoxSelecting = true;
                }
                else
                {
                    ClearSelection();
                }
                return;
            }

            _dragStartPt    = e.Location;
            _dragStartIndex = index;

            bool ctrl  = (ModifierKeys & Keys.Control) == Keys.Control;
            bool shift = (ModifierKeys & Keys.Shift)   == Keys.Shift;

            bool rightWithinMulti = e.Button == MouseButtons.Right
                && _selectedIndices.Count > 1
                && _selectedIndices.Contains(index);

            if (shift && _lastClickedIndex >= 0)
            {
                int lo = Math.Min(_lastClickedIndex, index);
                int hi = Math.Max(_lastClickedIndex, index);
                for (int i = lo; i <= hi; i++) _selectedIndices.Add(i);
            }
            else if (ctrl)
            {
                if (_selectedIndices.Contains(index))
                    _selectedIndices.Remove(index);
                else
                    _selectedIndices.Add(index);
            }
            else if (!rightWithinMulti)
            {
                _selectedIndices.Clear();
                _selectedIndices.Add(index);
            }

            _lastClickedIndex = index;
            Invalidate();
            SelectionChanged?.Invoke(this, EventArgs.Empty);

            ItemClicked?.Invoke(this, new GalleryClickEventArgs(_items[index], e.Button, e.Location));

            if (e.Button == MouseButtons.Right)
                _dragStartPt = Point.Empty;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);

            if (_isBoxSelecting && e.Button == MouseButtons.Left)
            {
                _boxCurrent = e.Location;
                UpdateBoxSelection();
                Invalidate();
                return;
            }

            if (e.Button != MouseButtons.Left || _dragStartPt == Point.Empty || _dragStartIndex < 0) return;

            if (Math.Abs(e.X - _dragStartPt.X) <= DragThreshold &&
                Math.Abs(e.Y - _dragStartPt.Y) <= DragThreshold) return;

            var dragItems = _selectedIndices.Contains(_dragStartIndex)
                ? GetSelectedItems()
                : new List<GalleryItem> { _items[_dragStartIndex] };

            var files = dragItems
                .Where(it => File.Exists(it.ImageData.Filepath))
                .Select(it => it.ImageData.Filepath)
                .ToArray();

            if (files.Length == 0) return;

            _dragStartPt = Point.Empty;
            IsDraggingOut = true;
            Calypso.ImageInfoPanel.Freeze();
            ItemsDraggedOut?.Invoke(this, dragItems.ToArray());
            DoDragDrop(new DataObject(DataFormats.FileDrop, files), DragDropEffects.Copy);
            IsDraggingOut = false;
            Calypso.ImageInfoPanel.Unfreeze();
            SelectionChanged?.Invoke(this, EventArgs.Empty);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (_isBoxSelecting)
            {
                _isBoxSelecting = false;
                _boxAnchor  = Point.Empty;
                _boxCurrent = Point.Empty;
                Invalidate();
                SelectionChanged?.Invoke(this, EventArgs.Empty);
            }
        }

        protected override void OnDoubleClick(EventArgs e)
        {
            base.OnDoubleClick(e);
            var pt = PointToClient(MousePosition);
            int index = HitTest(pt);
            if (index >= 0)
                ItemDoubleClicked?.Invoke(this, _items[index]);
        }

        // ══════════════════════════════════════════════════════════════════
        //  Drag-in
        // ══════════════════════════════════════════════════════════════════

        protected override void OnDragEnter(DragEventArgs drgevent)
        {
            if (drgevent.Data?.GetData(DataFormats.FileDrop) is string[] files &&
                files.Any(f => Util.IsSupportedExtension(Path.GetExtension(f).ToLower())))
                drgevent.Effect = DragDropEffects.Copy;
            else
                drgevent.Effect = DragDropEffects.None;
        }

        protected override void OnDragOver(DragEventArgs drgevent)
        {
            if (drgevent.Data?.GetData(DataFormats.FileDrop) is string[] files &&
                files.Any(f => Util.IsSupportedExtension(Path.GetExtension(f).ToLower())))
                drgevent.Effect = DragDropEffects.Copy;
            else
                drgevent.Effect = DragDropEffects.None;
        }

        protected override void OnDragDrop(DragEventArgs drgevent)
        {
            if (drgevent.Data?.GetData(DataFormats.FileDrop) is string[] files)
                FileDropped?.Invoke(this, files);
        }

        // ══════════════════════════════════════════════════════════════════
        //  Keyboard
        // ══════════════════════════════════════════════════════════════════

        protected override bool IsInputKey(Keys keyData) =>
            keyData is Keys.Left or Keys.Right or Keys.Up or Keys.Down || base.IsInputKey(keyData);

        public void ArrowSelect(Keys key)
        {
            if (_items.Count == 0) return;

            int current = _lastClickedIndex >= 0 ? _lastClickedIndex : (_selectedIndices.Count > 0 ? _selectedIndices.Min() : 0);
            int next = key switch
            {
                Keys.Left  => current - 1,
                Keys.Right => current + 1,
                Keys.Up    => current - _cols,
                Keys.Down  => current + _cols,
                _          => current
            };
            next = Math.Clamp(next, 0, _items.Count - 1);
            if (next == current) return;

            _selectedIndices.Clear();
            _selectedIndices.Add(next);
            _lastClickedIndex = next;
            EnsureVisible(next);
            Invalidate();
            SelectionChanged?.Invoke(this, EventArgs.Empty);
            ItemClicked?.Invoke(this, new GalleryClickEventArgs(_items[next], MouseButtons.None, Point.Empty));
        }

        private void EnsureVisible(int index)
        {
            var tb = TileBounds(index);
            if (tb.Top < 0)
                SetScrollY(_scrollY + tb.Top - TilePadding);
            else if (tb.Bottom > ClientSize.Height)
                SetScrollY(_scrollY + (tb.Bottom - ClientSize.Height) + TilePadding);
            Invalidate();
        }

        // ── box select helpers ────────────────────────────────────────────

        private Rectangle GetBoxRect()
        {
            int x = Math.Min(_boxAnchor.X, _boxCurrent.X);
            int y = Math.Min(_boxAnchor.Y, _boxCurrent.Y);
            int w = Math.Abs(_boxCurrent.X - _boxAnchor.X);
            int h = Math.Abs(_boxCurrent.Y - _boxAnchor.Y);
            return new Rectangle(x, y, w, h);
        }

        private void UpdateBoxSelection()
        {
            var screenRect = GetBoxRect();
            // convert to scroll-space for tile intersection
            var scrollRect = new Rectangle(screenRect.X, screenRect.Y + _scrollY, screenRect.Width, screenRect.Height);

            _selectedIndices.Clear();
            foreach (var i in _preBoxSelection) _selectedIndices.Add(i);

            for (int i = 0; i < _items.Count; i++)
            {
                int col = i % _cols;
                int row = i / _cols;
                int tx = TilePadding + col * _cellW;
                int ty = TilePadding + row * _cellH;
                var tileBounds = new Rectangle(tx, ty, _tileSize, _tileSize + (ShowLabels ? LabelH : 0));

                if (tileBounds.IntersectsWith(scrollRect))
                    _selectedIndices.Add(i);
            }

            SelectionChanged?.Invoke(this, EventArgs.Empty);
        }

        // ══════════════════════════════════════════════════════════════════
        //  Async image loading
        // ══════════════════════════════════════════════════════════════════

        private void BeginLoadImages(CancellationToken token, int startIndex = 0, int count = -1)
        {
            if (count < 0) count = _items.Count - startIndex;
            if (count == 0) return;

            int total = count;
            _loadedCount = 0;
            LoadProgressChanged?.Invoke(this, 0.01f);

            for (int i = startIndex; i < startIndex + count; i++)
            {
                int captured = i;
                string thumbPath = _items[i].ImageData.ThumbnailPath;

                Task.Run(() =>
                {
                    if (token.IsCancellationRequested) return;
                    try
                    {
                        var bmp = Util.LoadImage(thumbPath);
                        if (token.IsCancellationRequested) { bmp.Dispose(); return; }

                        BeginInvoke(() =>
                        {
                            if (token.IsCancellationRequested || captured >= _bitmaps.Length)
                            {
                                bmp.Dispose();
                                return;
                            }
                            _bitmaps[captured]?.Dispose();
                            _bitmaps[captured] = bmp;

                            // only repaint the affected tile rows
                            var tb = TileBounds(captured);
                            Invalidate(new Rectangle(0, tb.Y - 2, ClientSize.Width, tb.Height + LabelH + 4));

                            int done = Interlocked.Increment(ref _loadedCount);
                            float progress = (float)done / total;
                            LoadProgressChanged?.Invoke(this, done == total ? 0f : progress);
                        });
                    }
                    catch { }
                }, token);
            }
        }

        // ══════════════════════════════════════════════════════════════════
        //  Cleanup
        // ══════════════════════════════════════════════════════════════════

        private void DisposeAllBitmaps()
        {
            foreach (var bmp in _bitmaps)
                bmp?.Dispose();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _loadCts?.Cancel();
                DisposeAllBitmaps();
            }
            base.Dispose(disposing);
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Supporting types
    // ══════════════════════════════════════════════════════════════════════

    public sealed class GalleryItem
    {
        public ImageData ImageData { get; }
        public GalleryItem(ImageData data) => ImageData = data;
    }

    public sealed class GalleryClickEventArgs : EventArgs
    {
        public GalleryItem Item   { get; }
        public MouseButtons Button { get; }
        public Point        Location { get; }
        public GalleryClickEventArgs(GalleryItem item, MouseButtons button, Point location)
        {
            Item = item; Button = button; Location = location;
        }
    }
}
