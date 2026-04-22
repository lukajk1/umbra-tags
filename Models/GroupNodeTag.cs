namespace Calypso
{
    /// <summary>
    /// Tag object placed on group header TreeNodes in the tag tree.
    /// Distinct from TagNode (which is for real user tags).
    /// </summary>
    internal class GroupNodeTag
    {
        public TagGroup Group { get; }
        public GroupNodeTag(TagGroup group) { Group = group; }
    }
}
