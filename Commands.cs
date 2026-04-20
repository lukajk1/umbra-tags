using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso.UI
{
    internal class Commands
    {
        public static void AddFilesViaDialog()
        {
            using (OpenFileDialog openFileDialog = new OpenFileDialog())
            {
                openFileDialog.Title = "Add Image Files";
                openFileDialog.Filter = "Image Files|*.jpg;*.jpeg;*.jfif;*.png;*.bmp;*.gif;*.webp";
                openFileDialog.Multiselect = true;
                openFileDialog.InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);


                if (openFileDialog.ShowDialog() == DialogResult.OK)
                {
                    string[] selectedFiles = openFileDialog.FileNames;
                    Util.CopyImageFilesToLibraryDir(selectedFiles);
                }
            }
        }
    }
}
