if ~exist('db', 'var')
    testDatabase;
end

da = CountStudentsByTeacher();
da.run(db);

