using System;
using System.Collections.Generic;
using System.Drawing.Imaging;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace Calypso
{
    public delegate void ConfirmAction();

    internal class Util
    {
        public static bool TextPrompt(string message, out string output, string prefillText = "")
        {
            using (var prompt = new TextPrompt(MainWindow.i, message))
            {
                prompt.newTagTextBox.Text = prefillText;  
                if (prompt.ShowDialog() == DialogResult.OK)
                {
                    output = prompt.ResultText;
                    return true;
                    //Debug.WriteLine("User entered: " + userInput);
                }
                else
                {
                    output = string.Empty;
                    return false;
                    //.WriteLine("User cancelled input.");
                }
            }
        }
        public static void ShowErrorDialog(string message)
        {
            MessageBox.Show(message, "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        public static DialogResult ShowInfoDialog(string message)
        {
            return MessageBox.Show(
                message,
                "Notice",
                MessageBoxButtons.OKCancel,
                MessageBoxIcon.Information);
        }
        public static DialogResult ShowConfirmDialog(string message)
        {
            return MessageBox.Show(
                message,
                "Confirm",
                MessageBoxButtons.OKCancel,
                MessageBoxIcon.Question);
        }

        public static string[] GetAllImageFilepaths(string path)
        {
           return System.IO.Directory.GetFiles(path, "*.*")
                               .Where(f => f.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase) ||
                                           f.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase) ||
                                           f.EndsWith(".png", StringComparison.OrdinalIgnoreCase) ||
                                           f.EndsWith(".bmp", StringComparison.OrdinalIgnoreCase) ||
                                           f.EndsWith(".gif", StringComparison.OrdinalIgnoreCase))
                               .ToArray();
        }

        public static string CreateThumbnail(Library lib, string originalImagePath)
        {
            if (!File.Exists(originalImagePath)) return "";

            string originalFilename = Path.GetFileName(originalImagePath);
            string thumbDir = Path.Combine(lib.Dirpath, "data");
            string thumbSavePath = Path.Combine(thumbDir, "thumb_" + originalFilename);

            using Image thumb = CreateThumbnail(originalImagePath, GlobalValues.ThumbnailSize);
            ImageFormat format = GetImageFormatFromExtension(thumbSavePath);
            thumb.Save(thumbSavePath, format);

            return thumbSavePath;
        }

        private static Image CreateThumbnail(string imagePath, int thumbnailHeight)
        {

            using Image fullImage = Image.FromFile(imagePath);
            int originalWidth = fullImage.Width;
            int originalHeight = fullImage.Height;

            int newHeight = thumbnailHeight;
            int newWidth = (int)(originalWidth * (newHeight / (float)originalHeight));

            return fullImage.GetThumbnailImage(newWidth, newHeight, () => false, IntPtr.Zero);
        }



        public static ImageFormat GetImageFormatFromExtension(string filePath)
        {
            string ext = Path.GetExtension(filePath).ToLowerInvariant();

            return ext switch
            {
                ".jpg" or ".jpeg" => ImageFormat.Jpeg,
                ".png" => ImageFormat.Png,
                ".bmp" => ImageFormat.Bmp,
                ".gif" => ImageFormat.Gif,
                ".tiff" => ImageFormat.Tiff,
                _ => ImageFormat.Png // default fallback
            };
        }

        public static void CopyImageFilesToLibraryDir(string[] filepaths)
        {
            foreach (string filepath in filepaths)
            {
                if (File.Exists(filepath))
                {
                    string filename = Path.GetFileName(filepath);
                    string destFilepath = Path.Combine(DB.appdata.ActiveLibrary.Dirpath, filename);
                    File.Copy(filepath, destFilepath, overwrite: false);
                }
            }
        }
    }
}
