%clear
%clear classes

str = RandStream('mt19937ar','Seed',1);
RandStream.setGlobalStream(str);

%% Build tables
if ~exist('createTables', 'var')
    createTables = true;
end

if createTables || ~exist('t', 'var')  
% random data generation functions
capFirst = @(str) [upper(str(1)) str(2:end)];
randNameFn = @() capFirst(char(randi(double(['a', 'z']), 1, randi([3 7]))));
bdayLims = [datenum(datevec('1/1/1950')) datenum(datevec('12/31/2000'))];
randBdayFn = @() datestr(randi(bdayLims));
randGenderFn = @() subsref(randsample({'male', 'female'}, 1), substruct('{}', {1}));
randClassNameFn = @() [char(randi(double(['A', 'Z']), 1, 3)) ' ' num2str(randi([100 499]))];
randGradeOptionFn = @() subsref(randsample({'Grd', 'P/F'}, 1), substruct('{}', {1}));
randPermitIdFn = @() [char(randi(double(['A', 'Z']), 1, 3)) num2str(randi([1000 9999]))];
randPermitTypeFn = @() subsref(randsample({'Academic', 'Yearly', 'Monthly'}, 1), substruct('{}', {1}));
permitIssuedLims = [datenum(datevec('1/1/2010')) datenum(now)];
randPermitIssuedFn = @() datestr(permitIssuedLims(1) + diff(permitIssuedLims)*rand());
expiryLims = [datenum(datevec('1/1/2012')) datenum(datevec('12/31/2016'))];
randPermitExpiryFn = @() datestr(randi(expiryLims));

nStudents = 150;
nTeachers = 25;
nPermits = (nStudents + nTeachers) / 2;
nClasses = nTeachers * 2;
nEnrollment = nClasses * 5;

% create parking permits 
debug('Building permits table\n');
ptable = [];
for i = 1:nPermits
    ptable(i).id = randPermitIdFn();
    ptable(i).type = randPermitTypeFn();
    ptable(i).expiry = randPermitExpiryFn();
    ptable(i).issued = randPermitIssuedFn();
end
p = StructTable(ptable, 'entryName', 'permit');
p = p.setKeyFields({'id'}); 
p = p.sort('id');

% create students table 
debug('Building students table\n');
ptable = [];
for i = 1:nStudents
    ptable(i).id = i;
    ptable(i).first = randNameFn();
    ptable(i).last = randNameFn();
    ptable(i).bday = randBdayFn(); 
    ptable(i).gender = randGenderFn();
    
    iPermit = randi(2*nPermits);
    if iPermit < p.nEntries
        ptable(i).permitId = p.entry(iPermit).id;
    else
        ptable(i).permitId = '';
    end
end
s = StructTable(ptable, 'entryName', 'student');
s = s.setKeyFields({'last', 'first'}); 
s = s.sort('last', 'first');

% create teachers
debug('Building teachers table\n');
ptable = [];
for i = 1:nTeachers
    ptable(i).id = i;
    ptable(i).first = randNameFn();
    ptable(i).last = randNameFn();
    ptable(i).bday = randBdayFn(); 
    ptable(i).gender = randGenderFn();

    iPermit = randi(2*nPermits);
    if iPermit < p.nEntries
        ptable(i).permitId = p.entry(iPermit).id;
    else
        ptable(i).permitId = '';
    end
end
t = StructTable(ptable, 'entryName', 'teacher');
t = t.setKeyFields({'last', 'first'}); 
t = t.sort('last', 'first');

% create classes
debug('Building classes table\n');
ptable = [];
for i = 1:nClasses
    ptable(i).id = i;
    ptable(i).name = randClassNameFn();

    % choose a teacher and use first/last as keyfields
    iTeacher = randi(nTeachers);
    ptable(i).teacherFirst = t{iTeacher}.first;
    ptable(i).teacherLast = t{iTeacher}.last;
end
c = StructTable(ptable, 'entryName', 'class', 'entryNamePlural', 'classes');
c = c.setKeyFields('id');
c = c.sort('name');

% create student enrollment table
debug('Building enrollment table\n');
ptable = [];
for i = 1:nEnrollment
    ptable(i).id = i;

    % pick a student
    iStudent = randi(nStudents);
    ptable(i).studentFirst = s{iStudent}.first;
    ptable(i).studentLast = s{iStudent}.last;

    % pick a class
    iClass = randi(nClasses);
    ptable(i).classId = c{iClass}.id;
end  
e = StructTable(ptable, 'entryName', 'enrollment');
e = e.setKeyFields('id');
e = e.sort('classId', 'studentLast', 'studentFirst');

createTables = false;
end

%% Build database

db = Database();
t = db.addTable(t);
s = db.addTable(s);
c = db.addTable(c);
e = db.addTable(e);
p = db.addTable(p);

db.addRelationshipOneToMany('teacher', 'class');
db.addRelationshipOneToOne('teacher', 'permit');
db.addRelationshipOneToOne('student', 'permit');
db.addRelationshipManyToMany('students', 'classes', 'enrollments');

rel = db.findRelationship('students', 'permit');
