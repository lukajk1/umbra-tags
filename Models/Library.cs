
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.Xml.Linq;

namespace Calypso
{
    public class Library
    {
        public string Name { get; set; }
        public string Dirpath { get; set; }
        public TagTree tagTree { get; set; } = new();
        public Dictionary<string, List<ImageData>> tagDict { get; set; } = new();
        public Dictionary<string, ImageData> filenameDict { get; set; } = new();
        public List<TagGroup> Groups { get; set; } = new();

        public const string UngroupedName = "Ungrouped";

        // ── group helpers ─────────────────────────────────────────────────

        /// <summary>Returns the group that contains this tag, or null.</summary>
        public TagGroup? GetGroupForTag(string tagName)
        {
            foreach (var g in Groups)
                if (g.Tags.Contains(tagName)) return g;
            return null;
        }

        /// <summary>Ensures an Ungrouped group exists and is last in the list.</summary>
        public TagGroup EnsureUngrouped()
        {
            var ug = Groups.FirstOrDefault(g => g.Name == UngroupedName);
            if (ug == null)
            {
                ug = new TagGroup(UngroupedName);
                Groups.Add(ug);
            }
            else
            {
                // Keep Ungrouped last
                Groups.Remove(ug);
                Groups.Add(ug);
            }
            return ug;
        }

        /// <summary>
        /// Ensures every tag in the tree belongs to a group.
        /// Tags not found in any group are added to Ungrouped.
        /// Also removes group entries for tags that no longer exist.
        /// </summary>
        public void SyncGroupMembership()
        {
            var allTagNames = new HashSet<string>(tagTree.tagNodes.Select(n => n.Name));

            // Remove stale entries from all groups
            foreach (var g in Groups)
                g.Tags.RemoveAll(t => !allTagNames.Contains(t));

            // Find tags not in any group
            var assigned = new HashSet<string>(Groups.SelectMany(g => g.Tags));
            var unassigned = allTagNames.Where(t => !assigned.Contains(t)).ToList();

            if (unassigned.Count > 0)
            {
                var ug = EnsureUngrouped();
                foreach (var t in unassigned)
                    ug.Tags.Add(t);
            }
            else
            {
                EnsureUngrouped(); // still ensure it exists and is last
            }
        }

        /// <summary>Moves a tag (and its descendants) to the target group.</summary>
        public void MoveTagToGroup(string tagName, string groupName)
        {
            // Remove from current group
            foreach (var g in Groups)
                g.Tags.Remove(tagName);

            var target = Groups.FirstOrDefault(g => g.Name == groupName);
            if (target == null)
            {
                target = new TagGroup(groupName);
                // Insert before Ungrouped
                int ugIndex = Groups.FindIndex(g => g.Name == UngroupedName);
                if (ugIndex >= 0) Groups.Insert(ugIndex, target);
                else Groups.Add(target);
            }
            target.Tags.Add(tagName);

            // Move children to same group (children cannot be in a different group)
            foreach (var child in tagTree.GetAllChildren(tagName))
            {
                foreach (var g in Groups) g.Tags.Remove(child.Name);
                target.Tags.Add(child.Name);
            }

            RefreshTagStructure();
        }

        public void AddGroup(string name)
        {
            if (Groups.Any(g => g.Name == name)) return;
            var ug = Groups.FirstOrDefault(g => g.Name == UngroupedName);
            int ugIndex = ug != null ? Groups.IndexOf(ug) : Groups.Count;
            Groups.Insert(ugIndex, new TagGroup(name));
            RefreshTagStructure();
        }

        public void MoveGroupUp(string name)
        {
            int i = Groups.FindIndex(g => g.Name == name);
            if (i <= 0) return;
            // Don't move above index 0, don't swap Ungrouped
            if (Groups[i].Name == UngroupedName) return;
            (Groups[i], Groups[i - 1]) = (Groups[i - 1], Groups[i]);
            RefreshTagStructure();
        }

        public void MoveGroupDown(string name)
        {
            int i = Groups.FindIndex(g => g.Name == name);
            if (i < 0 || i >= Groups.Count - 1) return;
            if (Groups[i].Name == UngroupedName) return;
            // Don't swap into Ungrouped's position (always last)
            if (Groups[i + 1].Name == UngroupedName) return;
            (Groups[i], Groups[i + 1]) = (Groups[i + 1], Groups[i]);
            RefreshTagStructure();
        }

        public void RenameGroup(string oldName, string newName)
        {
            if (oldName == UngroupedName) return;
            if (Groups.Any(g => g.Name == newName)) return;
            var g = Groups.FirstOrDefault(g => g.Name == oldName);
            if (g != null) g.Name = newName;
            RefreshTagStructure();
        }

        public Library(string name, string dirpath) 
        {
            Name = name;
            Dirpath = dirpath;
        }

        public void RefreshTagStructure()
        {
            CleanTagDict();
            tagTree.OrderByDepthAndAlphabetical();
            DB.GenTagDictAndSaveLibrary();
            TagTreePanel.i.Populate(tagTree, tagDict);
        }
        private void CleanTagDict()
        {
            // check for and remove duplicate objects
            foreach (var key in tagDict.Keys.ToList())
            {
                tagDict[key] = tagDict[key].Distinct().ToList();
            }

            // if any imagedata in a value does not have that tag, remove it.
            foreach (var key in tagDict.Keys.ToList())
            {
                var imgs = tagDict[key];
                var filtered = imgs.Where(img => img.Tags.Contains(key)).ToList();
                tagDict[key] = filtered;
            }

        }

        public void FlushDeletedImages()
        {
            List<ImageData> toRemove = new();

            foreach (List<ImageData> list in tagDict.Values)
            {
                foreach (var img in list)
                {
                    if (!File.Exists(img.Filepath))
                        toRemove.Add(img);
                }

                foreach (var item in toRemove)
                    list.Remove(item);
            }

            // Also remove from filenameDict so stale entries are not persisted
            foreach (var img in toRemove)
                filenameDict.Remove(img.Filepath);

            TagTreePanel.i.Populate(tagTree, tagDict);
        }

        private bool FormatAndValidateNewTag(string input, out string output)
        {
            output = input.Trim();

            // Check for reserved names before any processing
            if (output == "all" || output == "untagged")
            {
                Util.ShowErrorDialog($"Invalid name for a tag!");
                return false;
            }

            // Replace spaces with hyphens
            output = output.Replace(" ", "-");

            // Remove special characters manually
            var sb = new StringBuilder();
            foreach (char c in output)
            {
                if (char.IsLetterOrDigit(c) || c == '-')
                {
                    sb.Append(c);
                }
            }
            output = sb.ToString();

            // Clean up multiple consecutive hyphens
            while (output.Contains("--"))
            {
                output = output.Replace("--", "-");
            }

            // Remove leading/trailing hyphens
            output = output.Trim('-');

            // Check if the result is empty or invalid
            if (string.IsNullOrEmpty(output))
            {
                Util.ShowErrorDialog("Tag name cannot be empty after formatting!");
                return false;
            }

            return true;
        }
        public bool AddTagToTree(TagNode newTag)
        {
            if (FormatAndValidateNewTag(newTag.Name, out string validName))
            {
                newTag.Name = validName;
            }
            else
            {
                return false;
            }

            if (DB.VirtualTags.Contains(newTag.Name))
            {
                Util.ShowErrorDialog($"\"{newTag.Name}\" is a protected tag and cannot be used as a tag name.");
                return false;
            }

            foreach (TagNode node in tagTree.tagNodes)
            {
                if (node.Name == newTag.Name)
                {
                    Util.ShowErrorDialog($"The tag {newTag.Name} already exists!");
                    return false;
                }
            }

            if (tagTree.Lookup(newTag.Parent, out TagNode parentNode))
            {
                parentNode.Children.Add(newTag.Name);
            }

            // New tag goes to parent's group, or Ungrouped
            var parentGroup = !string.IsNullOrEmpty(newTag.Parent)
                ? GetGroupForTag(newTag.Parent) : null;
            var targetGroup = parentGroup ?? EnsureUngrouped();
            targetGroup.Tags.Add(newTag.Name);

            tagTree.tagNodes.Add(newTag);
            tagDict[newTag.Name] = new List<ImageData>();
            RefreshTagStructure();
            return true;
        }
        public bool DeleteTagFromTree(string tag)
        {
            if (!tagTree.tagNodes.Any(n => n.Name == tag))
                return false;

            // Gather all descendant tags before modifying the tagTree
            var allTagsToRemove = new HashSet<string> { tag };
            foreach (var child in tagTree.GetAllChildren(tag))
                allTagsToRemove.Add(child.Name);

            // Remove TagNodes
            List<TagNode> toRemove = new();
            foreach (string tagName in allTagsToRemove)
            {
                var node = tagTree.tagNodes.FirstOrDefault(n => n.Name == tagName);
                if (!string.IsNullOrEmpty(node.Name))
                    toRemove.Add(node);
            }

            foreach (var node in toRemove)
            {
                tagTree.tagNodes.Remove(node);
                tagDict.Remove(node.Name);
                // Remove from groups
                foreach (var g in Groups) g.Tags.Remove(node.Name);
            }

            // Remove tag references from images
            foreach (ImageData img in tagDict["all"])
                img.Tags.RemoveAll(t => allTagsToRemove.Contains(t));

            RefreshTagStructure();
            return true;
        }

        public bool RenameTag(string oldName, string newName)
        {
            // Validate the new name
            if (!FormatAndValidateNewTag(newName, out string validName))
                return false;

            // Check if old tag exists
            if (!tagTree.Lookup(oldName, out TagNode tagNode))
            {
                Util.ShowErrorDialog($"Tag '{oldName}' does not exist!");
                return false;
            }

            // Check if new name already exists (and it's not the same tag)
            if (validName != oldName && tagTree.tagNodes.Any(n => n.Name == validName))
            {
                Util.ShowErrorDialog($"The tag '{validName}' already exists!");
                return false;
            }

            // If the name hasn't actually changed, no need to do anything
            if (validName == oldName)
                return true;

            // Update the tag node name
            tagNode.Name = validName;

            // Update parent's children list
            if (!string.IsNullOrEmpty(tagNode.Parent))
            {
                if (tagTree.Lookup(tagNode.Parent, out TagNode parent))
                {
                    if (parent.Children.Contains(oldName))
                    {
                        parent.Children.Remove(oldName);
                        parent.Children.Add(validName);
                    }
                }
            }

            // Update children's parent reference
            foreach (string childTag in tagNode.Children)
            {
                if (tagTree.Lookup(childTag, out TagNode child))
                {
                    child.Parent = validName;
                }
            }

            // Update group membership
            var grp = GetGroupForTag(oldName);
            if (grp != null)
            {
                int idx = grp.Tags.IndexOf(oldName);
                if (idx >= 0) grp.Tags[idx] = validName;
            }

            // Update tagDict entry
            if (tagDict.ContainsKey(oldName))
            {
                List<ImageData> images = tagDict[oldName];
                tagDict[validName] = images;
                tagDict.Remove(oldName);

                // Update image tags
                foreach (var image in images)
                {
                    if (image.Tags.Contains(oldName))
                    {
                        image.Tags.Remove(oldName);
                        image.Tags.Add(validName);
                    }
                }
            }

            RefreshTagStructure();
            return true;
        }
        public void TagImage(string tag, ImageData img)
        {
            Util.ShowInfoDialog("tagimage called");
            TagImages(tag, new List<ImageData>() { img });
        }
        public void TagImages(string tag, List<ImageData> imgList)
        {
            foreach (var img in imgList)
            {
                if (tagDict.ContainsKey(tag))
                {
                    if (!tagDict[tag].Contains(img))
                    {
                        tagDict[tag].Add(img);
                    }

                    if (!img.Tags.Contains(tag)) // nesting this check ensures that only tags with a tagdict entry are added to images
                    {
                        img.Tags.Add(tag);
                    }
                }

                //Util.ShowInfoDialog(string.Join(", ", img.Tags));
            }
            RefreshTagStructure(); 
            //TagTreePanel.i.Populate(tagTree, tagDict);
        }
        public void UntagImage(string tag, ImageData img)
        {
            UntagImages(tag, new List<ImageData>() { img });
        }
        public void UntagImages(string tag, List<ImageData> imgList)
        {
            Debug.WriteLine("untag images called");
            foreach (var img in imgList)
            {
                if (tagDict.ContainsKey(tag))
                {
                    tagDict[tag].Remove(img);
                }
                if (img.Tags.Contains(tag)) img.Tags.Remove(tag);

            }

            TagTreePanel.i.Populate(tagTree, tagDict);

        }
        
        public void FlushTagDictDuplicates()
        {
            foreach (var key in tagDict.Keys.ToList())
            {
                tagDict[key] = tagDict[key].Distinct().ToList();
            }

        }
    }
}
