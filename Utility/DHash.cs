namespace Calypso
{
    internal static class DHash
    {
        private const int HashThreshold = 12;

        public static ulong Compute(Bitmap img)
        {
            using var small = new Bitmap(9, 8);
            using (var g = Graphics.FromImage(small))
            {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.DrawImage(img, 0, 0, 9, 8);
            }
            ulong hash = 0;
            for (int y = 0; y < 8; y++)
            {
                for (int x = 0; x < 8; x++)
                {
                    float left = small.GetPixel(x, y).GetBrightness();
                    float right = small.GetPixel(x + 1, y).GetBrightness();
                    if (left > right)
                        hash |= 1UL << (y * 8 + x);
                }
            }
            return hash;
        }

        public static int Distance(ulong a, ulong b)
        {
            ulong xor = a ^ b;
            int count = 0;
            while (xor != 0) { count += (int)(xor & 1); xor >>= 1; }
            return count;
        }

        public static bool IsSimilar(ulong a, ulong b) => Distance(a, b) <= HashThreshold;
    }
}
