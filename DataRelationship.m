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

        isJunction = false;
        isHalfOfJunction = false;
        isBidirectional = false; % are the reference names and entry names equivalent on both sides? should we check both directions when determining matches?
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
        
        function tf = get.isOneToOne(rel)
            tf = ~rel.isManyLeft && ~rel.isManyRight;
        end
    end

    methods % Constructor, Swap-Left-Right and description
        function rel = DataRelationship(varargin)
            p = inputParser;
            p.addParamValue('tableLeft', [], @(t) isa(t, 'DataTable'));
            p.addParamValue('tableRight', [], @(t) isa(t, 'DataTable'));
            p.addParamValue('tableJunction', [], @(t) isempty(t) || isa(t, 'DataTable'));
            p.addParamValue('referenceLeftForRight', [], @ischar); 
            p.addParamValue('referenceRightForLeft', [], @ischar); 
            p.addParamValue('keyFieldsLeft', [], @iscellstr); 
            p.addParamValue('keyFieldsLeftInRight', [], @iscellstr); 
            p.addParamValue('keyFieldsRight', [], @iscellstr); 
            p.addParamValue('keyFieldsRightInLeft', [], @iscellstr); 
            p.addParamValue('isManyLeft', false, @(t) islogical(t) && isscalar(t));
            p.addParamValue('isManyRight', false, @(t) islogical(t) && isscalar(t));
            p.addParamValue('isHalfOfJunction', false, @islogical);
            p.addParamValue('isBidirectional', false, @islogical);
            p.parse(varargin{:});

            tableLeft = p.Results.tableLeft;
            tableRight = p.Results.tableRight;
            if ~ismember('tableLeft', p.UsingDefaults)
                rel.setTableLeft(tableLeft);
            end
            if ~ismember('tableRight', p.UsingDefaults)
                rel.setTableRight(tableRight);
            end

            if p.Results.isBidirectional
                rel.isBidirectional = true;
            end
            
            tableJunction = p.Results.tableJunction;
            if ~isempty(tableJunction)
                rel.entryNameJunction = tableJunction.entryName;
                rel.entryNameJunctionPlural = tableJunction.entryNamePlural;
                rel.isJunction = true;
            else
                rel.isJunction = false;
            end

            rel.isManyLeft = p.Results.isManyLeft; 
            rel.isManyRight = p.Results.isManyRight;

            % defaults (tableLeft.keyFields) already handled by setTable
            if ~ismember('keyFieldsLeft', p.UsingDefaults)
                rel.keyFieldsLeft = p.Results.keyFieldsLeft;
            end
                          
            if ~ismember('keyFieldsRight', p.UsingDefaults)
                rel.keyFieldsRight = p.Results.keyFieldsRight;
            end
            
            if isempty(rel.keyFieldsLeft)
                error('Table left must have at least one key field to identify its entries');
            end
            if isempty(rel.keyFieldsRight)
                error('Table right must have at least one key field to identify its entries');
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
                        [rel.keyFieldsLeftInRight, foundReferenceLeftInRight] = DataRelationship.defaultFieldReference(...
                            tableJunction, tableLeft);
                        % all references must be found for a junction table
                        % reference
                        if ~any(foundReferenceLeftInRight)
                            error('Could not locate any keyFieldsLeft in junction table. Provide keyFieldsLeftInRight to manually specify the mapping.');
                        end
                    else
                        [rel.keyFieldsLeftInRight, foundReferenceLeftInRight] = DataRelationship.defaultFieldReference(...
                            tableRight, tableLeft, 'fields', rel.keyFieldsLeft);
                        if ~any(foundReferenceLeftInRight)
                            rel.keyFieldsLeftInRight = {};
                            % for 1:1 relationships this might be okay if
                            % foundReferenceLeftInRight is true, we'll check this later
                            if ~rel.isOneToOne
                                error('Could not locate any keyFieldsLeft in right table. Provide keyFieldsLeftInRight to manually specify the mapping.');
                            end
                        end  
                    end
                    
                    rel.keyFieldsLeftInRight = rel.keyFieldsLeftInRight(foundReferenceLeftInRight);
                    
                    % filter default key fields based on which ones exist in the right table?
                    rel.keyFieldsLeft = rel.keyFieldsLeft(foundReferenceLeftInRight);
                end
            else
                % explicitly specified
                rel.keyFieldsLeftInRight = p.Results.keyFieldsLeftInRight;
                assert(length(rel.keyFieldsLeftInRight) == length(rel.keyFieldsLeft), ...
                    'keyFieldsLeftInRight must have same length as keyFieldsLeft');
            end

            if ismember('keyFieldsRightInLeft', p.UsingDefaults)
                % not explicitly specified
                if ~rel.isManyLeft && rel.isManyRight
                    % one side of one to many relationship, leave it blank
                    rel.keyFieldsRightInLeft = {};
                    foundReferenceRightInLeft = false;
                else
                    % generate default field names based on the fields that exist
                    % in the left table
                    if rel.isJunction
                        [rel.keyFieldsRightInLeft, foundReferenceRightInLeft] = DataRelationship.defaultFieldReference(...
                            tableJunction, tableRight);
                        if ~any(foundReferenceRightInLeft)
                            error('Could not locate any keyFieldsRight in junction table. Provide keyFieldsRightInLeft to manually specify the mapping.');
                        end
                    else
                        [rel.keyFieldsRightInLeft, foundReferenceRightInLeft]= DataRelationship.defaultFieldReference(...
                            tableLeft, tableRight, 'fields', rel.keyFieldsRight);
                        if ~any(foundReferenceRightInLeft)
                            rel.keyFieldsRightInLeft = {};
                            % for 1:1 relationships this might be okay if
                            % foundReferenceLeftInRight is true, we'll check this later
                            if ~rel.isOneToOne
                                error('Could not locate any keyFieldsRight in left table. Provide keyFieldsRightInLeft to manually specify the mapping.');
                            end
                        end       
                    end
                    
                    rel.keyFieldsRightInLeft = rel.keyFieldsRightInLeft(foundReferenceRightInLeft);
                    
                    % filter default key fields based on which ones exist in the left table?
                    rel.keyFieldsRight = rel.keyFieldsRight(foundReferenceRightInLeft);
                end
            else
                % explicitly specified
                rel.keyFieldsRightInLeft = p.Results.keyFieldsRightInLeft;
                assert(length(rel.keyFieldsRightInLeft) == length(rel.keyFieldsRight), ...
                    'keyFieldsRightInLeft must have same length as keyFieldsRight');
            end
            
            if rel.isOneToOne
                if ~any(foundReferenceRightInLeft) && ~any(foundReferenceRightInLeft)
                    error('Could not locate any keyFieldsLeft in right table or any keyFieldsRight in left table for this one:one relationship. Provide either keyFieldsLeftInRight or keyFieldsRightInLeft to manually specify the mapping.');
                end
            end
            
            % however, check that these fields exist in the corresponding table
            % and if not remove them
            % this also automatically handles 1-1 relationships, for which
            % only one table may have a pointer to the other
%             if ~isempty(rel.keyFieldsRightInLeft)
%                 if rel.isJunction && ~isempty(tableJunction)
%                     if ~all(tableJunction.isField(rel.keyFieldsRightInLeft))
%                         rel.keyFieldsRightInLeft = {};
%                     end
%                 elseif ~rel.isJunction && ~isempty(tableLeft)
%                     if ~all(tableLeft.isField(rel.keyFieldsRightInLeft))
%                         rel.keyFieldsRightInLeft = {};
%                     end
%                 end
%             end
%             
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

            rel.isHalfOfJunction = p.Results.isHalfOfJunction;
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
            
            % include reference name
            if ~strcmp(nameLeft, rel.referenceRightForLeft)
                nameLeft = [nameLeft ' (as ' rel.referenceRightForLeft ')'];
            end
            
            if rel.isManyRight
                nameRight = rel.entryNamePluralRight;
            else
                nameRight = rel.entryNameRight;
            end
            % include reference name
            if ~strcmp(nameRight, rel.referenceLeftForRight)
                nameRight = [nameRight ' (as ' rel.referenceLeftForRight ')'];
            end

            if rel.isHalfOfJunction
                prefix = '    ';
                postfix = '';
            else
                prefix = '';
                postfix = '';
            end
            
            if rel.isBidirectional
                postfix = [postfix ' [bidir]'];
            end

            str = sprintf('%s%s %s %s %s %s%s', prefix, numLeft, nameLeft, connector, ...
                numRight, nameRight, postfix); 
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
                %rightWidth = colWidth;
                leftField = sprintf('%s.%s', rel.entryNameLeft, rel.keyFieldsLeft{iField});
                rightField = sprintf('%s.%s', rightName, rel.keyFieldsLeftInRight{iField});

                desc = sprintf('%*s == %s\n', leftWidth, leftField, rightField);
                str = [str desc]; %#ok<AGROW>
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
                    str = [str desc]; %#ok<AGROW>
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
                rel.entryNamesPlural{ind} = p.Results.entryNamePlural;
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

        function [tf, referenceName] = involvesEntryName(rel, entryName)
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

        function [tf, leftToRight] = matchesEntryNameAndReference(rel, entryName, referenceName)
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
        
        function [relLeftToRight] = swapToMatchTables(rel, tableFrom, tableReference)
            % swap this relationship so that it can point from entryName to
            % entryNameReference (the entry name, not the reference name)
            
            if strcmp(tableFrom.entryName, rel.entryNameLeft) && strcmp(tableReference.entryName, rel.entryNameRight)
                relLeftToRight = rel;
            elseif strcmp(tableFrom.entryName, rel.entryNameRight) && strcmp(tableReference.entryName, rel.entryNameLeft)
                relLeftToRight = rel.swapCopy();
            else
                error('This relationship does not match this pair of entry names');
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
            if rel.isOneToOne
                assert(~isempty(rel.keyFieldsLeft) || ~isempty(rel.keyFieldsRight), ...
                    'KeyFields for left or right table must be specified for 1:1 relationships');
            else
                assert(~isempty(rel.keyFieldsLeft), 'No left key fields specified');
                tableLeft.assertIsField(rel.keyFieldsLeft);
                assert(~isempty(rel.keyFieldsRight), 'No right key fields specified');
                tableRight.assertIsField(rel.keyFieldsRight);
            end
            
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

        function matchIdx = matchLeftInRight(rel, tableLeft, tableRight, varargin)
            % given a data table corresponding to the left table and right table
            % in this relationship, return either:
            % if parameter 'combine', false is passed (default)
            %     a cell array of cells which each contains a list of idx
            %     listing entries in the right table which match each entry in the left table
            % if parameter 'combine' true is passed
            %     a list of idx containing all matching idx in the right
            %     table
            % parameter fillMissingWithNaN [default true] (meaningful only when combine = true)
            %   when no match is found, substitute a NaN idx keep the indices matched 
            %   for *toOne relationships. if false, no match idx will be
            %   included and the list of idx may be shorter than the original
            %   tableLeft

            p = inputParser;
            p.addRequired('tableLeft', @(x) isa(x, 'DataTable'));
            p.addRequired('tableRight', @(x) isa(x, 'DataTable'));
            p.addParamValue('tableJunction', [], @(x) isempty(x) || isa(x, 'DataTable')); 
            p.addParamValue('combine', true, @islogical);
            p.addParamValue('keepFirst', false, @isscalar); % keep first N matches
            p.addParamValue('warnIfMissing', false, @islogical);
            p.addParamValue('uniquify', true, @islogical);
            p.addParamValue('fillMissingWithNaN', false, @islogical); 
            p.parse(tableLeft, tableRight, varargin{:});

            tableJunction = p.Results.tableJunction;
            combine = p.Results.combine;
            keepFirst = double(p.Results.keepFirst);
            warnIfMissing = p.Results.warnIfMissing;
            uniquify = p.Results.uniquify;
            fillMissingWithNaN = p.Results.fillMissingWithNaN;
            
            % check entry names match
            assert(strcmp(tableLeft.entryName, rel.entryNameLeft));
            assert(strcmp(tableRight.entryName, rel.entryNameRight));

            keyFieldsLeftInRight = rel.keyFieldsLeftInRight;
            keyFieldsRightInLeft = rel.keyFieldsRightInLeft;

            nEntriesLeft = tableLeft.nEntries;
           % nEntriesRight = tableRight.nEntries;

            keyFieldsLeft = rel.keyFieldsLeft;
            keyFieldsRight = rel.keyFieldsRight;
            %nKeyFieldsRight = length(keyFieldsRight);
            %nKeyFieldsLeft = length(keyFieldsLeft);
            
            entriesLeft = tableLeft.getAllEntriesAsStruct(rel.keyFieldsLeft);
            entriesRight = tableRight.getAllEntriesAsStruct(rel.keyFieldsRight);
            
            if rel.isJunction
                %debug('Performing junction table lookup\n');
                assert(exist('tableJunction', 'var') > 0, 'tableJunction argument required');
                entriesJunctionForLeft = tableJunction.getAllEntriesAsStruct(keyFieldsLeftInRight);
                entriesJunctionForRight = tableJunction.getAllEntriesAsStruct(keyFieldsRightInLeft);
               
%                 % preload the fieldNames for .match(args{:} for tableJunction and tableRight
%                 matchFilterArgsJunction = DataRelationship.fillCellOddEntries(keyFieldsLeftInRight);
%                 matchFilterArgsRight = DataRelationship.fillCellOddEntries(keyFieldsRight);

                % (i,j) is true if entryLeft(i) matches entryJunction(j)
                matchMatLeftJunction = DataRelationship.getMatchMatrix(entriesLeft, entriesJunctionForLeft, ...
                    keyFieldsLeft, keyFieldsLeftInRight, tableLeft.fieldDescriptorMap);
            
                % TODO might be able to make this faster by prefiltering
                % columns of junction
                matchMatJunctionRight = DataRelationship.getMatchMatrix(entriesJunctionForRight, entriesRight, ...
                    keyFieldsRightInLeft, keyFieldsRight, tableJunction.fieldDescriptorMap);
                
                % simply multiply them together to find left-right matches via any
                % junction entry
                matchMat = (single(matchMatLeftJunction) * single(matchMatJunctionRight)) ~= 0;
                
            elseif ~isempty(keyFieldsLeftInRight)
                % key fields for left lie within right, so we can loop through left table 
                % and search directly for each's match(es) in right
                % this is essentially a reverse lookup
                %debug('Performing reverse key lookup\n');
                matchMat = DataRelationship.getMatchMatrix(entriesLeft, entriesRight, ...
                    keyFieldsLeft, keyFieldsLeftInRight, tableLeft.fieldDescriptorMap);

            else
                % key fields for right table lie within left, so we loop through left table
                % and lookup each right entry by key fields
                %debug('Performing forward key lookup\n');
                matchMat = DataRelationship.getMatchMatrix(entriesLeft, entriesRight, ...
                    keyFieldsRightInLeft, keyFieldsRight, tableLeft.fieldDescriptorMap);
            end

            % convert match matrix to list of matches for each left entry
            matchIdx = arrayfun(@(i) find(matchMat(i, :)), 1:nEntriesLeft, 'UniformOutput', false);
            
            counts = cellfun(@numel, matchIdx);
            if warnIfMissing && any(counts < 0)
                debug('WARNING: No match found for %d %s entries\n', nnz(counts==0), tableLeft.entryName);
            end

            if ~rel.isManyRight
                % ensure that multiple matches are NEVER returned for
                % *toOne relationships. When fillMissingWithNaN is also
                % true, this ensures that the match table returned will be
                % matched entry for entry to the left table
                if any(counts > 1)
                    debug('WARNING: Found unexpected multiple matches for %d %s entries, truncating.\n', ...
                        nnz(counts > 1), tableLeft.entryName);
                end
                keepFirst = 1;
            end
                        
            if keepFirst > 0 
                % truncate to first N matches
                matchIdx(counts > keepFirst) = ...
                    cellfun(@(idx) idx(1:keepFirst), matchIdx(counts > keepFirst), ...
                    'UniformOutput', false);
            end
            
            if combine
                if ~rel.isManyRight
                    % this is a *toOne rel, so the list should be the exact
                    % same length as nEntriesLeft, i.e. empty slots will be
                    % replaced with NaNs, if fillMissingWithEmpty is true        
                    if fillMissingWithNaN
                        [matchIdx{counts == 0}] = deal(NaN);
                    end
                    matchIdx = cell2mat(matchIdx);
                else
                    matchIdx = cell2mat(matchIdx);
                    if uniquify
                        matchIdx = unique(matchIdx, 'stable');
                    end
                end
            else
                % keep as cell
                %result = matchIdx;
            end
        end

        function matchTableCell = matchRightInLeft(rel, tableLeft, tableRight, varargin)
            % returning a list of idx, not DataTables
            relSwap = rel.swapCopy;
            matchTableCell = relSwap.matchLeftInRight(tableRight, tableLeft, varargin{:});
        end
        
        function matchTableCell = matchBidirectionally(rel, tableLeft, tableRight, varargin)
            % if bidirectional, automatically combine both directions
            % returning a list of idx, not DataTables
            assert(rel.isBidirectional, 'Relationship is not bidirectional');
            resultLR = rel.matchLeftInRight(tableLeft, tableRight, varargin{:});
            resultRL = rel.swapCopy.matchLeftInRight(tableLeft, tableRight, varargin{:});
            
            if iscell(resultLR)
                matchTableCell = cellfun(@(t1, t2) unique([t1 t2]), resultLR, resultRL, 'UniformOutput', false);
            else
                matchTableCell = unique([resultLR resultRL]);
            end
        end
        
        function matchIdx = match(rel, tableFrom, tableReference, varargin)
            % match tableFrom -> tableReference using the appropriate
            % match* method above
            rel = rel.swapToMatchTables(tableFrom, tableReference);
           
            if rel.isBidirectional
                matchIdx = rel.matchBidirectionally(tableFrom, tableReference, varargin{:});
            else
                matchIdx = rel.matchLeftInRight(tableFrom, tableReference, varargin{:});
            end
        end
    end

    methods % Tools for creating junction table entries
        function entryJunction = createJunctionTableEntry(rel, entryLeft, entryRight, varargin)
            % Assuming rel is a junction table relationship (many 2 many via junction)
            % creates a set of rows for the junction table which would join entries from
            % entryLeft to entries from entryRight. If either entryLeft or entryRight has length 1,
            % joins all in the other array to that 1 entry in entryRight. If both are the same size,
            % joins entryLeft(i) to entryRight(i) for each i. 
            %
            % If param 'allToAll' is set to true, 
            % joins each entryLeft to each entryRight regardless.
           
            p = inputParser();
            p.addRequired('entryLeft', @(t) isstruct(t) || isa(t, 'DataTable'));
            p.addRequired('entryRight', @(t) isstruct(t) || isa(t, 'DataTable'));
            p.addParamValue('allToAll', false, @islogical);
            p.parse(entryLeft, entryRight, varargin{:});
            allToAll = p.Results.allToAll;
             
            assert(rel.isJunction, 'Relationship must be via junction table');
            
            if ~isstruct(entryLeft)
                entryLeft = entryLeft.getFullEntriesAsStruct();
            end
            if ~isstruct(entryRight)
                entryRight = entryRight.getFullEntriesAsStruct();
            end

            if length(entryLeft) == 1 || length(entryRight) == 1
                % assume this is what they wanted, for backwards compatibility
                allToAll = true;
            end

            keyFieldsLeft = rel.keyFieldsLeft;
            keyFieldsLeftInRight = rel.keyFieldsLeftInRight;
            keyFieldsRight = rel.keyFieldsRight;
            keyFieldsRightInLeft = rel.keyFieldsRightInLeft;

            if allToAll
                % build up the junction entries for each left with every right
                iJunction = 1;
                nEntries = numel(entryLeft) * numel(entryRight);

                entryJunction = emptyStructArray([nEntries 1], [keyFieldsLeftInRight; keyFieldsRightInLeft]);

                for iLeft = 1:length(entryLeft)
                    for iRight = 1:length(entryRight)
                        entryJunction(iJunction) = createEntry(iLeft, iRight);
                        iJunction = iJunction + 1;
                    end
                end
            else
                assert(numel(entryRight) == numel(entryLeft), ...
                    'entryLeft and entryRight must be the same size if allToAll=false');

                % build up the junction entries for each left with the corresponding right
                nEntries = max([numel(entryLeft) numel(entryRight)]);

                entryJunction = emptyStructArray([nEntries 1], [keyFieldsLeftInRight; keyFieldsRightInLeft]);

                for iJunction = 1:numel(entryLeft)
                    entryJunction(iJunction) = createEntry(iJunction, iJunction);
                end
            end

            entryJunction = makecol(entryJunction);

            % utility function for creating a single row
            function entry = createEntry(iLeft, iRight)
                for iField = 1:length(keyFieldsLeft)
                    fieldLeft = keyFieldsLeft{iField};
                    fieldJunction = keyFieldsLeftInRight{iField};
                    entry.(fieldJunction) = entryLeft(iLeft).(fieldLeft);
                end
                for iField = 1:length(keyFieldsRight)
                    fieldRight = keyFieldsRight{iField};
                    fieldJunction = keyFieldsRightInLeft{iField};
                    entry.(fieldJunction) = entryRight(iRight).(fieldRight);
                end
            end
        end
    end

    methods(Static) % Utilities
        function matchMat = getMatchMatrix(entriesLeft, entriesRight, ...
                keyFieldsLeft, keyFieldsRight, dfdMap)
            % return a matrix which indicates whether entryLeft(i) matches
            % entryRight(j) along the specified sets of keyFields. Used in
            % joins via match*() above
            
            % whether entriesLeft(i) matches entriesRight(j)
            matchMat = true(numel(entriesLeft), numel(entriesRight));
            
            if isempty(matchMat)
                matchMat = false(size(matchMat));
                return;
            end
            
            for i = 1:length(keyFieldsLeft)
                dfd = dfdMap(keyFieldsLeft{i});
                valuesLeft = {entriesLeft.(keyFieldsLeft{i})}';
                valuesRight = {entriesRight.(keyFieldsRight{i})}';
                if dfd.matrix
                    valuesLeft = cell2mat(valuesLeft);
                    valuesRight = cell2mat(valuesRight);
                end
                
                matchMatThis = dfd.valueCompareMulti(valuesLeft, valuesRight);
                matchMat = matchMat & matchMatThis;
            end
            
        end
        
        function name = combinedTableFieldName(tableOrEntryName, field)
            % returns a camel-case-concatenation of the table entry name on to the field names
            % i.e. teacher.id --> teacherId 
            if ischar(tableOrEntryName)
                entryName = tableOrEntryName;
            else
                entryName = tableOrEntryName.entryName;
            end
            name = strcat(entryName, upper(field(1)), field(2:end));
        end

        function [namesReference, foundReference] = defaultFieldReference(tableWithFields, tableReferenced, varargin)
            % return the names of fields within tableWithFields that would be used to 
            % reference the keyFields of tableReferenced from within tableWithFields
            p = inputParser;
            p.addRequired('tableWithFields', @(x) isempty(x) || isa(x, 'DataTable'));
            p.addRequired('tableReferenced', @(x) isempty(x) || isa(x, 'DataTable'));
            p.addParamValue('fields', tableReferenced.keyFields, @(x) ischar(x) || iscellstr(x));
            p.parse(tableWithFields, tableReferenced, varargin{:});
            fieldsInOther = p.Results.fields;
            
            foundReference = false(length(fieldsInOther), 1);
            namesReference = cell(length(fieldsInOther), 1);
           
            if isempty(tableWithFields) || isempty(tableReferenced)
                return;
            end
            
            % first try camel-casing the table entry name on to the field names
            catFn = @(field) DataRelationship.combinedTableFieldName(tableReferenced, field); 
            if ischar(fieldsInOther)
                names = catFn(fieldsInOther);
            else
                names = cellfun(catFn, fieldsInOther, 'UniformOutput', false);
            end
            
            foundCamelCased = tableWithFields.isField(names);
            foundReference = foundReference | foundCamelCased;
            namesReference(foundCamelCased) = names(foundCamelCased);

            if all(foundReference)
                % all of these camel cased fields exist, we're good
                return;
            end
            
            % then try just using the fields exactly as is
            foundExact = tableWithFields.isField(fieldsInOther);
            replaceMask = foundExact & ~foundReference;
            namesReference(replaceMask) = fieldsInOther(replaceMask);
            foundReference = foundReference | foundExact;
            
            if all(foundReference)
                % found all of them either camel cased or exact
                return;
            end
        end

        function oddList = fillCellOddEntries(list) 
            oddList = cell(length(list)*2, 1);
            oddList(1:2:end) = list;
        end

        function [jTbl, relManyToMany, relLeftToJunction, relJunctionToRight] = ...
                buildEmptyJunctionTable(tbl1, tbl2, varargin)
            % builds a junction table and related DataRelationships to join
            % tbl1 to tbl2 via a junction table
            p = inputParser;
            p.addRequired('table1', @(x) isa(x, 'DataTable'));
            p.addRequired('table2', @(x) isa(x, 'DataTable'));
            
            % is this relationship undirected? if so, both directions will
            % be checked when matching
            p.addParamValue('isBidirectional', false, @islogical);

            % by default, the entry names of the two tables will be used both as 
            % field name prefixes and as the fieldname in the relationship
            p.addParamValue('referenceJunctionForLeft', '', @ischar);
            p.addParamValue('referenceJunctionForRight', '', @ischar);
            
            p.addParamValue('referenceLeftForRight', tbl2.entryName, @ischar);
            p.addParamValue('referenceRightForLeft', tbl1.entryName, @ischar);

            p.addParamValue('entryName', [], @ischar);
            p.addParamValue('entryNamePlural', [], @ischar);
            
            p.parse(tbl1, tbl2, varargin{:});
            
            keyName1 = p.Results.referenceJunctionForLeft;
            keyName2 = p.Results.referenceJunctionForRight;
            %entryName1 = tbl1.entryName;
            %entryNamePlural1 = tbl1.entryNamePlural;
            keyFields1 = tbl1.keyFields;
            %entryName2 = tbl2.entryName;
            %entryNamePlural2 = tbl2.entryNamePlural;
            keyFields2 = tbl2.keyFields;

            % default entryName junction12
            entryName = p.Results.entryName;
            entryNamePlural = p.Results.entryNamePlural;

            % keyNames (i.e. reference from junction out to individual tables)
            % defaults to reference names across junction
            if isempty(keyName1)
                keyName1 = p.Results.referenceRightForLeft;
            end
            if isempty(keyName2)
                keyName2 = p.Results.referenceLeftForRight;
            end
            
            % although if they are the same, add 1, 2 to the end to
            % disambiguate
            if strcmp(keyName1, keyName2)
                error('Tables constituting junction have same entryName. Please manually specify referenceJunctionForLeft and referenceJunctionForLeft to specify unique names\n');
            end

            if isempty(entryName)
                entryName = sprintf('junction%s%s', ...
                    upperFirst(keyName1), upperFirst(keyName2));
            end
%             if isempty(entryNamePlural)
%                 entryNamePlural = entryName;
%             end

            jTbl = StructTable('entryName', entryName, ...
                'entryNamePlural', entryNamePlural);
            
            % add keyFields from tbl1,2 using concatenated entryNameField names
            jField1 = cell(length(keyFields1), 1);
            for i = 1:length(keyFields1)
                field = keyFields1{i};
                jField1{i} = DataRelationship.combinedTableFieldName(keyName1, field);
                jTbl = tbl1.copyFieldToDataTable(field, jTbl, 'as', jField1{i}, 'keyField', true);
            end
            jField2 = cell(length(keyFields2), 1);
            for i = 1:length(keyFields2)
                field = keyFields2{i};
                jField2{i} = DataRelationship.combinedTableFieldName(keyName2, field);
                jTbl = tbl2.copyFieldToDataTable(field, jTbl, 'as', jField2{i}, 'keyField', true);
            end
            
            % build many to many relationship for convenience
            relManyToMany = DataRelationship('tableLeft', tbl1, 'tableRight', tbl2, ...
                'tableJunction', jTbl, 'isManyLeft', true, 'isManyRight', true, ...
                'keyFieldsLeftInRight', jField1, 'keyFieldsRightInLeft', jField2, ...
                'referenceLeftForRight', p.Results.referenceLeftForRight, ...
                'referenceRightForLeft', p.Results.referenceRightForLeft, ...
                'isBidirectional', p.Results.isBidirectional); 
            
            [relLeftToJunction, relJunctionToRight] = DataRelationship.buildRelationshipsToJunction(...
                relManyToMany, tbl1, tbl2, jTbl, ...
                'referenceJunctionForLeft', keyName1, 'referenceJunctionForRight', keyName2);
        end
        
        function [jTbl, relManyToMany, relLeftToJunction, relJunctionToRight] = buildEmptyJunctionTableForTableSelfLink(tbl, varargin)
            % builds a junction table and related relationships to join
            % entries in tbl to other entries in tbl (via that junction
            % table)
            p = inputParser();
            p.addParamValue('entryName', ['junction' upperFirst(tbl.entryName) upperFirst(tbl.entryName)], @(x) isempty(x) || ischar(x));
            p.addParamValue('referenceJunctionForLeft', [tbl.entryName '1'], @ischar);
            p.addParamValue('referenceJunctionForRight', [tbl.entryName '2'], @ischar);
            p.addParamValue('referenceLink', tbl.entryName, @ischar);
            p.KeepUnmatched = true;
            p.parse(varargin{:});
            
            referenceLink = p.Results.referenceLink;
            
            % cannot refer to the junction table itself and the entries at
            % the other side of the link by the same reference name
            assert(~strcmp(referenceLink, p.Results.entryName), ...
                'Junction table entry name cannot match referenceLink or the reference will be ambiguous');
            
            [jTbl, relManyToMany, relLeftToJunction, relJunctionToRight] = ...
                DataRelationship.buildEmptyJunctionTable(tbl, tbl, ...
                'entryName', p.Results.entryName, ...
                'referenceLeftForRight', referenceLink, ...
                'referenceRightForLeft', referenceLink, ...
                'isBidirectional', true, ...
                'referenceJunctionForRight', p.Results.referenceJunctionForLeft, ...
                'referenceJunctionForLeft', p.Results.referenceJunctionForRight, p.Unmatched);
        end
        
        function [relLeftToJunction, relJunctionToRight] = buildRelationshipsToJunction(...
                manyToManyRel, tableLeft, tableRight, tableJunction, varargin)
            % a junction relationship connects entryLeft to entryRight through entryJunction
            % this function builds the constituent relationships entryLeft to entryJunction
            % and entryJunction to entryRight. Typically when adding a junction relationship
            % to the database, these constituent 1:1 relationships will be automatically
            % added as well
            rel = manyToManyRel;
            
            % allow override of how junction table refers to left and right
            % matches
            p = inputParser;
            p.addParamValue('referenceJunctionForLeft', rel.referenceRightForLeft, @ischar);
            p.addParamValue('referenceJunctionForRight', rel.referenceLeftForRight, @ischar);
            p.parse(varargin{:});
            
            relLeftToJunction = DataRelationship('tableLeft', tableLeft, 'tableRight', tableJunction, ...
                'isManyLeft', false, 'isManyRight', true, ...
                'keyFieldsLeft', rel.keyFieldsLeft, ...
                'keyFieldsRight', rel.keyFieldsLeftInRight, ...
                'keyFieldsLeftInRight' , rel.keyFieldsLeftInRight, ...
                'isHalfOfJunction', true, ...
                'referenceRightForLeft', p.Results.referenceJunctionForLeft);

            relJunctionToRight = DataRelationship('tableLeft', tableJunction, 'tableRight', tableRight, ...
                'isManyLeft', true, 'isManyRight', false, ...
                'keyFieldsLeft', rel.keyFieldsRightInLeft, ...
                'keyFieldsRightInLeft', rel.keyFieldsRightInLeft, ...
                'keyFieldsRight', rel.keyFieldsRight, ...
                'isHalfOfJunction', true, ...
                'referenceLeftForRight', p.Results.referenceJunctionForRight);
        end
    end  

end
