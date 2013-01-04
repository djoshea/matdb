%clear
%clear classes

if ~exist('db', 'var')
    testDatabase
end

[jTbl rel] = DataRelationship.buildEmptyJunctionTable(...
    db.teacher, db.student);

db.addTable(jTbl);
db.addRelationship(rel);
