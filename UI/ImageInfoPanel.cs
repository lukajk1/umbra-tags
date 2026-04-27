using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Calypso.UI;

namespace Calypso
{
    internal class ImageInfoPanel
    {
        static PictureBox? pictureBox;
        static TableLayoutPanel? tableLayoutImageInfo;

        static Label labelTags;
        static Label labelDimensions;
        static Label labelFilename;
        static Label labelFilesize;
        static Label? labelVideoHint;

        static ImageData? displayedImage;

        private static CancellationTokenSource? _loadCts;
        private static Bitmap? _currentFullRes;
        private static Bitmap? _frozenSnapshot;

        // preview pane gradient
        private static GradientPanel? _gradientPanel;

        public static void Init(MainWindow mainW)
        {
            ImageInfoPanel.pictureBox = mainW.pictureBoxImagePreview;
            ImageInfoPanel.tableLayoutImageInfo = mainW.tableLayoutImageInfo;

            pictureBox.SizeMode = PictureBoxSizeMode.Zoom;
            pictureBox.DoubleClick += PictureBox_DoubleClick;

            // Reparent the metadata table into a GradientPanel so transparency works
            var tableParent = mainW.tableLayoutImageInfo.Parent;
            if (tableParent != null)
            {
                _gradientPanel = new GradientPanel
                {
                    Dock = DockStyle.Fill,
                };
                // Remove table from its current parent, add gradient panel in its place,
                // then add table as a child of the gradient panel
                tableParent.Controls.Remove(mainW.tableLayoutImageInfo);
                tableParent.Controls.Add(_gradientPanel);
                mainW.tableLayoutImageInfo.Dock = DockStyle.Fill;
                mainW.tableLayoutImageInfo.BackColor = Color.Transparent;
                _gradientPanel.Controls.Add(mainW.tableLayoutImageInfo);
            }

            InfoTableSetup();
        }

        private static void PictureBox_DoubleClick(object? sender, EventArgs e)
        {
            if (displayedImage?.IsVideo == true && File.Exists(displayedImage.Filepath))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName        = displayedImage.Filepath,
                    UseShellExecute = true
                });
            }
        }

        private static void InfoTableSetup()
        {
            tableLayoutImageInfo.RowCount = 0;
            tableLayoutImageInfo.ColumnCount = 2;
            tableLayoutImageInfo.GrowStyle = TableLayoutPanelGrowStyle.AddRows;
            tableLayoutImageInfo.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            tableLayoutImageInfo.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

            labelFilename   = new Label { Text = "--" };
            labelDimensions = new Label { Text = "--" };
            labelFilesize   = new Label { Text = "--" };
            labelTags       = new Label { Text = "--", AutoSize = true, TextAlign = ContentAlignment.TopLeft, MaximumSize = new Size(200, 0) };

            tableLayoutImageInfo.Controls.Add(new Label { Text = "File Name" },   0, 0);
            tableLayoutImageInfo.Controls.Add(labelFilename,   1, 0);
            tableLayoutImageInfo.Controls.Add(new Label { Text = "Dimensions" },  0, 1);
            tableLayoutImageInfo.Controls.Add(labelDimensions, 1, 1);
            tableLayoutImageInfo.Controls.Add(new Label { Text = "Size" },        0, 2);
            tableLayoutImageInfo.Controls.Add(labelFilesize,   1, 2);
            tableLayoutImageInfo.Controls.Add(new Label { Text = "Tags" },        0, 3);
            tableLayoutImageInfo.Controls.Add(labelTags,       1, 3);
        }

        public static void Display(ImageData imgData)
        {
            if (Calypso.UI.VirtualGalleryPanel.IsDraggingOut) return;
            if (imgData == displayedImage) return;
            displayedImage = imgData;

            // Cancel any in-flight load for the previous image
            _loadCts?.Cancel();
            _loadCts = new CancellationTokenSource();
            var token = _loadCts.Token;

            // Show thumbnail immediately so the UI is never blank
            var thumb = Util.LoadImage(imgData.ThumbnailPath);
            SetPreviewImage(thumb, owned: true);

            // Update preview pane gradient
            _gradientPanel?.SetColors(imgData.ColorGrid);

            // Populate metadata from file info without reading the image
            SetTableInfoFromData(imgData);

            // Show/hide the "double-click to open" hint for videos
            SetVideoHint(imgData.IsVideo);

            if (!File.Exists(imgData.Filepath)) return;
            if (imgData.IsVideo) return;  // thumbnail is enough for videos

            // Load full-res async; update preview and dimensions when ready
            Task.Run(() =>
            {
                if (token.IsCancellationRequested) return;
                try
                {
                    var fullRes = Util.LoadImage(imgData.Filepath);
                    if (token.IsCancellationRequested) { fullRes.Dispose(); return; }

                    pictureBox!.BeginInvoke(() =>
                    {
                        if (token.IsCancellationRequested) { fullRes.Dispose(); return; }
                        SetPreviewImage(fullRes, owned: true);
                        labelDimensions.Text = $"{fullRes.Width} x {fullRes.Height}";
                        LayoutManager.AutoSizeInfoPanel(tableLayoutImageInfo);
                    });
                }
                catch { }
            }, token);
        }

        public static void Freeze()
        {
            if (pictureBox?.Image == null) return;
            // snapshot the current display at its current rendered size, switch to Normal so it won't rescale
            var snap = new Bitmap(pictureBox.Image, pictureBox.ClientSize);
            _frozenSnapshot = snap;
            pictureBox.SizeMode = PictureBoxSizeMode.Normal;
            pictureBox.Image = snap;
        }

        public static void Unfreeze()
        {
            if (pictureBox == null) return;
            pictureBox.SizeMode = PictureBoxSizeMode.Zoom;
            // restore the real full-res image so Zoom mode can re-letterbox it correctly
            if (_currentFullRes != null)
                pictureBox.Image = _currentFullRes;
            _frozenSnapshot?.Dispose();
            _frozenSnapshot = null;
        }

        public static void Clear()
        {
            _loadCts?.Cancel();
            displayedImage = null;
            SetPreviewImage(null, owned: false);
            SetVideoHint(false);
            _gradientPanel?.SetColors(null);
            labelFilename.Text   = "--";
            labelDimensions.Text = "--";
            labelFilesize.Text   = "--";
            labelTags.Text       = "--";
            LayoutManager.AutoSizeInfoPanel(tableLayoutImageInfo);
        }

        public static void Refresh()
        {
            if (displayedImage == null) return;
            var img = displayedImage;
            displayedImage = null; // force re-display
            Display(img);
        }

        private static void SetVideoHint(bool visible)
        {
            if (pictureBox == null) return;

            if (visible)
            {
                if (labelVideoHint == null)
                {
                    labelVideoHint = new Label
                    {
                        Text      = "Double-click to open in player",
                        AutoSize  = false,
                        TextAlign = ContentAlignment.MiddleCenter,
                        ForeColor = Color.Gray,
                        BackColor = Color.Transparent,
                        Dock      = DockStyle.Bottom,
                        Height    = 22,
                        Cursor    = Cursors.Hand,
                    };
                    labelVideoHint.DoubleClick += PictureBox_DoubleClick;
                    pictureBox.Parent?.Controls.Add(labelVideoHint);
                    pictureBox.Parent?.Controls.SetChildIndex(labelVideoHint,
                        pictureBox.Parent.Controls.GetChildIndex(pictureBox) + 1);
                }
                labelVideoHint.Visible = true;
            }
            else if (labelVideoHint != null)
            {
                labelVideoHint.Visible = false;
            }
        }

        private static void SetPreviewImage(Bitmap? bmp, bool owned)
        {
            var old = pictureBox!.Image;
            pictureBox.Image = bmp;
            if (owned) _currentFullRes?.Dispose();
            if (owned) _currentFullRes = bmp;
            // dispose the previous image only if it wasn't the one we just set
            if (old != bmp) old?.Dispose();
        }

        private static void SetTableInfoFromData(ImageData imgData)
        {
            labelFilename.Text   = imgData.Filename;
            labelDimensions.Text = "--";  // filled in once full-res loads
            labelTags.Text       = imgData.Tags.Count > 0 ? string.Join(", ", imgData.Tags) : "none";

            try
            {
                long bytes = new FileInfo(imgData.Filepath).Length;
                labelFilesize.Text = bytes >= 1024 * 1024
                    ? $"{bytes / (1024.0 * 1024.0):F1} MB"
                    : $"{bytes / 1024.0:F1} KB";
            }
            catch { labelFilesize.Text = "--"; }

            LayoutManager.AutoSizeInfoPanel(tableLayoutImageInfo);
        }
    }
}
