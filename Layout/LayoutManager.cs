using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    internal static class LayoutManager
    {

        public static Layout DefaultLayout = 
            new Layout()
            {
                MetadataVSplitter_Ratio = 0.76f,
                LeftPanelHSplitter_Ratio = 0.2f,
                RightPanelHSplitter_Ratio = 0.65f,
                Metadata_IsOpen = true,
                LeftPanel_IsOpen = true,
                RightPanel_IsOpen = true
            };

        public static Layout LargeWindow =
            new Layout()
            {
                MetadataVSplitter_Ratio = 0.74f,
                LeftPanelHSplitter_Ratio = 0.28f,
                RightPanelHSplitter_Ratio = 0.35f,
                Metadata_IsOpen = false,
                LeftPanel_IsOpen = false,
                RightPanel_IsOpen = true
            };

        public static SplitContainer TagTreeSplitContainer { get; private set; }
        public static SplitContainer MasterSplitContainer { get; private set; }
        public static SplitContainer ImageInfoSplitContainer { get; private set; }

        static int metadataHSplitter_Distance;
        static int leftPanelVSplitter_Distance;
        static int rightPanelVSplitter_Distance;

        static MainWindow? mainW;
        public static void Init(MainWindow mainW)
        {
            LayoutManager.mainW = mainW;

            TagTreeSplitContainer = mainW.tagTreeGallerySplitContainer;
            ImageInfoSplitContainer = mainW.imageInfoHorizontalSplitContainer;
            MasterSplitContainer = mainW.masterSplitContainer;

            SetLayout(DefaultLayout);
        }

        public static void SetLayout(Layout ld)
        {
            SetPanel(MasterSplitContainer, 2, ld.RightPanel_IsOpen);
            SetPanel(TagTreeSplitContainer, 1, ld.LeftPanel_IsOpen);
            SetPanel(ImageInfoSplitContainer, 2, ld.Metadata_IsOpen);

            TagTreeSplitContainer.SplitterDistance = (int)Math.Round(TagTreeSplitContainer.Width * ld.LeftPanelHSplitter_Ratio);
            MasterSplitContainer.SplitterDistance = (int)Math.Round(MasterSplitContainer.Width * ld.RightPanelHSplitter_Ratio);
            ImageInfoSplitContainer.SplitterDistance = (int)Math.Round(ImageInfoSplitContainer.Height * ld.MetadataVSplitter_Ratio);
        }

        public static void SaveLayout()
        {

        }

        // managing methods -----------------------------------------------------------------------

        public static void SetPanel(SplitContainer splitContainer, int panelNumber, bool value)
        {
            //// if re-opening the splitter, set the distance 
            //int splitterDistance = 0;
            //if (value)
            //{
            //    if (splitContainer is metadataHSplitter_Distance)
            //        splitterDistance = metadataHSplitter_Distance
            //}
            //    splitContainer.SplitterDistance = 

            if (panelNumber == 1)
                splitContainer.Panel1Collapsed = !value;
            else
                splitContainer.Panel2Collapsed = !value;
        }

        public static void TogglePanel(SplitContainer splitContainer, int panelNumber) 
        {
            SetPanel(splitContainer, panelNumber, panelNumber == 1? splitContainer.Panel1Collapsed : splitContainer.Panel2Collapsed);
        }


    }
}
