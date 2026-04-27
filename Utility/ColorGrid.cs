using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace Calypso
{
    /// <summary>
    /// A 4x4 grid of average RGB colors representing an image's color distribution.
    /// Stored as a base64-encoded 48-byte array (16 cells × 3 bytes RGB).
    /// </summary>
    public static class ColorGrid
    {
        public const int Cols = 4;
        public const int Rows = 4;
        public const int CellCount = Cols * Rows;   // 16
        public const int ByteCount = CellCount * 3;  // 48

        /// <summary>Compute a color grid from a bitmap.</summary>
        public static string Compute(Bitmap src)
        {
            byte[] data = new byte[ByteCount];

            // Resize to 4x4 using high-quality interpolation
            using var small = new Bitmap(Cols, Rows, PixelFormat.Format24bppRgb);
            using (var g = Graphics.FromImage(small))
            {
                g.InterpolationMode  = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode    = PixelOffsetMode.HighQuality;
                g.DrawImage(src, 0, 0, Cols, Rows);
            }

            for (int row = 0; row < Rows; row++)
            {
                for (int col = 0; col < Cols; col++)
                {
                    Color c = small.GetPixel(col, row);
                    int i = (row * Cols + col) * 3;
                    data[i]     = c.R;
                    data[i + 1] = c.G;
                    data[i + 2] = c.B;
                }
            }

            return Convert.ToBase64String(data);
        }

        /// <summary>Decode a stored color grid string into an array of 16 Colors.</summary>
        public static Color[] Decode(string base64)
        {
            byte[] data   = Convert.FromBase64String(base64);
            var    colors = new Color[CellCount];
            for (int i = 0; i < CellCount; i++)
                colors[i] = Color.FromArgb(data[i * 3], data[i * 3 + 1], data[i * 3 + 2]);
            return colors;
        }

        /// <summary>
        /// Returns the average color of each column (4 values).
        /// Used for the gallery ambient background gradient.
        /// </summary>
        public static Color[] ColumnAverages(string base64)
        {
            Color[] cells = Decode(base64);
            var result    = new Color[Cols];
            for (int col = 0; col < Cols; col++)
            {
                int r = 0, g = 0, b = 0;
                for (int row = 0; row < Rows; row++)
                {
                    var c = cells[row * Cols + col];
                    r += c.R; g += c.G; b += c.B;
                }
                result[col] = Color.FromArgb(r / Rows, g / Rows, b / Rows);
            }
            return result;
        }

        /// <summary>
        /// Returns the 8 colors from the bottom 2 rows (row indices 2 and 3),
        /// ordered left-to-right then top-to-bottom.
        /// Used for the preview pane vertical streak gradient.
        /// </summary>
        public static Color[] BottomTwoRows(string base64)
        {
            Color[] cells  = Decode(base64);
            var result     = new Color[Cols * 2];
            for (int row = 2; row < Rows; row++)
                for (int col = 0; col < Cols; col++)
                    result[(row - 2) * Cols + col] = cells[row * Cols + col];
            return result;
        }

        /// <summary>
        /// Returns the overall average color of the image.
        /// </summary>
        public static Color AverageColor(string base64)
        {
            Color[] cells = Decode(base64);
            int r = 0, g = 0, b = 0;
            foreach (var c in cells) { r += c.R; g += c.G; b += c.B; }
            return Color.FromArgb(r / CellCount, g / CellCount, b / CellCount);
        }

        /// <summary>
        /// Euclidean distance in RGB space between a query color and the image's
        /// average color. Range 0–441 (√(255²×3)). Lower = closer match.
        /// </summary>
        public static double Distance(string base64, Color query)
        {
            Color avg = AverageColor(base64);
            double dr = avg.R - query.R;
            double dg = avg.G - query.G;
            double db = avg.B - query.B;
            return Math.Sqrt(dr * dr + dg * dg + db * db);
        }

        /// <summary>
        /// Returns true if the image's average color is within <paramref name="tolerance"/>
        /// (0–441) of the query color.
        /// </summary>
        public static bool IsMatch(string base64, Color query, double tolerance)
            => Distance(base64, query) <= tolerance;
    }
}
