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
        private const int TilePadding = 8;   // gap between tiles (and outer margin)
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

        // ── colors ────────────────────────────────────────────────────────
private static readonly Color SelectionColor    = Color.FromArgb(0, 120, 215);
        private static readonly Color SelectionOverlay  = Color.FromArgb(40, 0, 120, 215);
        private static readonly Color LabelForeground   = Color.FromArgb(220, 220, 220);

        // ── events ────────────────────────────────────────────────────────
        public event EventHandler<GalleryItem>?        ItemDoubleClicked;
        public event EventHandler<GalleryClickEventArgs>? ItemClicked;
        public event EventHandler<GalleryItem[]>?      ItemsDraggedOut;
        public event EventHandler<string[]>?           FileDropped;
        public event EventHandler?                     SelectionChanged;

        // ── progress ─────────────────────────────────────────────────────
        private int _loadedCount = 0;
        public event EventHandler<float>? LoadProgressChanged;

        public VirtualGalleryPanel()
        {
            SetStyle(
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.AllPaintingInWmPaint  |
                ControlStyles.UserPaint             |
                ControlStyles.ResizeRedraw,
                true);
            BackColor = Color.FromArgb(70, 70, 70);
            AllowDrop  = true;
            TabStop    = true;
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
            _scrollY = 0;
            UpdateScrollbar();
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
        //  Painting
        // ══════════════════════════════════════════════════════════════════

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.InterpolationMode = InterpolationMode.Bilinear;

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
            if (_totalContentH <= ClientSize.Height)
            {
                VerticalScroll.Visible = false;
                AutoScrollMinSize = Size.Empty;
                return;
            }
            AutoScrollMinSize = new Size(0, _totalContentH);
            VerticalScroll.SmallChange = ScrollStep;
            VerticalScroll.LargeChange = ClientSize.Height;
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
                // pass to zoom handler via event bubble — handled by parent
                base.OnMouseWheel(e);
                return;
            }

            int delta = -(e.Delta / 120) * ScrollStep * 3;
            int newY = Math.Max(0, Math.Min(_scrollY + delta, Math.Max(0, _totalContentH - ClientSize.Height)));
            if (newY == _scrollY) return;
            _scrollY = newY;
            VerticalScroll.Value = _scrollY;
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
                ClearSelection();
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

        protected override void OnMouseUp(MouseEventArgs e) => base.OnMouseUp(e);

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
            if (drgevent.Data?.GetDataPresent(DataFormats.FileDrop) == true)
                drgevent.Effect = DragDropEffects.Copy;
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
                _scrollY = Math.Max(0, _scrollY + tb.Top - TilePadding);
            else if (tb.Bottom > ClientSize.Height)
                _scrollY = Math.Min(_totalContentH - ClientSize.Height, _scrollY + (tb.Bottom - ClientSize.Height) + TilePadding);
            UpdateScrollbar();
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
