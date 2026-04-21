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

            foreach (LibraryStub stub in DB.appdata.Libraries)
            {
                int index = DB.appdata.Libraries.IndexOf(stub) + 1;
                bool activeLib = stub.Dirpath == DB.ActiveLibrary?.Dirpath;

                ToolStripMenuItem newItem = new ToolStripMenuItem(activeLib ? $"{index} - {stub.Name} (Current)" : $"{index} - {stub.Name}");

                var openSub = new ToolStripMenuItem("Open", null, (s, e) => HandleLibraryAction("open", stub));
                if (activeLib) openSub.Enabled = false;
                if (index < 10) openSub.ShortcutKeyDisplayString = $"Alt + {index}";

                var renameSub = new ToolStripMenuItem("Rename", null, (s, e) => HandleLibraryAction("rename", stub));
                var removeSub = new ToolStripMenuItem("Remove", null, (s, e) => HandleLibraryAction("remove", stub));

                newItem.DropDownItems.Add(openSub);
                newItem.DropDownItems.Add(renameSub);
                newItem.DropDownItems.Add(removeSub);

                mainW.openExistingLibraryToolStripMenuItem.DropDownItems.Insert(0, newItem);
            }

            Calypso.UI.ThemeManager.Apply(mainW.menuStrip1);
        }
        static void HandleLibraryAction(string action, LibraryStub stub)
        {
            switch (action)
            {
                case "open":
                    DB.LoadLibrary(stub);
                    break;
                case "rename":
                    if (Util.TextPrompt("Set new library name: ", out string result, stub.Name))
                    {
                        stub.Name = result;
                        if (DB.ActiveLibrary?.Dirpath == stub.Dirpath)
                            DB.ActiveLibrary.Name = result;
                        DB.Save();
                        LoadLibraryUI();
                    }
                    break;
                case "remove":
                    if (DB.appdata.Libraries.Count == 1)
                    {
                        Util.ShowErrorDialog("Add another library first to remove this one!");
                        break;
                    }

                    int index = DB.appdata.Libraries.IndexOf(stub);
                    if (index != -1)
                    {
                        int nextIndex = (index + 1) % DB.appdata.Libraries.Count;
                        var nextStub = DB.appdata.Libraries[nextIndex];

                        DB.LoadLibrary(nextStub);
                        DB.appdata.Libraries.Remove(stub);
                        DB.SaveAppdata();
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
