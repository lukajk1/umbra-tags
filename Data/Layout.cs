using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    internal struct Layout
    {
        public float MetadataVSplitter_Ratio { get; set; }
        public float LeftPanelHSplitter_Ratio { get; set; }
        public float RightPanelHSplitter_Ratio { get; set; }
        public bool Metadata_IsOpen { get; set; }
        public bool LeftPanel_IsOpen { get; set; }
        public bool RightPanel_IsOpen { get; set; }
    }
}
