using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace Calypso
{
    internal static class PhotoDetector
    {
        public record ScoreBreakdown(
            float Total,
            float Exif,
            float HueEntropy,
            float LaplacianVariance,
            float EdgeSoftness,
            float ColorDiversity,
            float SaturationPenalty);

        public static ScoreBreakdown Breakdown(Bitmap src, string? filepath = null)
        {
            float exif = ExifCameraScore(src);

            using var small = Downsample(src, 100);
            var pixels = ReadPixels(small);

            float entropy    = HueEntropy(pixels);
            float lapVar     = LaplacianVariance(small);
            float satScore   = SaturationScore(pixels);
            float edgeSoft   = EdgeSoftnessScore(small);
            float colorCount = ColorDiversityScore(small);

            float statistical = entropy    * 0.25f
                              + lapVar     * 0.25f
                              + edgeSoft   * 0.20f
                              + colorCount * 0.20f
                              + (1f - satScore) * 0.10f;

            float total = exif >= 1f ? 1f
                        : exif > 0f  ? Math.Clamp(statistical * 0.5f + exif * 0.5f, 0f, 1f)
                        : Math.Clamp(statistical, 0f, 1f);

            return new ScoreBreakdown(total, exif, entropy, lapVar, edgeSoft, colorCount, satScore);
        }

        // Returns a score in [0, 1] where 1 = almost certainly a photo.
        public static float Score(Bitmap src, string? filepath = null)
            => Breakdown(src, filepath).Total;

        public static bool IsPhoto(Bitmap src, string? filepath = null, float threshold = 0.5f)
            => Score(src, filepath) >= threshold;

        // ── EXIF ──────────────────────────────────────────────────────────

        // Camera EXIF tags. Presence of multiple = almost certainly a photo.
        private static readonly int[] CameraExifTags =
        {
            0x829A, // ExposureTime
            0x829D, // FNumber
            0x8827, // ISOSpeedRatings
            0x9201, // ShutterSpeedValue
            0x9202, // ApertureValue
            0x9204, // ExposureBiasValue
            0x920A, // FocalLength
            0x010F, // Make  (camera manufacturer)
            0x0110, // Model (camera model)
        };

        private static float ExifCameraScore(Bitmap bmp)
        {
            try
            {
                var ids = new HashSet<int>(bmp.PropertyIdList);
                int hits = CameraExifTags.Count(t => ids.Contains(t));
                if (hits >= 3) return 1f;   // conclusive
                if (hits == 2) return 0.8f;
                if (hits == 1) return 0.5f;
            }
            catch { }
            return 0f;
        }

        // ── edge softness ─────────────────────────────────────────────────

        // Sobel gradient at edge pixels vs. just inside them.
        // Photos: gradual falloff. Illustrations: hard step.
        // Returns 0–1 where 1 = soft (photo-like) edges.
        private static float EdgeSoftnessScore(Bitmap bmp)
        {
            int w = bmp.Width, h = bmp.Height;
            if (w < 3 || h < 3) return 0.5f;

            var gray = ReadGray(bmp);

            // Sobel magnitude at every interior pixel
            var mag = new float[w, h];
            float maxMag = 0f;
            for (int y = 1; y < h - 1; y++)
                for (int x = 1; x < w - 1; x++)
                {
                    float gx = -gray[x - 1, y - 1] + gray[x + 1, y - 1]
                               - 2 * gray[x - 1, y] + 2 * gray[x + 1, y]
                               - gray[x - 1, y + 1] + gray[x + 1, y + 1];
                    float gy = -gray[x - 1, y - 1] - 2 * gray[x, y - 1] - gray[x + 1, y - 1]
                               + gray[x - 1, y + 1] + 2 * gray[x, y + 1] + gray[x + 1, y + 1];
                    mag[x, y] = MathF.Sqrt(gx * gx + gy * gy);
                    if (mag[x, y] > maxMag) maxMag = mag[x, y];
                }

            if (maxMag < 1e-6f) return 0.5f;

            // threshold at 40% of max to find "edge" pixels
            float threshold = maxMag * 0.40f;
            double gradientRatio = 0;
            int edgeCount = 0;

            for (int y = 1; y < h - 1; y++)
                for (int x = 1; x < w - 1; x++)
                {
                    if (mag[x, y] < threshold) continue;
                    edgeCount++;

                    // sample neighbors one step off the edge
                    float neighborAvg = (mag[x - 1, y] + mag[x + 1, y] +
                                         mag[x, y - 1] + mag[x, y + 1]) / 4f;
                    // soft edge: neighbor mag is still substantial relative to center
                    gradientRatio += neighborAvg / mag[x, y];
                }

            if (edgeCount == 0) return 0.5f;

            // ratio near 1 = soft (neighbors almost as strong = gradual slope)
            // ratio near 0 = hard (center strong, neighbors weak = step edge)
            float softness = (float)(gradientRatio / edgeCount);
            return Math.Clamp(softness, 0f, 1f);
        }

        // ── color diversity ───────────────────────────────────────────────

        // Count distinct colors in a 32x32 downsample with tolerance bucketing.
        // Photos: thousands of distinct colors. Illustrations: very few.
        private static float ColorDiversityScore(Bitmap bmp)
        {
            using var tiny = Downsample(bmp, 32);
            int w = tiny.Width, h = tiny.Height;

            var data = tiny.LockBits(new Rectangle(0, 0, w, h),
                ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            var buf = new byte[data.Stride * h];
            Marshal.Copy(data.Scan0, buf, 0, buf.Length);
            tiny.UnlockBits(data);

            var buckets = new HashSet<int>();
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int off = y * data.Stride + x * 4;
                    // quantize to 5-bit per channel (32 levels) as bucket key
                    int r = buf[off + 2] >> 3;
                    int g = buf[off + 1] >> 3;
                    int b = buf[off + 0] >> 3;
                    buckets.Add((r << 10) | (g << 5) | b);
                }

            // 32x32 = 1024 pixels max. Photos fill most buckets; illustrations use <50.
            // map [0, 400] → [0, 1]  (photos typically 300–600+, illustrations 20–100)
            return Math.Clamp(buckets.Count / 400f, 0f, 1f);
        }

        // ── existing signals ──────────────────────────────────────────────

        private static float HueEntropy((float h, float s, float v)[] pixels)
        {
            const int bins = 16;
            int[] hist = new int[bins];
            int count = 0;

            foreach (var (h, s, v) in pixels)
            {
                if (s < 0.05f) continue;
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

            return Math.Clamp(entropy / 4f, 0f, 1f);
        }

        private static float LaplacianVariance(Bitmap bmp)
        {
            int w = bmp.Width, h = bmp.Height;
            if (w < 3 || h < 3) return 0f;

            var gray = ReadGray(bmp);

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
            return Math.Clamp((float)(variance / 0.025), 0f, 1f);
        }

        private static float SaturationScore((float h, float s, float v)[] pixels)
        {
            if (pixels.Length == 0) return 0f;
            int high = pixels.Count(p => p.s > 0.85f);
            return Math.Clamp((float)high / pixels.Length * 4f, 0f, 1f);
        }

        // ── helpers ───────────────────────────────────────────────────────

        private static float[,] ReadGray(Bitmap bmp)
        {
            int w = bmp.Width, h = bmp.Height;
            var data = bmp.LockBits(new Rectangle(0, 0, w, h),
                ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int stride = data.Stride;
            var buf = new byte[stride * h];
            Marshal.Copy(data.Scan0, buf, 0, buf.Length);
            bmp.UnlockBits(data);

            var gray = new float[w, h];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int off = y * stride + x * 4;
                    gray[x, y] = (buf[off + 2] * 0.299f +
                                  buf[off + 1] * 0.587f +
                                  buf[off + 0] * 0.114f) / 255f;
                }
            return gray;
        }

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
                    float r  = buf[off + 2] / 255f;
                    float g2 = buf[off + 1] / 255f;
                    float b  = buf[off + 0] / 255f;
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
