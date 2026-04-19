using Calypso.UI;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing.Imaging;
using System.Linq;
using System.Xml.Linq;

namespace Calypso
{
    public class Appdata
    {
        public List<Library> Libraries { get; set; }
        public Library ActiveLibrary { get; set; }
        public Session LastSession { get; set; }

        public Appdata(List<Library> libraries, Library activeLibrary, Session lastSession) 
        { 
            Libraries = libraries;
            ActiveLibrary = activeLibrary;
            LastSession = lastSession;
        }
    }

    internal static partial class DB
    {
        public static Appdata appdata;
        private static string appdataFilePath = string.Empty;

        // events
        public static event Action<Library>? OnNewLibraryLoaded;

        public static bool Init(MainWindow mainW)
        {
            string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string myAppFolder = Path.Combine(appDataPath, "Calypso");
            Directory.CreateDirectory(myAppFolder);
            appdataFilePath = Path.Combine(myAppFolder, "database.save");

            // exclamation is null-forgiving operator
            if (Load() || (appdata = NewAppdata()!) != null)
            {
                mainW.LoadSession(appdata.LastSession);
                LoadLibrary(appdata.LastSession.LastActiveLibrary);
                return true;
            }

            return false;
        }
        private static Appdata? NewAppdata()
        {
            string libraryPath;

            if (PromptUserForLibrary("No existing library was found. Specify a folder now?", out libraryPath))
            {
                if (!Util.TextPrompt("Set library name: ", out string libraryName)) return null;

                Library newLib = new(
                    name: libraryName,
                    dirpath: libraryPath
                );

                var newAppdata = new Appdata(
                    libraries: new List<Library>() { newLib },
                    activeLibrary: newLib,
                    lastSession: MainWindow.i.CaptureCurrentSession(newLib)
                );

                Save();
                return newAppdata;
            }

            return null; // No valid appdata could be created
        }

        private static bool PromptUserForLibrary(string message, out string libraryPath)
        {
            DialogResult result = Util.ShowInfoDialog(message);

            if (result == DialogResult.OK)
            {
                using (var dialog = new FolderBrowserDialog())
                {
                    DialogResult resultPath = dialog.ShowDialog();
                    if (resultPath == DialogResult.OK && !string.IsNullOrWhiteSpace(dialog.SelectedPath))
                    {
                        Debug.WriteLine(dialog.SelectedPath);
                        libraryPath = dialog.SelectedPath;
                        return true;
                    }
                }
            }
            // if either 'if' fails
            libraryPath = "";
            return false;
        }
        
        private static void AddNewEntriesToFilenameDict(string[] newImageFilepaths)
        {
            foreach (string filename in newImageFilepaths)
            {
                if (!appdata.ActiveLibrary.filenameDict.ContainsKey(filename))
                {
                    ImageData newImage = new(filename, Util.CreateThumbnail(appdata.ActiveLibrary, filename));
                    appdata.ActiveLibrary.filenameDict[filename] = newImage;

                }
            }
        }
        public static void LoadLibrary(int index)
        {
            index -= 1;
            if (!(index >= 0) || !(index < appdata.Libraries.Count())) return;

            if (appdata.Libraries[index] != appdata.ActiveLibrary)
            {
                LoadLibrary(appdata.Libraries[index]);
            }
        }
        public static void LoadLibrary(Library lib)
        {
            appdata.ActiveLibrary = lib;

            if (!Directory.Exists(lib.Dirpath))
            {
                Util.ShowInfoDialog($"The directory for library \"{lib.Name}\" at {lib.Dirpath} could not be found. This reference will now be removed. (If this library was manually moved you can re-add it via \"File > Add New Library\" at any time.");
                return;
            }

            string thumbPath = Path.Combine(lib.Dirpath, "data");
            if (!Directory.Exists(thumbPath)) Directory.CreateDirectory(thumbPath);

            string[] allImageFilepaths = Util.GetAllImageFilepaths(lib.Dirpath);
            List<string> unregisteredImages = allImageFilepaths.ToList();

            // add any new filepaths that don't have an entry in filenamedict to it
            AddNewEntriesToFilenameDict(allImageFilepaths);

            // remove entries whose source file no longer exists
            var deadKeys = appdata.ActiveLibrary.filenameDict
                .Where(kvp => !File.Exists(kvp.Value.Filepath))
                .Select(kvp => kvp.Key)
                .ToList();
            foreach (string key in deadKeys)
            {
                ImageData dead = appdata.ActiveLibrary.filenameDict[key];
                if (File.Exists(dead.ThumbnailPath))
                    File.Delete(dead.ThumbnailPath);
                appdata.ActiveLibrary.filenameDict.Remove(key);
            }

            // check all thumbnails are valid -- generate if not
            foreach (var kvp in appdata.ActiveLibrary.filenameDict)
            {
                ImageData img = kvp.Value;
                if (!File.Exists(img.ThumbnailPath))
                {
                    Util.CreateThumbnail(lib, img.Filepath);
                }
            }

            SetAllAndUntaggedToDict();
            Save();
            //Debug.WriteLine("hopefullythis works" + appdata.ActiveLibrary.filenameDict.Count);

            Searchbar.Search("all"); // dependencies but whatever

            if (MainWindow.initialized)
            {
                TagTreePanel.i.Populate(appdata.ActiveLibrary.tagTree, appdata.ActiveLibrary.tagDict);
            }

            OnNewLibraryLoaded?.Invoke(lib);
        }

        public static void GenTagDictAndSaveLibrary()
        {
            SetAllAndUntaggedToDict();
            //appdata.ActiveLibrary.FlushDeletedImages();
            Save();
        }

        public static void SetAllAndUntaggedToDict()
        {
            Dictionary<string, List<ImageData>> tagDict = appdata.ActiveLibrary.tagDict;
            List<ImageData> untagged = new();
            List<ImageData> allImages = new();

            foreach (var kvp in appdata.ActiveLibrary.filenameDict)
            {
                allImages.Add(kvp.Value);
                if (kvp.Value.Tags.Count == 0) untagged.Add(kvp.Value);
            }

            tagDict["all"] = allImages;
            tagDict["untagged"] = untagged;

        }


    }
}
