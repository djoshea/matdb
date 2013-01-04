classdef DataRelationship < matlab.mixin.Copyable & handle

    properties(SetAccess = protected)
        % each of these is a 2x1 cell array, one element for each of the two tables
        % joined by this relationship
        isMany = false(2,1);
        keyFields = {{}; {}};

        % keyFieldsLeft as known in right, keyFieldsRight as known in left
        keyFieldsReference = {{}; {}};

        % entryNames is the .entryName for the table on the {left, right} side
        % it is used simply for locating relationships involving a particular
        % database table by entryName
        entryNames = cell(2,1); 
        % entryNamesPlural is the .entryNamePlural for the table on the {left, right} side
        % it is simply used for locating relatinoships involving a particular
        % database table by entryNamePlural
        entryNamesPlural = cell(2,1);

        referenceNames = cell(2, 1);
    end

    properties 
        entryNameJunction = '';
        entryNameJunctionPlural = '';
    end

    properties(Dependent)
        keyFieldsLeft
        keyFieldsRight
        keyFieldsLeftInRight
        keyFieldsRightInLeft
        entryNameLeft
        entryNameRight
        entryNamePluralLeft
        entryNamePluralRight
        referenceLeftForRight
        referenceRightForLeft
        isManyLeft
        isManyRight

        isJunction 
        isOneToOne
    end

    methods % Dependent property implementations
        function name = get.entryNameLeft(rel)
            name = rel.entryNames{1};
        end

        function set.entryNameLeft(rel, name)
            assert(ischar(name));
            rel.entryNames{1} = name;
        end

        function name = get.entryNameRight(rel)
            name = rel.entryNames{2};
        end

        function set.entryNameRight(rel, name)
            assert(ischar(name));
            rel.entryNames{2} = name;
        end

        function name = get.entryNamePluralLeft(rel)
            name = rel.entryNamesPlural{1};
        end

        function set.entryNamePluralLeft(rel, name)
            rel.entryNamesPlural{r} = name;
        end

        function name = get.entryNamePluralRight(rel)
            name = rel.entryNamesPlural{2};
        end

        function set.entryNamePluralRight(rel, name)
            rel.entryNamesPlural{2} = name;
        end

        function tf = get.isManyLeft(rel)
            tf = rel.isMany(1);
        end

        function set.isManyLeft(rel, tf)
            assert(isscalar(tf) && islogical(tf));
            rel.isMany(1) = tf;
        end

        function tf = get.isManyRight(rel)
            tf = rel.isMany(2);
        end

        function set.isManyRight(rel, tf)
            assert(isscalar(tf) && islogical(tf));
            rel.isMany(2) = tf;
        end

        function name = get.referenceLeftForRight(rel)
            name = rel.referenceNames{1};
        end

        function set.referenceLeftForRight(rel, name)
            rel.referenceNames{1} = name;
        end

        function name = get.referenceRightForLeft(rel)
            name = rel.referenceNames{2};
        end
        
        function set.referenceRightForLeft(rel, name)
            rel.referenceNames{2} = name;
        end

        function fields = get.keyFieldsLeft(rel)
            fields = rel.keyFields{1};
        end

        function set.keyFieldsLeft(rel, fields)
            rel.keyFields{1} = fields;
        end

        function fields = get.keyFieldsRight(rel)
            fields = rel.keyFields{2};
        end

        function set.keyFieldsRight(rel, fields)
            rel.keyFields{2} = fields;
        end

        function fields = get.keyFieldsLeftInRight(rel)
            fields = rel.keyFieldsReference{1};
        end

        function set.keyFieldsLeftInRight(rel, fields)
            rel.keyFieldsReference{1} = fields;
        end

        function fields = get.keyFieldsRightInLeft(rel)
            fields = rel.keyFieldsReference{2};
        end

        function set.keyFieldsRightInLeft(rel, fields)
            rel.keyFieldsReference{2} = fields;
        end

        function tf = get.isJunction(rel)
            tf = rel.isManyLeft && rel.isManyRight;
        end

        function tf = get.isOneToOne(rel)
            tf = ~rel.isManyLeft && ~rel.isManyRight;
        end
    end

    methods % Constructor, Swap-Left-Right and description
        function rel = DataRelationship(varargin)
            p = inputParser;
            p.addParamValue('tableLeft', [], @(t) isa(t, 'DataTable'));
            p.addParamValue('tableRight', [], @(t) isa(t, 'DataTable'));
            p.addParamValue('tableJunction', [], @(t) isa(t, 'DataTable'));
            p.addParamValue('referenceLeftForRight', [], @iscellstr); 
            p.addParamValue('referenceRightForLeft', [], @iscellstr); 
            p.addParamValue('keyFieldsLeft', [], @iscellstr); 
            p.addParamValue('keyFieldsLeftInRight', [], @iscellstr); 
            p.addParamValue('keyFieldsRight', [], @iscellstr); 
            p.addParamValue('keyFieldsRightInLeft', [], @iscellstr); 
            p.addParamValue('isManyLeft', false, @(t) islogical(t) && isscalar(t));
            p.addParamValue('isManyRight', false, @(t) islogical(t) && isscalar(t));
            p.parse(varargin{:});

            tableLeft = p.Results.tableLeft;
            tableRight = p.Results.tableRight;
            if ~ismember('tableLeft', p.UsingDefaults)
                rel.setTableLeft(tableLeft);
            end
            if ~ismember('tableRight', p.UsingDefaults)
                rel.setTableRight(tableRight);
            end

            tableJunction = p.Results.tableJunction;
            if ~ismember('tableJunction', p.UsingDefaults)
                rel.entryNameJunction = tableJunction.entryName;
                rel.entryNameJunctionPlural = tableJunction.entryNamePlural;
            end

            rel.isManyLeft = p.Results.isManyLeft; 
            rel.isManyRight = p.Results.isManyRight;

            % defaults (table.keyFields) already handled by setTable
            if ~ismember('keyFieldsLeft', p.UsingDefaults)
                rel.keyFieldsLeft = p.Results.keyFieldsLeft;
            end
            if ~ismember('keyFieldsRight', p.UsingDefaults)
                rel.keyFieldsRight = p.Results.keyFieldsRight;
            end

            % handle keyFieldReference names
            % These are not just for convenience, they indicate how to join the 
            % tables together, either directly or thru an intermediary junction
            % table
            %
            % If keyFieldsLeftInRight or RightInLeft is explicitly specified,
            %   then they will be used as is
            %
            % If a name is not explicitly specified, we will either
            %   Leave it empty if this is the one side of a one to many 
            %     relationship, as the many side should contain the keyFields 
            %   -or-
            %   Generate a default name by camelCasing the table entryName
            %   onto each keyfield name. E.g. for table.entryName = 'teacher'
            %   and table.keyFields = 'id', the other table or junction table
            %   would refer to this as 'teacherId'
            %   
            if ismember('keyFieldsLeftInRight', p.UsingDefaults)
                % not explicitly specified
                if ~rel.isManyRight && rel.isManyLeft
                    % one side of one to many relationship, leave it blank
                    rel.keyFieldsLeftInRight = {};
                else
                    % generate default field names based on the fields that exist
                    % in the left table
                    if rel.isJunction
                        rel.keyFieldsLeftInRight = DataRelationship.defaultFieldReference(...
                            tableJunction, tableLeft);
                    else
                        rel.keyFieldsLeftInRight = DataRelationship.defaultFieldReference(...
                            tableRight, tableLeft);
                    end
                end
            else
                % explicitly specified
                rel.keyFieldsLeftInRight = p.Results.keyFieldsLeftInRight;
            end

            if ismember('keyFieldsRightInLeft', p.UsingDefaults)
                % not explicitly specified
                if ~rel.isManyLeft && rel.isManyRight
                    % one side of one to many relationship, leave it blank
                    rel.keyFieldsRightInLeft = {};
                else
                    % generate default field names based on the fields that exist
                    % in the left table
                    if rel.isJunction
                        rel.keyFieldsRightInLeft = DataRelationship.defaultFieldReference(...
                            tableJunction, tableRight);
                    else
                        rel.keyFieldsRightInLeft = DataRelationship.defaultFieldReference(...
                            tableLeft, tableRight);
                    end
                end
            else
                % explicitly specified
                rel.keyFieldsRightInLeft = p.Results.keyFieldsRightInLeft;
            end
            % however, check that these fields exist in the corresponding table
            % and if not remove them
            % this also automatically handles 1-1 relationships, for which
            % only one table may have a pointer to the other
            if ~isempty(rel.keyFieldsRightInLeft)
                if rel.isJunction && ~isempty(tableJunction)
                    if ~all(tableJunction.isField(rel.keyFieldsRightInLeft))
                        rel.keyFieldsRightInLeft = {};
                    end
                elseif ~rel.isJunction && ~isempty(tableLeft)
                    if ~all(tableLeft.isField(rel.keyFieldsRightInLeft))
                        rel.keyFieldsRightInLeft = {};
                    end
                end
            end
            
            % Reference names are the name by which we refer to a particular
            % relationship from the originating class
            %
            % Use explicitly specified reference names if provided,
            % otherwise use the relevant singular/plural entryName in the other 
            % table
            if ~ismember('referenceLeftForRight', p.UsingDefaults)
                rel.referenceLeftForRight = p.Results.referenceLeftForRight;
            elseif ~isempty(tableRight)
                if rel.isManyRight
                    rel.referenceLeftForRight = tableRight.entryNamePlural;
                else
                    rel.referenceLeftForRight = tableRight.entryName;
                end
            end

            if ~ismember('referenceRightForLeft', p.UsingDefaults)
                rel.referenceRightForLeft = p.Results.referenceRightForLeft;
            elseif ~isempty(tableLeft)
                if rel.isManyLeft
                    rel.referenceRightForLeft = tableLeft.entryNamePlural;
                else
                    rel.referenceRightForLeft = tableLeft.entryName;
                end
            end
        end

        function str = describeLink(rel)
            if rel.isManyLeft
                numLeft = 'Many';
            else
                numLeft = 'One';
            end
            if rel.isManyRight
                numRight = 'Many';
            else
                numRight = 'One';
            end

            if rel.isJunction
                connector = sprintf('<- %s ->', rel.entryNameJunctionPlural); 
            elseif ~isempty(rel.keyFieldsLeftInRight)
                if ~isempty(rel.keyFieldsRightInLeft) 
                    % redundant key fields on both sides?
                    connector = '<->';
                else
                    % right table stores key to left table
                    connector = '<-';
                end
            else
                if ~isempty(rel.keyFieldsRightInLeft) 
                    % left table stores key to right table
                    connector = '<->';
                else
                    % keyFieldsReference is empty: this isn't going to work!
                    connector = '-???-';
                end
            end

            if rel.isManyLeft
                nameLeft = rel.entryNamePluralLeft;
            else
                nameLeft = rel.entryNameLeft;
            end
            if rel.isManyRight
                nameRight = rel.entryNamePluralRight;
            else
                nameRight = rel.entryNameRight;
            end

            str = sprintf('%s %s %s %s %s', numLeft, nameLeft, connector, ...
                numRight, nameRight); 
        end

        function str = describeKeyFields(rel)
            str = '';
            colWidth = 20;
            for iField = 1:length(rel.keyFieldsLeftInRight)
                if rel.isJunction
                    rightName = rel.entryNameJunction;
                else
                    rightName = rel.entryNameRight;
                end
                leftWidth = colWidth;
                rightWidth = colWidth;
                leftField = sprintf('%s.%s', rel.entryNameLeft, rel.keyFieldsLeft{iField});
                rightField = sprintf('%s.%s', rightName, rel.keyFieldsLeftInRight{iField});

                desc = sprintf('%*s == %s\n', leftWidth, leftField, rightField);
                str = [str desc];
            end

            % the links pointing in the other direction are unnecessary if
            % one to one relationship (for other relationship types, one of
            % the two keyFieldsAinB is empty, whereas they are both
            % occupied symmetrically for one to one).
            if rel.isManyLeft || rel.isManyRight
                for iField = 1:length(rel.keyFieldsRightInLeft)
                    if rel.isJunction
                        leftName = rel.entryNameJunction;
                    else
                        leftName = rel.entryNameLeft;
                    end
                    leftWidth = colWidth;
                    leftField = sprintf('%s.%s', leftName, rel.keyFieldsRightInLeft{iField});
                    rightField = sprintf('%s.%s', rel.entryNameRight, rel.keyFieldsRight{iField});

                    desc = sprintf('%*s == %s\n', leftWidth, leftField, rightField);
                    str = [str desc];
                end
            end
        end

        function str = describe(rel)
            str = sprintf('DataRelationship : %s\n%s', rel.describeLink(), rel.describeKeyFields());
        end

        function disp(rel)
            fprintf('%s\n\n', rel.describe());
        end

        function rel = swapCopy(rel)
            % perform shallow copy
            rel = rel.copy();
            swap = [2 1];

            rel.isMany = rel.isMany(swap);
            rel.keyFields = rel.keyFields(swap);
            rel.keyFieldsReference = rel.keyFieldsReference(swap); 
            rel.entryNames = rel.entryNames(swap); 
            rel.entryNamesPlural = rel.entryNamesPlural(swap);
            rel.referenceNames = rel.referenceNames(swap);
        end
    end

    methods(Access=protected) % Internal .setTable accessor
        function setTable(rel, ind, varargin)
            % sets the properties of one side of this table-to-table relationship
            % this is an internal method, you will want setTable1 or setTable2 
            % ind : either 1 or 2, i.e. set the properties of the left side or
            %   right side of the relationship
            % isMany : boolean, indicating whether this side of the relationship
            %   refers to multiple entries rather than a single entry
            % keyFields : the set of fields that uniquely identify an entry in
            %   this table when joining to the other table
            % entryName, entryNamePlural : the string that describes the table
            %   from which this relationship derives

            p = inputParser;
            p.addRequired('ind', @(x) validateattributes(x, {'numeric'}, ...
                {'scalar', 'nonempty', '>=', 1, '<=', 2}));
            p.addOptional('table', [], @(t) isa(t, 'DataTable'));
            p.addParamValue('isMany', false, @islogical);
            p.addParamValue('keyFields', {}, @iscellstr);
            p.addParamValue('entryName', '', @isvarname);
            p.addParamValue('entryNamePlural', '', @isvarname);
            p.parse(ind, varargin{:});

            table = p.Results.table;

            if isempty(p.Results.isMany)
                error('Property isMany not specified');
            else
                rel.isMany(ind) = p.Results.isMany;
            end

            if isempty(p.Results.keyFields)
                if isempty(table)
                    error('Property keyFields not specified');
                else
                    rel.keyFields{ind} = table.keyFields;
                end
            else
                rel.keyFields{ind} = p.Results.keyFields;
            end


            if isempty(p.Results.entryName)
                if isempty(table)
                    error('Property entryName not specified');
                else
                    rel.entryNames{ind} = table.entryName;
                end
            else
                rel.entryNames{ind} = p.Results.entryName;
            end

            if isempty(p.Results.entryNamePlural)
                if isempty(table)
                    error('Property entryNamePlural not specified');
                else
                    rel.entryNamesPlural{ind} = table.entryNamePlural;
                end
            else
                db.entryNamesPlural{ind} = p.Results.entryNamePlural;
            end
        end
    end

    methods % Accessor methods
        function setTableLeft(rel, varargin)
            rel.setTable(1, varargin{:});
        end

        function setTableRight(rel, varargin)
            rel.setTable(2, varargin{:});
        end

        function [tf referenceName] = involvesEntryName(rel, entryName)
            idx = rel.mapEntryNameToIdx(entryName); 
            tf = ~isempty(idx);
            if tf
                referenceName = rel.referenceNames{idx};
            else
                referenceName = '';
            end
        end
    end

    methods % Matching methods for looking up across reference
        function idx = mapEntryNameToIdx(rel, entryName)
            idxS = find(strcmp(entryName, rel.entryNames), 1, 'first');
            idxP = find(strcmp(entryName, rel.entryNamesPlural), 1, 'first');
            idx = unique([idxS idxP]);
        end

        function [tf leftToRight] = matchesEntryNameAndReference(rel, entryName, referenceName)
            % check whether this relationship involves an entryName(Plural) which
            % refers to referenceName, either left to right or right to left
            if ismember(entryName, [rel.entryNames(1) rel.entryNamesPlural(1)]) && ...
                    strcmp(referenceName, rel.referenceNames{1})
                tf = true;
                leftToRight = true;
            elseif ismember(entryName, [rel.entryNames(2) rel.entryNamesPlural(2)]) && ...
                    strcmp(referenceName, rel.referenceNames{2})
                tf = true;
                leftToRight = false;
            else
                tf = false;
                leftToRight = [];
            end
        end

        function assertInvolvesEntryName(rel, entryName)
            assert(rel.involvesEntryName(entryName), 'This DataRelationship does not involve entryName %s', entryName);
        end

        function checkFields(rel, tableLeft, tableRight, tableJunction)
            if rel.isJunction
                assert(nargin == 4, 'Usage: checkFields(tableLeft, tableRight, tableJunction) for Many-Many');
            else
                assert(nargin == 3, 'Usage: checkFields(tableLeft, tableRight) for non Many-Many');
            end
            % check that all fields referenced by this relationship actually exist
            
            % check key Fields
            assert(~isempty(rel.keyFieldsLeft), 'No left key fields specified');
            tableLeft.assertIsField(rel.keyFieldsLeft);
            assert(~isempty(rel.keyFieldsRight), 'No right key fields specified');
            tableRight.assertIsField(rel.keyFieldsRight);
            
            % check that sufficient key field references exist
            if rel.isManyLeft 
                assert(~isempty(rel.keyFieldsRightInLeft), 'Must specify keyFieldsRightInLeft');
            end
            if rel.isManyRight
                assert(~isempty(rel.keyFieldsLeftInRight), 'Must specify keyFieldsLeftInRight');
            end
            if rel.isOneToOne
                assert(~isempty(rel.keyFieldsLeftInRight) || ~isempty(rel.keyFieldsRightInLeft), ...
                    'Must specify either keyFieldsLeftInRight or keyFieldsRightInLeft');
            end

            % check key fields right in left
            if rel.isJunction
                tableCheck = tableJunction;
            else
                tableCheck = tableLeft;
            end
            tableCheck.assertIsField(rel.keyFieldsRightInLeft);

            % check key fields left in right 
            if rel.isJunction
                tableCheck = tableJunction;
            else
                tableCheck = tableRight;
            end
            tableCheck.assertIsField(rel.keyFieldsLeftInRight);
        end

        function result = matchLeftInRight(rel, tableLeft, tableRight, varargin)
            % given a data table corresponding to the left table and right table
            % in this relationship, return either:
            % if parameter 'combine', false is passed (default)
            %     a cell array of cells which each contains a DataTable
            %     listing entries in the right table which match each entry in the left table

            p = inputParser;
            p.addRequired('tableLeft', @(x) isa(x, 'DataTable'));
            p.addRequired('tableRight', @(x) isa(x, 'DataTable'));
            p.addParamValue('tableJunction', [], @(x) isa(x, 'DataTable')); 
            p.addParamValue('combine', true, @islogical);
            p.parse(tableLeft, tableRight, varargin{:});

            tableJunction = p.Results.tableJunction;
            combine = p.Results.combine;
            
            % check entry names match
            assert(strcmp(tableLeft.entryName, rel.entryNameLeft));
            assert(strcmp(tableRight.entryName, rel.entryNameRight));

            keyFieldsLeftInRight = rel.keyFieldsLeftInRight;
            keyFieldsRightInLeft = rel.keyFieldsRightInLeft;

            nEntriesLeft = tableLeft.nEntries;
            nEntriesRight = tableRight.nEntries;

            keyFieldsLeft = rel.keyFieldsLeft;
            keyFieldsRight = rel.keyFieldsRight;
            nKeyFieldsRight = length(keyFieldsRight);
            nKeyFieldsLeft = length(keyFieldsLeft);
            
            entriesLeft = tableLeft.getEntriesAsStruct(true(nEntriesLeft, 1), rel.keyFieldsLeft);

            if combine
                matchIdx = [];
            else
                matchTableCell = cell(nEntriesLeft, 1);
            end

            if rel.isJunction
                %debug('Performing junction table lookup\n');
                assert(exist('tableJunction', 'var') > 0, 'tableJunction argument required');
                entriesJunction = tableJunction.entries;
               
                % preload the fieldNames for .match(args{:} for tableJunction and tableRight
                matchFilterArgsJunction = DataRelationship.fillCellOddEntries(keyFieldsLeftInRight);
                matchFilterArgsRight = DataRelationship.fillCellOddEntries(keyFieldsRight);

                for iEntryLeft = 1:nEntriesLeft
                    % find matches for this left entry in junction table
                    for iField = 1:nKeyFieldsLeft
                        matchFilterArgsJunction{2*iField} = ...
                            entriesLeft(iEntryLeft).(keyFieldsLeft{iField});
                    end
                    junctionMatchIdx{iEntryLeft} = ...
                        tableJunction.matchIdx(matchFilterArgsJunction{:});
                end

                for iEntryLeft = 1:nEntriesLeft
                    % for each junction match, find the corresponding row idx in tableRight
                    rightMatchIdx = [];
                    junctionMatchIdxThisLeft = junctionMatchIdx{iEntryLeft};
                    for iMatch = 1:length(junctionMatchIdxThisLeft)
                        match = junctionMatchIdxThisLeft(iMatch);
                        for iField = 1:nKeyFieldsRight
                            matchFilterArgsRight{2*iField} = ...
                                entriesJunction(match).(keyFieldsRightInLeft{iField});
                        end
                        rightMatchIdx = [rightMatchIdx; tableRight.matchIdx(matchFilterArgsRight{:})];
                    end

                    if combine
                        matchIdx = [matchIdx; rightMatchIdx];
                    else
                        % now filter tableRight by these idx
                        matchTableCell{iEntryLeft} = tableRight.select(rightMatchIdx);
                    end
                end
                
            elseif ~isempty(keyFieldsLeftInRight)
                % key fields lie within right, so we can loop through and search directly
                % this is essentially a reverse lookup
                %debug('Performing reverse key lookup\n');
                matchFilterArgs = DataRelationship.fillCellOddEntries(keyFieldsLeftInRight);

                for iEntryLeft = 1:nEntriesLeft
                    for iField = 1:nKeyFieldsLeft
                        matchFilterArgs{2*iField} = entriesLeft(iEntryLeft).(keyFieldsLeft{iField});
                    end
                    if combine 
                        matchIdx = [matchIdx; tableRight.matchIdx(matchFilterArgs{:})];
                    else
                        matchTableCell{iEntryLeft} = tableRight.match(matchFilterArgs{:});
                    end
                end

            else
                % key fields lie within left, so we loop through left table
                % and lookup each right entry by key fields
                %debug('Performing forward key lookup\n');
                matchFilterArgs = DataRelationship.fillCellOddEntries(keyFieldsRight);
                for iEntryLeft = 1:nEntriesLeft
                    missingValue = false;
                    for iField = 1:nKeyFieldsRight
                        value = entriesLeft(iEntryLeft).(keyFieldsRightInLeft{iField});
                        if isempty(value)
                            missingValue = true;
                            break;
                        end
                        matchFilterArgs{2*iField} = value;
                    end
                    if combine
                        if ~missingValue
                            matchIdx = [matchIdx; tableRight.matchIdx(matchFilterArgs{:})];
                        end
                    else
                        if ~missingValue
                            matchTableCell{iEntryLeft} = tableRight.match(matchFilterArgs{:});
                        else
                            matchTableCell{iEntryLeft} = tableRight.none();
                        end
                    end
                end
            end

            if combine
                matchIdx = unique(matchIdx);
                result = tableRight.select(matchIdx);
            else
                result = matchTableCell;
            end

        end

        function matchTableCell = matchRightInLeft(rel, tableLeft, tableRight, varargin)
            relSwap = rel.swapCopy;
            matchTableCell = relSwap.matchLeftInRight(tableRight, tableLeft, varargin{:});
        end
    end

    methods % Tools for creating junction table entries
        function entryJunction = createJunctionTableEntry(rel, entryLeft, entryRight)
            assert(rel.isJunction, 'Relationship must be via junction table');
            
            if ~isstruct(entryLeft)
                entryLeft = entryLeft.getFullEntriesAsStruct();
            end
            if ~isstruct(entryRight)
                entryRight = entryRight.getFullEntriesAsStruct();
            end

            assert(length(entryLeft) == 1 || length(entryRight) == 1, ...
                'Either entryLeft or entryRight must be a single entry');

            keyFieldsLeft = rel.keyFieldsLeft;
            keyFieldsLeftInRight = rel.keyFieldsLeftInRight;
            keyFieldsRight = rel.keyFieldsRight;
            keyFieldsRightInLeft = rel.keyFieldsRightInLeft;

            % build up the junction entries for each left with each right
            % due to the assert above one of the two outer loops will have one
            % iteration only
            iJunction = 1;
            entryJunction = emptyStructArray([0 1], [keyFieldsLeftInRight; keyFieldsRightInLeft]);
            for iLeft = 1:length(entryLeft)
                for iRight = 1:length(entryRight)
                
                    for iField = 1:length(keyFieldsLeft)
                        fieldLeft = keyFieldsLeft{iField};
                        fieldJunction = keyFieldsLeftInRight{iField};
                        entryJunction(iJunction).(fieldJunction) = entryLeft(iLeft).(fieldLeft);
                    end
                    for iField = 1:length(keyFieldsRight)
                        fieldRight = keyFieldsRight{iField};
                        fieldJunction = keyFieldsRightInLeft{iField};
                        entryJunction(iJunction).(fieldJunction) = entryRight(iRight).(fieldRight);
                    end
                    
                    iJunction = iJunction + 1;
                end
            end
            
            entryJunction = makecol(entryJunction);
        end
    end

    methods(Static) % Utilities
        function name = combinedTableFieldName(table, field)
            % returns a camel-case-concatenation of the table entry name on to the field names
            % i.e. teacher.id --> teacherId 
            entryName = table.entryName;
            name = strcat(entryName, upper(field(1)), field(2:end));
        end

        function names = defaultFieldReference(tableWithFields, tableReferenced, varargin)
            % return the names of fields within tableWithFields that would be used to 
            % reference the keyFields of tableReferenced from within tableWithFields
            if isempty(tableWithFields)
                names = {};
                return;
            end
            if isempty(tableReferenced)
                names = {};
                return;
            end
            
            p = inputParser;
            p.addRequired('tableWithFields', @(x) isa(x, 'DataTable'));
            p.addRequired('tableReferenced', @(x) isa(x, 'DataTable'));
            p.addParamValue('fields', tableReferenced.keyFields, @(x) ischar(x) || iscellstr(x));
            p.parse(tableWithFields, tableReferenced, varargin{:});

            fieldsInOther = p.Results.fields;
            entryName = tableReferenced.entryName;
            
            % first try camel-casing the table entry name on to the field names
            catFn = @(field) DataRelationship.combinedTableFieldName(tableReferenced, field); 
            if ischar(fieldsInOther)
                names = catFn(fieldsInOther);
            else
                names = cellfun(catFn, fieldsInOther, 'UniformOutput', false);
            end

            if all(tableWithFields.isField(names))
                % all of these fields exist, we're good
                return;
            end
            
            % then try just using the fields exactly as is
            if all(tableWithFields.isField(fieldsInOther))
                names = fieldsInOther;
                return;
            end

            % not sure otherwise
            names = {};
        end

        function oddList = fillCellOddEntries(list) 
            oddList = cell(length(list)*2, 1);
            oddList(1:2:end) = list;
        end

        function [jTbl rel] = buildEmptyJunctionTable(tbl1, tbl2, varargin)
            p = inputParser;
            p.addRequired('table1', @(x) isa(x, 'DataTable'));
            p.addRequired('table2', @(x) isa(x, 'DataTable'));
            p.addParamValue('entryName', [], @ischar);
            p.addParamValue('entryNamePlural', [], @ischar);
            p.parse(tbl1, tbl2, varargin{:});
            
            entryName1 = tbl1.entryName;
            entryNamePlural1 = tbl1.entryNamePlural;
            keyFields1 = tbl1.keyFields;
            entryName2 = tbl2.entryName;
            entryNamePlural2 = tbl2.entryNamePlural;
            keyFields2 = tbl2.keyFields;

            % default entryName junction12
            entryName = p.Results.entryName;
            entryNamePlural = p.Results.entryNamePlural;
            if isempty(entryName)
                entryName = sprintf('junction%s%s', ...
                    upperFirst(entryName1), upperFirst(entryName2));
            end
            if isempty(entryNamePlural)
                entryNamePlural = entryName;
            end

            jTbl = StructTable('entryName', entryName, ...
                'entryNamePlural', entryNamePlural);
            
            % add keyFields from tbl1,2 using concatenated entryNameField names
            for i = 1:length(keyFields1)
                field = keyFields1{i};
                jField = DataRelationship.combinedTableFieldName(tbl1, field);
                jTbl = tbl1.copyFieldToDataTable(field, jTbl, 'as', jField, 'keyField', true);
            end
            for i = 1:length(keyFields2)
                field = keyFields2{i};
                jField = DataRelationship.combinedTableFieldName(tbl2, field);
                jTbl = tbl2.copyFieldToDataTable(field, jTbl, 'as', jField, 'keyField', true);
            end
            
            % build many to many relationship for convenience
            rel = DataRelationship('tableLeft', tbl1, 'tableRight', tbl2, ...
                'tableJunction', jTbl, 'isManyLeft', true, 'isManyRight', true); 
        end
    end  

end
