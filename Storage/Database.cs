using Calypso.UI;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;

namespace Calypso
{
    public class Appdata
    {
        public List<LibraryStub> Libraries    { get; set; } = new();
        public LibraryStub?      ActiveLibrary { get; set; }
        public Session           LastSession   { get; set; }

        public Appdata() { }
        public Appdata(List<LibraryStub> libraries, LibraryStub activeLibrary, Session lastSession)
        {
            Libraries     = libraries;
            ActiveLibrary = activeLibrary;
            LastSession   = lastSession;
        }
    }

    internal static partial class DB
    {
        public static Appdata  appdata       = new();
        public static Library  ActiveLibrary = null!;

        private static string _appFolder      = string.Empty;
        private static string _appdataPath    = string.Empty;
        private static string _appdataBakPath = string.Empty;
        private static string _appdataTmpPath = string.Empty;

        // keep old names as aliases so existing callers compile unchanged
        internal static string appdataBackupPath => _appdataBakPath;
        internal static string appdataTempPath   => _appdataTmpPath;

        private static System.Windows.Forms.Timer? _autoSaveTimer;

        public static event Action<Library>? OnNewLibraryLoaded;

        // ── init ──────────────────────────────────────────────────────────

        public static bool Init(MainWindow mainW)
        {
            string roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            _appFolder      = Path.Combine(roaming, "Umbra Tags");
            Directory.CreateDirectory(_appFolder);
            _appdataPath    = Path.Combine(_appFolder, "database.save");
            _appdataBakPath = Path.Combine(_appFolder, "database.save.bak");
            _appdataTmpPath = Path.Combine(_appFolder, "database.save.tmp");

            _autoSaveTimer = new System.Windows.Forms.Timer { Interval = 5 * 60 * 1000 };
            _autoSaveTimer.Tick += (_, _) => Save();
            _autoSaveTimer.Start();

            if (Load() || (appdata = NewAppdata()!) != null)
            {
                PreferencesManager.Init();
                mainW.LoadSession(appdata.LastSession);
                mainW.ApplyPreferences(PreferencesManager.Prefs);
                var toLoad = appdata.LastSession.LastActiveLibrary
                          ?? appdata.Libraries.FirstOrDefault();
                LoadLibrary(toLoad, search: false);
                if (ActiveLibrary != null)
                    Searchbar.Search(appdata.LastSession.LastSearch ?? "all");
                return true;
            }

            return false;
        }

        // ── save ──────────────────────────────────────────────────────────

        // Saves both the appdata shell and the active library.
        public static void Save()
        {
            SaveAppdata();
            if (ActiveLibrary != null) SaveLibrary(ActiveLibrary);
        }

        internal static void SaveAppdata()
        {
            try
            {
                string json = JsonConvert.SerializeObject(appdata, Formatting.Indented);
                AtomicWrite(_appdataPath, _appdataTmpPath, _appdataBakPath, json);
            }
            catch (Exception ex) { Debug.WriteLine($"Failed to save appdata: {ex.Message}"); }
        }

        public static void SaveLibrary(Library lib)
        {
            try
            {
                string path    = LibraryPath(lib);
                string tmpPath = path + ".tmp";
                string bakPath = path + ".bak";

                var settings = new JsonSerializerSettings
                {
                    PreserveReferencesHandling = PreserveReferencesHandling.Objects,
                    Formatting = Formatting.Indented
                };

                string json = JsonConvert.SerializeObject(lib, settings);
                AtomicWrite(path, tmpPath, bakPath, json);
            }
            catch (Exception ex) { Debug.WriteLine($"Failed to save library '{lib.Name}': {ex.Message}"); }
        }

        private static void AtomicWrite(string dest, string tmp, string bak, string json)
        {
            File.WriteAllText(tmp, json);
            if (File.Exists(dest)) File.Copy(dest, bak, overwrite: true);
            File.Move(tmp, dest, overwrite: true);
        }

        // ── load ──────────────────────────────────────────────────────────

        private static bool Load()
        {
            if (!File.Exists(_appdataPath))
            {
                Util.ShowErrorDialog($"database.save not found at:\n{_appdataPath}\n\nA new one will be created.");
                return false;
            }
            try
            {
                string json = File.ReadAllText(_appdataPath);
                var loaded = JsonConvert.DeserializeObject<Appdata>(json);
                if (loaded == null) return false;
                appdata = loaded;
                return true;
            }
            catch (Exception ex)
            {
                Util.ShowErrorDialog($"Failed to load appdata: {ex.Message}");
                return false;
            }
        }

        private static Library? LoadLibraryFile(LibraryStub stub)
        {
            string path = LibraryPath(stub);
            if (!File.Exists(path))
            {
                Util.ShowErrorDialog($"Library file for \"{stub.Name}\" not found at:\n{path}\n\nTag data will be empty. Re-importing images will restore file entries but tags will be lost.");
                return null;
            }
            try
            {
                var settings = new JsonSerializerSettings
                {
                    PreserveReferencesHandling = PreserveReferencesHandling.Objects
                };
                string json = File.ReadAllText(path);
                return JsonConvert.DeserializeObject<Library>(json, settings);
            }
            catch (Exception ex)
            {
                Util.ShowErrorDialog($"Failed to read library file for \"{stub.Name}\":\n{ex.Message}");
                return null;
            }
        }

        // ── close ─────────────────────────────────────────────────────────

        public static void OnClose(Session session)
        {
            appdata.LastSession = session;
            Save();
        }

        // ── library switching ─────────────────────────────────────────────

        public static void LoadLibrary(int index)
        {
            index -= 1;
            if (index < 0 || index >= appdata.Libraries.Count) return;
            var stub = appdata.Libraries[index];
            if (stub.Dirpath != ActiveLibrary?.Dirpath)
                LoadLibrary(stub);
        }

        public static void LoadLibrary(LibraryStub? stub, bool search = true)
        {
            if (stub == null) return;

            // try loading from .library file; fall back to a fresh Library
            Library lib = LoadLibraryFile(stub) ?? new Library(stub.Name, stub.Dirpath);
            LoadLibrary(lib, search);
        }

        public static void LoadLibrary(Library lib, bool search = true)
        {
            ActiveLibrary         = lib;
            appdata.ActiveLibrary = LibraryStub.FromLibrary(lib);

            if (!Directory.Exists(lib.Dirpath))
            {
                Util.ShowInfoDialog($"The directory for library \"{lib.Name}\" at {lib.Dirpath} could not be found. " +
                    "This reference will now be removed. (If this library was manually moved you can re-add it via " +
                    "\"File > Add New Library\" at any time.)");
                return;
            }

            string thumbPath = Path.Combine(lib.Dirpath, "data");
            if (!Directory.Exists(thumbPath)) Directory.CreateDirectory(thumbPath);

            SyncLibraryFiles(lib);
            Save();

            if (search) Searchbar.Search("all");

            if (MainWindow.initialized)
                TagTreePanel.i.Populate(ActiveLibrary.tagTree, ActiveLibrary.tagDict);

            MainWindow.i.UpdateTitle(lib.Name);
            OnNewLibraryLoaded?.Invoke(lib);
        }

        // ── helpers ───────────────────────────────────────────────────────

        private static string LibraryPath(LibraryStub stub)
            => Path.Combine(_appFolder, SanitizeName(stub.Name) + ".library");

        private static string LibraryPath(Library lib)
            => Path.Combine(_appFolder, SanitizeName(lib.Name) + ".library");

        private static string SanitizeName(string name)
            => string.Concat(name.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));

        private static Appdata? NewAppdata()
        {
            if (!PromptUserForLibrary("No existing library was found. Specify a folder now?", out string libraryPath))
                return null;
            if (!Util.TextPrompt("Set library name: ", out string libraryName)) return null;

            var newLib  = new Library(libraryName, libraryPath);
            var stub    = LibraryStub.FromLibrary(newLib);
            var session = MainWindow.i.CaptureCurrentSession();

            var newAppdata = new Appdata(
                libraries:     new List<LibraryStub> { stub },
                activeLibrary: stub,
                lastSession:   session
            );

            appdata       = newAppdata;
            ActiveLibrary = newLib;
            Save();
            return newAppdata;
        }

        private static bool PromptUserForLibrary(string message, out string libraryPath)
        {
            if (Util.ShowInfoDialog(message) == DialogResult.OK)
            {
                using var dialog = new FolderBrowserDialog();
                if (dialog.ShowDialog() == DialogResult.OK && !string.IsNullOrWhiteSpace(dialog.SelectedPath))
                {
                    libraryPath = dialog.SelectedPath;
                    return true;
                }
            }
            libraryPath = "";
            return false;
        }

        /// <summary>
        /// Manually sync the active library against its directory:
        /// picks up new files, prunes deleted ones, generates missing thumbnails, saves.
        /// </summary>
        public static void RefreshLibrary()
        {
            if (ActiveLibrary == null) return;
            SyncLibraryFiles(ActiveLibrary);
            PurgeReservedTags(ActiveLibrary);
            Save();
            TagTreePanel.i.Populate(ActiveLibrary.tagTree, ActiveLibrary.tagDict);
            Searchbar.RepeatLastSearch();
        }

        private static void PurgeReservedTags(Library lib)
        {
            var reserved = lib.tagTree.tagNodes
                .Where(n => VirtualTags.Contains(n.Name))
                .Select(n => n.Name)
                .ToList();

            foreach (string name in reserved)
                lib.DeleteTagFromTree(name);
        }

        private static void SyncLibraryFiles(Library lib)
        {
            AddNewEntriesToFilenameDict(Util.GetAllImageFilepaths(lib.Dirpath));

            var deadKeys = lib.filenameDict
                .Where(kvp => !File.Exists(kvp.Value.Filepath))
                .Select(kvp => kvp.Key).ToList();
            foreach (string key in deadKeys)
            {
                ImageData dead = lib.filenameDict[key];
                if (File.Exists(dead.ThumbnailPath)) File.Delete(dead.ThumbnailPath);
                lib.filenameDict.Remove(key);
            }

            foreach (var img in lib.filenameDict.Values)
                if (!File.Exists(img.ThumbnailPath))
                    Util.CreateThumbnail(lib, img.Filepath);

            SetAllAndUntaggedToDict();
            BackfillDHashes();
        }

        private static void AddNewEntriesToFilenameDict(string[] newImageFilepaths)
        {
            foreach (string filename in newImageFilepaths)
            {
                if (!ActiveLibrary.filenameDict.ContainsKey(filename))
                {
                    ActiveLibrary.filenameDict[filename] =
                        new ImageData(filename, Util.CreateThumbnail(ActiveLibrary, filename));
                }
            }
        }

        public static void GenTagDictAndSaveLibrary()
        {
            SetAllAndUntaggedToDict();
            SaveLibrary(ActiveLibrary);
        }

        public static void SetAllAndUntaggedToDict()
        {
            var tagDict  = ActiveLibrary.tagDict;
            var untagged = new List<ImageData>();
            var all      = new List<ImageData>();

            foreach (var img in ActiveLibrary.filenameDict.Values)
            {
                if (img.IsArchived) continue;
                all.Add(img);
                if (img.Tags.Count == 0) untagged.Add(img);
            }

            tagDict["all"]      = all;
            tagDict["untagged"] = untagged;
        }
    }
}
