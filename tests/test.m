%clear
%clear classes

data(1).a = 1;
data(2).a = 2;
data(3).a = 1;
data(4).a = 1;

data = assignIntoStructArray(data, 'b', {'1','2','3', '4'});

data = assignIntoStructArray(data, 'date', {'5-Aug-2012', '6-Aug-2012', '5-Aug-2012', '12-Jul-2011'});

t = StructTable(data, 'entryName', 'testEntry', 'entryNamePlural', 'testEntries');
t = t.applyFields();

t = t.filter('equals', 'a', 1);
t = t.sort('date');
t = t.applyEntryMask();
t = t.applyEntryData();

dates = t.getValues('date');
debug('dates : %s\n', strjoin(dates, ', '));

b = t.getValues('b');
debug('b : %s\n', vec2str(b)); 

b = t.getUnique('b');
debug('unique b : %s\n', vec2str(b)); 

dates = t.getUnique('date');
debug('unique dates : %s\n', cellstr2str(dates)); 
