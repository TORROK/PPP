MMP.Packet p;
mapping misc = ([]);
// change -> applied
mapping(Serialization.Atom:int) state_changes;
object snapshot;

void create(MMP.Packet p, object snapshot) {
    this_program::snapshot = snapshot;
    this_program::p = p;
    state_changes = mkmapping(p->packet->state_changes, allocate(sizeof(p->packet->state_changes)));
}
