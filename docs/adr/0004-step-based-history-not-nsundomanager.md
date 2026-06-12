# Undo history is a Step-based stack, not NSUndoManager

Undo/redo is a custom history stack of inverted Steps: undoing applies them in
a Transaction tagged `Origin.history`, and older entries are carried forward
through later edits via Mapping. The obvious iOS path — registering closures
with NSUndoManager — was rejected because it cannot rebase entries through
subsequent edits (no Mapping), offers only coarse grouping, and would dead-end
the collaboration story that Origin/Mapping exist to keep open. NSUndoManager
remains only as a bridge so system gestures (shake, Cmd+Z, the keyboard undo
bar) route into our stack. Consecutive typing coalesces into one entry, broken
by a ~500ms pause or a selection jump; the stack is bounded (~100 entries).
