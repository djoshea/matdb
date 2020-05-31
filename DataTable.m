classdef DataTable < DynamicClass & Cacheable
% Represents an abstract row/column database table
% and methods for filtering, sorting, grouping the rows of that table

    properties(SetAccess=protected)
        entryName
        entryNamePlural

        autoApply = true; % automatically apply changes to database, rather than requiring explicit calls to .apply()

        pendingApplyEntryData = true; % must apply changes that load data into the tableCache and allow access to .data
        pendingApplyEntryMask = true; % must apply changes to table that affect which rows are included, for mask and count info
        pendingApplyFields = true; % must apply changes to table that affect which columns are included

        sortByList % list of field names to sort by, prefixed by '-' for reverse
        sortByListPending

        groupFields = {}; % how this datatable's rows are currently grouped 
        groupCommon % when using .groups, this is the particular values of group by fields assigned to this instance

        filtersApplied % array of DataFilter classes already applied to data
        filtersPending % array of DataFilter classes TO BE applied to data
                       % these get applied when applyEntryMask is called

        keyFields = {}; % cellstr of fields which uniquely represent each entry

        createdTimestamp;  
        modifiedTimestamp;
    end
    
    properties(Transient)
        database % handle of the database I belong to, for relationship traversal
    end

    properties(Access=private) % was Hidden
        nEntriesCache;
        fieldsCache % cell array of field names
        fieldInfoCache % ValueMap fieldName -> field info struct 

        fieldDescriptorMapCache % ValueMap fieldName -> DataFieldDescriptor instance
    end

    properties(Dependent, SetAccess=protected)
        nEntries % wraps nEntriesCache 

        fields % list of fields in the data table
        nFields % number of fields
        
        fieldsDisplayable % fields filtered by fieldDescriptor.isDisplayable

        fieldDescriptorMap % ValueMap fieldName -> DataFieldDescriptor instance 

        lastUpdated

        groups
        nGroups

        % lists of related entry names via the database 
        relationshipReferences

        % write access
        supportsWrite
    end

    % METHODS which subclasses MUST implement
    methods(Abstract,Access=protected)
        
        % fields: a cell array of names of fields in the data table
        % fieldDescriptorMap : ValueMap ( fieldName -> DataFieldDescriptor )
        [fields, fieldDescriptorMap] = getFields(db)

        % returns the number of entries currently selected by the current filter 
        nEntries = getEntryCount(db)

        % returns a ValueMap : fieldName --> array of values 
        %   for entries masked by idx
        % values may be either a numeric or cell vector
        % idx may or may not be provided, if not provided all entries should
        %   be included
        % map may include extra fields but only the fields
        %   included in cellstr fields must be returned
        map = getFieldToValuesMap(db, fields, idx)

        % keep only the entries whose indices are found in indsInSortOrder
        % in the order they appear. e.g. indsInSortOrder = [3 2] means order
        % entries: 3, then 2. drop entry 1.
        db = selectSortEntries(db, indsInSortOrder)

        % change the field descriptor for field to dfd, and apply any relevant
        % conversions to the data stored internally. If this new data field
        % descriptor is inadequate for the data in this field, throw an error.
        % Typically, both of these functions may be subserved by calling 
        %     newValues = dfd.convertValues(oldValues)
        %
        db = subclassSetFieldDescriptor(db, field, dfd)

        tf = subclassSupportsWrite(db)

        % add a field with DataFieldDescriptor dfd, name field, and value vector
        % values (which you may assume have already been appropriately converted)
        db = subclassAddField(db, field, values, dfd)

        % add a field with DataFieldDescriptor dfd, name field, and value vector
        % values (which you may assume have already been appropriately converted)
        db = subclassRemoveField(db, field)

        % add one or more new entries. valueMap is a struct array that looks like
        %   struct(i).field = value
        % Values have already been converted according to the field 
        % descriptor.
        db = subclassAddEntry(db, valueStruct)

        % replace the entry in position iEntry with valueStruct
        % in the same format as subclassAddEntry
        db = subclassReplaceEntry(db, valueStruct, entryMask)

        % set the value of entry(idx).field = value
        % assume that value has already been converted by the 
        % fieldDescriptor to an appropriate value
        db = subclassSetFieldValue(db, idx, field, value)
    end

    % METHODS which subclasses SHOULD override 
    methods
        % subclasses should call this constructor
        function dt = DataTable(varargin)
            dt.createdTimestamp = now;
            dt.modifiedTimestamp = now;
            
            dt = dt.doAutoApply();
        end

        function db = initialize(db)
            db.pendingApplyFields = true;
            db.pendingApplyEntryMask = true;
            db.pendingApplyEntryData = true;
            db = db.doAutoApply();
        end

        % this method is used to access a particular entry or set of entrys by 
        % their index. Here, we could do this by calling getFieldToValuesMap
        % and assembling this ourselves, but often its faster to do this directly
        % in the subclass, so we provide an interface to override this functionality
        % Return a struct array which satisfies
        %   entries(i).field = value of field for entry idx(i)
        % Only the fields in fields need be returned, though returning more fields
        % is fine. However, only return the entries masked by idx
        function entries = getEntriesAsStruct(db, idx, fields)
            % default implementation, calls getFieldToValuesMap
            map = db.getFieldToValuesMap(fields);

            entries = struct([]);
            for iField = 1:length(fields)
                field = fields{iField};
                values = map(field);
                values = values(idx);
                entries = assignIntoStructArray(entries, field, values);
            end
        end
        
        % optional argument: fields cell array
        function entries = getAllEntriesAsStruct(db, varargin)
            entries = db.getEntriesAsStruct(true(db.nEntries, 1), varargin{:});
        end

    end

    methods % Apply changes utilities
        function checkAppliedFields(db)
            % assert that various changes to the table's fields have been applied
            if db.pendingApplyFields
                error('Changes have been made to this table''s fields which has .autoApply==false. Call .apply() to apply changes');
            end
        end

        function checkAppliedEntryMask(db)
            % assert that various changes to the table's entry selection have been applied
            db.checkAppliedFields();
            if db.pendingApplyEntryMask
                error('Changes have been made to this table''s entries which has .autoApply==false. Call .apply() to apply changes');
            end
        end

        function checkAppliedEntryData(db)
            % assert that various changes to the table's data have been applied
            db.checkAppliedEntryMask();
            if db.pendingApplyEntryData
                error('Changes have been made to this table''s entries which has .autoApply==false. Call .apply() to apply changes');
            end
        end

        function db = apply(db)
            % apply all changes to the table manually
            db.warnIfNoArgOut(nargout);
            db = db.applyFields();
            db = db.applyEntryMask();
            db = db.applyEntryData();
        end

        function db = doAutoApply(db)
            % if .autoApply == true, call .apply()
            % this can and should be called after making any changes
            db.warnIfNoArgOut(nargout);
            if db.autoApply
                db = db.apply();
            end
        end

        function db = setAutoApply(db, tf)
            % allow set access to autoApply
            assert(islogical(tf) && isscalar(tf));
            db.autoApply = tf;
        end
    end

    methods % Fields 
        function fields = get.fields(db)
            db.checkAppliedFields();
            fields = db.fieldsCache;
        end
        
        % Allows tab completion after dot to suggest variables
        function p = properties(dt)
            % This will be called for properties of an instance, but the
            % built-in will be still be called for the class name.
            pp = makecol(dt.fields);
            
            if ~isempty(dt.database)
                % include relationships as well
                relNames = dt.database.listRelationshipsWith(dt.entryName);
                pp = [pp; makecol(relNames)];
            end
            
            if nargout == 0
                fprintf('%s\n',getString(message('MATLAB:ClassText:PROPERTIES_FUNCTION_LABEL',class(dt))));
                fprintf('    %s\n',pp{:});
            else
                p = pp;
            end
        end
        
        function f = fieldnames(t), f = properties(t); end
        
        function nFields = get.nFields(db)
            db.checkAppliedFields(); 
            nFields = length(db.fieldsCache);
        end
        
        function fieldsDisplayable = get.fieldsDisplayable(db)
            fields = db.fields;
            mask = false(size(fields));
            for iField = 1:length(fields)
                mask(iField) = db.getFieldDescriptor(fields{iField}).isDisplayable;
            end
            
            fieldsDisplayable = fields(mask);
        end

        function tf = isField(db, fld)
            tf = ismember(fld, db.fields);
        end

        function tf = assertIsField(db, fld)
            tf = ismember(fld, db.fields);
            if any(~tf)
                idx = find(~tf, 1);
                if iscell(fld)
                    field = fld{idx};
                else
                    field = fld;
                end
                error('DataTable does not have field %s', field);
            end
        end

        function dfd = getFieldDescriptor(db, field)
            db.fieldDescriptorMapCache.dynamicClassActive = false;
            dfd = db.fieldDescriptorMapCache.get(field);
            db.fieldDescriptorMapCache.dynamicClassActive = true;
        end

        function db = setFieldDescriptor(db, field, dfd)
            % call subclassSetFieldDescriptor to update the dfd for a particular
            % field, then force a full update by applying fields
            % Note: we assume that subclassSetFieldDescriptor applies any
            % relevant conversions internally, as it will be faster most likely.
            
            db.warnIfNoArgOut(nargout);
            db.assertIsField(field);
            assert(isa(dfd, 'DataFieldDescriptor'));

            db = db.subclassSetFieldDescriptor(field, dfd);

            db.pendingApplyFields = true;
            db = db.autoApplyFields();
        end

        function other = copyFieldToDataTable(db, field, other, varargin)
            % adds a field to table other with the same field descriptor and name
            % as `field` in this table
            
            p = inputParser;
            p.addRequired('field', @ischar);
            p.addRequired('other', @(x) isa(x, 'DataTable'));
            
            % make a key field in the other table
            p.addParameter('keyField', false, @islogical);

            % rename the field to this in the other table
            p.addParameter('as', field, @ischar);

            % pass this along as values to other.addField()
            p.addParameter('values', []);
            
            % copy the values 1:1 from db to other
            p.addParameter('copyValues', false, @islogical);
            
            p.parse(field, other, varargin{:});

            as = p.Results.as;
            values = p.Results.values;
            keyField = p.Results.keyField;
            
            if p.Results.copyValues
                assert(isempty(values), 'Do not specify values param when copyValues is true');
                values = db.getValues(field);
            end

            db.warnIfNoArgOut(nargout);

            dfd = db.getFieldDescriptor(field);
            other = other.addField(as, values, 'fieldDescriptor', dfd, 'keyField', keyField);
        end

        function db = copyField(db, field, newField, varargin)
            db.warnIfNoArgOut(nargout);

            values = db.getValues(field);
            db = db.copyFieldToDataTable(field, db, 'as', newField, 'values', values, varargin{:});
        end

        function fieldDescriptorMap = get.fieldDescriptorMap(db)
            % access to the fieldDescriptorMap
            db.checkAppliedFields();
            fieldDescriptorMap = db.fieldDescriptorMapCache;
        end

        function db = applyFields(db)
            % call the subclass method getFields and store
            % the appropriate values in nFields and fields

            db.warnIfNoArgOut(nargout);

            if ~db.pendingApplyFields
                % only apply when necessary
                return;
            end
            %debug('Applying fields\n');

            [db.fieldsCache, db.fieldDescriptorMapCache] = db.getFields(); 
            assert(iscellstr(db.fieldsCache) && isvector(db.fieldsCache), ...
                'Fields returned by .getFields() must be a cell vector of strings');
            db.pendingApplyFields = false;
            db.pendingApplyEntryMask = true;
            db.pendingApplyEntryData = true;
        end

        function db = autoApplyFields(db)
            warnIfNoArgOut(db, nargout);
            if db.autoApply && db.pendingApplyFields
                db = db.doAutoApply();
            end
        end
    end

    methods % Entry Mask : filtering, sorting 
        function nEntries = get.nEntries(db)
            db.checkAppliedEntryMask();
            nEntries = db.nEntriesCache;
        end

        function db = filterAppend(db, filt)
            db.warnIfNoArgOut(nargout);
            assert(isa(filt, 'DataFilter'), 'filt must be a DataFilter instance');
            if filt.keepMatches
                %debug('Filtering by %s : %s\n', class(filt), filt.describe());
            else
                %debug('Filtering out by %s : %s\n', class(filt), filt.describe());
            end

            db.filtersPending = [db.filtersPending; filt];

            db.pendingApplyEntryMask = true;
            db = db.autoApplyEntryMask();
        end

        function db = filterEntries(db, filterOrKeyword, varargin)
            db.warnIfNoArgOut(nargout);

            if nargin < 2 
                error('Usage: .filterEntries(keyword, ...) or .filterEntries(DataFilter)');
            end
            
            if isa(filterOrKeyword, 'DataFilter')
                % DataFilter passed directly
                filt = filterOrKeyword;
                if ~isempty(varargin)
                    error('Extra arguments passed to .filterEntries with DataFilter specified');
                end
            else
                % build keyword from the keyword
                keyword = filterOrKeyword;
                filterArgs = varargin;
                filt = DataFilter.createFromKeyword(keyword, filterArgs{:});
            end

            filt.keepMatches = true; 
            db = db.filterAppend(filt);
        end

        function db = filterOutEntries(db, filterOrKeyword, varargin)
            db.warnIfNoArgOut(nargout);

            if nargin < 2 
                error('Usage: .filterOutEntries(keyword, ...) or .filterOutEntries(DataFilter)');
            end
            
            if isa(filterOrKeyword, 'DataFilter')
                % DataFilter passed directly
                filt = filterOrKeyword;
                if ~isempty(varargin)
                    error('Extra arguments passed to .filterEntries with DataFilter specified');
                end
            else
                % build keyword from the keyword
                keyword = filterOrKeyword;
                filterArgs = varargin;
                filt = DataFilter.createFromKeyword(keyword, filterArgs{:});
            end

            filt.keepMatches = false; 
            db = db.filterAppend(filt);
        end
        
        function db = filterByField(db, field, filterKeyword, varargin)
            db.warnIfNoArgOut(nargout);
            assert(ischar(filterKeyword), 'Usage: filterByField(field, filterKeyword, [filterArgs])');
            db = db.filterEntries(filterKeyword, field, varargin{:});
        end

        function db = filterOutByField(db, field, filterKeyword, varargin)
            db.warnIfNoArgOut(nargout);
            db = db.filterOutEntries(filterKeyword, field, varargin{:});
        end

        function db = match(db, varargin)
            db = db.filterEntries('match', varargin{:});
        end

        function tf = hasMatch(db, varargin)
            tf = nnz(db.filterGetMask('match', varargin{:})) > 0;
        end

        function db = matchExclude(db, varargin)
            db = db.filterOutEntries('match', varargin{:});
        end

        function db = select(db, idx)
            % select(idx) : filter only the entries in mask or list idx
            db.warnIfNoArgOut(nargout);
            %filt = IndexSelectDataFilter(idx); 
            db = db.removeSort();
            assert(isempty(idx) || isvector(idx), 'Selection must be a vector');
            if islogical(idx)
                % simple logical mask
                assert(numel(idx) == db.nEntries, 'Logical mask must match table size');
                db = db.selectSortEntries(idx);
                
            else
                assert(all(isnan(idx) | idx >= 1 | idx <= db.nEntries), 'Index invalid or out of range');
                
                % deal with NaN values: remove them to select the "valid
                % trials"
                nanMask = isnan(idx);
                idxFilt = removenan(idx);
                dbFiltered = db.selectSortEntries(idxFilt);
                
                if any(nanMask)
                    % add in an empty row to substitute where nans were
                    % found
                    dbFiltered.pendingApplyEntryMask = true;
                    dbFiltered = dbFiltered.autoApplyEntryMask();
                    % get the empty row to fill with nan
                    emptyStruct = db.getEmptyEntryAsStruct();

                    % add one empty row at the end of this table
                    dbFiltered = dbFiltered.addEntry(emptyStruct);
                    indOfEmpty = dbFiltered.nEntries;

                    % now rebuild the full table by selecting the right entries
                    % from dbFiltered
                    idxFull = nan(numel(idx), 1);
                    idxFull(~nanMask) = 1:nnz(~nanMask);
                    idxFull(nanMask) = indOfEmpty;
                    db = dbFiltered.selectSortEntries(idxFull);
                else
                    % no nans, don't bother
                    db = dbFiltered;
                end
            end
             
            db.pendingApplyEntryMask = true;
            db = db.autoApplyEntryMask();
        end

        function db = exclude(db, idx)
            % exclude(idx) : filter out the entries in mask or list idx
            db.warnIfNoArgOut(nargout);
            filt = IndexSelectDataFilter(idx);
            db = db.filterOutEntries(filt);
        end

        function db = none(db)
            % get empty table
            db.warnIfNoArgOut(nargout)
            filt = IndexSelectDataFilter(false(db.nEntries, 1));
            db = db.filterEntries(filt);
        end

        function mask = filterGetMask(db, filterOrKeyword, varargin)
            db.checkAppliedEntryMask();

            if nargin < 2 
                error('Usage: .filterGetMask(keyword, ...) or .filterGetMask(DataFilter)');
            end
            
            if isa(filterOrKeyword, 'DataFilter')
                % DataFilter passed directly
                filt = filterOrKeyword;
                if ~isempty(varargin)
                    error('Extra arguments passed to .filterEntries with DataFilter specified');
                end
            else
                % build keyword from the keyword
                keyword = filterOrKeyword;
                filterArgs = varargin;
                filt = DataFilter.createFromKeyword(keyword, filterArgs{:});
            end

            filt.keepMatches = true; 

            fieldToValuesMap = db.getFieldToValuesMap(filt.fields);

            if db.nEntries > 0
                filtMask = filt.getMask(fieldToValuesMap, true(db.nEntries, 1), db.fieldDescriptorMap);
                mask = makecol(filtMask);
            else
                mask = logical([]);
            end
        end
        
        function mask = filterByFieldGetMask(db, field, keyword, varargin)
            mask = db.filterGetMask(keyword, field, varargin{:});
        end

        function mask = filterOutByFieldGetMask(db, field, keyword, varargin)
            mask = ~db.filterGetMask(keyword, field, varargin{:});
        end
        
        function mask = matchMask(db, varargin)
            mask = db.filterGetMask('match', varargin{:});
        end

        function idx = matchIdx(db, varargin)
            idx = find(db.matchMask(varargin{:}));
        end

        function fieldsRequired = getFieldsRequiredByFilters(db)
            % figure out all of the fields which are referenced by all of the 
            % pending filters
            fieldsByFilter = arrayfun(@(filt) makerow(filt.fields), db.filtersPending, ...
                'UniformOutput', false);
            fieldsRequired = unique([fieldsByFilter{:}]);
        end

        function db = removeSort(db)
            db = db.sort();
        end

        function db = sort(db, varargin)
            % supply a list of field names either as a cell array or comma 
            % separated argument list
            % prefix the field name with '-' to use descending order
            % multiple fields means sort by 1, then by 2 if tied, then by 3 if tied
            db.warnIfNoArgOut(nargout);
            db.checkAppliedFields();

            % build list of fields from arguments
            sortByList = {}; %#ok<*PROP>
            for iArg = 1:length(varargin)
                arg = varargin{iArg};
                if iscell(arg)
                    sortByList = [sortByList; makecol(arg)];  %#ok<AGROW>
                else
                    sortByList = [sortByList; arg]; %#ok<AGROW>
                end
            end

            % check that all fields exist
            for iField = 1:length(sortByList)
                field = sortByList{iField};
                if field(1) == '-'
                    field = field(2:end);
                end

                assert(db.isField(field), 'Field %s not found', field);
            end

            %debug('Sorting by %s\n', strjoin(sortByList));
            db.sortByListPending = sortByList;

            db.pendingApplyEntryMask = true;
            db = db.autoApplyEntryMask();
        end

        function [fieldsRequired, reverse] = getFieldsRequiredBySorting(db)
            % figure out all of the fields which are referenced by sortByList
            % reverse(i) == true 
            fieldsList = {};
            reverse = false(length(db.sortByListPending), 1);
            for iField = 1:length(db.sortByListPending)
                field = db.sortByListPending{iField};
                if field(1) == '-'
                    field = field(2:end);
                    reverse(iField) = true;
                else
                    reverse(iField) = false;
                end

                fieldsList = [fieldsList field]; %#ok<AGROW>
            end

            % figure out whether the last reference to each field is reversed
            %[fieldsRequired idx] = unique(fieldsList, 'last');
            fieldsRequired = fieldsList;
            %reverse = reverse(idx);
        end

        function db = applyEntryMask(db)
            % this function should look at all of the DataFilters in 
            % pendingDataFilters, grab the field values needed to apply these
            % filters, apply them to come up with the entry mask.
            %
            % It should then look at all of the sorts in pendingSorts and resort
            % the data according to these rules.

            db.checkAppliedFields();
            db.warnIfNoArgOut(nargout);

            if ~db.pendingApplyEntryMask
                % only apply when necessary
                return;
            end
            %debug('Applying entry mask\n');

            % query current entry count 
            nEntries = db.getEntryCount();
            
            if nEntries > 0                
                %debug('%d entries pre-filtering\n', nEntries); 

                if ~isempty(db.filtersPending)
                    % build list of fields for all filters 
                    filterFields = getFieldsRequiredByFilters(db);

                    %debug('%d fields required for filtering: %s\n', length(filterFields), strjoin(filterFields));
                    %debug('Requesting required fields\n');
                    fieldToValuesMap = db.getFieldToValuesMap(filterFields);

                    mask = true(nEntries, 1);
                    for iFilter = 1:length(db.filtersPending)
                        filt = db.filtersPending(iFilter);
                        if filt.keepMatches
                            filtMask = filt.getMask(fieldToValuesMap, mask, db.fieldDescriptorMap);
                            mask = mask & makecol(filtMask);
                        else
                            filtMask = filt.getMask(fieldToValuesMap, mask, db.fieldDescriptorMap); 
                            mask = mask & makecol(~filtMask);
                        end
                    end

                    nEntries = nnz(mask);
                    %debug('%d entries post-filtering\n', nEntries); 
                    %debug('Mask after filtering: [%s]\n', num2str(mask));
                else
                    mask = true(nEntries, 1);
                end
                idxKeep = find(mask);
                nEntries = length(idxKeep);

                % construct initial sort order
                sortIdx = 1:nEntries;

                if ~isempty(db.sortByListPending)
                    %debug('Sorting entries\n');

                    % build list of sort fields 
                    [sortFields, reverse] = getFieldsRequiredBySorting(db);
                    uniqueSortFields = unique(sortFields);
                    %debug('%d fields required for filtering: %s\n', ...
                    %    length(uniqueSortFields), strjoin(uniqueSortFields));
                    %debug('Requesting required fields\n');
                    fieldToValuesMap = db.getFieldToValuesMap(uniqueSortFields);

                    % loop through the sort fields in reverse order so that first sort
                    % field is the primary sort, second is the secondary sort, etc.
                    for iSort = length(sortFields):-1:1
                        field = sortFields{iSort};
                        isAscending = ~reverse(iSort);

                        % pull out values for this field and apply the filter mask
                        % and the current sortIdx 
                        values = fieldToValuesMap(field);
                        values = values(mask);
                        values = values(sortIdx);

                        % call the field descriptors' sort method on this fields values
                        dfd = db.fieldDescriptorMap(field);
                        sortIdxNew = dfd.sortValues(values, isAscending);

                        % reorder the sortIdx appropriately
                        sortIdx = sortIdx(sortIdxNew);
                    end

                    %debug('Final sort order : [%s]\n', num2str(makerow(sortIdx)));
                end

                % select and sort the entries in the raw data via callback 
                newOrderIdx = idxKeep(sortIdx);
                %debug('Calling selectSortEntries with idx [%s]\n', num2str(makerow(newOrderIdx)));
                db = db.selectSortEntries(newOrderIdx);
            else
                mask = [];
            end

            % get new entry count from callback
            db.nEntriesCache = db.getEntryCount();
            %debug('%d new reported entry count\n', db.nEntriesCache);
            assert(nnz(mask) == db.nEntriesCache, 'New nEntries reported does not match instructed entry count after filtering');

            % transfer filters from pending to applied
            db.filtersApplied = [db.filtersApplied db.filtersPending];
            db.filtersPending = [];

            db.sortByList = db.sortByListPending;

            db.pendingApplyEntryMask = false;
            db.pendingApplyEntryData = true;
        end

        function db = autoApplyEntryMask(db)
            warnIfNoArgOut(db, nargout);
            if db.autoApply && db.pendingApplyEntryMask
                db = db.doAutoApply();
            end
        end
    end

    methods % Retrieving values
        function db = applyEntryData(db)
            % does nothing for now, ultimately here to be useful for database linked
            % subclasses which wish to defer data querying until all filters, sorts
            % have been specified
            
            db.checkAppliedFields();
            db.checkAppliedEntryMask();

            if ~db.pendingApplyEntryData
                % only apply when necessary
                return;
            end
            %debug('Applying entry data\n');

            db.warnIfNoArgOut(nargout);
            db.pendingApplyEntryData = false;
        end

        function db = autoApplyEntryData(db)
            warnIfNoArgOut(db, nargout);
            if db.autoApply && db.pendingApplyEntryData
                db = db.doAutoApply();
            end
        end

        function s = getFullEntriesAsStruct(db)
            s = db.getEntriesAsStruct(true(db.nEntries, 1), db.fields);
        end
        
        function t = getFullEntriesAsMatlabTable(db)
            s = db.getFullEntriesAsStruct();
            t = struct2table(s);
        end
        
        function t = getFullEntriesAsDisplayStringsAsMatlabTable(db)
            s = db.getFullEntriesAsDisplayStringsAsStruct();
            % workaround for matlab bug with empty strings
            if numel(s) == 1
                s = structfun(@(f) [f blanks(isempty(f))], s, 'UniformOutput', false);
            end
            t = struct2table(s);
        end
        
        function printAsRestructuredText(db)
            t = db.getFullEntriesAsDisplayStringsAsMatlabTable();
            table2rst(t);
        end
        
        function s = getKeyFieldValuesAsStruct(db)
            s = db.getEntriesAsStruct(true(db.nEntries, 1), db.keyFields);
        end
        
        function [db, maskRemoved] = deduplicateBasedOnKeyFields(db, varargin)
            p = inputParser();
            p.addParameter('verbose', true, @islogical);
            p.parse(varargin{:});
            
            warnIfNoArgOut(db, nargout);
            
            kf = db.getKeyFieldValuesAsStruct();
            [~, idxUnique] = Matdb.uniqueStruct(kf);
            
            db = db.select(idxUnique);
            maskRemoved = truevec(db.nEntries);
            maskRemoved(idxUnique) = false;
            
            if any(maskRemoved) && p.Results.verbose
                debug('Removing %d %s entries using key field deduplication\n', nnz(maskRemoved), db.entryName);
            end
        end
        
        function db = addEmptyEntry(db)
            % add a new [default] empty entry
            warnIfNoArgOut(db, nargout);
            db = db.addEntry(struct());
        end
        
        function s = getEmptyEntry(db)
            % return a single entry table with blank rows filled in
            s = db.none().addEntry(struct());
        end

        function s = getEmptyEntryAsStruct(db)
            % filter out all the existing entries, add one using entirely
            % empty/default values, and return as struct
            s = db.getEmptyEntry().getFullEntriesAsStruct();
            
            % this way of doing things is simpler, but returns an empty
            % struct (size 0 x 1) with no values filled in with defaults
            %s = db.getEntriesAsStruct(false(db.nEntries, 1), db.fields);
        end

        function s = getFullEntriesAsStringsAsStruct(db)
            s = mapToStructArray(db.getValueMapAsStrings(db.fields));
            s = orderfields(s, db.fields);
        end

        function values = getValues(db, field, idx)
            db.checkAppliedEntryData();
            db.assertIsField(field);

            % request the values from the subclass either with or without idx
            if nargin == 2
                valueMap = db.getFieldToValuesMap({field});
            else
                valueMap = db.getFieldToValuesMap({field}, idx);
            end
            values = makecol(valueMap(field));

            % shouldn't need to convert, the subclass should take care of this
            %dfd = db.fieldDescriptorMap(field);
            %values = makecol(dfd.convertValues(valueMap(field)));
        end

        % same as getValues, except returns a single value not wrapped in 
        % a cell array. Throws an error if there is more than 1 entry in the
        % table selected by idx (or in total)
        function value = getValue(db, field, idx)
            db.checkAppliedEntryData();
            db.assertIsField(field);

            if nargin == 2
                values = db.getValues(field);
            else
                values = db.getValues(field, idx);
            end

            if length(values) > 1
                error('Cannot call getValue with more than one entry selected');
            end

            dfd = db.fieldDescriptorMap(field);
            if ~dfd.matrix
                value = values{1};
            else
                value = values(1);
            end
        end

        function value = getValueAsDateStr(db, field, fmat, varargin)
            dfd = db.fieldDescriptorMap(field);
            assert(isa(dfd, 'DateField') || isa(dfd, 'DateTimeField'), ...
                'Field %s is not a DateField or DateTimeField', field);
            
            if ~exist('fmat', 'var')
                % use default format when no format provided
                fmat = dfd.standardDisplayFormat;
            end
                
            value = db.getValue(field, varargin{:});

            str = dfd.getAsDateStr(value, fmat);
            value = str{1};
        end
        
        function str = getValueAsString(db, field, varargin)
            db.checkAppliedEntryData();
            db.assertIsField(field);
            value = db.getValue(field);

            dfd = db.fieldDescriptorMap(field);
            strCell = dfd.getAsStrings(value);
            str = strCell{1};
        end

        function valueMap = getValuesMap(db, fields, varargin)
            assert(iscellstr(fields), 'fields must be a cell array of field names');
            db.checkAppliedEntryData();
            db.assertIsField(fields);

            % request the values from the subclass and convert them according
            % to the field descriptor
            valueMapOrig = db.getFieldToValuesMap(fields);
            valueMap = valueMapOrig;
            return;

            % shouldn't need to convert, the subclass should take care of this
            valueMap = ValueMap('KeyType', 'char', 'ValueType', 'any');
            for iField = 1:length(fields)
                field = fields{iFld};
                dfd = db.fieldDescriptorMap(field);
                values = makecol(dfd.convertValues(valueMap(field)));
                valueMap(field) = values;
            end
        end

        function strCell = getValuesAsStrings(db, field, varargin)
            db.checkAppliedEntryData();
            db.assertIsField(field);
            values = db.getValues(field);

            dfd = db.fieldDescriptorMap(field);
            strCell = dfd.getAsStrings(values);
        end

        function stringMap = getValueMapAsStrings(db, fields, varargin)
            assert(iscellstr(fields), 'fields must be a cell array of field names');
            db.checkAppliedEntryData();
            db.assertIsField(fields);

            valueMap = db.getValuesMap(fields);
            stringMap = ValueMap('KeyType', 'char', 'ValueType', 'any');
            for iField = 1:length(fields)
                field = fields{iField};
                dfd = db.fieldDescriptorMap(field);
                stringMap(field) = dfd.getAsStrings(valueMap(field));
            end
        end

        function strCell = getValuesAsDisplayStrings(db, field, varargin)
            db.checkAppliedEntryData();
            db.assertIsField(field);
            values = db.getValues(field);

            dfd = db.fieldDescriptorMap(field);
            if db.isKeyField(field)
                % never truncate key fields, it's annoying
                strCell = dfd.getAsStrings(values);
            else
                strCell = dfd.getAsDisplayStrings(values);
            end
        end

        function [stringMap displayableFields] = getValueMapAsDisplayStrings(db, fields, varargin)
            assert(iscellstr(fields), 'fields must be a cell array of field names');
            db.checkAppliedEntryData();
            db.assertIsField(fields);

            valueMap = db.getValuesMap(fields);
            stringMap = ValueMap('KeyType', 'char', 'ValueType', 'any');
            displayableFields = {};
            for iField = 1:length(fields)
                field = fields{iField};
                dfd = db.fieldDescriptorMap(field);
%                 if dfd.isDisplayable()
                    displayableFields = [displayableFields; field];
                    if db.isKeyField(field)
                        stringMap(field) = dfd.getAsStrings(valueMap(field));
                    else
                        stringMap(field) = dfd.getAsDisplayStrings(valueMap(field));
                    end
                    %if ~iscellstr(stringMap(field))
                    %    error('getAsDisplayStrings failed to return a cellstr');
                    %end
%                 end
            end
        end
        
        function [fieldsDisplayable maskOverAllFields] = getFieldsDisplayable(db)
            fields = db.fields;
            maskOverAllFields = false(length(fields), 1);
            for iField = 1:length(fields)
                field = fields{iField};
                dfd = db.getFieldDescriptor(field);
                if dfd.isDisplayable()
                    maskOverAllFields(iField) = true;
                end
            end
            
            fieldsDisplayable = fields(maskOverAllFields);
        end
        
        function strStruct = getFullEntriesAsDisplayStringsAsStruct(db, varargin)
            p = inputParser();
            p.addParameter('extraFields', {}, @iscell);
            p.parse(varargin{:});
            fieldsDisplayable = union(db.getFieldsDisplayable(), p.Results.extraFields, 'stable');
            [stringMap displayableFields] = db.getValueMapAsDisplayStrings(fieldsDisplayable);
            strStruct = mapToStructArray(stringMap); 
        end

        function [stringMap] = getKeyFieldMapAsFilenameStrings(db, varargin)
            db.checkAppliedEntryData();

            fields = db.keyFields;
            valueMap = db.getValuesMap(fields);
            stringMap = ValueMap('KeyType', 'char', 'ValueType', 'any');
            for iField = 1:length(fields)
                field = fields{iField};
                dfd = db.fieldDescriptorMap(field);
                stringMap(field) = dfd.getAsFilenameStrings(valueMap(field));
            end
        end

        function uniqueVals = getUnique(db, field, varargin)
            db.checkAppliedEntryData();

            values = db.getValues(field);
            dfd = db.fieldDescriptorMap(field);
            uniqueVals = dfd.uniqueValues(values); 

            uniqueVals = makecol(uniqueVals);
        end

        function [uniqueIdx uniqueVals] = getValuesAsIdxIntoUnique(db, fld, varargin)
            % instead of returning an array containing the actual values of field
            % fld down the rows, return an index of each value into the set of values
            % returned by .getUnique(fld)

            db.checkAppliedEntryData();
            
            vals = db.getValues(fld, varargin{:});

            % pass along varargin in case other params are overridden
            uniqueVals = db.getUnique(fld, 'removeEmpty', false, varargin{:});
            if isnumeric(uniqueVals)
                [~, uniqueIdx] = ismember(vals, uniqueVals);
            elseif iscell(uniqueVals)
                % ismemberCell handles cell arrays of non-strings as well
                [~, uniqueIdx] = ismemberCell(vals, uniqueVals);
            end
        end

        function [uniqueTupleIdx uniqueTuples entryCount] = getUniqueTuples(db, varargin)
            % looks for unique occurrences of a set of several field values
            % uniqueTuples will be a struct with each field in fields (param: default .fields)
            % uniqueTupleIdx will be a nEntries long vector of indices in uniqueTuples, inicating which 
            %   set of field values describes that entry
            % entryCount counts the number of entries used by uniqueTuples(i)
            p = inputParser;
            p.addParameter('fields', db.fields, @iscellstr);
            p.parse(varargin{:});
            fields = p.Results.fields;

            % return the gridData but replace each field's value with the index into
            % the set of unique values returned by .getUnique(fld)
            db.checkAppliedEntryData();
           
            uniqueIdxMat = nan(db.nEntries, length(fields));
            uniqueValsCell = cell(length(fields), 1);
            for iField = 1:length(fields)
                field = fields{iField};
                [uniqueIdxMat(:, iField), uniqueVals] = db.getValuesAsIdxIntoUnique(field);

                if ~iscell(uniqueVals)
                    uniqueVals = num2cell(uniqueVals);
                end
                uniqueValsCell{iField} = uniqueVals;
            end

            [tupleLookups, ~, uniqueTupleIdx] = unique(uniqueIdxMat, 'rows'); 

            % build a struct where uniqueTuples(i).field is the value of field in the ith unique tuple
            nTuples = size(tupleLookups, 1);
            for iTuple = 1:nTuples
                for iField = 1:length(fields)
                    field = fields{iField};
                    valueIdx = tupleLookups(iTuple, iField);
                    if valueIdx > 0 % 0 happens when the value was NaN
                        uniqueTuples(iTuple).(field) = uniqueValsCell{iField}{valueIdx}; %#ok<AGROW>
                    end
                end
            end

            % count the number of entries used by each tuple
            entryCount = nan(nTuples, 1);
            for iTuple = 1:nTuples
                entryCount(iTuple) = nnz(uniqueTupleIdx == iTuple);
            end
        end
        
        function [counts, uniqueVals, uniqueIdx] = getUniqueCounts(db, fld, varargin)
            [uniqueIdx, uniqueVals] = db.getValuesAsIdxIntoUnique(fld, varargin{:});
            
            counts = histc(uniqueIdx, 1:numel(uniqueVals));
        end
        
        function utbl = getUniqueCountsTable(db, fld, varargin)
            [counts, uniqueVals] = db.getUniqueCounts(fld, varargin{:});
            
            for iS = 1:numel(uniqueVals)
                S(iS).count = counts(iS);
                if iscell(uniqueVals)
                    S(iS).value = uniqueVals{iS};
                else
                    S(iS).value = uniqueVals(iS);
                end 
            end
            
            utbl = StructTable(S, 'entryName', 'uniqueValueCount');
            utbl = utbl.setFieldDescriptor('count', ScalarField());
            utbl = utbl.setKeyFields('value');
            utbl = utbl.sort('-count');
        end
    end

    methods % Display / visualization
        function disp(db)
            db.printTable();
        end

        function printTable(db, varargin)
            % get the dimensions of the terminal we're in to size the printout
            % appropriately
            [termRows, termCols] = getTerminalSize();

            % determine if we are in a data tip
            inDataTip = calledViaDataTip();
            if inDataTip
                % constrain the size in a data tip
                termRows = 15;
                termCols = 78;
            end
    
            p = inputParser;
            % use a | between columns: simple means ascii, grid means unicode box characters
            p.addParameter('grid', true, @(x) isempty(x) || islogical(x));
            p.addParameter('color', true, @islogical);
            % insert spaces between columns or between columns and |
            p.addParameter('padding', 0, @(x) isscalar(x) && x >= 0);
            p.addParameter('maxEntries', termRows-9, @(x) isscalar(x) && x >= 0);
            p.addParameter('maxWidth', termCols, @(x) isscalar(x) && x >= 0);
            p.addParameter('maxWidthPerField', 25, @isscalar);
            p.parse(varargin{:});

            grid = p.Results.grid;
            color = p.Results.color;
            padding = round(p.Results.padding);
            if ~grid && padding == 0
                padding = 1;
            end

            maxEntries = p.Results.maxEntries;
            maxWidth = p.Results.maxWidth;

            % use utf depending on OS, but never in data tip
            useUTF32 = isunix && ~ismac && ~inDataTip;
            useUTF8 = ~useUTF32 && isunix && ~inDataTip;
            if ismac % temporary hack because newer iTerm is messing up double width characters
                %useUTF8 = false;
            end
            useUTF32 = false;
            useUTF8 = false;

            % determine utf bytecodes for + - | characters
            if grid
                if useUTF32
                    crossHeader = char(hex2dec('253F'));
                    vline = char(hex2dec('2502'));
                    hlineHeader = char(hex2dec('2501'));
                elseif useUTF8
                    crossHeader = char(hex2dec({'e2', '94', 'bc'}))'; 
                    hlineHeader = char(hex2dec({'e2', '94', '80'}))';
                    vline = char(hex2dec({'e2', '94', '82'}))';
                else
                    crossHeader = '+';
                    hlineHeader = '-';
                    vline = '|';
                end
            end
            
            if color && ~inDataTip
                printf = @tcprintf;
                %printf = @(color, fmatStr, varargin) hcprintf(['{' color, '}' ;
            else
                printf = @(c, varargin) fprintf(varargin{:});
            end

            if grid
                idxHeaderColor = 'darkGray';
                fieldColor = 'bright yellow';
                keyFieldHeaderColor = 'bright blue';
                keyFieldColor = 'bright blue';
            else
                idxHeaderColor = 'darkGray underline';
                fieldColor = 'bright yellow underline';
                keyFieldHeaderColor = 'bright blue underline';
                keyFieldColor = 'bright blue';
            end
            idxColor = '';
            messageColor = 'darkGray';
            gridColor = '';
            valueColor = 'none';

            % build divider between columns
            paddingStr = repmat(' ', 1, padding);
            if grid 
                divider = [paddingStr vline paddingStr];
                dividerWidth = 2*padding + 1;
                %divider = vline;
            else
                divider = paddingStr;
                dividerWidth = padding;
            end

            db.checkAppliedEntryData(); 

            nEntries = db.nEntries;
            if nEntries > maxEntries
                db = db.select(1:maxEntries);
            end

            % filter by displayable fields
            fields = db.fields;
            isDisplayable = cellfun(@(field) db.fieldDescriptorMap(field).isDisplayable(), fields);
            fields = fields(isDisplayable);
            nFields = length(fields);

            isKeyField = db.isKeyField(fields);

            % get the values for each field
            % and figure out how wide to make each column
            if db.nEntries > 0
                valueMap = db.getValueMapAsDisplayStrings(fields); 
                valueWidths = min(p.Results.maxWidthPerField, cellfun(@(field) max(cellfun(@length, valueMap(field))), fields));
            else
                valueWidths = zeros(length(fields), 1);
            end
            fieldWidths = cellfun(@length, fields);
            colWidths = max(valueWidths, fieldWidths);
            idxColWidth = max(3, ceil(log(db.nEntries) / log(10)));

            % figure out how many columns to print to fit within window
            cumWidth = idxColWidth + cumsum(colWidths) + dividerWidth*[1:length(colWidths)]';
            nFieldsPrint = find(cumWidth < maxWidth, 1, 'last'); 
            if isempty(nFieldsPrint)
                nFieldsPrint == 1;
            end

            if nFieldsPrint < nFields
                truncatedFields = fields(nFieldsPrint+1:end);
                nFields = nFieldsPrint;
                fields = fields(1:nFields); 
            else
                truncatedFields = {};
            end
            
            function str = truncateStr(str, l)
                if numel(str) > l
                    str = [str(1:l-2), '..'];
                end
            end

            % print header row
            printf(idxColor, '%-*s', idxColWidth, 'idx');
            printf(gridColor, divider);
            for iField = 1:nFields
                field = fields{iField};
                if isKeyField(iField)
                    color = keyFieldHeaderColor;
                else
                    color = fieldColor;
                end
                printf(color, '%-*s', colWidths(iField), truncateStr(field, colWidths(iField)));
                if iField < nFields
                    printf(gridColor, divider);
                end
            end
            fprintf('\n');

            % print header / values divider line for grid?
            if grid
                dashFn = @(width) repmat(hlineHeader, 1, width);
                printf(gridColor, '%s', dashFn(idxColWidth+padding));
                printf(gridColor, crossHeader);
                for iField = 1:nFields
                    printf(gridColor, '%s', dashFn(padding+colWidths(iField)+padding));
                    if iField < nFields 
                        printf(gridColor, crossHeader);
                    end
                end
                fprintf('\n');
            end

            % print each entry row
            nEntriesDisplay = min(maxEntries, db.nEntries);
            for iEntry = 1:nEntriesDisplay
                printf(idxColor, '%*d', idxColWidth, iEntry);
                printf(gridColor, divider);
                for iField = 1:nFields
                    field = fields{iField};
                    if isKeyField(iField)
                        color = keyFieldColor;
                    else
                        color = valueColor;
                    end
                    values = valueMap(field);
                    printf(color, '%*s', colWidths(iField), truncateStr(values{iEntry}, colWidths(iField)));
                    if iField < nFields
                        printf(gridColor, '%s', divider);
                    end
                end
                fprintf('\n');
            end

            if nEntries == 0 %#ok<*PROPLC>
                printf(messageColor, '(empty table)\n');
            end
            if nEntriesDisplay < nEntries
                printf(messageColor, '(truncated at %d of %d entries)\n', nEntriesDisplay, nEntries);
            end
            if any(~isDisplayable) 
                omittedFields = db.fields(~isDisplayable);
                printf(messageColor, '(omitting non-displayable fields %s)\n', ...
                    strjoin(omittedFields, ', '));
            end
            if ~isempty(truncatedFields)
%                 if length(truncatedFields) < 5
                    printf(messageColor, '(omitting fields %s to fit display)\n', ...
                        strjoin(truncatedFields, ', '));
%                 else
%                     printf(messageColor, '(omitting %d fields to fit display)\n', ...
%                         length(truncatedFields));
%                 end
            end

            fprintf('\n');
            fprintf('%c\n', 15);
        end

        function printRelationships(db)
            [~, ~, relationships] = db.listRelationships();
            for i = 1:length(relationships) %#ok<*PROP>
                fprintf('%s\n', relationships{i}.describeLink());
            end
        end
        
        function viewAsHtml(db)
            fileName = tempname();
            html = db.saveAsHtml(fileName);
            html.openInBrowser();
        end

        function html = saveAsHtml(db, fileName)
            html = HTMLDataTableWriter(fileName);
            html.copyResources();
            html.generate(db);
        end
    end

    methods % Dynamic property access

        function [value appliedNext] = mapDynamicPropertyAccess(db, name, typeNext, subsNext)
            if strcmp(name, 'entries') || strcmp(name, 'entry')
                % here we support a special "dependent" properties .entry and .entries
                % which act just like a proxy for getEntriesAsStruct
                % except is more efficient in that it knows the (idx) 
                % that are being requested ahead of time, to make
                % access faster
                if strcmp(typeNext, '()')
                    assert(length(subsNext) == 1, 'Only vector entry indexing is allowed');
                    idx = subsNext{1};
                else
                    idx = true(db.nEntries, 1);
                end

                % for .entry, only allow one 1 entry to be accessed at a time
                if strcmp(name, 'entry')
                    assert(nnz(idx) == 1, 'Only single indices may be requested using .entry');
                end

                value = db.getEntriesAsStruct(idx, db.fields);
                appliedNext = true;

            elseif db.isField(name)
                %                 if strcmp(typeNext, '()')
                %                     assert(length(subsNext) == 1, 'Only vector indexing is allowed');
                %                     idx = subsNext{1};
                %                     value = db.getValues(name, idx);
                %                     appliedNext = true;
                %                 else
                value = db.getValues(name);
                
                % THIS IS ERROR PRONE, USE {1} INDEXING FOR THIS
                % The following line removes the unnecessary cell array around
                % a singular value when there is only one entry
                % This is nice for the extremely common case of t(1).field
                % but could potentially be confusing when filtering with a mask
                % that may or may not have more than one match. Technically, 
                % there are better ways to do this (i.e. call .select) and then
                % loop through the entries. Note that this makes the common case
                % more convenient but can cause confusion in the less common case
                %if db.nEntries == 1 && iscell(value) 
                %    value = value{1};
                %end
                appliedNext = false;
                %                 end

            elseif db.isReference(name)
                % reference through a database relationship
                value = db.database.matchRelated(db, name, 'combine', true);
                appliedNext = false;

            else
                value = DynamicClass.NotSupported;
                appliedNext = false;
            end
        end

        function [value, appliedNext] = parenIndex(db, subs, typeNext, subsNext)
            assert(length(subs) == 1, 'Only vector entry indexing is allowed');
            idx = subs{1};
            value = db.select(idx);
            appliedNext = false;
        end

        function [valueCell appliedNext] = cellIndex(db, subs, typeNext, subsNext)
            assert(length(subs) == 1, 'Only vector entry indexing is allowed');
            idx = subs{1};

            if isempty(typeNext)
                % no field access, simply grab entries 
                entries = makecol(db.getEntriesAsStruct(idx, db.fields));
                valueCell = arrayfun(@(x) x, entries, 'UniformOutput', false);
                appliedNext = false;

            elseif strcmp(typeNext, '.')
                field = subsNext;

                if db.isField(field)
                    % just grab that one field's values, filtered by idx 
                    entry = db.getFieldToValuesMap({field}, idx);
                    values = entry(field);

                    % multiple idx --> return as cell or matrix, only for convenience
                    % single idx --> return element of cell, typical case
                    if nnz(idx) == 1 && iscell(values)
                        valueCell = {values{1}};
                    else
                        valueCell = makecol(entry(field));
                        if ~iscell(values)
                            valueCell = num2cell(valueCell);
                        end
                    end
                    appliedNext = true;

                elseif db.isReference(field)
                    % it's a reference to another table's entries via a DataRelationship
                    % here we follow that reference, and grab the entries directly 
                    % rather than return the DataTable instance
                    selected = db.select(idx);
                    % get the matches in a cell array, one table for each of my entries
                    tableCell = db.database.matchRelated(selected, field, 'combine', false);
                    % extract the entries from each as a struct
                    valueCell = cellfun(@(table) table.getFullEntriesAsStruct(), tableCell, 'UniformOutput', false);
                    appliedNext = true;
                end

            else
                % not sure if it's possible to get here, but err just in case
                error('Indexing beyond () not supported');
            end
        end

        function sz = end(db, k, n)
            if k == 1
                sz = db.nEntries;
            else
                sz = 1;
            end
        end

        function sz = size(db, dim)
            sz = [db.nEntries 1];
            if nargin > 1
                if dim >= 2
                    dim = 2;
                end
                sz = sz(dim);
            end
        end

        % overriding length but not numel in order to not break subsref
        function len = length(db)
            len = db.nEntries;
        end

    end

    methods % Modifying data
        function tf = get.supportsWrite(db)
            tf = db.subclassSupportsWrite();
        end

        function checkSupportsWrite(db)
            assert(db.supportsWrite);
        end

        function db = addField(db, field, values, varargin)
            % db = addField(db, field, values, ['fieldDescriptor', dfd])
            % adds a field to the table, filled with values in values
            % and described by DataFieldDescriptor dfd.
            %
            % If values is a numeric vector or cell array of length nEntries
            % each element will be stored individually for each entry.
            % If values is a scalar or single element cell array, the same 
            % value will be stored in each entry.
            %
            % If fieldDescriptor is provided, it will be used as the field
            % descriptor. If not, DataFieldDescriptor.inferFromValues will 
            % be used to determine the appropriate field descriptor.
            %
            % If values contains an empty element, this empty element will
            % be replaced by the value returned by dfd.getEmptyValue() 
            %
            % Lastly, values will be converted using  dfd.convertValues before
            % storing for consistency

            p = inputParser;
            p.addRequired('field', @ischar);
            p.addOptional('values', [], @(x) true);
            p.addParameter('fieldDescriptor', [], @(x) isa(x, 'DataFieldDescriptor'));
            p.addParameter('position', [], @(x) isnumeric(x) && isscalar(x));
            p.addParameter('keyField', false, @islogical);
            p.parse(field, values, varargin{:});
            field = p.Results.field;
            values = p.Results.values;
            dfd = p.Results.fieldDescriptor;
            position = p.Results.position;
            keyField = p.Results.keyField;
            
            if ischar(values)
                values = {values};
            end

            if isempty(dfd) 
                % no field descriptor provided, infer from values
                dfd = DataFieldDescriptor.inferFromValues(values);
            end

            db.warnIfNoArgOut(nargout);

            db.checkSupportsWrite();

            % check whether this field already exists
            if db.isField(field)
                warning('Field %s already exists in DataTable. Overwriting', field); 
                % have the subclass remove this field in preparation for adding it back in
                db = db.removeField(field);
                overwritingExistingField = true;
            else
                overwritingExistingField = false;
            end

            if isempty(position)
                position = db.nFields + 1;
            end
            assert(position > 0 && position <= db.nFields + 1, 'Field position out of range');

            if isempty(values)
                % if no values specified, fill with default empty values
                values = dfd.getEmptyValue(db.nEntries);

            else
                % otherwise convert the values to the appropriate format
                values = dfd.convertValues(values);

                % is this a single entry value for each entry?
                % if so expand this for each entry
                if length(values) == 1
                    values = repmat(values, db.nEntries, 1); 
                end
            end

            % check for size match
            assert(isempty(values) || isvector(values), 'Values must be a vector');
            assert(length(values) == db.nEntries, 'Length of values must match .nEntries');
            values = makecol(values);

            % have subclass actually add this fields data
            db = db.subclassAddField(field, values, dfd, position);

            db.pendingApplyFields = true;
            db = db.doAutoApply();

            if keyField
                keyFields = db.keyFields;
                keyFields{end+1} = field;
                db = db.setKeyFields(keyFields);

                % not sure this is necessary right now, but it might be in the future
                % db.pendingApplyFields = true;
                % db = db.doAutoApply();
            end

        end

        % same as addField, except with keyField set to true
        function db = addKeyField(db, varargin)
            db.warnIfNoArgOut(nargout);
            db = db.addField(varargin{:}, 'keyField', true);
        end
        
        function db = keepFields(db, fields, varargin)
            db.warnIfNoArgOut(nargout);
            remove = setdiff(db.fields, fields);
            db = db.removeField(remove);
        end

        function db = removeField(db, field, varargin)
            p = inputParser;
            p.addRequired('field', @(x) ischar(x) || iscellstr(x));
            p.parse(field, varargin{:});
            field = p.Results.field;

            if ~iscell(field)
                fields = {field};
            else
                fields = field;
            end

            db.warnIfNoArgOut(nargout);
            db.checkSupportsWrite();

            for iField = 1:length(fields)
                field = fields{iField};
                % check whether this field already exists
                if ~db.isField(field)
                    error('Field %s not found.', field); 
                end

                % remove from keyFields list
                if db.isKeyField(field)
                    keyFields = setdiff(db.keyFields, field);
                    db = db.setKeyFields(keyFields);
                end

                % have subclass actually add this fields data
                db = db.subclassRemoveField(field);
            end

            db.pendingApplyFields = true;
            db = db.doAutoApply();
        end
        
        function db = splitEntriesWithMultipleValues(db, varargin)
            error('not yet implemented');
            % db = splitEntriesWithMultipleValues(db, fieldNames ...)
            % For entries with an array of values for the specified fields, splits into several 
            % separate entries, each with the i-th value for that field. If multiple field names
            % are provided, these fields must have the same number of values for each entry, 
            % and the ith entry created will have the i-th value from each field.
            %
            % Note that this operation only affects active entries (i.e. that satisfy the filters)
            %
            % Example:
            %   e(1).a = [1 2];  e(1).b = {'b1', 'b2'};
            %   db = GridDatabase(e)
            %   db = splitEntriesWithMultipleValues(db, 'a', 'b')
            %   e = db.gridData;
            %   e(1).a = 1; e(1).b = 'b1';
            %   e(2).a = 2; e(2).b = 'b2';
            db.warnIfNoArgOut(nargout);

            if isempty(varargin)
                error('Usage: splitEntriesWithMultipleValues(''field1'', ''field2'', ...)');
            end
            if iscell(varargin{1})
                fieldList = varargin{1};
            else    
                fieldList = varargin;
            end
            nFieldsSplit = length(fieldList);

            origGridData = db.origGridData;

            valsByField = cell(nFieldsSplit, db.nEntriesOrig);
            for iFld = 1:length(fieldList)
                valsByField(iFld,:) = db.getValuesOrig(fieldList{iFld}, 'convertNumeric', false);
            end

            iNew = 1;
            for iE = 1:length(origGridData)
                if ~db.mask(iE)
                    % not active, copy over
                    newGridData(iNew) = origGridData(iE);
                    iNew = iNew + 1;
                else
                    % active, check for multiple values
                    nValuesByField = cellfun(@numel, valsByField(:, iE));
                    if any(nValuesByField ~= nValuesByField(1) & nValuesByField > 1)
                        error('Differing value counts found for entry %d', iE);
                    end

                    entry = origGridData(iE); 
                    if nValuesByField == 1
                        newGridData(iNew) = entry;
                        iNew = iNew+1;
                    else
                        % split this entry into nValues copies, each with the ith value
                        % of each field in fieldsList
                        nValues = nValuesByField(1);
                        for iCopy = 1:nValues
                            for iFld = 1:nFieldsSplit
                                if nValuesByField(iFld) == 1
                                    entry.(fieldList{iFld}) = valsByField{iFld, iE}(1);
                                elseif nValuesByField > 1
                                    entry.(fieldList{iFld}) = valsByField{iFld, iE}(iCopy);
                                end
                            end
                            newGridData(iNew) = entry;
                            iNew = iNew + 1;
                        end
                    end
                end
            end

            db.origGridData = makecol(newGridData);
            db = db.invalidateCaches();
        end

        function [db indInOrigTable indInAddedTable] = addEntry(db, entryTable, varargin)
            % adds a new entryTable or entries to the , varargindata store.
            % entryTable must be either a:
            %   struct (array) with each field containing the value for that field
            %   ValueMap : field name -> field values for all added entries
            %
            % for each entry i in the table after the add, if the field values
            % came from table original entry j, then indInOrigTable(i) == j and indInAddedTable(i) == NaN.
            % if the values came from the added table, then indInAddedTable(i) == j and indInOrigTable(j) == NaN

            db.warnIfNoArgOut(nargout);
            db.checkSupportsWrite();

            validateentryTable = @(entryTable) isstruct(entryTable) || ...
                (isscalar(entryTable) && isa(entryTable, 'ValueMap'));

            p = inputParser;
            p.addRequired('entryTable', validateentryTable);

            % if true, checks for exact keyfields matches and overwrites this entries data
            % with the other tables
            p.addParameter('overwriteKeyFieldsMatch', false, @islogical);
            % if true, keeps ONLY rows in other that keyField match with this one.
            % automatically sets overwriteKeyFieldsMatch to true
            p.addParameter('keyFieldMatchesOnly', false, @islogical);
            % run all values through field conversion in order to avoid errors. Set this to false
            % if you know the values are already converted
            p.addParameter('convertValues', true, @islogical);
            p.parse(entryTable, varargin{:});
            overwriteKeyFieldsMatch = p.Results.overwriteKeyFieldsMatch;
            convertValues = p.Results.convertValues;
            keyFieldMatchesOnly = p.Results.keyFieldMatchesOnly;

            if isempty(entryTable)
                indInOrigTable = [];
                indInAddedTable = [];
                return;
            elseif isa(entryTable, 'ValueMap') || isa(entryTable, 'containers.Map')
                S = mapToStructArray(entryTable);
            elseif isstruct(entryTable)
                S = entryTable;
            else
                error('Invalid entryTable in addentryTable');
            end

            S = makecol(S);
            nNewEntries = length(S);
            
            % check for extra fields that will mess this up
            extraFields = setdiff(fieldnames(S), db.fields);
            if ~isempty(extraFields)
                error('Entries to add contain unknown fields: %s', ...
                    strjoin(extraFields));
            end

            % S is now a struct array with values for each field
            % convert each value if requested
            % add missing fields set to field appropriate empty values
            for iField = 1:db.nFields
                field = db.fields{iField};
                dfd = db.fieldDescriptorMap(field);

                if isfield(S, field)
                    if convertValues
                        values = {S.(field)};
                        values = dfd.convertValues(values);
                        S = assignIntoStructArray(S, field, values);
                    end
                else
                    % field is missing
                    % use default empty value for this field
                    values = dfd.getEmptyValue(numel(S));
                    S = assignIntoStructArray(S, field, values);
                end
            end

            % build up list of ind correspondence
            [indInOrigTable, indInAddedTable] = deal(nan(db.nEntries+length(S), 1));
            indInOrigTable(1:db.nEntries) = 1:db.nEntries;
            Sinds = 1:length(S);

            if overwriteKeyFieldsMatch || keyFieldMatchesOnly
                % delete any rows from this table that have key field matches in
                % other that will be overwriting thetu
                overwriteMask = false(db.nEntries, 1);
                hasMatchMask = false(nNewEntries, 1);
                nonKeyFields = setdiff(db.fields, db.keyFields);
                for iEntry = 1:nNewEntries
                    keyFieldEntry = rmfield(S(iEntry), nonKeyFields);
                    idx = makecol(db.matchIdx(keyFieldEntry));
                    if ~isempty(idx)
                        hasMatchMask(iEntry) = true;
                    end
                    overwriteMask(idx) = true;
                end

                % replace the matched entries 
                db = db.subclassReplaceEntry(S(hasMatchMask), overwriteMask);

                if keyFieldMatchesOnly
                    % keyFieldMatchesOnly means we're not adding any unmatched rows
                    % from the new table, so throw the non-matches away
                    S = [];
                    Sinds = [];
                else
                    % add the non-matching ones
                    S = S(~hasMatchMask);
                    Sinds = Sinds(~hasMatchMask);
                end

                % update the correspondence list accordingly
                indInOrigTable(overwriteMask) = NaN;
                indInAddedTable(overwriteMask) = find(hasMatchMask);
            end

            if ~isempty(S)
                indInAddedTable(db.nEntries+ (1:length(S))) = Sinds;
                db = db.subclassAddEntry(S);
            end

            db = db.updateModifiedTimestamp();
            db.pendingApplyEntryMask = true;
            db.pendingApplyEntryData = true;
            db = db.doAutoApply();
        end

        function [db indInOrigTable indInAddedTable] = addEntriesFrom(db, table, varargin)
            % adds all entries from a second table to this one. This function requires
            % that the field set and fieldDescriptors match exactly. If they do
            % not match, see .mergeEntriesWith

            p = inputParser;
            p.addRequired('table', @(t) isa(t, 'DataTable'));
            p.KeepUnmatched = true;
            p.parse(table, varargin{:});
            db.warnIfNoArgOut(nargout);
            db.checkSupportsWrite();

            sameFields = isempty(setxor(db.fields, table.fields)); 
            assert(sameFields, 'Table fields must match exactly');

            for iField = 1:length(db.fields)
                field = db.fields{iField};
                desc = db.fieldDescriptorMap(field);
                descOther = table.fieldDescriptorMap(field);
                assert(isequal(desc, descOther), 'Field descriptors do not match for field %s', field);
            end

            entries = table.getFullEntriesAsStruct();        
            [db indInOrigTable indInAddedTable] = db.addEntry(entries, p.Unmatched);
            db = db.updateModifiedTimestamp();
        end

        function [db indInOrigTable indInAddedTable] = mergeEntriesWith(db, other, varargin)
            % adds all entries from a second table to this one. This function
            % does not require that the field set and fieldDescriptors match exactly. 
            %
            % If fields are missing from a table, they will be added as blank. If
            % a field descriptor does not match, it will be converted to the first
            % table's dfd or to one of the dfds in 'fallbackFieldDescriptors', unless
            % 'convertMismatchedFields' is false, then an error will be thrown.

            db.checkSupportsWrite();
            db.warnIfNoArgOut(nargout);

            p = inputParser;
            p.addRequired('other', @(table) isa(table, 'DataTable'));
            p.addParameter('convertMismatchedFields', true, @islogical); 
            p.addParameter('fallbackFieldDescriptors', {ScalarField(), NumericVectorField(), ...
                StringField(), UnspecifiedField()}, @iscell);
            % if true, checks for exact keyfields matches and overwrites this entries data
            % with the other tables
            p.KeepUnmatched = true;
            p.parse(other, varargin{:});
            convertMismatchedFields = p.Results.convertMismatchedFields;
            fallbackFieldDescriptors = p.Results.fallbackFieldDescriptors;

            fieldsThis = db.fields;
            fieldsOther = other.fields;

            % field in this, not in other
            fieldsMissingOther = setdiff(fieldsThis, fieldsOther);
            for i = 1:length(fieldsMissingOther)
                field = fieldsMissingOther{i};
                dfd = db.fieldDescriptorMap(field);
                other = other.addField(field, [], 'fieldDescriptor', dfd);
            end

            % fields in other, not in db 
            fieldsMissingThis = setdiff(fieldsOther, fieldsThis);
            for i = 1:length(fieldsMissingThis)
                field = fieldsMissingThis{i};
                dfd = other.fieldDescriptorMap(field);
                db = db.addField(field, [], 'fieldDescriptor', dfd);
            end

            % check field descriptors match and convert mismatched to db's dfd
            dfdsMatch = cellfun(@(field) isequal(db.fieldDescriptorMap(field), ...
                other.fieldDescriptorMap(field)), db.fields);
            fieldsToConvert = db.fields(~dfdsMatch);
            valueMapThis = db.getValuesMap(fieldsToConvert);
            valueMapOther = other.getValuesMap(fieldsToConvert);

            if ~convertMismatchedFields && ~isempty(fieldsToConvert)
                error('Field descriptors do not match with convertMismatchedFields=false:\n\t%s', ...
                    strjoin(fieldsToConvert, ', '));
            end

            for i = 1:length(fieldsToConvert)
                field = fieldsToConvert{i}; 
                dfdThis = db.fieldDescriptorMap(field);
                dfdOther = other.fieldDescriptorMap(field);

                if dfdThis.canDescribeValues(valueMapOther(field))
                    % convert to dfdThis
                    other = other.setFieldDescriptor(field, dfdThis);
                    debug('Converting field %s to %s to match first table\n', field, dfdThis.describe());
                else
                    dfdToTry = fallbackFieldDescriptors; 
                    for iTry = 1:length(dfdToTry)
                        dfd = dfdToTry{iTry};
                        if dfd.canDescribeValues(valueMapOther(field)) && ...
                                dfd.canDescribeValues(valueMapThis(field))

                            other = other.setFieldDescriptor(field, dfd);
                            db = db.setFieldDescriptor(field, dfd);
                            debug('Converted field %s to %s IN BOTH TABLES\n', field, dfd.describe());

                            successful = true;
                            break;
                        end
                    end

                    if ~successful
                        error('Could not convert field %s to any in fallbackFieldDescriptors list');
                    end
                end
            end

            % and defer to addEntriesFrom to do the heavy lifting
            [db indInOrigTable indInAddedTable] = db.addEntriesFrom(other, p.Unmatched);
        end

        function dt = setFieldValue(dt, idx, field, value)
            dt.warnIfNoArgOut(nargout);
            dt.checkSupportsWrite();

            assert(isscalar(idx) && isnumeric(idx) && idx > 0 && idx <= dt.nEntries, ...
                'Index invalid or out of range [0 nEntries]');
            %dt.assertIsField(field);

            dfd = dt.getFieldDescriptor(field);
            value = dfd.convertValues(value);

            if isempty(value)
                value = dfd.getEmptyValue();
            end

            if ~dfd.matrix && ~isempty(value) && iscell(value)
                % if it's a matrix, this should be a cell array
                value = value{1};
            end

            dt = dt.subclassSetFieldValue(idx, field, value);
            dt = dt.updateModifiedTimestamp();
        end

        function dt = updateEntry(dt, idx, entry)
            dt.warnIfNoArgOut(nargout);
            dt.checkSupportsWrite();

            if isa(entry, 'DataTable')
                entry = entry.getFullEntriesAsStruct();
            end
            
            assert(length(entry) == 1, 'Currently only supported for single entries');
            assert(isscalar(idx) && isnumeric(idx) && idx > 0 && idx <= dt.nEntries, ...
                'Index invalid or out of range [0 nEntries]');

            fields = intersect(dt.fields, fieldnames(entry));
            for field = fields 
                dt = dt.setFieldValue(idx, field{1}, entry.(fields{1}));
            end
        end
    end

    methods % Filtering and grouping (OLD)
        function db = groupBy(db, varargin)
            error('Not Supported');
            db.warnIfNoArgOut(nargout);

            % db = groupBy('field1', 'field2', ...)
            % set the current group by field to the list of input fields
            % groupBy overwrites the current grouping, unlike filters
            if isempty(varargin)
                db.groupByFields = {};
            elseif iscell(varargin{1})
                db.groupByFields = varargin{1};
            else
                db.groupByFields = varargin;
            end

            db = db.invalidateCaches('cachedGroups');
        end

        function groups = get.groups(db)
            error('Not Supported');
            if ~isempty(db.cachedGroups)
                groups = db.cachedGroups;
            else
                if isempty(db.groupByFields)
                    groups = db;
                else
                    [idxIntoUniqueByField uniqueValsByField] = ...
                        db.getGridDataAsIdxIntoUnique('fields', db.groupByFields, ...
                        'asMatrix', true);
                    uniqueIdxIntoUnique = unique(idxIntoUniqueByField, 'rows');

                    nGroups = size(uniqueIdxIntoUnique, 1);
                    for iGrp = 1:nGroups
                        for iFld = 1:length(db.groupByFields)
                            fld = db.groupByFields{iFld};
                            values = uniqueValsByField{iFld}(uniqueIdxIntoUnique(iGrp, iFld));
                            filters.(fld) = values;
                        end
                        groups(iGrp) = db.filterBy(filters);
                        for iFld = 1:length(db.groupByFields)
                            values = filters.(fld);
                            if iscell(values) && length(values) == 1
                                groups(iGrp).groupCommon.(fld) = values{1}; 
                            else
                                groups(iGrp).groupCommon.(fld) = values;
                            end
                        end
                    end
                end
            end
        end
    end

    methods(Access=protected) % utility function for mapping
        function [resultStruct status] = mapEachWrapperFn(db, fn, catchErrors)
            results = cell(db.nEntries, 1);
            status = repmat(struct('success', false, 'exception', []), db.nEntries, 1);

            % textprogressbar('Running on each entry');
            for iEntry = 1:db.nEntries
                %textprogressbar(iEntry / db.nEntries);
                try
                    results{iEntry} = fn(db.select(iEntry), iEntry);
                    status(iEntry).success = true;
                catch exc
                    status(iEntry).success = false;
                    status(iEntry).exception = exc;
                    if ~catchErrors
                        rethrow(exc);
                    else
                        debug('Exception caught:\n');
                        tcprintf('bright yellow', exc.getReport());
                        fprintf('\n');
                    end
                end
            end
            %   textprogressbar('done', true);

            resultStruct = structcat(results);
        end
    end

    methods % Iterating, mapping
        function resultTable = keyFieldsTable(db, varargin)
            db.warnIfNoArgOut(nargout);
            resultTable = db.keepFields(db.keyFields);
        end

        function [resultTable status] = map(db, fn, varargin)
            % map(fn) : calls function handle fn on each entry in table and wraps 
            % a DataTable around the results with the appropriate key fields added from
            % this table
            %
            % fn should have the following signature:
            %   [resultStruct status] = fn(dataTable, entryIndex)
            p = inputParser;
            p.KeepUnmatched = true;
            p.addParameter('catchErrors', true, @islogical); 
            p.parse(varargin{:});
            catchErrors = p.Results.catchErrors;

            [resultTable status] = db.mapOneCall(@(db) db.mapEachWrapperFn(fn, catchErrors), p.Unmatched);
        end

        function [resultTable status] = mapThrowErrors(db, fn, varargin)
            % map(fn) : calls function handle fn on each entry in table and wraps 
            [resultTable status] = map(db, fn, 'catchErrors', false, varargin{:});
        end

        function [resultTable status] = mapOneCall(db, fn, varargin)
            % map(fn) : calls function handle fn once for the entire table and wraps 
            % a DataTable around the results with the appropriate key fields added from
            % this table
            %
            % fn should have the following signature:
            %   [resultStruct status] = fn(dataTable)
            %
            % dataTable will be a copy of this dataTable 
            % This format enables easy related reference lookups via the 
            % database, as opposed to simply passing a struct with the entry fields
            %
            % resultStruct is a vector struct array with length nEntries containing the
            % results of the analysis. 
            %
            % status will be a struct array of length nEntries with fields:
            %   success : logical if the function succeeded
            %   exception : the exception which was caught
            %
            % resultTable will be a DataTable instance where the fields and values
            % of resultsStruct have been merged with the keyfields from this DataTable
            %
            % Optional params:
            %   addToDatabase : default false. If true, this result table will
            %       be stored in the database with entryName as provided, and a 
            %       1 to 1 relationship will be created.
            %   entryName : entry name to create resultTable with, by default
            %       will be set to 'result'. Not optional if
            %       addToDatabase == true
            %   entryNamePlural : entry name plural for resultTable
            %

            p = inputParser;
            p.addRequired('fn', @(fn) isa(fn, 'function_handle'));
            p.addParameter('addToDatabase', false, @(tf) islogical(tf) && isscalar(tf));
            p.addParameter('entryName', '', @ischar);
            p.addParameter('entryNamePlural', '', @ischar);
            p.parse(fn, varargin{:});

            addToDatabase = p.Results.addToDatabase;
            entryName = p.Results.entryName;
            entryNamePlural = p.Results.entryNamePlural;

            if addToDatabase
                db.checkHasDatabase();
                if isempty(entryName)
                    error('Must specify param/value entryName when addToDatabase==true');
                end
            else
                if isempty(entryName)
                    entryName = 'result';
                end
            end
            if isempty(entryNamePlural) 
                entryNamePlural = [entryName 's'];
            end

            % concatenate the results together
            [resultStruct status] = fn(db);

            % auto convert map to struct array
            if isa(resultStruct, 'ValueMap')
                resultStruct = mapToStructArray(resultStruct);
            end

            if isempty(resultStruct)
                resultStruct = struct([]);
            end

            % merge in the key fields into the struct array
            resultFields = makecol(fieldnames(resultStruct));
            if ~isempty(intersect(resultFields, db.keyFields))
                warning('Overriding some fields in results with key field values');
            end

            keyFieldMap = db.getValuesMap(db.keyFields);
            for iKeyField = 1:length(keyFieldMap)
                fld = db.keyFields{iKeyField};
                values = keyFieldMap(fld);
                resultStruct = assignIntoStructArray(resultStruct, fld, values);
            end

            % put keyFields first
            if ~isempty(intersect(db.keyFields, resultFields))
                error('Map function has defined fields which overlap with this table''s keyFields');
            end
            resultStruct = orderfields(resultStruct, [db.keyFields; resultFields]);

            % create resultTable
            resultTable = StructTable(resultStruct, 'entryName', entryName, ...
                'entryNamePlural', entryNamePlural);
            resultTable.keyFields = db.keyFields;

            % copy the keyFields' fieldDescriptors over for consistency
            dfdMap = db.fieldDescriptorMap;
            for iKeyField = 1:length(keyFieldMap)
                fld = db.keyFields{iKeyField};
                dfd = dfdMap(fld);
                resultTable = resultTable.setFieldDescriptor(fld, dfd);
            end

            if addToDatabase
                resultTable = db.database.addTable(resultTable);
                db.database.addRelationshipOneToOne(db.entryName, resultTable.entryName);
            end

        end

        function db = mapToField(db, fn, field)
            % db = db.mapToField(fn, field);
            % calls fn on each entry (e.g. fn(db(i))) and stores the result (first
            % output argument) in a new field
            db.warnIfNoArgOut(nargout);
            db.checkSupportsWrite();

            results = cell(db.nEntries, 1);
            for iEntry = 1:db.nEntries
                results{iEntry} = fn(db.select(iEntry));
            end

            db = db.addField(field, results);
        end
    end

    methods % Database methods
        function checkHasDatabase(db)
            assert(~isempty(db.database), 'This DataTable is not linked to a Database');
        end

        function db = setDatabase(db, database)
            db.warnIfNoArgOut(nargout);
            assert(nargin == 2 && isa(database, 'Database'), 'Must provide a Database instance');
            db.database = database;
        end

        function db = setEntryName(db, entryName, entryNamePlural)
            % WARNING!!: setting the entryName can disrupt database relationships
            db.warnIfNoArgOut(nargout);
            db.entryName = entryName;
            if nargin < 3
                entryNamePlural = [entryName 's'];
            end
            db.entryNamePlural = entryNamePlural;
        end

        function db = setKeyFields(db, keyFields)
            db.warnIfNoArgOut(nargout);
            if ischar(keyFields)
                keyFields = {keyFields};
            end
            assert(iscellstr(keyFields), 'Must be cell array of field names'); 
            db.assertIsField(keyFields);
            db.keyFields = makecol(keyFields);
        end

        function tf = isKeyField(db, field)
            tf = ismember(field, db.keyFields);
        end

        % return a unique string for each entry that combines the values of each
        % keyField, i.e. 'keyField1value1.keyField2value2'
        function strCell = getKeyFieldValueDescriptors(db)
            fields = db.keyFields;
            nFields = length(fields);

            strCell = cell(db.nEntries, 1);

            values = mapToStructArray(db.getKeyFieldMapAsFilenameStrings(fields));
            fieldValueStrings = cell(nFields, 1);
            for iEntry = 1:db.nEntries
                for iField = 1:nFields
                    field = fields{iField};
                    fieldValueStrings{iField} = sprintf('%s_%s', ...
                        field, values(iEntry).(field));
                end
                strCell{iEntry} = strjoin(fieldValueStrings, '.');
            end
        end

        function refs = get.relationshipReferences(db)
            if isempty(db.database)
                refs = {};
            else
                refs = db.database.listRelationshipsWith(db.entryName);
            end
        end
        
        function [referenceNames, refIdx, relationships] = listRelationships(db)
            if isempty(db.database)
                referenceNames = {};
                refIdx = [];
                relationships = [];
            else
                [referenceNames, refIdx, relationships] = db.database.listRelationshipsWith(db.entryName);
            end
        end

        function tf = isReference(db, name)
            tf = ismember(name, db.relationshipReferences);
        end
        
        function names = getReferenceNames(db)
            % list all relationships in the database that this table can access via
            db.checkHasDatabase();
            names = db.database.listRelationshipsWith(db.entryName);
        end

        function count = getRelatedCount(db, entryName, varargin)
            db.checkHasDatabase();
            relatedCell = db.getRelatedIdx(entryName, 'combine', false, 'fillMissingWithNaN', false);
            count = makecol(cellfun(@numel, relatedCell));
        end
        
        function tab = getRelatedCountTable(db, entryName, varargin)
            tab = db.keyFieldsTable.addFieldWithRelatedCount(entryName, varargin{:});
        end
        
        function db = addFieldWithRelatedCount(db, entryName, varargin)
            
            p = inputParser();
            p.addParameter('as', '', @(x) ischar(x) || iscellstr(x));
            p.KeepUnmatched = true;
            p.parse(varargin{:});
           
            if ischar(entryName)
                entryName = {entryName};
            end
            as = p.Results.as;
            if isempty(as)
                as = cellfun(@(fld) sprintf('num_%s', fld), entryName, 'UniformOutput', false);
            elseif ischar(as)
                as = {as};
            end
            
            for i = 1:numel(entryName)
                counts = db.getRelatedCount(entryName{i});
                db = db.addField(as{i}, counts);
            end
        end
        
        function [db, mask] = filterHasRelated(db, entryName)
            db.warnIfNoArgOut(nargout);
            mask = db.getRelatedCount(entryName) > 0;
            db = db.select(mask);
        end

        function match = getRelated(db, entryName, varargin)
            % one param value useful is combine = true/false
            db.checkHasDatabase();
            match = db.database.matchRelated(db, entryName, varargin{:});
        end
        
        function matchIdx = getRelatedIdx(db, entryName, varargin)
            db.checkHasDatabase();
            matchIdx = db.database.getRelatedIdx(db, entryName, varargin{:});
        end

        % update the table stored in the database with this version of it,
        % thereby making any filtering done here also affect database queries
        % from related tables
        function db = updateInDatabase(db, varargin)
            db.database.updateTable(db, varargin{:});
        end
    end

    methods(Access=protected) % Caching
        function timestamp = getLastUpdated(obj)
            timestamp = obj.modifiedTimestamp;
        end
    end

    methods % Caching
        % return a datenum style timestamp that indicates when this table's data
        % was last altered. This is used by the caching framework and with 
        % DatabaseAnalyses to know when to rerun analyses by invalidating the cache
        % Subclasses may wish to override this function
        function ts = get.lastUpdated(obj)
            ts = obj.getLastUpdated();
        end

        % return the cacheName to be used when instance 
        function name = getCacheName(obj)
            name = obj.entryName;
        end

        % return the param to be used when caching
        function param = getCacheParam(obj) 
            param = [];
        end

        function obj = updateModifiedTimestamp(obj)
            obj.warnIfNoArgOut(nargout);
            obj.modifiedTimestamp = now;
        end
    end

    methods % Utility methods
        function warnIfNoArgOut(db, nargOut)
            if nargOut == 0
                message = sprintf('%s is not a handle class. If the instance handle returned by this method is not stored, this call has no effect.\\n', ...
                    class(db));
                warning(message);
            end
        end
    end
end
