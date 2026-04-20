using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    public abstract class ContentData 
    {
        public string Filepath { get; protected set; }
        public string Filename { get; protected set; }
        public List<string> Tags { get; set; } = new(); // still allows addition and removal of tags
        public string GetFileExtension() => Path.GetExtension(Filepath);
        public bool FileExists() => File.Exists(Filepath);
        public void AddTags(List<string> tags)
        {
            foreach(var tag in tags)
            {
                if (!tags.Contains(tag))
                {
                    Tags.Add(tag);
                }
            }
        }
    }
    public class ImageData : ContentData
    {
        public string ThumbnailPath { get; }
        public ulong DHash { get; set; }
        public bool IsArchived { get; set; } = false;

        public ImageData(string filepath, string thumbnailPath)
        {
            Filepath = filepath;
            Filename = Path.GetFileName(Filepath);
            ThumbnailPath = thumbnailPath;
        }
    }
}
