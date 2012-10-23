csvPath = '/Users/djoshea/code/npl/labData/csv';

if ~exist('subj', 'var')
    subjList(1).subject = 'Olaf';
    subjList(2).subject = 'Quincy';
    subj = StructTable(subjList, 'entryName', 'subject');
    subj = subj.setKeyFields({'subject'});
    subj = subj.sort('subject');
end

if ~exist('st', 'var') 
    fname = fullfile(csvPath, 'Olaf Run Log - SaveTags.csv');
    st = CSVTable(fname, 'entryName', 'saveTagInfo', 'entryNamePlural', 'saveTagInfo');
    st = st.addField('subject', 'Olaf');
    st = st.setKeyFields({'subject', 'date', 'saveTag', 'cellNumber'});
    st = st.sort('subject', '-date', 'saveTag', 'cellNumber');
end

if ~exist('loc', 'var') 
    fname = fullfile(csvPath, 'Olaf Run Log - RecordingLocations.csv');
    loc = CSVTable(fname, 'entryName', 'location');
    loc = loc.addField('subject', 'Olaf');
    loc = loc.setKeyFields({'subject', 'date'});
    loc = loc.sort('subject', '-date', 'channel');
end

if ~exist('su', 'var')
    fname = fullfile(csvPath, 'Olaf Run Log - SingleUnit.csv');
    su = CSVTable(fname, 'entryName', 'unit');
    su = su.addField('subject', 'Olaf');
    su = su.setKeyFields({'subject', 'date', 'saveTag', 'cellNumber'});
    su = su.setFieldDescriptor('date', DateField('yyyymmdd'));
    su = su.sort('subject', '-date', 'saveTag', 'cellNumber');
end

db = Database;
subj = db.addTable(subj);
st = db.addTable(st);
loc = db.addTable(loc);
su = db.addTable(su);

db.addRelationshipOneToMany('subject', 'saveTagInfo');
db.addRelationshipOneToMany('subject', 'locations');
db.addRelationshipOneToMany('subject', 'units');

db.addRelationshipManyToOne('saveTagInfo', 'location'); 
db.addRelationshipOneToMany('saveTagInfo', 'units');

