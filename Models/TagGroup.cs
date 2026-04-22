using System.Collections.Generic;

namespace Calypso
{
    public class TagGroup
    {
        public string Name { get; set; } = string.Empty;
        public List<string> Tags { get; set; } = new();

        public TagGroup() { }
        public TagGroup(string name) { Name = name; }
    }
}
