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

            if (stripped == "randtag" || stripped == "rtag" || stripped == "randomtag")
            {
                // implement later..
            }
            else
            {
                if (appdata.ActiveLibrary.tagDict.ContainsKey(stripped))
                {
                    results = appdata.ActiveLibrary.tagDict[stripped];

                    List<TagNode> children = appdata.ActiveLibrary.tagTree.GetAllChildren(stripped);
                    Debug.WriteLine("children count" + children.Count);

                    foreach (TagNode child in children)
                    {
                        if (appdata.ActiveLibrary.tagDict.TryGetValue(child.Name, out var imgs))
                            results.AddRange(imgs);
                    }

                    results = results.Distinct().ToList();
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

        private static void Save()
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
            //string targetDir = appdata.ActiveLibrary.Dirpath;
            //string thumbSavePath = string.Empty;
            //string destPath = string.Empty;
            //List<ImageData> newImages = new();

            //foreach (string fp in filepaths)
            //{
            //    // copy to main folder
            //    string filename = string.Empty;
            //    string ext = Path.GetExtension(fp).ToLower();
            //    if (ext is ".jpg" or ".jpeg" or ".png" or ".bmp" or ".gif")
            //    {
            //        filename = Path.GetFileName(fp);
            //        destPath = Path.Combine(targetDir, filename);

            //        if (!File.Exists(destPath))
            //        {
            //            File.Copy(fp, destPath, overwrite: false);
            //            thumbSavePath = Util.CreateThumbnail(appdata.ActiveLibrary, destPath);
            //        }
            //        else
            //        {
            //            Util.ShowErrorDialog($"A file named {filename} already exists in {targetDir}!");
            //            return null;
            //        }
            //    }

            //    if (thumbSavePath != string.Empty && filename != string.Empty)
            //    {
            //        ImageData newImageData = new(destPath, thumbSavePath);
            //        newImages.Add(newImageData);
            //        appdata.ActiveLibrary.ImageDataList.Add(newImageData);
            //    }
            //}

            GenTagDictAndSaveLibrary();
            return new List<ImageData>();
        }
        #endregion
    }
}
