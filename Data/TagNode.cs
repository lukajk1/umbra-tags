using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    public class TagNode
    {
        public int Depth {  get; set; }
        public string Parent { get; set; }
        public string Name { get; set; }
        public bool Pinned { get; set; } = false;
        public List<string> Children { get; set; } = new();

        public TagNode(string tag, string parent = "", int depth = 0) // parent empty by default
        {
            Name = tag;
            Parent = parent;
            Depth = depth;
        }    
    }
}
