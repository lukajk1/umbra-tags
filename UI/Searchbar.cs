using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    internal static class Searchbar
    {
        static MainWindow? mainW;
        static string lastSearch = "all";
        public static void Init(MainWindow? mainW)
        {
            Searchbar.mainW = mainW;
            mainW.searchBox.Click += FocusSearch;
        }

        public static void Search(string text)
        {
            mainW.searchBox.Text = text;
            lastSearch = text;

            int index = mainW.comboBoxResultsNum.SelectedIndex;
            int[] map = { 0, 25, 50 }; // upperlimit settings
            int resultsCount = map[index];

            DB.Search(text, mainW.checkBoxRandomize.Checked, resultsCount);
        }

        public static void RepeatLastSearch()
        {
            Search(lastSearch);
        }

        private static void FocusSearch(object sender, EventArgs e)
        {
            MainWindow.FocusedPane = Pane.Searchbar;
            mainW.searchBox.Focus();
        }
    }
}
