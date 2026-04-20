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
        #region searching
        public static void Search(string searchTextRaw, bool randomize, int upperLimit)
        {
            List<ImageData> results = new();
            string[] tagsInclude = { };
            string[] tagsExclude = { };

            string stripped = new string(searchTextRaw.Where(c => !char.IsWhiteSpace(c)).ToArray());

            if (stripped == "randimg")
            {
                var all = appdata.ActiveLibrary.filenameDict.Values.Where(img => !img.IsArchived).ToList();
                if (all.Count > 0)
                {
                    var img = all[new Random().Next(all.Count)];
                    results.Add(img);
                    Gallery.Populate(results);
                    ImageInfoPanel.Display(img);
                    return;
                }
            }
            else if (stripped == "archived")
            {
                results = appdata.ActiveLibrary.filenameDict.Values.Where(img => img.IsArchived).ToList();
            }
            else
            {
                if (appdata.ActiveLibrary.tagDict.ContainsKey(stripped))
                {
                    results = new List<ImageData>(appdata.ActiveLibrary.tagDict[stripped]);

                    List<TagNode> children = appdata.ActiveLibrary.tagTree.GetAllChildren(stripped);

                    foreach (TagNode child in children)
                    {
                        if (appdata.ActiveLibrary.tagDict.TryGetValue(child.Name, out var imgs))
                            results.AddRange(imgs);
                    }

                    results = results.Distinct().Where(img => !img.IsArchived).ToList();

                    if (stripped == "untagged")
                        results = results.OrderByDescending(img => File.GetLastWriteTime(img.Filepath)).ToList();
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

        public static void Save()
        {
            try
            {
                var settings = new JsonSerializerSettings
                {
                    PreserveReferencesHandling = PreserveReferencesHandling.Objects,
                    Formatting = Formatting.Indented
                };

                string json = JsonConvert.SerializeObject(appdata, settings);
                File.WriteAllText(appdataFilePath, json);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to save appdata: {ex.Message}");
            }
        }
        private static bool Load()
        {
            try
            {
                var settings = new JsonSerializerSettings
                {
                    PreserveReferencesHandling = PreserveReferencesHandling.Objects
                };

                string json = File.ReadAllText(appdataFilePath);
                appdata = JsonConvert.DeserializeObject<Appdata>(json, settings);

                return appdata != null;
            }
            catch (Exception ex)
            {
                Util.ShowErrorDialog($"Failed to load appdata: {ex.Message}");
                return false;
            }
        }



        public static void OnClose(Session session)
        {
            appdata.LastSession = session;
            Save();
        }

        private static void BackfillDHashes()
        {
            foreach (var img in appdata.ActiveLibrary.filenameDict.Values)
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

        #region miscellaneous helpers
        public static void DeleteImageData(List<ImageData> imgDataList)
        {
            foreach (ImageData imgData in imgDataList)
            {
                if (File.Exists(imgData.ThumbnailPath))
                {
                    File.Delete(imgData.ThumbnailPath);
                }

                if (File.Exists(imgData.Filepath))
                {
                    File.Delete(imgData.Filepath);
                }
            }

            appdata.ActiveLibrary.FlushDeletedImages();
            GenTagDictAndSaveLibrary();
        }
        public static void AddNewLibrary()
        {
            if (appdata.Libraries.Count > 8) Util.ShowErrorDialog("9 is the maximum allowed libraries!");

            if (PromptUserForLibrary("Add new library directory?", out string libraryPath))
            {
                Util.TextPrompt("Name this library (can be changed later)", out string libName);

                Library newLib = new Library(
                    name: libName,
                    dirpath: libraryPath
                );

                appdata.Libraries.Add(newLib);
                LoadLibrary(newLib);
            }
        }
        public static void OpenCurrentLibrarySourceFolder()
        {
            if (appdata.ActiveLibrary == null) return;

            Process.Start(new ProcessStartInfo
            {
                FileName = appdata.ActiveLibrary.Dirpath,
                UseShellExecute = true
            });
        }

        public static List<ImageData> AddFilesToLibrary(string[] filepaths)
        {
            var lib = appdata.ActiveLibrary;
            var added = new List<ImageData>();

            foreach (string fp in filepaths)
            {
                string ext = Path.GetExtension(fp).ToLower();
                if (ext is not (".jpg" or ".jpeg" or ".jfif" or ".png" or ".bmp" or ".gif" or ".webp"))
                    continue;

                if (!File.Exists(fp)) continue;

                // Check for similar images before importing
                ulong incomingHash;
                using (var bmp = Util.LoadImage(fp))
                    incomingHash = DHash.Compute(bmp);

                var similar = lib.filenameDict.Values
                    .FirstOrDefault(img => DHash.IsSimilar(incomingHash, img.DHash));
                if (similar != null)
                {
                    using var modal = new PotentialDuplicateModal(fp, similar.Filepath);
                    modal.ShowDialog();
                    if (modal.Action == DuplicateAction.Cancel) continue;
                    if (modal.Action == DuplicateAction.DeleteSource)
                    {
                        if (File.Exists(fp)) File.Delete(fp);
                        continue;
                    }
                    if (modal.Action == DuplicateAction.Replace)
                    {
                        DeleteImageData(new List<ImageData> { similar });
                    }
                }

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

                if (lib.filenameDict.ContainsKey(destPath)) continue;

                string thumbPath = Util.CreateThumbnail(lib, destPath);
                if (string.IsNullOrEmpty(thumbPath)) continue;

                var imgData = new ImageData(destPath, thumbPath) { DHash = incomingHash };
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
