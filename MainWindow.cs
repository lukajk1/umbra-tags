
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
            this.Text = $"Calypso {GlobalValues.Version} - ...";

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
            ShortcutHandler.Init(this);

            DB.Init(this);
            new TagTreePanel(this);
            LibraryUIManager.Init(this);
            initialized = true;
        }

        public void UpdateTitle(string libraryName)
        {
            this.Text = $"Calypso {GlobalValues.Version} - {libraryName}";
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
            if (ShortcutHandler.HandleGlobal(keyData)) return true;
            if (FocusedPane == Pane.Searchbar) return base.ProcessCmdKey(ref msg, keyData);
            if (ShortcutHandler.HandleContextual(keyData)) return true;
            return base.ProcessCmdKey(ref msg, keyData);
        }
        private void MainWindow_MouseWheel(object sender, MouseEventArgs e)
        {
            Gallery.ZoomFromWheel(e);
        }

        private static readonly Size DefaultWindowedSize = new Size(1100, 720);

        public void LoadSession(Session session)
        {
            // Use a sensible windowed size so Windows has a valid restore bound
            // if the session was always maximized or is first-run.
            var screen = Screen.FromControl(this).WorkingArea;
            bool sizeValid = session.WindowWidth >= MinimumSize.Width
                          && session.WindowHeight >= MinimumSize.Height
                          && session.WindowWidth < screen.Width
                          && session.WindowHeight < screen.Height;

            var size = sizeValid ? new Size(session.WindowWidth, session.WindowHeight) : DefaultWindowedSize;
            this.Size = size;
            this.checkBoxRandomize.Checked = session.RandomiseChecked;
            this.WindowState = session.WindowState;
            DB.appdata.ActiveLibrary = session.LastActiveLibrary;
            Gallery.Zoom = session.ZoomModifier;
            if (session.LastActiveLibrary != null)
                UpdateTitle(session.LastActiveLibrary.Name);
        }

        private void MainWindow_FormClosed(object sender, FormClosedEventArgs e)
        {
            DB.OnClose(CaptureCurrentSession());
        }

        public void ApplyPreferences(Preferences prefs)
        {
            hideFilenamesToolStripMenuItem.Checked = !prefs.ShowFilenames;
            Gallery.RefreshTileLabels();
        }

        public Session CaptureCurrentSession()
        {
            return new Session(
                windowHeight: this.Height,
                windowWidth: this.Width,
                randomiseChecked: this.checkBoxRandomize.Checked,
                windowState: this.WindowState,
                lastActiveLibrary: DB.appdata.ActiveLibrary,
                zoomModifier: Gallery.Zoom,
                lastSearch: searchBox.Text
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
                zoomModifier: Gallery.Zoom,
                lastSearch: searchBox.Text
            );
        }

        private void exitToolStripMenuItem_Click(object sender, EventArgs e)
        {
            Close();
        }
        private void aboutToolStripMenuItem_Click(object sender, EventArgs e)
        {
            string message = $"Calypso Image Manager {GlobalValues.Version}\nSupported file types: .jpg, .jpeg, .jfif, .png, .bmp, .gif, .webp\nCreated by lukajk\n\nOpen Source Notices:\nImazen.WebP (MIT) — Copyright 2012–2026 Imazen LLC\nhttps://github.com/imazen/libwebp-net\nNewtonsoft.Json (MIT) — Copyright 2007 James Newton-King\nhttps://github.com/JamesNK/Newtonsoft.Json";
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

        private void hideFilenamesToolStripMenuItem_Click(object sender, EventArgs e)
        {
            DB.Prefs.ShowFilenames = !DB.Prefs.ShowFilenames;
            hideFilenamesToolStripMenuItem.Checked = !DB.Prefs.ShowFilenames;
            Gallery.RefreshTileLabels();
        }
    }
}
