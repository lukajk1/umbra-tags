using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Calypso
{
    internal static class PhotoDetector
    {
        // Returns a score in [0, 1] where 1 = almost certainly a photo.
        // Works on any bitmap; downsample first for speed.
        public static float Score(Bitmap src)
        {
            using var small = Downsample(src, 100);
            var pixels = ReadPixels(small);

            float entropy    = HueEntropy(pixels);        // 0–1, high = photo
            float lapVar     = LaplacianVariance(small);  // 0–1, high = photo
            float satScore   = SaturationScore(pixels);   // 0–1, high = illustration

            // satScore is inverted (high sat = NOT a photo)
            float score = entropy * 0.45f + lapVar * 0.40f + (1f - satScore) * 0.15f;
            return Math.Clamp(score, 0f, 1f);
        }

        public static bool IsPhoto(Bitmap src, float threshold = 0.5f)
            => Score(src) >= threshold;

        // ── signals ───────────────────────────────────────────────────────

        // Shannon entropy of the hue histogram (16 bins).
        // Photos span many hues; flat art clusters into few.
        private static float HueEntropy((float h, float s, float v)[] pixels)
        {
            const int bins = 16;
            int[] hist = new int[bins];
            int count = 0;

            foreach (var (h, s, v) in pixels)
            {
                if (s < 0.05f) continue; // skip near-grey pixels
                int bin = (int)(h / 360f * bins) % bins;
                hist[bin]++;
                count++;
            }

            if (count == 0) return 0f;

            float entropy = 0f;
            for (int i = 0; i < bins; i++)
            {
                if (hist[i] == 0) continue;
                float p = (float)hist[i] / count;
                entropy -= p * MathF.Log2(p);
            }

            // max entropy = log2(16) = 4.0
            return Math.Clamp(entropy / 4f, 0f, 1f);
        }

        // Variance of a 3x3 Laplacian applied to grayscale.
        // Photos have sensor noise / fine texture; digital art is smooth.
        private static float LaplacianVariance(Bitmap bmp)
        {
            int w = bmp.Width, h = bmp.Height;
            if (w < 3 || h < 3) return 0f;

            // read grayscale
            var gray = new float[w, h];
            var data = bmp.LockBits(new Rectangle(0, 0, w, h),
                ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int stride = data.Stride;
            var buf = new byte[stride * h];
            Marshal.Copy(data.Scan0, buf, 0, buf.Length);
            bmp.UnlockBits(data);

            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int off = y * stride + x * 4;
                    gray[x, y] = (buf[off + 2] * 0.299f +
                                  buf[off + 1] * 0.587f +
                                  buf[off + 0] * 0.114f) / 255f;
                }

            // Laplacian kernel: [0,1,0 / 1,-4,1 / 0,1,0]
            double sum = 0, sumSq = 0;
            int n = 0;
            for (int y = 1; y < h - 1; y++)
                for (int x = 1; x < w - 1; x++)
                {
                    float v = gray[x, y - 1] + gray[x, y + 1]
                            + gray[x - 1, y] + gray[x + 1, y]
                            - 4 * gray[x, y];
                    sum   += v;
                    sumSq += v * v;
                    n++;
                }

            if (n == 0) return 0f;
            double mean = sum / n;
            double variance = sumSq / n - mean * mean;

            // empirically photos sit ~0.003–0.02, illustrations ~0–0.002
            // map [0, 0.025] → [0, 1]
            return Math.Clamp((float)(variance / 0.025), 0f, 1f);
        }

        // Fraction of pixels with saturation above 0.85.
        // Illustrations often have vivid fully-saturated regions; photos rarely do.
        private static float SaturationScore((float h, float s, float v)[] pixels)
        {
            if (pixels.Length == 0) return 0f;
            int high = pixels.Count(p => p.s > 0.85f);
            return Math.Clamp((float)high / pixels.Length * 4f, 0f, 1f); // scale: 25%+ vivid → score=1
        }

        // ── helpers ───────────────────────────────────────────────────────

        private static Bitmap Downsample(Bitmap src, int size)
        {
            int w, h;
            if (src.Width >= src.Height) { w = size; h = Math.Max(1, src.Height * size / src.Width); }
            else                          { h = size; w = Math.Max(1, src.Width  * size / src.Height); }

            var dst = new Bitmap(w, h);
            using var g = Graphics.FromImage(dst);
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.Bilinear;
            g.DrawImage(src, 0, 0, w, h);
            return dst;
        }

        private static (float h, float s, float v)[] ReadPixels(Bitmap bmp)
        {
            int w = bmp.Width, h = bmp.Height;
            var data = bmp.LockBits(new Rectangle(0, 0, w, h),
                ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int stride = data.Stride;
            var buf = new byte[stride * h];
            Marshal.Copy(data.Scan0, buf, 0, buf.Length);
            bmp.UnlockBits(data);

            var result = new (float, float, float)[w * h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int off = y * stride + x * 4;
                    float r = buf[off + 2] / 255f;
                    float g2 = buf[off + 1] / 255f;
                    float b = buf[off + 0] / 255f;
                    RgbToHsv(r, g2, b, out float hue, out float sat, out float val);
                    result[y * w + x] = (hue, sat, val);
                }
            return result;
        }

        private static void RgbToHsv(float r, float g, float b,
            out float h, out float s, out float v)
        {
            float max = MathF.Max(r, MathF.Max(g, b));
            float min = MathF.Min(r, MathF.Min(g, b));
            float delta = max - min;

            v = max;
            s = max < 1e-6f ? 0f : delta / max;

            if (delta < 1e-6f) { h = 0f; return; }

            if      (max == r) h = 60f * (((g - b) / delta) % 6f);
            else if (max == g) h = 60f * (((b - r) / delta) + 2f);
            else               h = 60f * (((r - g) / delta) + 4f);

            if (h < 0f) h += 360f;
        }
    }
}
