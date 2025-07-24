
using Calypso.UI;
using System.Diagnostics;
using System.Windows.Forms;

namespace Calypso
{
    public enum Pane
    {
        TagSideTab,
        Gallery,
        Searchbar
    }
    public partial class MainWindow : Form
    {
        public static MainWindow i;
        public static Pane FocusedPane;
        public static bool initialized;
        public MainWindow()
        {
            CreateSingleton();

            InitializeComponent();
            this.KeyPreview = true;
            this.FormClosed += MainWindow_FormClosed;
            this.MouseWheel += MainWindow_MouseWheel;
            this.Text = $"Calypso {GlobalValues.Version}";


            Activate();
            Focus();

            comboBoxResultsNum.SelectedIndex = 0;

            // start initialization
            Gallery.Init(this); // in order to load the last session properly gallery references must be initialized first
            StatusBar.Init(this);
            ImageInfoPanel.Init(this);
            Searchbar.Init(this);
            TagEditManager.Init(this);
            LayoutManager.Init(this);

            DB.Init(this);
            new TagTreePanel(this);
            LibraryUIManager.Init(this);
            initialized = true;
        }
        private void CreateSingleton()
        {

            if (i == null)
            {
                i = this;
            }
            else
            {
                Util.ShowErrorDialog("There are multiple main window instances. That's probably a problem.");
            }
        }
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            Control focused = Form.ActiveForm?.ActiveControl;

            bool searchBoxFocused = (FocusedPane != Pane.Searchbar);

            #region single key shortcuts
            if (keyData == Keys.R)
            {
                if (!searchBoxFocused)
                {
                    LayoutManager.TogglePanel(tagTreeGallerySplitContainer, 1);
                    return true; // suppress further handling
                }

            }
            else if (keyData == Keys.N)
            {
                if (!searchBoxFocused)
                {
                    LayoutManager.TogglePanel(masterSplitContainer, 2);
                    return true;
                }
            }
            else if (keyData == Keys.I)
            {
                if (!searchBoxFocused)
                {
                    LayoutManager.TogglePanel(imageInfoHorizontalSplitContainer, 2);
                    return true;
                }
            }
            else if (keyData == Keys.T)
            {
                if (!searchBoxFocused)
                {
                    Gallery.OpenTagEditorByCommand();
                    return true;
                }
            }

            else if (keyData == Keys.Delete)
            {
                if (FocusedPane == Pane.Gallery) Gallery.DeleteSelected();
            }
            #endregion

            #region control shortcuts
            if (keyData == (Keys.Control | Keys.Q))
            {
                Close();
                return true;
            }
            else if (keyData == (Keys.Control | Keys.L))
            {
                if (focused == searchBox)
                {
                    // focus the tagtree I guess. just has to move focus off the searchbar
                    tagTree.Focus();
                }
                else
                    searchBox.Focus();


                return true;
            }
            else if (keyData == (Keys.Control | Keys.Enter))
            {
                DB.OpenCurrentLibrarySourceFolder();
                return true;
            }
            else if (keyData == (Keys.Control | Keys.A))
            {
                if (!(focused == searchBox))
                {
                    Gallery.SelectAll();
                }
                return true;
            }

            else if (keyData == (Keys.Control | Keys.D1))
            {
                LayoutManager.SetLayout(LayoutManager.DefaultLayout);
                return true;
            }
            else if (keyData == (Keys.Control | Keys.D2))
            {
                //MessageBox.Show("received");
                LayoutManager.SetLayout(LayoutManager.LargeWindow);
                return true;
            }

            else if (keyData == (Keys.Control | Keys.S))
            {
                MessageBox.Show($"{masterSplitContainer.SplitterDistance}");
                return true;
            }

            else if (keyData == (Keys.Control | Keys.N))
            {
                DB.AddNewLibrary();
                return true;
            }

            else if (keyData == (Keys.Control | Keys.K))
            {
                DB.appdata.ActiveLibrary.FlushTagDictDuplicates();
                return true;
            }

            else if (keyData == (Keys.Control | Keys.T))
            {
                if (Util.TextPrompt("Set tag name: ", out string newTag))
                {
                    DB.appdata.ActiveLibrary.AddTagToTree(new TagNode(newTag));
                }
                return true;
            }
            else if (keyData == (Keys.Control | Keys.I))
            {
                Commands.AddFilesViaDialog();
                return true;
            }
            // arrow keys
            else if (keyData == Keys.Left || keyData == Keys.Right || keyData == Keys.Up || keyData == Keys.Down)
            {
                Gallery.ArrowSelect(keyData);
            }


            else if (keyData == Keys.Enter)
            {
                if (FocusedPane == Pane.Gallery)
                {
                    Gallery.OpenSelected();
                }
                return true;
            }
            #endregion

            // shift
            else if ((keyData & (Keys.Control | Keys.Shift)) == (Keys.Control | Keys.Shift))
            {
                for (int i = 1; i <= 9; i++)
                {
                    if ((keyData & Keys.KeyCode) == (Keys)((int)Keys.D0 + i))
                    {
                        DB.LoadLibrary(i);
                        break;
                    }
                }
            }

            return base.ProcessCmdKey(ref msg, keyData);
        }
        private void MainWindow_MouseWheel(object sender, MouseEventArgs e)
        {
            Gallery.ZoomFromWheel(e);
        }

        public void LoadSession(Session session)
        {
            this.Height = session.WindowHeight;
            this.Width = session.WindowWidth;
            this.checkBoxRandomize.Checked = session.RandomiseChecked;
            this.WindowState = session.WindowState;
            DB.appdata.ActiveLibrary = session.LastActiveLibrary;
            Gallery.Zoom = session.ZoomFactor;
        }

        private void MainWindow_FormClosed(object sender, FormClosedEventArgs e)
        {
            DB.OnClose(CaptureCurrentSession());
        }

        public Session CaptureCurrentSession()
        {
            return new Session(
                windowHeight: this.Height,
                windowWidth: this.Width,
                randomiseChecked: this.checkBoxRandomize.Checked,
                windowState: this.WindowState,
                lastActiveLibrary: DB.appdata.ActiveLibrary,
                zoomFactor: Gallery.Zoom
            );
        }

        // overload to insert custom library into the session object
        public Session CaptureCurrentSession(Library lib)
        {
            return new Session(
                windowHeight: this.Height,
                windowWidth: this.Width,
                randomiseChecked: this.checkBoxRandomize.Checked,
                windowState: this.WindowState,
                lastActiveLibrary: lib,
                zoomFactor: Gallery.Zoom
            );
        }

        private void exitToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }
        private void aboutToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string message = $"Calypso Image Manager {GlobalValues.Version}\nSupported file types: .jpg, .jpeg, .png, .bmp, .gif\nCreated by lukajk";
            string title = "About Calypso";
            MessageBox.Show(message, title, MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void textBox1_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter)
            {
                // suppress potential sfx
                e.SuppressKeyPress = true;
                e.Handled = true;


                if (File.Exists(searchBox.Text))
                {
                    // handle file explorer capabilities at some point? 
                }
                else
                {
                    Searchbar.Search(searchBox.Text);
                }

            }
        }

        private void toolStripMenuItem5_Click(object sender, EventArgs e)
        {

            LayoutManager.SetLayout(LayoutManager.DefaultLayout);
        }

        private void toolStripMenuItem3_Click(object sender, EventArgs e)
        {
            LayoutManager.SetLayout(LayoutManager.LargeWindow);
        }

        private void toolStripMenuItem9_Click(object sender, EventArgs e)
        {
            Commands.AddFilesViaDialog();
        }

        private void toolStripMenuItem1_Click_1(object sender, EventArgs e)
        {
            DB.OpenCurrentLibrarySourceFolder();
        }

        private void checkBoxRandomize_CheckedChanged(object sender, EventArgs e)
        {
            Searchbar.RepeatLastSearch();
        }

        private void newGalleryToolStripMenuItem_Click(object sender, EventArgs e)
        {
            DB.AddNewLibrary();
        }

        private void removeTagToolStripMenuItem_Click(object sender, EventArgs e)
        {
            TagTreePanel.i.RenameTag(sender);
        }

        private void deleteToolStripMenuItem_Click(object sender, EventArgs e)
        {

            TagTreePanel.i.DeleteTag(sender);
        }

        private void addChildTagToolStripMenuItem_Click(object sender, EventArgs e)
        {
            TagTreePanel.i.AddChildTag(sender);
        }

        private void addNewTagToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (Util.TextPrompt("Set tag name: ", out string newTag))
            {
                DB.appdata.ActiveLibrary.AddTagToTree(new TagNode(newTag));
            }
        }

        private void addTagButton_Click(object sender, EventArgs e)
        {
            if (Util.TextPrompt("Set tag name: ", out string newTag))
            {
                DB.appdata.ActiveLibrary.AddTagToTree(new TagNode(newTag));
            }
        }
    }
}
