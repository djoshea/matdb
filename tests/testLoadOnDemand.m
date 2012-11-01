if ~exist('db', 'var')
    db = Database;
end

src = OptoMonkeyDataSource();
db.loadSource(src);

dt = RDelayedReachTable('database', db, 'entryName', 'rDelayedReach');

