using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
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
        private static void FlowLayoutGallery_MouseWheel(object sender, MouseEventArgs e)
        {
            ZoomFromWheel(e);
        }
        private static void flowLayoutGallery_DragEnter(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
                e.Effect = DragDropEffects.Copy;
        }

        private static void flowLayoutGallery_DragDrop(object sender, DragEventArgs e)
        {
            string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
            List<ImageData> added = DB.AddFilesToLibrary(files);
            if (added.Count == 0) return;

            // Insert shells at the top of the gallery, then load images async
            flowLayoutGallery.SuspendLayout();
            var newTiles = new List<(TileTag tileTag, string thumbnailPath)>();
            for (int i = added.Count - 1; i >= 0; i--)
            {
                var tileTag = AddCardShell(added[i]);
                if (tileTag == null) continue;

                // Move the control and tile to the front
                flowLayoutGallery.Controls.SetChildIndex(tileTag._Container, 0);
                allTiles.Remove(tileTag);
                allTiles.Insert(0, tileTag);

                newTiles.Add((tileTag, added[i].ThumbnailPath));
            }
            flowLayoutGallery.ResumeLayout(true);

            foreach (var (tileTag, thumbPath) in newTiles)
            {
                var captured = tileTag;
                Task.Run(() =>
                {
                    try
                    {
                        var bmp = Util.LoadImage(thumbPath);
                        flowLayoutGallery.BeginInvoke(() =>
                        {
                            if (captured._PictureBox.Tag != captured) { bmp.Dispose(); return; }
                            captured._PictureBox.Image?.Dispose();
                            captured._PictureBox.Image = bmp;
                        });
                    }
                    catch { }
                });
            }
        }

        private static System.Windows.Forms.Timer? _resizeDebounceTimer;

        private static void FlowLayoutGallery_SizeChanged(object sender, EventArgs e)
        {
            if (_resizeDebounceTimer == null)
            {
                _resizeDebounceTimer = new System.Windows.Forms.Timer { Interval = 150 };
                _resizeDebounceTimer.Tick += (s, _) =>
                {
                    _resizeDebounceTimer.Stop();
                    CountPictureBoxesPerRow();
                };
            }

            _resizeDebounceTimer.Stop();
            _resizeDebounceTimer.Start();
        }

        const int DragThreshold = 17; // (px) less sensitive than system default to avoid false positives more 
        private static void AddDraggableHandlers(PictureBox pb)
        {
            Point dragStartPoint = Point.Empty;

            pb.MouseDown += (s, e) =>
            {
                if (e.Button == MouseButtons.Left)
                    dragStartPoint = e.Location;
            };

            pb.MouseMove += (s, e) =>
            {
                if (e.Button == MouseButtons.Left &&
                    dragStartPoint != Point.Empty &&
                    (Math.Abs(e.X - dragStartPoint.X) > DragThreshold ||
                     Math.Abs(e.Y - dragStartPoint.Y) > DragThreshold))
                {
                    if (pb.Tag is TileTag tTag && File.Exists(tTag._ImageData.Filepath))
                    {
                        pb.DoDragDrop(
                            new DataObject(DataFormats.FileDrop, new string[] { tTag._ImageData.Filepath }),
                            DragDropEffects.Copy);
                        dragStartPoint = Point.Empty;
                    }
                }
            };
        }

        public static void PictureBox_DoubleClick(object? sender, EventArgs e)
        {
            if (sender is PictureBox pb && pb.Tag is TileTag tTag && File.Exists(tTag._ImageData.Filepath))
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                {
                    FileName = tTag._ImageData.Filepath,
                    UseShellExecute = true
                });
            }
        }
        public static void PictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            MainWindow.FocusedPane = Pane.Gallery;
            if (sender is not PictureBox pb || pb.Tag is not TileTag tTag)
                return;

            lastSelected = tTag;
            

            bool ctrlHeld = (Control.ModifierKeys & Keys.Control) == Keys.Control;
            bool shiftHeld = (Control.ModifierKeys & Keys.Shift) == Keys.Shift;

            bool rightClickWithinMultiSelection = e.Button == MouseButtons.Right
                && selectedTiles.Count > 1
                && selectedTiles.Contains(tTag);

            if (shiftHeld)
            {
                if (selectedTiles.Count == 1)
                {
                    int index1 = allTiles.IndexOf(selectedTiles[0]);
                    int index2 = allTiles.IndexOf(tTag);

                    if (index1 != -1 && index2 != -1)
                    {
                        int start = Math.Min(index1, index2);
                        int end = Math.Max(index1, index2);

                        for (int i = start; i <= end; i++)
                        {
                            if (!selectedTiles.Contains(allTiles[i])) AddToSelection(allTiles[i]);
                        }
                    }
                }
            }
            else if (!ctrlHeld && !rightClickWithinMultiSelection)
            {
                ClearSelection();
            }

            if (!rightClickWithinMultiSelection)
                AddToSelection(tTag);

            //if (e.Button == MouseButtons.Left || e.Button == MouseButtons.Right) {}

            if (e.Button == MouseButtons.Right && File.Exists(tTag._ImageData.Filepath))
            {
                TagEditManager.Open(selectedTiles);
            }
        }

        public static void ArrowSelect(Keys keyData)
        {
            if (selectedTiles.Count != 1) return;

            int index = allTiles.IndexOf(selectedTiles[0]);
            int newIndex = 0;

            switch(keyData)
            {
                case Keys.Left:
                    newIndex = index - 1;
                    break;
                case Keys.Right:
                    newIndex = index + 1;
                    break;
                case Keys.Up:
                    newIndex = index - pbPerRow;
                    break;
                case Keys.Down:
                    newIndex = index + pbPerRow;
                    break;
            }

            newIndex = Math.Max(0, Math.Min(newIndex, allTiles.Count - 1));

            ClearSelection();
            AddToSelection(allTiles[newIndex]);
        }

        public static void OpenSelectedInExplorer()
        {
            if (lastSelected != null)
            {
                Process.Start("explorer.exe", $"/select,\"{lastSelected._ImageData.Filepath}\"");
            }

        }

    }
}
