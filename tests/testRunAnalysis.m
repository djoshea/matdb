
setDataContext('Olaf');

if ~exist('db', 'var')
    db = Database;
end

%da = UnitCountBySaveTag();
da = UnitCountHistogramBySubject();

r = da.run(db);

