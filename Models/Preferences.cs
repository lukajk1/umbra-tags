namespace Calypso
{
    public enum RightClickBehavior
    {
        ContextMenu,
        TagEditor
    }

    public class Preferences
    {
        public bool ShowFilenames { get; set; } = true;
        public RightClickBehavior RightClickBehavior { get; set; } = RightClickBehavior.ContextMenu;
        public bool DeleteSourceOnDragIn { get; set; } = false;
    }
}
