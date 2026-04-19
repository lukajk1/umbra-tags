using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    public class Tag
    {
        public Tag? Parent { get; set; }
        public string Name { get; set; }
        //public List<Tag> Children { get; set; }

        public Tag(string tag, Tag parent = null) // parent empty by default
        {
            Name = tag;
            Parent = parent;
        }
    }
    public class WrapperTest
    {
        public Dictionary<string, List<ImageData>> dict;
        public TagTree tagTreeData;
        public WrapperTest(Dictionary<string, List<ImageData>> dict, TagTree tagTreeData)
        {
            this.dict = dict;
            this.tagTreeData = tagTreeData;
        }
    }

    internal class SerializationTest
    {

        public SerializationTest()
        {
        }

        public static void CreateJson()
        {
            string[] allImageFiles = Util.GetAllImageFilepaths("C:\\Users\\lukaj\\My Drive\\art\\art ref\\serializeTest");

            Tag tag1 = new("AAAA");
            Tag tag2 = new("BBBB", tag1);
            Tag tag3 = new("CCCC");

            List<Tag> newList = new()
            {
                tag1, tag2, tag3
            };

            List<ImageData> images = new();
            foreach (string filepath in allImageFiles)
            {
                images.Add(new ImageData(filepath, filepath));
            }

            Dictionary<string, List<ImageData>> tagDict = new()
            {
                { "AAAA", images },
                { "BBBB", images },
                { "CCCC", images }
            };

            TagTree ttr = new TagTree();

            ttr.tagNodes = new()
            {
                new TagNode("tag5", "tag4", 2),
                new TagNode("tag4", "tag2", 1),
                new TagNode("tag1"),
                new TagNode("tag2"),
                new TagNode("tag3")
            };
            ttr.OrderByDepthAndAlphabetical();

            var settings = new JsonSerializerSettings
            {
                PreserveReferencesHandling = PreserveReferencesHandling.Objects,
                Formatting = Formatting.Indented
            };

            WrapperTest wrap = new(tagDict, ttr);

            string json = JsonConvert.SerializeObject(wrap, settings);
            File.WriteAllText("C:\\Users\\lukaj\\My Drive\\art\\art ref\\serializeTest\\output.json", json);

        }

        public static void ReadFromJson()
        {
            var settings = new JsonSerializerSettings
            {
                PreserveReferencesHandling = PreserveReferencesHandling.Objects
            };

            string json = File.ReadAllText("C:\\Users\\lukaj\\My Drive\\art\\art ref\\serializeTest\\output.json");
            //Dictionary<string, List<ImageData>> tagDict = JsonConvert.DeserializeObject<Dictionary<string, List<ImageData>>>(json, settings);

            WrapperTest wrapper = JsonConvert.DeserializeObject<WrapperTest>(json, settings);

            Debug.WriteLine("test begins here...");
            foreach (var kvp in wrapper.dict)
            {
                Debug.WriteLine(kvp.Key);
                Debug.WriteLine(kvp.Value[3].Filename);

            }


            Debug.WriteLine(wrapper.tagTreeData.tagNodes[1].Name);
        }

    }
}
