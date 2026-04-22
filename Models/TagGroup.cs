using System.Collections.Generic;

namespace Calypso
{
    public class TagGroup
    {
        public string Name { get; set; } = string.Empty;
        public List<string> Tags { get; set; } = new();

        /// <summary>ARGB int, or 0 for no color (uses default foreground).</summary>
        public int GroupColor { get; set; } = 0;

        public TagGroup() { }
        public TagGroup(string name) { Name = name; }
    }
}
