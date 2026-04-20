using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
namespace Calypso
{
    internal class ImageInfoPanel
    {

        static PictureBox? pictureBox;
        static PictureBox? senderPictureBox;
        static TableLayoutPanel? tableLayoutImageInfo;
        static MainWindow? mainW;

        static Image senderImageData;

        static Label labelTags;
        static Label labelDimensions;
        static Label labelFilename;
        static Label labelFilesize;

        static ImageData displayedImage;

        public static void Init(MainWindow mainW)
        {
            ImageInfoPanel.mainW = mainW;
            ImageInfoPanel.pictureBox = mainW.pictureBoxImagePreview;
            ImageInfoPanel.tableLayoutImageInfo = mainW.tableLayoutImageInfo;

            pictureBox.SizeChanged += (s, e) => DrawImage(senderImageData);

            InfoTableSetup();
        }
        private static void InfoTableSetup()
        {
            tableLayoutImageInfo.RowCount = 0;
            tableLayoutImageInfo.ColumnCount = 2;
            tableLayoutImageInfo.GrowStyle = TableLayoutPanelGrowStyle.AddRows;
            tableLayoutImageInfo.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            //tableLayoutImageInfo.ColumnStyles.Clear();
            //tableLayoutImageInfo.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));     // Column 0: fixed to content
            tableLayoutImageInfo.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); // Column 1: expands to fill

            // references, so each must be set to invidually
            labelFilename = new Label { Text = "--" };
            labelDimensions = new Label { Text = "--" }; 
            labelFilesize  = new Label { Text = "--" };

            labelTags = new Label { Text = "--" };
            labelTags.AutoSize = true;
            labelTags.TextAlign = ContentAlignment.TopLeft;
            labelTags.MaximumSize = new Size(200, 0);

            tableLayoutImageInfo.Controls.Add(new Label { Text = "File Name" }, 0, 0);
            tableLayoutImageInfo.Controls.Add(labelFilename, 1, 0);

            tableLayoutImageInfo.Controls.Add(new Label { Text = "Dimensions" }, 0, 1);
            tableLayoutImageInfo.Controls.Add(labelDimensions, 1, 1);

            tableLayoutImageInfo.Controls.Add(new Label { Text = "Size" }, 0, 2);
            tableLayoutImageInfo.Controls.Add(labelFilesize, 1, 2);

            tableLayoutImageInfo.Controls.Add(new Label { Text = "Tags" }, 0, 3);
            tableLayoutImageInfo.Controls.Add(labelTags, 1, 3);
        }
        public static void Display(ImageData imgData)
        {
            displayedImage = imgData;
            if (!Path.Exists(imgData.Filepath))
            {
                Util.ShowErrorDialog("Error loading image.");
                return;
            }

            using (Bitmap img = Util.LoadImage(imgData.Filepath))
            {
                Image clone = new Bitmap(img);
                senderImageData = clone;

                DrawImage(clone);
                SetTableInfo(imgData, clone);
            }


        }
        public static void Clear()
        {
            senderImageData = null;
            displayedImage = default;
            pictureBox.Image = null;
            labelFilename.Text = "--";
            labelDimensions.Text = "--";
            labelFilesize.Text = "--";
            labelTags.Text = "--";
            LayoutManager.AutoSizeInfoPanel(tableLayoutImageInfo);
        }

        public static void Refresh()
        {
            Display(displayedImage);
        }
        private static void SetTableInfo(ImageData imgData, Image img)
        {
            if (imgData.Tags.Count > 0) labelTags.Text = string.Join(", ", imgData.Tags);
            else labelTags.Text = "none";

            labelDimensions.Text = $"{img.Width} x {img.Height}";
            labelFilename.Text = imgData.Filename;

            long byteSize = new FileInfo(imgData.Filepath).Length;
            string sizeStr = byteSize >= 1024 * 1024
                ? $"{byteSize / (1024.0 * 1024.0):F1} MB"
                : $"{byteSize / 1024.0:F1} KB";
            labelFilesize.Text = sizeStr;
            LayoutManager.AutoSizeInfoPanel(tableLayoutImageInfo);
        }

        private static void DrawImage(Image img)
        {
            if (img == null) return;

            float boxRatio = (float)pictureBox.Width / pictureBox.Height;
            float imageRatio = (float)img.Width / img.Height;

            int targetWidth, targetHeight;

            if (imageRatio > boxRatio)
            {
                targetWidth = pictureBox.Width;
                targetHeight = (int)(pictureBox.Width / imageRatio);
            }
            else
            {
                targetHeight = pictureBox.Height;
                targetWidth = (int)(pictureBox.Height * imageRatio);
            }

            var resized = new Bitmap(pictureBox.Width, pictureBox.Height);
            using (Graphics g = Graphics.FromImage(resized))
            {
                g.Clear(Color.Transparent);
                int x = (pictureBox.Width - targetWidth) / 2;
                int y = (pictureBox.Height - targetHeight) / 2;
                g.DrawImage(img, x, y, targetWidth, targetHeight);
            }

            pictureBox.Image = resized;
        }

    }
}
