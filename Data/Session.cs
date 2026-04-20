using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    public struct Session
    {
        public int WindowWidth { get; set; }
        public int WindowHeight { get; set; }
        public bool RandomiseChecked { get; set; }
        public FormWindowState WindowState { get; set; }
        public Library LastActiveLibrary { get; set; }
        public int ZoomModifier { get; set; }
        public bool ShowFilenames { get; set; } = true;
        public string LastSearch { get; set; } = "all";

        public Session(int windowWidth, int windowHeight, bool randomiseChecked,
                    FormWindowState windowState, Library lastActiveLibrary, int zoomModifier,
                    bool showFilenames = true, string lastSearch = "all")
        {
            WindowWidth = windowWidth;
            WindowHeight = windowHeight;
            RandomiseChecked = randomiseChecked;
            WindowState = windowState;
            LastActiveLibrary = lastActiveLibrary;
            ZoomModifier = zoomModifier;
            ShowFilenames = showFilenames;
            LastSearch = lastSearch;
        }
    }
}
