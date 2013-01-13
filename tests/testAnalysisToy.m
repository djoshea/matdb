if ~exist('db', 'var')
    testDatabase;
end

da = CountStudentsByTeacher(db);
da.run();

