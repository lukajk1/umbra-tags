using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Calypso
{
    public class PooledTile
    {
        public Panel Container { get; }
        public PictureBox PictureBox { get; }
        public Label Label { get; }

        public PooledTile()
        {
            Label = new Label
            {
                TextAlign = ContentAlignment.MiddleCenter,
                Dock = DockStyle.Bottom,
                AutoSize = false,
                Height = 20
            };

            PictureBox = new PictureBox
            {
                SizeMode = PictureBoxSizeMode.Zoom,
                Cursor = Cursors.Hand,
                Dock = DockStyle.Top,
                Margin = new Padding(5),
                BackColor = Color.Transparent
            };

            Container = new Panel
            {
                Margin = new Padding(5)
            };

            Container.Controls.Add(PictureBox);
            Container.Controls.Add(Label);
        }

        public void Reset()
        {
            PictureBox.Image?.Dispose();
            PictureBox.Image = null;
            PictureBox.Tag = null;
            Label.Text = string.Empty;

            // Detach handlers
            PictureBox.DoubleClick -= Gallery.PictureBox_DoubleClick;
            PictureBox.MouseClick -= Gallery.PictureBox_MouseClick;
            // Detach any other handlers you attach (e.g., drag handlers)
        }
    }
}

