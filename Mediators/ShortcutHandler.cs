using System.Windows.Forms;
using Calypso.UI;

namespace Calypso
{
    internal static class ShortcutHandler
    {
        private static TextBox searchBox;
        private static TreeView tagTree;

        public static void Init(MainWindow mainW)
        {
            searchBox = mainW.searchBox;
            tagTree = mainW.tagTree;
        }

        // Always fires regardless of focused pane.
        public static bool HandleGlobal(Keys keyData)
        {
            if (keyData == (Keys.Control | Keys.Q))
            {
                Application.Exit();
                return true;
            }

            if (keyData == (Keys.Control | Keys.L))
            {
                if (MainWindow.FocusedPane == Pane.Searchbar)
                    tagTree.Focus();
                else
                    searchBox.Focus();
                return true;
            }

            if ((keyData & (Keys.Control | Keys.Shift)) == (Keys.Control | Keys.Shift))
            {
                for (int i = 1; i <= 9; i++)
                {
                    if ((keyData & Keys.KeyCode) == (Keys)((int)Keys.D0 + i))
                    {
                        DB.LoadLibrary(i);
                        return true;
                    }
                }
            }

            return false;
        }

        // Fires only when the searchbox is not focused.
        public static bool HandleContextual(Keys keyData)
        {
            // Layout shortcuts
            if (keyData == (Keys.Control | Keys.D1)) { LayoutManager.SetLayout(LayoutManager.DefaultLayout); return true; }
            if (keyData == (Keys.Control | Keys.D2)) { LayoutManager.SetLayout(LayoutManager.LargeWindow); return true; }

            // Single-key panel toggles
            if (keyData == Keys.R) { LayoutManager.TogglePanel(LayoutManager.TagTreeSplitContainer, 1); return true; }
            if (keyData == Keys.N) { LayoutManager.TogglePanel(LayoutManager.MasterSplitContainer, 2); return true; }
            if (keyData == Keys.I) { LayoutManager.TogglePanel(LayoutManager.ImageInfoSplitContainer, 2); return true; }

            // Gallery actions
            if (keyData == (Keys.Control | Keys.T)) { Gallery.OpenTagEditorByCommand(); return true; }
            if (keyData == Keys.Delete) { if (MainWindow.FocusedPane == Pane.Gallery) Gallery.DeleteSelected(); return true; }
            if (keyData == Keys.Enter) { if (MainWindow.FocusedPane == Pane.Gallery) Gallery.OpenSelected(); return true; }
            if (keyData == Keys.Left || keyData == Keys.Right || keyData == Keys.Up || keyData == Keys.Down)
            {
                Gallery.ArrowSelect(keyData);
                return true;
            }

            // Ctrl shortcuts blocked during text input
            if (keyData == (Keys.Control | Keys.A)) { Gallery.SelectAll(); return true; }
            if (keyData == (Keys.Control | Keys.Enter)) { DB.OpenCurrentLibrarySourceFolder(); return true; }
            if (keyData == (Keys.Control | Keys.N)) { DB.AddNewLibrary(); return true; }
            if (keyData == (Keys.Control | Keys.I)) { Commands.AddFilesViaDialog(); return true; }
            if (keyData == (Keys.Control | Keys.E)) { Gallery.OpenSelectedInExplorer(); return true; }
            if (keyData == (Keys.Control | Keys.K)) { DB.appdata.ActiveLibrary.FlushTagDictDuplicates(); return true; }
            if (keyData == (Keys.Control | Keys.T))
            {
                if (Util.TextPrompt("Set tag name: ", out string newTag))
                    DB.appdata.ActiveLibrary.AddTagToTree(new TagNode(newTag));
                return true;
            }

            return false;
        }
    }
}
