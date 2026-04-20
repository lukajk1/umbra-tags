using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.IO;
using System.Diagnostics;
using System.Data;
using Calypso.UI;
namespace Calypso
{
    internal partial class Gallery
    {
        static FlowLayoutPanel? flowLayoutGallery;
        static ContextMenuStrip? imageContextMenuStrip; 
        static MainWindow? mainW;
        static PictureBox? pictureBoxPreview;
        static ToolStripStatusLabel? selectedCountLabel;
        static ToolStripStatusLabel? resultsCountLabel;

        static List<ImageData> lastSearch = new();
        static List<TileTag> selectedTiles = new();
        static List<TileTag> allTiles = new();

        static TileTag? lastSelected; 

        private static readonly Stack<PooledTile> pooledTiles = new();
        private static readonly Color PlaceholderColor = Color.FromArgb(60, 60, 60);

        private static int pbPerRow = 0;
        private static float _loadProgress = 0f;
        public static float LoadProgress
        {
            get => _loadProgress;
            set
            {
                mainW.toolStripProgressBar1.Value = (int)(value * 100f);

                if (value == 0) mainW.toolStripProgressBar1.Visible = false;
                else mainW.toolStripProgressBar1.Visible = true;
            }
        }
        private const int ZoomPixelInterval = 50;
        private const int MinZoomSteps = -4;
        private const int MaxZoomSteps = 8;
        private static int _zoomSteps = 0;
        public static int Zoom
        {
            get => _zoomSteps;
            set
            {
                int clamped = Math.Clamp(value, MinZoomSteps, MaxZoomSteps);
                if (clamped != _zoomSteps)
                {
                    _zoomSteps = clamped;
                    SetZoom(GlobalValues.DefaultThumbnailSize + _zoomSteps * ZoomPixelInterval);
                }
            }
        }

        public static void Init(MainWindow mainW)
        {
            Gallery.mainW = mainW;
            Gallery.flowLayoutGallery = mainW.flowLayoutGallery;
            Gallery.pictureBoxPreview = mainW.pictureBoxImagePreview;
            Gallery.selectedCountLabel = mainW.selectedCountLabel;
            Gallery.resultsCountLabel = mainW.statusLabelResultsCount;

            var editTagsItem = new ToolStripMenuItem("Edit Tags");
            editTagsItem.Click += (s, e) => OpenTagEditorByCommand();
            var showInFolderItem = new ToolStripMenuItem("Show in Folder");
            showInFolderItem.Click += (s, e) => OpenSelectedInExplorer();
            var deleteItem = new ToolStripMenuItem("Delete");
            deleteItem.Click += (s, e) => DeleteSelected();
            imageContextMenuStrip = new ContextMenuStrip();
            imageContextMenuStrip.Items.AddRange(new ToolStripItem[] { editTagsItem, showInFolderItem, new ToolStripSeparator(), deleteItem });

            flowLayoutGallery.AllowDrop = true;
            flowLayoutGallery.DragEnter += flowLayoutGallery_DragEnter;
            flowLayoutGallery.DragDrop += flowLayoutGallery_DragDrop;
            flowLayoutGallery.SizeChanged += FlowLayoutGallery_SizeChanged;
            flowLayoutGallery.MouseWheel += FlowLayoutGallery_MouseWheel;

            // Enable double-buffering on the FlowLayoutPanel to reduce repaint flicker during resize.
            // DoubleBuffered is protected on Control, so reflection is required to set it externally.
            typeof(Control).GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
                ?.SetValue(flowLayoutGallery, true);

            DB.OnNewLibraryLoaded += OnNewLibraryLoaded;
        }

        public static void Populate(List<ImageData> results)
        {
            lastSearch = results;
            ClearExistingControls();
            GenerateGallery(results);

            if (_zoomSteps != 0)
                SetZoom(GlobalValues.DefaultThumbnailSize + _zoomSteps * ZoomPixelInterval);

            resultsCountLabel.Text = $"Results: {results.Count}";
            mainW.toolStripLabelThumbnailSize.Text = $"Thumbnail Height: {GlobalValues.DefaultThumbnailSize + _zoomSteps * ZoomPixelInterval}px";
        }
        public static void OnNewLibraryLoaded(Library lib)
        {
            selectedTiles.Clear();
            lastSelected = null;
            ImageInfoPanel.Clear();
        }
        private static Bitmap MakePlaceholder(int width, int height)
        {
            var bmp = new Bitmap(width, height);
            using var g = Graphics.FromImage(bmp);
            g.Clear(PlaceholderColor);
            return bmp;
        }

        private static PooledTile GetPooledTile()
        {
            return pooledTiles.Count > 0 ? pooledTiles.Pop() : new PooledTile();
        }

        private static void ReturnPooledTile(PooledTile tile)
        {
            tile.Reset();
            pooledTiles.Push(tile);
        }


        private static CancellationTokenSource? _loadCts;

        private static void GenerateGallery(List<ImageData> results)
        {
            _loadCts?.Cancel();
            _loadCts = new CancellationTokenSource();
            var token = _loadCts.Token;

            // Add all tiles to the gallery immediately with no image, so the grid appears at once.
            flowLayoutGallery.SuspendLayout();
            var tiles = new List<(TileTag tileTag, string thumbnailPath)>(results.Count);
            foreach (ImageData imageData in results)
            {
                var tileTag = AddCardShell(imageData);
                if (tileTag != null)
                    tiles.Add((tileTag, imageData.ThumbnailPath));
            }
            flowLayoutGallery.ResumeLayout(true);
            CountPictureBoxesPerRow();

            // Load images from disk in parallel, marshal each result back to the UI thread.
            int completed = 0;
            foreach (var (tileTag, thumbnailPath) in tiles)
            {
                var capturedTag = tileTag;
                Task.Run(() =>
                {
                    if (token.IsCancellationRequested) return;
                    try
                    {
                        var bmp = Util.LoadImage(thumbnailPath);

                        if (token.IsCancellationRequested) { bmp.Dispose(); return; }

                        flowLayoutGallery.BeginInvoke(() =>
                        {
                            if (token.IsCancellationRequested || capturedTag._PictureBox.Tag != capturedTag) { bmp.Dispose(); return; }
                            capturedTag._PictureBox.Image?.Dispose();
                            capturedTag._PictureBox.Image = bmp;

                            int done = Interlocked.Increment(ref completed);
                            LoadProgress = (float)done / tiles.Count;
                            if (done == tiles.Count) LoadProgress = 0f;
                        });
                    }
                    catch { /* skip tiles that can't be read */ }
                }, token);
            }
        }

        private static void ClearExistingControls()
        {
            foreach (Control control in flowLayoutGallery.Controls.Cast<Control>().ToList())
            {
                if (control is Panel panel &&
                    panel.Controls.OfType<PictureBox>().FirstOrDefault() is PictureBox pb &&
                    pb.Tag is TileTag tTag)
                {
                    if (pb.Tag is TileTag tileTag && tTag._PooledTile != null)
                    {
                        ReturnPooledTile(tileTag._PooledTile);
                    }
                }
            }

            flowLayoutGallery.Controls.Clear();
            flowLayoutGallery.Invalidate();
            flowLayoutGallery.Update();
        }

        private static DateTime _lastZoomTime = DateTime.MinValue;
        private static readonly TimeSpan ZoomCooldown = TimeSpan.FromMilliseconds(400);

        public static void ZoomFromWheel(MouseEventArgs e)
        {
            if ((Control.ModifierKeys & Keys.Control) != Keys.Control) return;
            if (DateTime.UtcNow - _lastZoomTime < ZoomCooldown) return;

            _lastZoomTime = DateTime.UtcNow;

            if (e.Delta > 0)
                Gallery.Zoom += 1;
            else if (e.Delta < 0)
                Gallery.Zoom -= 1;
        }

        private static void SetZoom(int thumbSize)
        {
            flowLayoutGallery.SuspendLayout();
            foreach (TileTag tile in allTiles)
            {
                tile._PictureBox.Size = new Size(thumbSize, thumbSize);

                Label? label = tile._Container.Controls.OfType<Label>().FirstOrDefault();
                int labelHeight = label?.Height ?? 20;

                tile._Container.Width = thumbSize + 10;
                tile._Container.Height = thumbSize + labelHeight + 10;
            }
            flowLayoutGallery.ResumeLayout(true);
            CountPictureBoxesPerRow();
        }


        private static void ClearSelection()
        {
            foreach (TileTag tTag in selectedTiles)
            {
                tTag._Container.BorderStyle = BorderStyle.None;
            }

            selectedTiles.Clear();
        }

        private static void AddToSelection(TileTag tTag)
        {
            selectedTiles.Add(tTag);
            tTag._Container.BorderStyle = BorderStyle.FixedSingle;
            selectedCountLabel.Text = $"Selected: ({selectedTiles.Count})";

            ImageInfoPanel.Display(tTag._ImageData);
        }

        public static void SelectAll()
        {
            ClearSelection(); // Optional, depending on behavior

            foreach (TileTag tTag in allTiles)
            {
                tTag._Container.BorderStyle = BorderStyle.FixedSingle;
            }

            selectedTiles = new List<TileTag>(allTiles);
            selectedCountLabel.Text = $"Selected: ({selectedTiles.Count})";

            if (selectedTiles.Count > 0)
                ImageInfoPanel.Display(selectedTiles[0]._ImageData);
        }


        // Creates the tile shell on the UI thread without loading the image.
        // Returns null if the thumbnail file doesn't exist.
        private static TileTag? AddCardShell(ImageData imgData)
        {
            if (!File.Exists(imgData.ThumbnailPath)) return null;

            PooledTile tile = GetPooledTile();
            int thumbSize = GlobalValues.DefaultThumbnailSize + _zoomSteps * ZoomPixelInterval;
            tile.PictureBox.Size = new Size(thumbSize, thumbSize);
            tile.Container.Width = thumbSize + 10;
            tile.Container.Height = thumbSize + tile.Label.Height + 10;
            tile.Label.Text = imgData.Filename;
            tile.Label.Visible = PreferencesManager.Prefs.ShowFilenames;

            TileTag tileTag = new TileTag
            {
                _ImageData = imgData,
                _Container = tile.Container,
                _PictureBox = tile.PictureBox,
                _PooledTile = tile
            };

            tile.PictureBox.Tag = tileTag;
            tile.PictureBox.Image = MakePlaceholder(thumbSize, thumbSize);
            allTiles.Add(tileTag);

            tile.PictureBox.DoubleClick += PictureBox_DoubleClick;
            tile.PictureBox.MouseClick += PictureBox_MouseClick;
            AddDraggableHandlers(tile.PictureBox);

            flowLayoutGallery.Controls.Add(tile.Container);
            return tileTag;
        }

        public static void AddCard(ImageData imgData)
        {
            var tileTag = AddCardShell(imgData);
            if (tileTag == null) return;

            tileTag._PictureBox.Image = Util.LoadImage(imgData.ThumbnailPath);
        }


        public static void DeleteSelected()
        {
            foreach (TileTag t in selectedTiles)
            {
                if (t._Container != null && flowLayoutGallery.Controls.Contains(t._Container))
                {
                    flowLayoutGallery.Controls.Remove(t._Container);
                    t._Container.Dispose();
                }

                if (t._PictureBox.Image != null)
                {
                    t._PictureBox.Image.Dispose();
                }
            }

            DB.DeleteImageData(selectedTiles.Select(t => t._ImageData).ToList());

            selectedTiles.Clear();
        }

        public static int CountPictureBoxesPerRow()
        {
            int? currentRowY = null;
            int count = 0;

            foreach (Control ctrl in flowLayoutGallery.Controls)
            {
                if (ctrl is Panel panel)
                {
                    if (currentRowY == null)
                    {
                        currentRowY = panel.Top;
                    }

                    if (panel.Top == currentRowY)
                    {
                        count++;
                    }
                    else
                    {
                        break;
                    }
                }
            }
            pbPerRow = count;
            return count;
        }
        public static void OpenTagEditorByCommand()
        {
            if (selectedTiles.Count > 0)
            {
                TagEditManager.Open(selectedTiles);
            }
        }

        public static void OpenSelected()
        {
            Debug.WriteLine("Debug message");

            foreach (TileTag tTag in selectedTiles)
            {
                if (File.Exists(tTag._ImageData.Filepath))
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = tTag._ImageData.Filepath,
                        UseShellExecute = true
                    });
                }
            }
        }

        public static void RefreshTileLabels()
        {
            foreach (TileTag tTag in allTiles)
                tTag._PooledTile.Label.Visible = PreferencesManager.Prefs.ShowFilenames;
        }


    }
}
