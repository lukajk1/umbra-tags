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

        public static void Open(List<GalleryItem> selection)
        {
            if (selection.Count == 1)
                Window.Text = "Tag Editor - " + selection[0].ImageData.Filename;
            else
                Window.Text = $"Tag Editor - {selection.Count} Items Selected";

            Window.Populate(selection);
            Window.Show();
        }
    }
}
