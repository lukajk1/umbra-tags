using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    internal static class LibraryUIManager
    {
        private static MainWindow mainW;
        private static Session Session;
        public static void Init(MainWindow mainW)
        {
            LibraryUIManager.mainW = mainW;
            LoadLibraryUI();
            DB.OnNewLibraryLoaded += OnNewLibraryLoaded;
        }
        static void OnNewLibraryLoaded(Library library)
        {
            LoadLibraryUI(); // refresh ui
        }
        static void LoadLibraryUI()
        {
            RemovePlaceholders();

            foreach (Library lib in DB.appdata.Libraries)
            {
                int index = DB.appdata.Libraries.IndexOf(lib) + 1;
                bool activeLib = (lib == DB.appdata.ActiveLibrary);

                ToolStripMenuItem newItem = new ToolStripMenuItem(activeLib ? $"{index} - {lib.Name} (Current)" : $"{index} - {lib.Name}");

                var openSub = new ToolStripMenuItem("Open", null, (s, e) => HandleLibraryAction("open", lib));
                if (activeLib) openSub.Enabled = false;
                if (index < 10) openSub.ShortcutKeyDisplayString = $"Alt + {index}";

                var renameSub = new ToolStripMenuItem("Rename", null, (s, e) => HandleLibraryAction("rename", lib));
                var removeSub = new ToolStripMenuItem("Remove", null, (s, e) => HandleLibraryAction("remove", lib));

                newItem.DropDownItems.Add(openSub);
                newItem.DropDownItems.Add(renameSub);
                newItem.DropDownItems.Add(removeSub);

                mainW.openExistingLibraryToolStripMenuItem.DropDownItems.Insert(0, newItem);
            }
        }
        static void HandleLibraryAction(string action, Library lib)
        {
            switch (action)
            {
                case "open":
                    DB.LoadLibrary(lib);
                    break;
                case "rename":
                    if (Util.TextPrompt("Set new library name: ", out string result, lib.Name))
                    {
                        lib.Name = result;
                        LoadLibraryUI();
                    }
                    break;
                case "remove":
                    if (DB.appdata.Libraries.Count == 1)
                    {
                        Util.ShowErrorDialog("Add another library first to remove this one!");
                        break;
                    }

                    int index = DB.appdata.Libraries.IndexOf(lib);
                    if (index != -1)
                    {
                        int nextIndex = (index + 1) % DB.appdata.Libraries.Count;
                        var nextItem = DB.appdata.Libraries[nextIndex];

                        DB.LoadLibrary(nextItem);
                        DB.appdata.Libraries.Remove(lib);
                        LoadLibraryUI();
                    }

                    break;
            }
        }
        static void RemovePlaceholders()
        {
            var toRemove = new List<ToolStripItem>();

            foreach (ToolStripItem item in mainW.openExistingLibraryToolStripMenuItem.DropDownItems)
            {
                if (item is ToolStripMenuItem menuItem && item.Tag?.ToString() != "no-delete")
                {
                    toRemove.Add(item);
                }
            }

            foreach (var item in toRemove)
            {
                mainW.openExistingLibraryToolStripMenuItem.DropDownItems.Remove(item);
            }
        }
    }
}
