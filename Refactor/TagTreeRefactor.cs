using System;
using System.Collections.Generic;
using System.Diagnostics.Eventing.Reader;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Calypso
{
    public class TagTreeRefactor
    {
        public List<TagNode> tagNodes { get; set; } = new();

        public bool Lookup(string tagName, out TagNode tagNode)
        {
            foreach (TagNode tag in tagNodes)
            {
                if (tag.Name == tagName)
                {
                    tagNode = tag;
                    return true;
                }
            }

            tagNode = new("throwaway");
            return false;
        }

        public List<TagNode> GetAllChildren(string tag)
        {
            List<TagNode> allChildren = new();

            if (Lookup(tag, out TagNode tagNode))
            {
                foreach (string child in tagNode.Children)
                {
                    if (Lookup(child, out TagNode childNode))
                    {
                        allChildren.Add(childNode);
                        allChildren.AddRange(GetAllChildren(childNode.Name));
                    }
                }
            }

            return allChildren;
        }


        public void OrderByDepthAndAlphabetical()
        {
            tagNodes = tagNodes.OrderBy(t => t.Depth).ThenBy(t => !t.Pinned).ThenBy(t => t.Name).ToList();
        }
    }
}
