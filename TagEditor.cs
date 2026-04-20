using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Calypso
{
    public partial class TagEditor : Form
    {
        private MainWindow? mainW;
        List<Calypso.UI.GalleryItem> selection = new();
        private ImageData currentImageData;
        private List<string> commonTags = new();

        public TagEditor(MainWindow mainW)
        {
            this.mainW = mainW;
            InitializeComponent();
            Calypso.UI.ThemeManager.Apply(this);
            this.BackColor = Calypso.UI.Theme.Background;
            this.ForeColor = Calypso.UI.Theme.Foreground;
            this.HandleCreated += (_, _) => Calypso.UI.ThemeManager.SetImmersiveDarkMode(this.Handle, Calypso.UI.Theme.IsDark);

            this.Deactivate += OnLossOfFocus;

            this.StartPosition = FormStartPosition.CenterScreen;
            this.MinimizeBox = false;
            this.MaximizeBox = false;
            this.ControlBox = true; 
            this.KeyPreview = true;
            this.KeyDown += TagEditor_KeyDown; 
            this.ShowIcon = false;

            // treeview config
            tagEditorTree.CheckBoxes = true;
            tagEditorTree.BeforeSelect += (s, e) =>
            {
                if (e.Node.Tag is string tag && tag == "unselectable")
                    e.Cancel = true;
            };
            tagEditorTree.BeforeCollapse += (s, e) => e.Cancel = true;
            tagEditorTree.NodeMouseClick += (s, e) =>
            {
                if (e.Button == MouseButtons.Left)
                {
                    e.Node.Checked = !e.Node.Checked;
                }
            };



            this.FormClosing += (s, e) =>
            {
                e.Cancel = true;
                CloseForm();
            };
        }

        public void Populate(List<Calypso.UI.GalleryItem> selection)
        {
            this.selection = selection;

            commonTags = selection
                .Select(t => t.ImageData.Tags)
                .Aggregate((prev, next) => prev.Intersect(next).ToList());

            GenerateTagTree(DB.appdata.ActiveLibrary.tagTree, DB.appdata.ActiveLibrary.tagDict);

        }
        public void GenerateTagTree(TagTree tagTreeRefactor, Dictionary<string, List<ImageData>> tagDict)
        {
            tagEditorTree.BeginUpdate();
            tagEditorTree.Nodes.Clear();

            foreach (TagNode node in tagTreeRefactor.tagNodes)
            {
                int num;
                if (tagDict.ContainsKey(node.Name))
                {
                    num = tagDict[node.Name].Count;
                }
                else
                {
                    continue;
                }

                AddToTree(node, num);
            }

            tagEditorTree.ExpandAll();
            tagEditorTree.EndUpdate();
        }

        private void AddToTree(TagNode node, int contentCount)
        {
            string displayText = $"#{node.Name}";
            bool isChecked = commonTags.Contains(node.Name);

            TreeNode newTreeNode = new TreeNode(displayText)
            {
                Tag = node,
                Checked = isChecked
            };

            if (node.Parent != string.Empty)
            {
                foreach (TreeNode parent in GetNodes(tagEditorTree))
                {
                    if (parent.Tag is TagNode parentTagNode && parentTagNode.Name == node.Parent)
                    {
                        parent.Nodes.Add(newTreeNode);
                        //Debug.WriteLine($"added {node.Name} to tree");
                    }
                }
            }
            else
            {
                tagEditorTree.Nodes.Add(newTreeNode);
                //Debug.WriteLine($"added {node.Name} to tree");
            }
        }
        private IEnumerable<TreeNode> GetNodes(TreeView treeView, bool onlyChecked = false)
        {
            foreach (TreeNode node in treeView.Nodes)
                foreach (var child in GetNodes(node, onlyChecked))
                    yield return child;
        }

        private IEnumerable<TreeNode> GetNodes(TreeNode parent, bool onlyChecked = false)
        {
            if (!onlyChecked || parent.Checked)
                yield return parent;
            foreach (TreeNode child in parent.Nodes)
                foreach (var descendant in GetNodes(child, onlyChecked))
                    yield return descendant;
        }

        private void OnLossOfFocus(object sender, EventArgs e)
        {
            List<string> tagsToAdd = new();
            foreach (TreeNode node in GetNodes(tagEditorTree, true))
            {
                if (node.Tag is TagNode tagNode)
                {
                    tagsToAdd.Add(tagNode.Name);
                }
            }

            List<string> toRemove = new();
            foreach (var item in selection)
            {
                foreach (string tag in item.ImageData.Tags)
                {
                    if (!tagsToAdd.Contains(tag))
                        toRemove.Add(tag);
                }
                foreach (string tag in toRemove)
                    DB.appdata.ActiveLibrary.UntagImage(tag, item.ImageData);
            }

            List<ImageData> images = selection.Select(it => it.ImageData).ToList();

            // tag images with each tag from checkedtags
            foreach (string tag in tagsToAdd)
            {
                DB.appdata.ActiveLibrary.TagImages(tag, images);
            }

            DB.GenTagDictAndSaveLibrary();
            ImageInfoPanel.Refresh(); // nonessential dependency, just QOL to refresh and show the new tags
            this.CloseForm();
        }
        private void TagEditor_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                CloseForm();
                e.Handled = true;
            }
        }
        private void CloseForm()
        {
            this.Hide();
        }
    }
}
