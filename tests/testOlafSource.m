
db = Database;

src = OlafDataSource();
db.loadSource(src);
assert(db.hasSourceLoaded(src));

view = OlafDatabaseView();
db.applyView(view);
assert(db.hasViewApplied(view));

