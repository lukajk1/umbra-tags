using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    internal class StatusBar
    {
        private static ToolStripStatusLabel? statusStripImageCount;
        public static void Init(MainWindow mainW)
        {
            StatusBar.statusStripImageCount = mainW.statusLabelResultsCount;
        }
    }
}
