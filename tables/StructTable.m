classdef StructTable < DataTable

    properties(Hidden)
        table = struct([]); % struct array with data
        localDfdMap % temporary cache to hold onto our dfd map before requested from DataTable
    end

    methods
        function db = StructTable(varargin)
            db = db@DataTable();

            if ~isempty(varargin)
                db = db.initialize(varargin{:});
            end
        end

        function db = initialize(db, varargin)
            p = inputParser;
            p.addOptional('table', struct([]), @(t) isa(t, 'DataTable') || isempty(t) || (isstruct(t) && isvector(t)));
            p.addParamValue('entryName', '', @(t) ischar(t) && ~isempty(t));
            p.addParamValue('entryNamePlural', '', @(t) ischar(t) && ~isempty(t));
            p.addParamValue('fieldDescriptorMap', '', @(m) isempty(m) || isa(m, 'ValueMap'));
            p.parse(varargin{:});

            table = p.Results.table;
            entryName = p.Results.entryName;
            entryNamePlural = p.Results.entryNamePlural;
            dfdMap = p.Results.fieldDescriptorMap;

            if isempty(entryName) && isempty(db.entryName);
                if isa(table, 'DataTable')
                    entryName = table.entryName;
                else
                    error('Please provide argument ''entryName''');
                end
            end
            if isempty(entryNamePlural) && isempty(db.entryNamePlural)
                if isa(table, 'DataTable')
                    entryNamePlural = table.entryNamePlural;
                else
                    % assume simple pluralization
                    entryNamePlural = [entryName 's'];
                end
            end

            if ~isempty(dfdMap)
                db.localDfdMap = dfdMap;
            end

            if isempty(db.table)
                if isempty(table) 
                    table = struct([]);
                end

                if isa(table, 'DataTable')
                    % if a data table was passed in, use the values and 
                    % field descriptors already there
                    db.table = table.getFullEntriesAsStruct();
                    db.keyFields = table.keyFields();
                    db.localDfdMap = table.fieldDescriptorMap;
                else
                    db.table = makecol(structReplaceEmptyValues(table));
                end
            end

            if isempty(db.localDfdMap)
                db.localDfdMap = db.inferFieldDescriptors(db.table);
                db = db.convertTableValues(db.localDfdMap, fieldnames(db.table)); 
            end

            if isempty(db.entryName)
                db.entryName = entryName;
            end
            if isempty(db.entryNamePlural)
                db.entryNamePlural = entryNamePlural;
            end
            
            db = initialize@DataTable(db);
        end
    end

    methods(Access=protected)
        % returns a cell array of names of fields in the data table
        function [fields fieldDescriptorMap] = getFields(db)
            fields = fieldnames(db.table);
            fieldDescriptorMap = db.localDfdMap;
        end

        % returns the number of entries currently selected by the current filter 
        function nEntries = getEntryCount(db)
            nEntries = length(db.table);
        end

        % returns the struct array of full data table values with table(iE).fld = value
        function table = getTableData(db, fields)
            table = db.table;
        end
        
        function map = getFieldToValuesMap(db, fields, idx)
            map = ValueMap('KeyType', 'char', 'ValueType', 'any');
            

            for iField = 1:length(fields)
                field = fields{iField};
                cellValues = {db.table.(field)};
                assert(numel(cellValues) == numel(db.table), 'Size mismatch');

                % filter by idx if provided
                if exist('idx', 'var')
                    cellValues = cellValues(idx);
                end

                dfd = db.fieldDescriptorMap(field);
                if dfd.matrix
                    values = cell2mat(cellValues);
                else
                    values = cellValues;
                end
                map(field) = makecol(values);
            end
        end

        function db = selectSortEntries(db, indsInSortOrder)
            db.table = db.table(indsInSortOrder);
        end

        function db = subclassSetFieldDescriptor(db, field, dfd)
            db.warnIfNoArgOut(nargout);
            db.assertIsField(field);
            assert(isa(dfd, 'DataFieldDescriptor'));

            db.localDfdMap(field) = dfd;
            db = db.convertTableValues(db.localDfdMap, field);
        end

        function tf = subclassSupportsWrite(db)
            tf = true;
        end

        function db = subclassAddField(db, field, values, dfd, position)
            db.warnIfNoArgOut(nargout);
            db.localDfdMap(field) = dfd;
            db.table = assignIntoStructArray(db.table, field, values);

            % set field order so that this field ends up at position
            fields = fieldnames(db.table);
            [~, idx] = ismember(field, fields);
            if idx ~= position
                fields = [fields(1:idx-1); fields(idx+1:end)];
                fields = [fields(1:position-1); field; fields(position:end)];
                db.table = orderfields(db.table, fields);
            end
        end

        function db = subclassRemoveField(db, field)
            % remove field from the list of fields
            db.warnIfNoArgOut(nargout);

            db.localDfdMap = db.localDfdMap.remove(field);
            db.table = rmfield(db.table, field);
        end
        
        % S will be a struct with the same fields as this table and already
        % converted values
        function db = subclassAddEntry(db, S)
            db.warnIfNoArgOut(nargout);

            S = orderfields(S, db.table);
            S = makecol(S);
            
            db.table = [db.table; S]; 
        end
        
        % S will be a struct or struct array with the same fields as this table and already
        % converted values
        function db = subclassReplaceEntry(db, S, entryMask)
            db.warnIfNoArgOut(nargout);

            S = orderfields(S, db.table);
            S = makecol(S);
            
            db.table(entryMask) = S;
        end

        function db = subclassSetFieldValue(db, idx, field, value)
            db.table(idx).(field) = value;
        end
    end

    methods
        function entries = getEntriesAsStruct(db, idx, fields)
            entries = db.table(idx);
        end
    end

    methods 
        function map = inferFieldDescriptors(db, table)
            debug('Inferring field descriptors from values\n');

            map = ValueMap('KeyType', 'char', 'ValueType', 'any');
            fields = fieldnames(table);
            for iField = 1:length(fields)
                field = fields{iField};
                % extract values as cell
                cellValues = {table.(field)};
                assert(numel(cellValues) == numel(table), 'Size mismatch');

                dfd = DataFieldDescriptor.inferFromValues(cellValues);

                map(field) = dfd;
                debug('%30s : %s\n', field, dfd.describe());
            end
        end

        function db = convertTableValues(db, dfdMap, fields)
            db.warnIfNoArgOut(nargout);
            %debug('Converting table values via DFD\n');
            if ischar(fields)
                fields = {fields};
            end
            for iField = 1:length(fields)
                field = fields{iField};
                dfd = dfdMap(field);
                
                % extract values as cell
                cellValues = {db.table.(field)};
                if ~isempty(cellValues)
                    % don't want to accidentally add an entry when its
                    % empty
                    values = dfd.convertValues(cellValues);
                    db.table = assignIntoStructArray(db.table, field, values);
                end
            end
        end  
    end
end
