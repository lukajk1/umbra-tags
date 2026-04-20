using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso.UI
{
    internal class TagEditManager
    {
        public static TagEditor Window;
        static MainWindow? mainW;
        public static void Init(MainWindow mainW)
        {
            Window = new TagEditor(mainW);
            Window.StartPosition = FormStartPosition.CenterScreen;
        }

        public static void Open(List<TileTag> selection)
        {
            List<string> filenames = new();

            foreach (var tTag in selection)
            {
                filenames.Add(tTag._ImageData.Filename);
            }

            int last = 0;
            if (selection.Count > 0)
            {
                last = selection.Count - 1;   
            }
            // hack solution but whatever
            int displayCount = Math.Max(1, selection.Count - 1);
            if (displayCount == 1)
            {
                Window.Text = "Tag Editor - " + selection[0]._ImageData.Filename;
            }
            else
            {
                Window.Text = $"Tag Editor - {displayCount} Items Selected";
            }

            Window.Populate(selection);
            Window.Show();
        }
    }
}
