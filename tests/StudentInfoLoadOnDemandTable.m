classdef StudentInfoLoadOnDemandTable < LoadOnDemandMappedTable
% This class is used to test LoadOnDemandMappedTable

    methods
        function dt = StudentInfoLoadOnDemandTable(varargin)
            dt = dt@LoadOnDemandMappedTable(varargin{:});
        end
        
        % Return entry name for this table
        function [entryName entryNamePlural] = getEntryName(dt)
            entryName = 'studentInfo';
            entryNamePlural = 'studentInfo';
        end

        % if true, cacheable fields are written to the cache individually
        % if false, all cacheable fields are written to the cache collectively by entry
        function tf = getCacheFieldsIndividually(dt)
            tf = false;
        end
        
        % LoadOnDemandMappedTables are defined via a one-to-one relationship with
        % another data table. Here you define the entryName of that corresponding
        % DataTable. When you call the constructor on this table, you must pass
        % in a Database which must have this table in it.
        function entryName = getMapsEntryName(dt) 
            entryName = 'student';
        end

        % return a list of fields which are empty when creating this table
        % but can be loaded by a call to loadFields. These fields typically 
        % contain large amounts of data and are typically loaded only when needed
        % rather than cached as part of the table and thereby loaded in aggregate.
        function [fields map] = getFieldsLoadOnDemand(dt)
            map = ValueMap();
            map('infofield1') = StringField();
            map('infofield2') = ScalarField();
            fields = map.keys;
        end

        % from the fields above, return a list of fields that you would like
        % to be cached automatically, using independent mat files for each entry
        % For these fields, the cache will be loaded if present, otherwise
        % loadValuesForEntry will be called. 
        function fields = getFieldsCacheable(dt)
            % all fields are cacheable
            fields = dt.getFieldsLoadOnDemand();
        end

        % these are fields not in load on demand, they will be cached with the 
        % table. the keyFields of the mapped table will be automatically included
        % as part of this set, you need not return them
        function [fields fieldDescriptorMap] = getFieldsNotLoadOnDemand(dt)
            fields = {};
            fieldDescriptorMap = ValueMap();
        end
            
        % here's where you specify where the values for the loaded fields come
        % from. When passed a list of fields, guaranteed to be valid, you generate
        % or load the values of those fields for a specific entry in the mapped table
        % and return a struct containing those field values.
        function valueStruct = loadValuesForEntry(dt, entry, fields)
            valueStruct.infofield1 = 'hello!';
            valueStruct.infofield2 = randn();
        end
    end
    
end
