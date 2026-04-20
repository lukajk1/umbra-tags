using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Calypso
{
    public partial class Preferences : Form
    {
        public Preferences()
        {
            InitializeComponent();
            Calypso.UI.ThemeManager.Apply(this);
            this.BackColor = Calypso.UI.Theme.Background;
            this.ForeColor = Calypso.UI.Theme.Foreground;
            this.HandleCreated += (_, _) => Calypso.UI.ThemeManager.SetImmersiveDarkMode(this.Handle, Calypso.UI.Theme.IsDark);
            checkboxShowFilenames.Checked = PreferencesManager.Prefs.ShowFilenames;
            checkboxDeleteSourceOnDragIn.Checked = PreferencesManager.Prefs.DeleteSourceOnDragIn;
        }

        private void buttonApply_Click(object sender, EventArgs e)
        {
            PreferencesManager.Prefs.ShowFilenames = checkboxShowFilenames.Checked;
            MainWindow.i.hideFilenamesToolStripMenuItem.Checked = !PreferencesManager.Prefs.ShowFilenames;
            Gallery.RefreshTileLabels();

            PreferencesManager.Prefs.DeleteSourceOnDragIn = checkboxDeleteSourceOnDragIn.Checked;
            PreferencesManager.Save();
        }
    }
}
