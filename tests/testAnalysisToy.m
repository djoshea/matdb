if ~exist('db', 'var')
    testDatabase;
end

da = CountStudentsByTeacher();
da.setDatabase(db);
da.run('parallel', true);

