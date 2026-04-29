using System;
using System.Collections.Generic;
using System.Drawing.Imaging;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Imazen.WebP;

namespace Calypso
{
    public delegate void ConfirmAction();

    // ── Windows Shell COM interop for video thumbnails ────────────────────
    internal static class ShellThumbnail
    {
        [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItemImageFactory
        {
            [PreserveSig]
            int GetImage([In] SIZE size, [In] SIIGBF flags, out IntPtr phbm);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SIZE { public int cx, cy; }

        [Flags]
        private enum SIIGBF : int
        {
            ResizeToFit    = 0x00,
            BiggerSizeOk   = 0x01,
            MemoryOnly     = 0x02,
            IconOnly       = 0x04,
            ThumbnailOnly  = 0x08,
            InCacheOnly    = 0x10,
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
        private static extern void SHCreateItemFromParsingName(
            string pszPath, IntPtr pbc, ref Guid riid, out IShellItemImageFactory ppv);

        private static readonly Guid IID_IShellItemImageFactory =
            new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");

        /// <summary>
        /// Extract a thumbnail from any file using the Windows Shell thumbnail cache.
        /// Returns null if the Shell cannot produce a thumbnail.
        /// </summary>
        public static Bitmap? GetThumbnail(string path, int size = 256)
        {
            try
            {
                var iid = IID_IShellItemImageFactory;
                SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out var factory);

                int hr = factory.GetImage(new SIZE { cx = size, cy = size },
                    SIIGBF.ThumbnailOnly | SIIGBF.BiggerSizeOk, out IntPtr hbm);
                if (hr != 0 || hbm == IntPtr.Zero) return null;

                var bmp = Image.FromHbitmap(hbm);
                DeleteObject(hbm);  // release the GDI handle
                return bmp;
            }
            catch { return null; }
        }

        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
    }

    internal class Util
    {
        public static readonly string[] SupportedImageExtensions =
            { ".jpg", ".jpeg", ".jfif", ".png", ".bmp", ".gif", ".webp" };

        public static readonly string[] SupportedVideoExtensions =
            { ".mp4", ".mov", ".webm", ".mkv", ".avi", ".wmv", ".m4v" };

        public static bool IsVideoExtension(string ext) =>
            Array.IndexOf(SupportedVideoExtensions, ext.ToLower()) >= 0;

        public static bool IsSupportedExtension(string ext)
        {
            string lower = ext.ToLower();
            return Array.IndexOf(SupportedImageExtensions, lower) >= 0
                || Array.IndexOf(SupportedVideoExtensions, lower) >= 0;
        }

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
                                .Where(f => IsSupportedExtension(Path.GetExtension(f)))
                                .ToArray();
        }

        public static Bitmap LoadImage(string path)
        {
            if (IsVideoExtension(Path.GetExtension(path)))
            {
                // Use Windows Shell to extract a frame thumbnail
                var thumb = ShellThumbnail.GetThumbnail(path, 512);
                if (thumb != null) return thumb;
                // Fallback: return a small placeholder
                return MakeVideoPlaceholder(512);
            }

            if (path.EndsWith(".webp", StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    byte[] bytes = File.ReadAllBytes(path);
                    return new SimpleDecoder().DecodeFromBytes(bytes, bytes.LongLength);
                }
                catch
                {
                    // Corrupt or invalid WebP — fall through to GDI+ as a last resort
                    try
                    {
                        using var ms2 = new MemoryStream(File.ReadAllBytes(path));
                        return new Bitmap(ms2);
                    }
                    catch
                    {
                        return MakeVideoPlaceholder(256); // last resort placeholder
                    }
                }
            }
            // Load via MemoryStream so GDI+ doesn't hold a file lock on the source
            using var ms = new MemoryStream(File.ReadAllBytes(path));
            return new Bitmap(ms);
        }

        /// <summary>Plain dark placeholder with a ▶ symbol, used when Shell returns nothing.</summary>
        private static Bitmap MakeVideoPlaceholder(int size)
        {
            var bmp = new Bitmap(size, size);
            using var g = Graphics.FromImage(bmp);
            g.Clear(Color.FromArgb(30, 30, 30));
            using var brush = new SolidBrush(Color.FromArgb(180, 180, 180));
            float fs = size * 0.35f;
            using var font = new Font("Segoe UI Symbol", fs, GraphicsUnit.Pixel);
            var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            g.DrawString("▶", font, brush, new RectangleF(0, 0, size, size), sf);
            return bmp;
        }

        public static string CreateThumbnail(Library lib, string originalImagePath)
        {
            if (!File.Exists(originalImagePath)) return "";

            string originalFilename = Path.GetFileName(originalImagePath);
            string thumbDir = DB.LibraryDataDir(lib.Name);

            string nameNoExt = Path.GetFileNameWithoutExtension(originalFilename);
            string ext = Path.GetExtension(originalFilename);

            // Videos and WebP/JFIF thumbnails are always stored as PNG
            bool isVideo = IsVideoExtension(ext);
            bool isWebP  = ext.Equals(".webp", StringComparison.OrdinalIgnoreCase);
            bool isJfif  = ext.Equals(".jfif", StringComparison.OrdinalIgnoreCase);

            string thumbFilename = (isVideo || isWebP)
                ? "thumb_" + nameNoExt + ".png"
                : isJfif
                    ? "thumb_" + nameNoExt + ".jpg"
                    : "thumb_" + originalFilename;

            string thumbSavePath = Path.Combine(thumbDir, thumbFilename);

            try
            {
                using Image thumb = CreateThumbnailBitmap(originalImagePath, GlobalValues.ThumbnailSize);
                ImageFormat format = GetImageFormatFromExtension(thumbSavePath);
                thumb.Save(thumbSavePath, format);
            }
            catch { /* corrupt or unreadable file — skip thumbnail */ }

            return thumbSavePath;
        }

        private static Image CreateThumbnailBitmap(string imagePath, int thumbnailHeight)
        {
            using Bitmap fullImage = LoadImage(imagePath);
            int newWidth = (int)(fullImage.Width * (thumbnailHeight / (float)fullImage.Height));
            var thumb = new Bitmap(newWidth, thumbnailHeight);
            using var g = Graphics.FromImage(thumb);
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
            g.DrawImage(fullImage, 0, 0, newWidth, thumbnailHeight);
            return thumb;
        }



        public static ImageFormat GetImageFormatFromExtension(string filePath)
        {
            string ext = Path.GetExtension(filePath).ToLowerInvariant();

            return ext switch
            {
                ".jpg" or ".jpeg" or ".jfif" => ImageFormat.Jpeg,
                ".png" => ImageFormat.Png,
                ".bmp" => ImageFormat.Bmp,
                ".gif" => ImageFormat.Gif,
                ".tiff" => ImageFormat.Tiff,
                _ => ImageFormat.Png // default fallback
            };
        }

        /// <summary>
        /// Resizes an image file in-place to the given dimensions.
        /// Regenerates thumbnail, DHash, and ColorGrid on the ImageData afterward.
        /// </summary>
        public static void ResizeImage(ImageData img, int newW, int newH)
        {
            string path = img.Filepath;
            if (!File.Exists(path)) return;

            // Render at new size
            using var src  = LoadImage(path);
            using var dest = new Bitmap(newW, newH);
            using (var g = Graphics.FromImage(dest))
            {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode   = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.DrawImage(src, 0, 0, newW, newH);
            }

            // Overwrite original
            var format = GetImageFormatFromExtension(path);
            dest.Save(path, format);

            // Regenerate thumbnail
            if (File.Exists(img.ThumbnailPath))
                File.Delete(img.ThumbnailPath);
            CreateThumbnail(DB.ActiveLibrary, path);

            // Update DHash and ColorGrid
            img.DHash = DHash.Compute(dest);

            if (File.Exists(img.ThumbnailPath))
            {
                try
                {
                    using var thumb = new Bitmap(img.ThumbnailPath);
                    img.ColorGrid = ColorGrid.Compute(thumb);
                }
                catch { }
            }
        }

        public static void CopyImageFilesToLibraryDir(string[] filepaths)
        {
            foreach (string filepath in filepaths)
            {
                if (File.Exists(filepath))
                {
                    string filename = Path.GetFileName(filepath);
                    string destFilepath = Path.Combine(DB.ActiveLibrary.Dirpath, filename);
                    File.Copy(filepath, destFilepath, overwrite: false);
                }
            }
        }
    }
}
