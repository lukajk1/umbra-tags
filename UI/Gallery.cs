using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using Calypso.UI;

namespace Calypso
{
    internal static partial class Gallery
    {
        // ── refs ──────────────────────────────────────────────────────────
        static VirtualGalleryPanel? panel;
        static ContextMenuStrip?    imageContextMenuStrip;
        static MainWindow?          mainW;
        static ToolStripStatusLabel? selectedCountLabel;
        static ToolStripStatusLabel? resultsCountLabel;

        // ── zoom ─────────────────────────────────────────────────────────
        private const int ZoomPixelInterval = 50;
        private const int MinZoomSteps = -2;
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
                    if (panel != null)
                        panel.TileSize = GlobalValues.DefaultThumbnailSize + _zoomSteps * ZoomPixelInterval;
                    mainW?.Invoke(() => mainW.toolStripLabelThumbnailSize.Text =
                        $"Thumbnail Height: {panel?.TileSize}px");
                }
            }
        }

        private static float _loadProgress = 0f;
        public static float LoadProgress
        {
            get => _loadProgress;
            set
            {
                _loadProgress = value;
                mainW!.toolStripProgressBar1.Value = (int)(value * 100f);
                mainW.toolStripProgressBar1.Visible = value > 0f;
            }
        }

        private static DateTime _lastZoomTime = DateTime.MinValue;
        private static readonly TimeSpan ZoomCooldown = TimeSpan.FromMilliseconds(400);

        // ── init ─────────────────────────────────────────────────────────

        public static void Init(MainWindow mw)
        {
            mainW           = mw;
            panel           = mw.galleryPanel;
            selectedCountLabel = mw.selectedCountLabel;
            resultsCountLabel  = mw.statusLabelResultsCount;

            var editTagsItem     = new ToolStripMenuItem("Edit Tags");
            editTagsItem.Click  += (s, e) => OpenTagEditorByCommand();
            var showInFolderItem     = new ToolStripMenuItem("Show in Folder");
            showInFolderItem.Click  += (s, e) => OpenSelectedInExplorer();
            var archiveItem     = new ToolStripMenuItem("Archive");
            archiveItem.Click  += (s, e) => ArchiveSelected();
            var deleteItem     = new ToolStripMenuItem("Delete");
            deleteItem.Click  += (s, e) => DeleteSelected();

            imageContextMenuStrip = new ContextMenuStrip();
            imageContextMenuStrip.Items.AddRange(new ToolStripItem[]
                { editTagsItem, showInFolderItem, new ToolStripSeparator(), archiveItem, deleteItem });

            panel.ShowLabels  = PreferencesManager.Prefs.ShowFilenames;
            panel.TileSize    = GlobalValues.DefaultThumbnailSize;

            panel.SelectionChanged  += Panel_SelectionChanged;
            panel.ItemClicked       += Panel_ItemClicked;
            panel.ItemDoubleClicked += Panel_ItemDoubleClicked;
            panel.FileDropped       += Panel_FileDropped;
            panel.LoadProgressChanged += (_, p) => LoadProgress = p;

            panel.MouseWheel += (_, e) => ZoomFromWheel(e);

            DB.OnNewLibraryLoaded += OnNewLibraryLoaded;
        }

        // ── population ───────────────────────────────────────────────────

        public static void Populate(List<ImageData> results)
        {
            panel!.Populate(results);
            resultsCountLabel!.Text = $"Results: {results.Count}";
            mainW!.toolStripLabelThumbnailSize.Text =
                $"Thumbnail Height: {panel.TileSize}px";
        }

        public static void AddCard(ImageData imgData)
        {
            panel!.InsertAtFront(new[] { imgData });
        }

        public static void OnNewLibraryLoaded(Library lib)
        {
            panel?.ClearSelection();
            ImageInfoPanel.Clear();
        }

        // ── selection ────────────────────────────────────────────────────

        public static void SelectAll() => panel?.SelectAll();

        public static List<GalleryItem> GetSelectedItems() =>
            panel?.GetSelectedItems() ?? new List<GalleryItem>();

        // ── actions ──────────────────────────────────────────────────────

        public static void ArchiveSelected()
        {
            var items = panel!.GetSelectedItems();
            foreach (var it in items)
                it.ImageData.IsArchived = true;

            panel.RemoveItems(items);
            DB.GenTagDictAndSaveLibrary();
        }

        public static void DeleteSelected()
        {
            var items = panel!.GetSelectedItems();
            panel.RemoveItems(items);
            DB.DeleteImageData(items.Select(it => it.ImageData).ToList());
        }

        public static void OpenSelected()
        {
            foreach (var it in panel!.GetSelectedItems())
            {
                if (File.Exists(it.ImageData.Filepath))
                    Process.Start(new ProcessStartInfo
                    {
                        FileName       = it.ImageData.Filepath,
                        UseShellExecute = true
                    });
            }
        }

        public static void OpenTagEditorByCommand()
        {
            var items = panel?.GetSelectedItems();
            if (items?.Count > 0)
            {
                TagEditManager.Open(items);
            }
        }

        public static void OpenSelectedInExplorer()
        {
            var items = panel?.GetSelectedItems();
            if (items?.Count > 0)
                Process.Start("explorer.exe", $"/select,\"{items[0].ImageData.Filepath}\"");
        }

        public static void ArrowSelect(Keys key) => panel?.ArrowSelect(key);

        public static void RefreshTileLabels()
        {
            if (panel == null) return;
            panel.ShowLabels = PreferencesManager.Prefs.ShowFilenames;
            panel.Invalidate();
        }

        public static int CountPictureBoxesPerRow() => panel?.ColsPerRow ?? 1;

        // ── zoom ─────────────────────────────────────────────────────────

        public static void ZoomFromWheel(MouseEventArgs e)
        {
            if ((Control.ModifierKeys & Keys.Control) != Keys.Control) return;
            if (DateTime.UtcNow - _lastZoomTime < ZoomCooldown) return;
            _lastZoomTime = DateTime.UtcNow;

            if (e.Delta > 0) Zoom += 1;
            else if (e.Delta < 0) Zoom -= 1;
        }

        // ── panel event handlers ─────────────────────────────────────────

        private static void Panel_SelectionChanged(object? sender, EventArgs e)
        {
            var items = panel!.GetSelectedItems();
            selectedCountLabel!.Text = $"Selected: ({items.Count})";
            if (items.Count > 0)
                ImageInfoPanel.Display(items[0].ImageData);
        }

        private static void Panel_ItemClicked(object? sender, GalleryClickEventArgs e)
        {
            MainWindow.FocusedPane = Pane.Gallery;

            if (e.Button == MouseButtons.Right)
            {
                if (PreferencesManager.Prefs.RightClickBehavior == RightClickBehavior.TagEditor)
                    OpenTagEditorByCommand();
                else
                    imageContextMenuStrip?.Show(panel!, e.Location);
            }
        }

        private static void Panel_ItemDoubleClicked(object? sender, GalleryItem e)
        {
            if (File.Exists(e.ImageData.Filepath))
                Process.Start(new ProcessStartInfo
                {
                    FileName       = e.ImageData.Filepath,
                    UseShellExecute = true
                });
        }

        private static void Panel_FileDropped(object? sender, string[] files)
        {
            List<ImageData> added = DB.AddFilesToLibrary(files);
            if (added.Count == 0) return;

            if (PreferencesManager.Prefs.DeleteSourceOnDragIn)
                foreach (string f in files)
                    if (File.Exists(f)) File.Delete(f);

            panel!.InsertAtFront(added);
            panel.ScrollToTop();
        }
    }
}
