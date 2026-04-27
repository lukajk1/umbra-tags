using Calypso.UI;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Calypso
{
    internal class TagTreePanel
    {
        // main refs
        private TreeView tagTree;
        private MainWindow mainW;
        public static TagTreePanel i;

        // internal use
        private TreeNode? selectedNode = null;
        private bool _suppressNextGroupClick = false;

        // context menu items added dynamically
        private ToolStripMenuItem pinItem;
        private ToolStripMenuItem moveToGroupItem;
        private ToolStripSeparator groupSep;

        // predefined group color palette — (label, color)
        private static readonly (string Label, Color Color)[] GroupColorPalette =
        {
            ("None",   Color.Empty),
            ("Red",    Color.FromArgb(220,  80,  80)),
            ("Orange", Color.FromArgb(220, 140,  50)),
            ("Yellow", Color.FromArgb(210, 200,  60)),
            ("Green",  Color.FromArgb( 80, 180,  80)),
            ("Teal",   Color.FromArgb( 60, 180, 170)),
            ("Blue",   Color.FromArgb( 80, 140, 220)),
            ("Purple", Color.FromArgb(150,  80, 220)),
            ("Pink",   Color.FromArgb(220, 100, 160)),
            ("White",  Color.FromArgb(220, 220, 220)),
            ("Gray",   Color.FromArgb(130, 130, 130)),
        };

        // group header context menu (separate)
        private ContextMenuStrip groupContextMenu;

        public TagTreePanel(MainWindow mainW)
        {
            i = this;
            this.mainW = mainW;
            tagTree = mainW.tagTree;
            tagTree.BeforeCollapse += (s, e) =>
            {
                if (e.Node.Tag is not GroupNodeTag)
                {
                    e.Cancel = true;
                    return;
                }
                if (e.Action != TreeViewAction.Collapse)
                {
                    e.Cancel = true;
                    return;
                }
                _suppressNextGroupClick = true;
            };
            tagTree.BeforeExpand += (s, e) =>
            {
                if (e.Node.Tag is not GroupNodeTag) return;
                if (e.Action != TreeViewAction.Expand)
                {
                    e.Cancel = true;
                    return;
                }
                _suppressNextGroupClick = true;
            };

            // ── tag node context menu additions ───────────────────────────
            pinItem = new ToolStripMenuItem("Pin Tag") { Name = "pinTagToolStripMenuItem" };
            pinItem.Click += (s, e) => TogglePin(s);

            moveToGroupItem = new ToolStripMenuItem("Move to Group") { Name = "moveToGroupToolStripMenuItem" };

            groupSep = new ToolStripSeparator();

            var menu = mainW.contextMenuTagTree;
            menu.Items.Insert(0, pinItem);
            menu.Items.Insert(1, moveToGroupItem);
            menu.Items.Insert(2, groupSep);
            menu.Items.Insert(menu.Items.IndexOf(mainW.deleteToolStripMenuItem), new ToolStripSeparator());

            // ── group header context menu ─────────────────────────────────
            groupContextMenu = new ContextMenuStrip();
            ThemeManager.ApplyContextMenu(groupContextMenu);

            var newGroupItem    = new ToolStripMenuItem("New Group...");
            var renameGroupItem = new ToolStripMenuItem("Rename Group...");
            var setColorItem    = new ToolStripMenuItem("Set Color") { Name = "setColorToolStripMenuItem" };
            var deleteGroupItem = new ToolStripMenuItem("Delete Group");
            var mergeIntoItem   = new ToolStripMenuItem("Merge into") { Name = "mergeIntoToolStripMenuItem" };
            var moveUpItem      = new ToolStripMenuItem("Move Group Up");
            var moveDownItem    = new ToolStripMenuItem("Move Group Down");

            newGroupItem.Click    += (s, e) => NewGroup();
            renameGroupItem.Click += (s, e) => RenameSelectedGroup();
            deleteGroupItem.Click += (s, e) => DeleteSelectedGroup();
            moveUpItem.Click      += (s, e) => MoveSelectedGroupUp();
            moveDownItem.Click    += (s, e) => MoveSelectedGroupDown();

            // populate color submenu once
            BuildColorSubmenu(setColorItem);

            groupContextMenu.Items.AddRange(new ToolStripItem[]
            {
                newGroupItem,
                new ToolStripSeparator(),
                renameGroupItem,
                setColorItem,
                mergeIntoItem,
                deleteGroupItem,
                new ToolStripSeparator(),
                moveUpItem,
                moveDownItem
            });

            Populate(DB.ActiveLibrary.tagTree, DB.ActiveLibrary.tagDict);
        }

        public void Populate(TagTree tagTreeData, Dictionary<string, List<ImageData>> tagDict)
        {
            tagTree.BeginUpdate();
            tagTree.Nodes.Clear();

            tagTree.NodeMouseClick -= OnTagNodeClick;
            tagTree.NodeMouseClick += OnTagNodeClick;

            // ── virtual tags block ────────────────────────────────────────
            int activeCount  = tagDict.ContainsKey("all")      ? tagDict["all"].Count      : 0;
            int untaggedCount= tagDict.ContainsKey("untagged") ? tagDict["untagged"].Count : 0;
            int archivedCount= DB.ActiveLibrary?.filenameDict.Values.Count(img => img.IsArchived) ?? 0;
            int videoCount   = DB.ActiveLibrary?.filenameDict.Values.Count(img => !img.IsArchived && img.IsVideo) ?? 0;

            TreeNode nodeAll      = MakeVirtualNode($"All Images ({activeCount})",    "all");
            TreeNode nodeVideos   = MakeVirtualNode($"All Videos ({videoCount})",     "allvideos");
            TreeNode nodeUntagged = MakeVirtualNode($"Untagged ({untaggedCount})",    "untagged");
            TreeNode nodeArchived = MakeVirtualNode($"Archived ({archivedCount})",    "archived");
            TreeNode nodeRandImg  = MakeVirtualNode("Random Image",                   "randimg");
            TreeNode nodeRandTag  = MakeVirtualNode("Random Tag",                     "randtag");

            tagTree.Nodes.Add(nodeAll);
            tagTree.Nodes.Add(nodeVideos);
            tagTree.Nodes.Add(nodeUntagged);
            tagTree.Nodes.Add(nodeArchived);
            tagTree.Nodes.Add(nodeRandImg);
            tagTree.Nodes.Add(nodeRandTag);

            // separator
            var sep = new TreeNode("──────────") { ForeColor = Color.Gray, NodeFont = new Font("Consolas", 8) };
            sep.Tag = "separator";
            tagTree.Nodes.Add(sep);

            // ── groups + tags ─────────────────────────────────────────────
            var lib = DB.ActiveLibrary;
            if (lib != null)
            {
                foreach (var group in lib.Groups)
                {
                    Color groupColor = group.GroupColor != 0
                        ? Color.FromArgb(group.GroupColor)
                        : Color.FromArgb(180, 180, 180);

                    var groupNode = new TreeNode(group.Name)
                    {
                        Tag       = new GroupNodeTag(group),
                        ForeColor = groupColor,
                        NodeFont  = new Font(tagTree.Font, FontStyle.Bold),
                    };

                    // Only top-level tags in this group (no parent, or parent not in same group)
                    var topTagsQuery = group.Tags
                        .Select(t => tagTreeData.tagNodes.FirstOrDefault(n => n.Name == t))
                        .Where(n => n != null && string.IsNullOrEmpty(n.Parent));

                    IEnumerable<TagNode?> topTags;
                    if (group.Name == Library.DateGroupName)
                    {
                        // Sort date tags newest-first (parse MM-yy, treat yy as 2000+yy)
                        topTags = topTagsQuery.OrderByDescending(n =>
                        {
                            if (DateTime.TryParseExact(n!.Name, "MM-yy",
                                System.Globalization.CultureInfo.InvariantCulture,
                                System.Globalization.DateTimeStyles.None, out var d)) return d;
                            return DateTime.MinValue;
                        });
                    }
                    else
                    {
                        topTags = topTagsQuery
                            .OrderBy(n => n!.Pinned ? 0 : 1)
                            .ThenBy(n => n!.Name);
                    }

                    foreach (var node in topTags)
                    {
                        int count = tagDict.ContainsKey(node!.Name) ? tagDict[node.Name].Count : 0;
                        AddTagNodeToTree(node, count, groupNode, tagDict);
                    }

                    tagTree.Nodes.Add(groupNode);
                }
            }

            tagTree.ExpandAll();
            tagTree.EndUpdate();
        }

        private static TreeNode MakeVirtualNode(string text, string tag)
            => new TreeNode(text) { Tag = tag };

        private void AddTagNodeToTree(TagNode node, int count, TreeNode parent, Dictionary<string, List<ImageData>> tagDict)
        {
            string pin = node.Pinned ? "★ " : "";
            var treeNode = new TreeNode($"{pin}{node.Name} ({count})") { Tag = node };

            foreach (var childName in node.Children)
            {
                var child = DB.ActiveLibrary?.tagTree.tagNodes.FirstOrDefault(n => n.Name == childName);
                if (child == null) continue;
                int childCount = tagDict.ContainsKey(child.Name) ? tagDict[child.Name].Count : 0;
                AddTagNodeToTree(child, childCount, treeNode, tagDict);
            }

            parent.Nodes.Add(treeNode);
        }

        private IEnumerable<TreeNode> GetAllNodes(TreeView treeView)
        {
            foreach (TreeNode node in treeView.Nodes)
                foreach (var child in GetAllNodes(node))
                    yield return child;
        }

        private IEnumerable<TreeNode> GetAllNodes(TreeNode parent)
        {
            yield return parent;
            foreach (TreeNode child in parent.Nodes)
                foreach (var descendant in GetAllNodes(child))
                    yield return descendant;
        }

        private void OnTagNodeClick(object sender, TreeNodeMouseClickEventArgs e)
        {
            selectedNode = e.Node;

            if (e.Button == MouseButtons.Left)
            {
                if (selectedNode.Tag is TagNode tagNode)
                {
                    Searchbar.Search(tagNode.Name);
                }
                else if (selectedNode.Tag is GroupNodeTag gnt)
                {
                    if (_suppressNextGroupClick)
                    {
                        _suppressNextGroupClick = false;
                        return;
                    }
                    Searchbar.Search($"g:{gnt.Group.Name}");
                }
                else if (selectedNode.Tag is string value)
                {
                    Searchbar.Search(value);
                }
            }
            else if (e.Button == MouseButtons.Right)
            {
                // Group header node — show group context menu instead
                if (selectedNode.Tag is GroupNodeTag)
                {
                    UpdateGroupContextMenuState();
                    groupContextMenu.Show(tagTree, e.Location);
                    return;
                }

                // Tag node — show normal context menu
                bool isPinned = selectedNode?.Tag is TagNode tn && tn.Pinned;
                var pinMenuItem = mainW.contextMenuTagTree.Items
                    .OfType<ToolStripMenuItem>()
                    .FirstOrDefault(i => i.Name == "pinTagToolStripMenuItem");
                if (pinMenuItem != null)
                {
                    pinMenuItem.Text    = isPinned ? "Unpin Tag" : "Pin Tag";
                    pinMenuItem.Visible = selectedNode?.Tag is TagNode;
                }

                // Build "Move to Group" submenu
                var moveItem = mainW.contextMenuTagTree.Items
                    .OfType<ToolStripMenuItem>()
                    .FirstOrDefault(i => i.Name == "moveToGroupToolStripMenuItem");
                if (moveItem != null)
                {
                    moveItem.Visible = selectedNode?.Tag is TagNode;
                    if (selectedNode?.Tag is TagNode)
                        BuildMoveToGroupSubmenu(moveItem);
                }

                groupSep.Visible = selectedNode?.Tag is TagNode;

                mainW.contextMenuTagTree.Show(tagTree, e.Location);
            }
        }

        private void BuildMoveToGroupSubmenu(ToolStripMenuItem parent)
        {
            parent.DropDownItems.Clear();
            var lib = DB.ActiveLibrary;
            if (lib == null) return;

            foreach (var group in lib.Groups)
            {
                string gname = group.Name;
                var item = new ToolStripMenuItem(gname);
                item.Click += (s, e) =>
                {
                    if (selectedNode?.Tag is TagNode tn)
                        lib.MoveTagToGroup(tn.Name, gname);
                };
                parent.DropDownItems.Add(item);
            }

            parent.DropDownItems.Add(new ToolStripSeparator());

            var newGroupEntry = new ToolStripMenuItem("New Group...");
            newGroupEntry.Click += (s, e) =>
            {
                if (selectedNode?.Tag is TagNode tn)
                    NewGroupAndMoveTag(tn.Name);
            };
            parent.DropDownItems.Add(newGroupEntry);

            // Re-apply theme to the freshly-built submenu items
            foreach (ToolStripItem ddi in parent.DropDownItems)
            {
                ddi.BackColor = Theme.Surface;
                ddi.ForeColor = Theme.Foreground;
            }
        }

        private void UpdateGroupContextMenuState()
        {
            if (selectedNode?.Tag is not GroupNodeTag gnt) return;
            var lib = DB.ActiveLibrary;
            if (lib == null) return;

            string name = gnt.Group.Name;
            bool isSystem = name == Library.UngroupedName || name == Library.DateGroupName;

            foreach (ToolStripItem item in groupContextMenu.Items)
            {
                if (item is ToolStripMenuItem mi)
                {
                    switch (mi.Text)
                    {
                        case "Rename Group...":
                        case "Delete Group":
                            mi.Enabled = !isSystem;
                            break;
                    }
                }
            }

            // Build "Merge into" submenu — all groups except the selected one
            var mergeItem = groupContextMenu.Items
                .OfType<ToolStripMenuItem>()
                .FirstOrDefault(i => i.Name == "mergeIntoToolStripMenuItem");
            if (mergeItem != null)
            {
                mergeItem.DropDownItems.Clear();
                var others = lib.Groups.Where(g => g.Name != name).ToList();
                mergeItem.Enabled = others.Count > 0;
                foreach (var group in others)
                {
                    string targetName = group.Name;
                    var entry = new ToolStripMenuItem(targetName);
                    entry.BackColor = Theme.Surface;
                    entry.ForeColor = Theme.Foreground;
                    entry.Click += (s, e) =>
                    {
                        if (Util.ShowConfirmDialog($"Merge \"{name}\" into \"{targetName}\"? All tags will be moved and \"{name}\" will be removed.") == DialogResult.OK)
                            lib.MergeGroup(name, targetName);
                    };
                    mergeItem.DropDownItems.Add(entry);
                }
            }
        }

        // ── color submenu ─────────────────────────────────────────────────

        private void BuildColorSubmenu(ToolStripMenuItem parent)
        {
            parent.DropDownItems.Clear();

            foreach (var (label, color) in GroupColorPalette)
            {
                Color captured = color;
                var item = new ColorSwatchMenuItem(label, color);
                item.Click += (s, e) =>
                {
                    if (selectedNode?.Tag is GroupNodeTag gnt)
                        DB.ActiveLibrary?.SetGroupColor(gnt.Group.Name, captured);
                };
                parent.DropDownItems.Add(item);
            }
        }

        // ── group actions ─────────────────────────────────────────────────

        private void NewGroup()
        {
            if (Util.TextPrompt("New group name:", out string name))
                DB.ActiveLibrary?.AddGroup(name);
        }

        private void NewGroupAndMoveTag(string tagName)
        {
            if (Util.TextPrompt("New group name:", out string name))
            {
                var lib = DB.ActiveLibrary;
                if (lib == null) return;
                lib.AddGroup(name);
                lib.MoveTagToGroup(tagName, name);
            }
        }

        private void RenameSelectedGroup()
        {
            if (selectedNode?.Tag is not GroupNodeTag gnt) return;
            if (Util.TextPrompt("New group name:", out string name, gnt.Group.Name))
                DB.ActiveLibrary?.RenameGroup(gnt.Group.Name, name);
        }

        private void DeleteSelectedGroup()
        {
            if (selectedNode?.Tag is not GroupNodeTag gnt) return;
            var lib = DB.ActiveLibrary;
            if (lib == null) return;

            string groupName = gnt.Group.Name;

            int tagCount = gnt.Group.Tags.Count;
            string detail = tagCount > 0
                ? $" Its {tagCount} tag(s) will be moved to Ungrouped."
                : string.Empty;
            if (Util.ShowConfirmDialog($"Delete group \"{groupName}\"?{detail}") != DialogResult.OK)
                return;
            var group = lib.Groups.FirstOrDefault(g => g.Name == groupName);
            if (group == null) return;

            // Move all tags in this group to Ungrouped
            var tagsToMove = group.Tags.ToList();
            lib.Groups.Remove(group);
            var ug = lib.EnsureUngrouped();
            foreach (var t in tagsToMove)
                ug.Tags.Add(t);

            lib.RefreshTagStructure();
        }

        private void MoveSelectedGroupUp()
        {
            if (selectedNode?.Tag is GroupNodeTag gnt)
                DB.ActiveLibrary?.MoveGroupUp(gnt.Group.Name);
        }

        private void MoveSelectedGroupDown()
        {
            if (selectedNode?.Tag is GroupNodeTag gnt)
                DB.ActiveLibrary?.MoveGroupDown(gnt.Group.Name);
        }

        // ── tag actions ───────────────────────────────────────────────────

        public void RenameTag(object sender)
        {
            if (selectedNode.Tag is not TagNode tagNode) return;

            if (Util.TextPrompt("Set new tag name: ", out string newName, tagNode.Name))
            {
                DB.ActiveLibrary.RenameTag(tagNode.Name, newName);
            }
        }

        public void DeleteTag(object sender)
        {
            int children = selectedNode.Nodes.Count;
            if (children > 0)
            {
                Util.ShowConfirmDialog($"This tag has children which will be deleted as well. Proceed?");
            }
            if (selectedNode.Tag is TagNode tn)
            {
                DB.ActiveLibrary.DeleteTagFromTree(tn.Name);
            }
        }

        public void TogglePin(object sender)
        {
            if (selectedNode?.Tag is not TagNode tagNode) return;
            tagNode.Pinned = !tagNode.Pinned;
            DB.ActiveLibrary.RefreshTagStructure();
        }

        public void AddChildTag(object sender)
        {
            if (selectedNode.Tag is TagNode parentNode)
            {
                if (Util.TextPrompt("Set tag name: ", out string name))
                {
                    var newTag = new TagNode(name, parentNode.Name, parentNode.Depth + 1);
                    DB.ActiveLibrary.AddTagToTree(newTag);
                }
            }
        }
    }

    /// <summary>
    /// A ToolStripMenuItem that draws a colored square swatch next to its label.
    /// </summary>
    internal sealed class ColorSwatchMenuItem : ToolStripMenuItem
    {
        private readonly Color _swatch;
        private const int SwatchSize   = 13;
        private const int SwatchMargin = 6;

        public ColorSwatchMenuItem(string label, Color swatch) : base(label)
        {
            _swatch = swatch;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g      = e.Graphics;
            var bounds = new Rectangle(Point.Empty, Size);

            bool selected = Selected;
            Color bg = selected ? Theme.SurfaceRaised : Theme.Surface;
            g.FillRectangle(new SolidBrush(bg), bounds);

            int swatchY   = (bounds.Height - SwatchSize) / 2;
            var swatchRect = new Rectangle(SwatchMargin, swatchY, SwatchSize, SwatchSize);

            if (_swatch != Color.Empty)
            {
                g.FillRectangle(new SolidBrush(_swatch), swatchRect);
                g.DrawRectangle(new Pen(Theme.Border), swatchRect);
            }
            else
            {
                g.DrawRectangle(new Pen(Theme.Border), swatchRect);
                g.DrawLine(new Pen(Theme.ForegroundDim), swatchRect.Left, swatchRect.Top,  swatchRect.Right,  swatchRect.Bottom);
                g.DrawLine(new Pen(Theme.ForegroundDim), swatchRect.Right, swatchRect.Top, swatchRect.Left, swatchRect.Bottom);
            }

            int textX = swatchRect.Right + SwatchMargin;
            using var brush = new SolidBrush(Theme.Foreground);
            g.DrawString(Text, Font, brush,
                new RectangleF(textX, 0, bounds.Width - textX, bounds.Height),
                new StringFormat { LineAlignment = StringAlignment.Center });
        }

        public override Size GetPreferredSize(Size constrainingSize)
        {
            return new Size(130, 22);
        }
    }
}
