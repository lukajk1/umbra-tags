using Newtonsoft.Json;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    internal static partial class DB
    {
        public static Dictionary<string, List<ImageData>> tagIndex = new();

        /// <summary>
        /// Virtual tags (shown to users as "protected tags") appear at the top of the tag tree
        /// as built-in searches. They are not stored in the tag data model and cannot be used
        /// as user-defined tag names.
        /// </summary>
        public static readonly HashSet<string> VirtualTags = new(StringComparer.OrdinalIgnoreCase)
        {
            "@all", "@untagged", "@archived", "@randimg", "@allvideos", "@randtag", "@bydate"
        };

        private const string GroupPrefix = "g:";

        #region searching
        public static void Search(string searchTextRaw, bool randomize, int upperLimit)
        {
            if (ActiveLibrary == null) return;
            List<ImageData> results = new();
            string[] tagsInclude = { };
            string[] tagsExclude = { };

            string stripped = new string(searchTextRaw.Where(c => !char.IsWhiteSpace(c)).ToArray());

            if (stripped == "@randimg")
            {
                var all = ActiveLibrary.filenameDict.Values.Where(img => !img.IsArchived).ToList();
                if (all.Count > 0)
                {
                    var img = all[new Random().Next(all.Count)];
                    results.Add(img);
                    Gallery.Populate(results);
                    ImageInfoPanel.Display(img);
                    return;
                }
            }
            else if (stripped == "@randtag")
            {
                var userTags = ActiveLibrary.tagTree.tagNodes
                    .Where(n => !VirtualTags.Contains(n.Name))
                    .ToList();
                if (userTags.Count > 0)
                {
                    string picked = userTags[new Random().Next(userTags.Count)].Name;
                    Searchbar.Search(picked);
                    return;
                }
            }
            else if (stripped == "@archived")
            {
                results = ActiveLibrary.filenameDict.Values.Where(img => img.IsArchived).ToList();
            }
            else if (stripped == "@bydate")
            {
                results = ActiveLibrary.filenameDict.Values
                    .Where(img => !img.IsArchived)
                    .OrderByDescending(img => img.ImportedAt)
                    .ToList();
            }
            else if (stripped == "@allvideos")
            {
                results = ActiveLibrary.filenameDict.Values
                    .Where(img => !img.IsArchived && img.IsVideo).ToList();
            }
            else if (stripped.StartsWith(GroupPrefix, StringComparison.OrdinalIgnoreCase))
            {
                string groupName = stripped.Substring(GroupPrefix.Length);
                var group = ActiveLibrary.Groups
                    .FirstOrDefault(g => string.Equals(g.Name, groupName, StringComparison.OrdinalIgnoreCase));

                if (group != null)
                {
                    foreach (string tagName in group.Tags)
                    {
                        if (ActiveLibrary.tagDict.TryGetValue(tagName, out var imgs))
                            results.AddRange(imgs);

                        // include children of each tag in the group
                        foreach (var child in ActiveLibrary.tagTree.GetAllChildren(tagName))
                            if (ActiveLibrary.tagDict.TryGetValue(child.Name, out var childImgs))
                                results.AddRange(childImgs);
                    }
                    results = results.Distinct().Where(img => !img.IsArchived).ToList();
                }
            }
            else
            {
                if (ActiveLibrary.tagDict.ContainsKey(stripped))
                {
                    results = new List<ImageData>(ActiveLibrary.tagDict[stripped]);

                    List<TagNode> children = ActiveLibrary.tagTree.GetAllChildren(stripped);

                    foreach (TagNode child in children)
                    {
                        if (ActiveLibrary.tagDict.TryGetValue(child.Name, out var imgs))
                            results.AddRange(imgs);
                    }

                    results = results.Distinct().Where(img => !img.IsArchived).ToList();

                    if (stripped == "@untagged")
                        results = results.OrderByDescending(img => img.ImportedAt).ToList();
                }
            }

            if (randomize)
            {
                var rng = new Random();
                results = results.OrderBy(_ => rng.Next()).ToList();
            }

            if (upperLimit > 0 && upperLimit < results.Count)
            {
                results = results.Take(upperLimit).ToList();
            }

            Gallery.Populate(results);
        }
        #endregion





        private static void BackfillDHashes()
        {
            foreach (var img in ActiveLibrary.filenameDict.Values)
            {
                if (img.DHash != 0) continue;
                if (!File.Exists(img.Filepath)) continue;
                try
                {
                    using var bmp = Util.LoadImage(img.Filepath);
                    img.DHash = DHash.Compute(bmp);
                }
                catch { }
            }
        }

        private static void BackfillColorGrids()
        {
            foreach (var img in ActiveLibrary.filenameDict.Values)
            {
                if (img.ColorGrid != null) continue;
                if (img.IsVideo) continue;
                if (!File.Exists(img.ThumbnailPath)) continue;
                try
                {
                    using var bmp = new System.Drawing.Bitmap(img.ThumbnailPath);
                    img.ColorGrid = ColorGrid.Compute(bmp);
                }
                catch { }
            }
        }

        private static void BackfillImportTimestamps()
        {
            long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            foreach (var img in ActiveLibrary.filenameDict.Values)
                if (img.ImportedAt == 0)
                    img.ImportedAt = now;
        }

        #region miscellaneous helpers
        public static void DeleteImageData(List<ImageData> imgDataList)
        {
            foreach (ImageData imgData in imgDataList)
            {
                if (File.Exists(imgData.ThumbnailPath))
                    try { File.Delete(imgData.ThumbnailPath); } catch { }

                if (File.Exists(imgData.Filepath))
                    try { File.Delete(imgData.Filepath); } catch { }

                // Remove from filenameDict so the entry is not persisted to the library file
                ActiveLibrary.filenameDict.Remove(imgData.Filepath);
            }

            ActiveLibrary.FlushDeletedImages();
            GenTagDictAndSaveLibrary();
        }
        public static void AddNewLibrary()
        {
            if (appdata.Libraries.Count > 8) Util.ShowErrorDialog("9 is the maximum allowed libraries!");

            if (PromptUserForLibrary("Add new library directory?", out string libraryPath))
            {
                Util.TextPrompt("Name this library (can be changed later)", out string libName);

                var newLib  = new Library(libName, libraryPath);
                var stub    = LibraryStub.FromLibrary(newLib);
                appdata.Libraries.Add(stub);
                LoadLibrary(newLib);
            }
        }
        public static void OpenCurrentLibrarySourceFolder()
        {
            if (ActiveLibrary == null) return;

            Process.Start(new ProcessStartInfo
            {
                FileName = ActiveLibrary.Dirpath,
                UseShellExecute = true
            });
        }

        public static List<ImageData> AddFilesToLibrary(string[] filepaths)
        {
            var lib = ActiveLibrary;
            var added = new List<ImageData>();

            foreach (string fp in filepaths)
            {
                string ext = Path.GetExtension(fp).ToLower();
                if (!Util.IsSupportedExtension(ext))
                    continue;

                if (!File.Exists(fp)) continue;

                if (lib.filenameDict.ContainsKey(fp)) continue;

                // Check for similar images before importing (skip duplicate check for videos)
                bool isVideo = Util.IsVideoExtension(ext);
                ulong incomingHash = 0;
                if (!isVideo)
                {
                    using var bmp = Util.LoadImage(fp);
                    incomingHash = DHash.Compute(bmp);
                }

                bool skipFile = false;
                var dismissed = new HashSet<string>();
                while (!isVideo)
                {
                    var similar = lib.filenameDict.Values
                        .FirstOrDefault(img => DHash.IsSimilar(incomingHash, img.DHash)
                                            && !dismissed.Contains(img.Filepath));
                    if (similar == null) break;

                    using var modal = new PotentialDuplicateModal(fp, similar.Filepath);
                    modal.ShowDialog();
                    if (modal.Action == DuplicateAction.Cancel) { skipFile = true; break; }
                    if (modal.Action == DuplicateAction.DeleteSource)
                    {
                        if (File.Exists(fp)) File.Delete(fp);
                        skipFile = true; break;
                    }
                    if (modal.Action == DuplicateAction.Replace)
                        DeleteImageData(new List<ImageData> { similar });
                    else
                        dismissed.Add(similar.Filepath); // ImportAnyway: skip this one next iteration
                }
                if (skipFile) continue;

                string filename = Path.GetFileName(fp);
                string destPath = Path.Combine(lib.Dirpath, filename);

                // Resolve name collision
                if (File.Exists(destPath))
                {
                    string nameNoExt = Path.GetFileNameWithoutExtension(filename);
                    string newFilename = $"{nameNoExt}_{Guid.NewGuid():N}{ext}";
                    destPath = Path.Combine(lib.Dirpath, newFilename);
                }

                File.Copy(fp, destPath);

                if (PreferencesManager.Prefs.DeleteSourceOnDragIn)
                    try { if (File.Exists(fp)) File.Delete(fp); } catch { }

                if (lib.filenameDict.ContainsKey(destPath)) continue;

                Util.CreateThumbnail(lib, destPath);
                string thumbPath = DB.GetThumbnailPath(destPath);
                if (!File.Exists(thumbPath)) continue;

                string? colorGrid = null;
                if (!isVideo)
                {
                    try
                    {
                        using var bmp = new System.Drawing.Bitmap(thumbPath);
                        colorGrid = ColorGrid.Compute(bmp);
                    }
                    catch { }
                }

                var imgData = new ImageData(destPath) { DHash = incomingHash, ColorGrid = colorGrid };
                ApplyDateTag(imgData);
                lib.filenameDict[destPath] = imgData;
                added.Add(imgData);
            }

            if (added.Count > 0)
                GenTagDictAndSaveLibrary();

            return added;
        }
        #endregion
    }
}
