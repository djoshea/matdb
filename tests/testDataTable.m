%clear
%clear classes

capFirst = @(str) [upper(str(1)) str(2:end)];
randStrFn = @() capFirst(char(randi(double(['a', 'z']), 1, randi([3 7]))));
bdayLims = [datenum(datevec('1/1/1950')) datenum(datevec('12/31/2000'))];
randBdayFn = @() datestr(randi(bdayLims));
randGenderFn = @() subsref(randsample({'male', 'female'}, 1), substruct('{}', {1}));

% create people table 
N = 100;
ptable = [];
for i = 1:N
    ptable(i).id = i;
    ptable(i).first = randStrFn();
    ptable(i).last = randStrFn();
    ptable(i).bday = randBdayFn(); 
    ptable(i).gender = randGenderFn();
end

t = StructTable(ptable, 'entryName', 'student', 'entryNamePlural', 'students');
%t = t.applyFields();

t = t.filterByField('gender', 'equals', 'female');
t = t.sort('last', 'first');
%t = t.applyEntryMask();
%t = t.applyEntryData();

