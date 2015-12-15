classdef Database < DynamicClass & handle & matlab.mixin.Copyable

    properties(Hidden)
        tableMap % ValueMap mapping :entryName --> Table
        relationships % cell array of DataRelationship instances 
        singularToPluralMap % conversion table from entryName to entryNamePlural
        pluralToSingularMap % vice versa

        viewsApplied = {}; % cell array of DatabaseView
        sourcesLoaded = {}; % cell array of DataSource
    end

    properties(Dependent)
        tableEntryNameList
        nTables
        nRelationships
        sourcesLoadedDescription 
        viewsAppliedDescription
    end

    methods
        function db = Database(varargin)
            db.tableMap = ValueMap('KeyType', 'char', 'ValueType', 'any');
            db.singularToPluralMap = ValueMap('KeyType', 'char', 'ValueType', 'char');
            db.pluralToSingularMap = ValueMap('KeyType', 'char', 'ValueType', 'char');
            db.relationships = {};
        end
    end

    methods % Tables
       % Allows tab completion after dot to suggest variables
        function p = properties(dt)
            % This will be called for properties of an instance, but the
            % built-in will be still be called for the class name.
            pp = dt.tableEntryNameList;
            if nargout == 0
                fprintf('%s\n',getString(message('MATLAB:ClassText:PROPERTIES_FUNCTION_LABEL',class(dt))));
                fprintf('    %s\n',pp{:});
            else
                p = pp;
            end
        end
        
        function f = fieldnames(t), f = properties(t); end
        
        function disp(db)
            tcprintf('light blue', 'Database with %d tables, %d relationships\n\n', ...
                db.nTables, db.nRelationships);

            tables = db.tableEntryNameList;
            tcprintf('light blue', 'Tables: ');
            for i = 1:length(tables)
                nEntries = db.tableMap(tables{i}).nEntries;
                tcprintf('inline', '%s({yellow}%d{none})', tables{i}, nEntries);
                if i < length(tables)
                    fprintf(', ');
                end
            end

            tcprintf('light blue', '\nRelationships: \n');
            relationships = db.relationships;
            for i = 1:length(relationships) %#ok<*PROP>
                fprintf('\t%s\n', relationships{i}.describeLink());
            end

            tcprintf('light blue', 'Sources Loaded: ');
            fprintf('%s\n', db.sourcesLoadedDescription);

            tcprintf('light blue', 'Views Applied: ');
            fprintf('%s\n', db.viewsAppliedDescription);

            fprintf('\n'); 
        end

        function table = addTable(db, table, varargin)
            if nargout == 0
                warning('When adding tables to the database, store the table returned as it has been updated to point at the database');
            end
            p = inputParser;
            p.addRequired('table', @(t) validateattributes(t, {'DataTable'}, {'nonempty'}));
            %p.addParamValue('entryName', '', @ischar);
            %p.addParamValue('entryNamePlural', '', @ischar);
            p.parse(table, varargin{:});

            % allowing these to be overriden complicates things and will probably never be used
            % be sure to look at updateTable if this is restored
            entryName = table.entryName;
            entryNamePlural = table.entryNamePlural;
            % use provided entryName, entryNamePlural, or use defaults from table.
            %if isempty(p.Results.entryName);
            %    entryName = table.entryName;
            %else
            %    entryName = p.Results.entryName;
            %end
            %if isempty(p.Results.entryNamePlural)
            %    if isempty(p.Results.entryName)
            %        % neither provided, ask table  
            %        entryNamePlural = table.entryNamePlural;
            %    else
            %        % singular provided, use simple pluralization
            %        entryNamePlural = [entryName 's'];
            %    end
            %else
            %    % use explicitly provided plural
            %    entryNamePlural = p.Results.entryNamePlural; 
            %end

            debug('Adding table with entryName %s (%s)\n', entryName, entryNamePlural)

            if db.hasTable(entryName)
                debug('WARNING: Database already has table with entryName %s, overwriting\n', entryName);
                % remove old keys
                oldPlural = db.singularToPluralMap(entryName);
                db.pluralToSingularMap = db.pluralToSingularMap.remove(oldPlural);
                db.singularToPluralMap = db.singularToPluralMap.remove(entryName);
            end
            if db.pluralToSingularMap.isKey(entryName)
                % another table has the same plural
                conflictingEntryName = db.pluralToSingularMap(entryName);
                error('Database has another table with the same entryNamePlural and entryName %s', conflictingEntryName);
            end

            table = table.setDatabase(db);
            db.tableMap(entryName) = table;
            db.pluralToSingularMap(entryNamePlural) = entryName;
            db.singularToPluralMap(entryName) = entryNamePlural;
        end

        function table = addOrMergeWithTable(db, table, varargin)
            if db.hasTable(table.entryName)
                debug('Merging into existing table %s\n', table.entryName);
                combined = db.getTable(table.entryName).mergeEntriesWith(table);
                table = db.updateTable(combined);
            else
                table = db.addTable(table);
            end
        end

        function table = updateTable(db, table, varargin)
            p = inputParser();
            p.addParameter('filterOneToRelationships', true, @islogical); % filter tables that refer to a single unit across a relationships as well
            p.addParameter('recursive', true, @islogical);
            p.addParameter('excludeEntryNames', {}, @iscellstr); % mostly used internally to prevent infinite recursion
            p.parse(varargin{:});
            
            % replace the current table with 
            assert(isa(table, 'DataTable'), 'table must be a DataTable instance');
            entryName = table.entryName;

            if ~db.hasTable(entryName)
                table = db.addTable(table, varargin{:});
            else
                oldTable = db.tableMap(entryName);
                assert(isempty(setxor(oldTable.keyFields, table.keyFields)), ...
                    'Key fields of new table must match existing');

                table = table.setDatabase(db);
                db.tableMap(entryName) = table;
                
                if p.Results.filterOneToRelationships && ~ismember(table.entryName, p.Results.excludeEntryNames)
                    % update recursively across one to relationships
                    excludeEntryNames = union(p.Results.excludeEntryNames, table.entryName);
                    db.filterOneToRelationships(table.entryName, 'recursive', p.Results.recursive, 'excludeEntryNames', excludeEntryNames);
                end
            end
        end
        
        function filterOneToRelationships(db, entryName, varargin)
            % look at all tables that are connected to table entryName by a
            % one/many to one relationships, i.e. one entryName for ? other
            % and remove entries in those tables that refer to a now
            % filtered out entryName.
            p = inputParser();
            p.addParameter('recursive', true, @islogical);
            p.addParameter('excludeEntryNames', {}, @iscellstr); % mostly used internally to prevent infinite recursion
            p.parse(varargin{:});
            
            db.assertHasTable(entryName);
            
            [refNames, referredToAsCell] = db.listRelationshipsWithAsOneTo(entryName);
            
            for iRef = 1:numel(refNames)
                debug('Filtering %s entries for those that have corresponding %s entry\n', refNames{iRef}, entryName);
                t = db.getTable(refNames{iRef}).filterHasRelated(referredToAsCell{iRef});
                if p.Results.recursive
                    % update recursively across one to relationships
                    excludeEntryNames = union(p.Results.excludeEntryNames, {entryName; refNames{iRef}});
                    db.updateTable(t, 'recursive', true, 'excludeEntryNames', excludeEntryNames);
                end
            end
        end
        
        function filterAllOneToRelationships(db)
            entryNames = db.tableEntryNameList();
            for iE = 1:numel(entryNames)
                db.filterOneToRelationships(entryNames{iE}, 'recursive', false); % no need for recursive since we're doing this over all tables already
            end
        end

        function removeTable(db, entryName)
            db.assertHasTable(entryName);
            if ~db.tableMap.isKey(entryName)
                entryNamePlural = entryName;
                entryName = db.pluralToSingularMap(entryName);
            else
                entryNamePlural = db.singularToPluralMap(entryName);
            end
            db.tableMap.remove(entryName);
            db.pluralToSingularMap.remove(entryNamePlural);
            db.singularToPluralMap.remove(entryName);
        end
        
        function deduplicateAllTables(db, varargin)
            p = inputParser();
            p.addParameter('filterOneToRelationships', true, @islogical);
            p.parse(varargin{:});
            
            entryNames = db.tableEntryNameList();
            for iE = 1:numel(entryNames)
                dt = db.getTable(entryNames{iE}).deduplicateBasedOnKeyFields();
                db.tableMap(dt.entryName) = dt; % update relationships once at the end
            end

            if p.Results.filterOneToRelationships
                db.filterAllOneToRelationships();
            end
        end
        
        function tableEntryNameList = get.tableEntryNameList(db)
            tableEntryNameList = makecol(db.tableMap.keys);
        end

        function nTables = get.nTables(db)
            nTables = length(db.tableMap);
        end

        function nRelationships = get.nRelationships(db)
            nRelationships = length(db.relationships);
        end

        function table = getTable(db, entryName)
            db.assertHasTable(entryName);
            if ~db.tableMap.isKey(entryName)
                entryName = db.pluralToSingularMap(entryName);
            end
            table = db.tableMap(entryName);
        end

        function [tf, entryName] = hasTable(db, entryName)
            % look for singular
            if db.tableMap.isKey(entryName)
                tf = true;
            elseif db.pluralToSingularMap.isKey(entryName)
                entryName = db.pluralToSingularMap(entryName);
                tf = true;
            else
                tf = false;
                entryName = '';
            end
        end

        function assertHasTable(db, entryName)
            assert(db.hasTable(entryName), 'Database does not have table %s', entryName);
        end

        % get the latest updated timestamp for all tables in the database
        % or if an argument is specified, for all entry names listed
        function timestamp = getLastUpdated(db, entryNames)
            if nargin == 1
                entryNames = db.tableEntryNameList;
            end

            timestamp = -Inf;

            for i = 1:length(entryNames)
                entryName = entryNames{i};
                lastUpdated = db.getTable(entryName).lastUpdated;
                timestamp = max(timestamp, lastUpdated);
            end
        end
    end

    methods % Relationships
        function [referenceNames, refIdx] = listRelationshipsWith(db, entryName)
            referenceNames = {};
            refIdx = [];
            for iRel = 1:db.nRelationships
                rel = db.relationships{iRel};
                [tf, referenceName] = rel.involvesEntryName(entryName);
                if tf
                    referenceNames = [referenceNames referenceName]; %#ok<AGROW>
                    refIdx = [refIdx; iRel]; %#ok<AGROW>
                end
            end
            referenceNames = makecol(referenceNames);
        end
        
        function [referenceNames, referredToAsCell, refIdx] = listRelationshipsWithAsOneTo(db, entryName)
            % finds referneces where one entryName is related to one/many
            % referenceNames. referredToAs is the name of the entryName on
            % the one side of the relationship. 
            referenceNames = {};
            referredToAsCell = {};
            refIdx = [];
            for iRel = 1:db.nRelationships
                rel = db.relationships{iRel};
                [tf, referenceName, referredToAs] = rel.involvesEntryNameAsOneTo(entryName);
                if tf
                    referenceNames = [referenceNames referenceName]; %#ok<AGROW>
                    referredToAsCell{end+1} = referredToAs;
                    refIdx = [refIdx; iRel]; %#ok<AGROW>
                end
            end
            referenceNames = makecol(referenceNames);
            referredToAsCell = makecol(referredToAsCell);
        end

        function [referenceNames, referredToAsCell, refIdx] = listRelationshipsWithAsManyTo(db, entryName)
            referenceNames = {};
            referredToAsCell = {};
            refIdx = [];
            for iRel = 1:db.nRelationships
                rel = db.relationships{iRel};
                [tf, referenceName] = rel.involvesEntryNameAsManyTo(entryName);
                if tf
                    referenceNames = [referenceNames referenceName]; %#ok<AGROW>
                    referredToAsCell{end+1} = referredToAs;
                    refIdx = [refIdx; iRel]; %#ok<AGROW>
                end
            end
            referenceNames = makecol(referenceNames);
            referredToAsCell = makecol(referredToAsCell);
        end


        function [matchRel, leftToRight] = findRelationship(db, entryName, referenceName)
            % determine whether a relationship from table with entryName referring
            % to the other table as referenceName is found within db.relationships
            % Return the relationship if found or [] if not found
            % If the relationship is found with the reverse order, automatically swapCopies the relationship
            % to point in the other direction

            for iRel = 1:db.nRelationships
                rel = db.relationships{iRel};
                [tf leftToRight] = rel.matchesEntryNameAndReference(entryName, referenceName);
                if tf
                    if leftToRight
                        matchRel = rel;
                    else
                        matchRel = rel.swapCopy();
                    end
                    return;
                end
            end

            % not found
            matchRel = [];
            leftToRight = [];
        end
        
        % like the above but returns more than one relationship if there
        % are multiple matches
        function [relCell] = findAllRelationships(db, entryName, referenceName)
            relCell = {};
            for iRel = 1:db.nRelationships
                rel = db.relationships{iRel};
                [tf leftToRight] = rel.matchesEntryNameAndReference(entryName, referenceName);
                if tf
                    if leftToRight
                        relCell{end+1} = rel;
                    else
                        relCell{end+1} = rel.swapCopy();
                    end
                end
            end
        end

        function removeRelationship(db, entryName, referenceName)
            % remove any relationships from the table with entryName referring
            % to the other table as referenceName within db.relationships

            remove = false(db.nRelationships, 1);
            for iRel = 1:db.nRelationships
                rel = db.relationships{iRel};
                remove(iRel) = rel.matchesEntryNameAndReference(entryName, referenceName);
            end

            db.relationships = db.relationships(~remove);
        end

        function tf = hasRelationship(db, entryName, referenceName)
            tf = ~isempty(db.findRelationship(entryName, referenceName));
        end

        function addRelationship(db, rel, varargin);
            p = inputParser;
            p.addRequired('rel', @(x) validateattributes(x, {'DataRelationship'}, {'nonempty'})); 
            p.parse(rel, varargin{:});
            rel = p.Results.rel;

            % check for existing entry->reference relationships
            if db.hasRelationship(rel.entryNameLeft, rel.referenceLeftForRight) && ...
                ~rel.isHalfOfJunction
                %warning('Overwriting existing relationship %s -> %s', ...
                %    rel.entryNameLeft, rel.referenceLeftForRight);
                db.removeRelationship(rel.entryNameLeft, rel.referenceLeftForRight);
            end

            if db.hasRelationship(rel.entryNameRight, rel.referenceRightForLeft) && ...
                ~rel.isHalfOfJunction
                %warning('Overwriting existing relationship %s -> %s', ...
                %    rel.entryNameRight, rel.referenceRightForLeft);
                db.removeRelationship(rel.entryNameRight, rel.referenceRightForLeft);
            end

            % check that the fields referenced by the relationship all exist
            tableLeft = db.getTable(rel.entryNameLeft);
            tableRight = db.getTable(rel.entryNameRight);
            if rel.isJunction
                tableJunction = db.getTable(rel.entryNameJunction);
                rel.checkFields(tableLeft, tableRight, tableJunction);
            else
                rel.checkFields(tableLeft, tableRight);
            end

            debug('Adding DataRelationship: %s\n', rel.describeLink());

            db.relationships{db.nRelationships+1} = rel;
        end

        function addRelationshipOneToOne(db, entryLeft, entryRight, varargin)
            p = inputParser;
            p.KeepUnmatched = true;
            p.addRequired('entryLeft', @ischar);
            p.addRequired('entryRight', @ischar);
            p.parse(entryLeft, entryRight, varargin{:});

            tableLeft = db.getTable(entryLeft);
            tableRight = db.getTable(entryRight);

            rel = DataRelationship('tableLeft', tableLeft, 'tableRight', tableRight, ...
                'isManyLeft', false, 'isManyRight', false, p.Unmatched); 

            db.addRelationship(rel);
        end

        function addRelationshipOneToMany(db, entryLeft, entryRight, varargin)
            p = inputParser;
            p.KeepUnmatched = true;
            p.addRequired('entryLeft', @ischar);
            p.addRequired('entryRight', @ischar);
            p.parse(entryLeft, entryRight, varargin{:});

            tableLeft = db.getTable(entryLeft);
            tableRight = db.getTable(entryRight);

            rel = DataRelationship('tableLeft', tableLeft, 'tableRight', tableRight, ...
                'isManyLeft', false, 'isManyRight', true, p.Unmatched); 

            db.addRelationship(rel);
        end

        function addRelationshipManyToOne(db, entryLeft, entryRight, varargin)
            p = inputParser;
            p.KeepUnmatched = true;
            p.addRequired('entryLeft', @ischar);
            p.addRequired('entryRight', @ischar);
            p.parse(entryLeft, entryRight, varargin{:});

            tableLeft = db.getTable(entryLeft);
            tableRight = db.getTable(entryRight);

            rel = DataRelationship('tableLeft', tableLeft, 'tableRight', tableRight, ...
                'isManyLeft', true, 'isManyRight', false, p.Unmatched); 

            db.addRelationship(rel);
        end

        function addRelationshipManyToMany(db, entryLeft, entryRight, varargin)
            p = inputParser;
            p.KeepUnmatched = true;
            p.addRequired('entryLeft', @ischar);
            p.addRequired('entryRight', @ischar);
            p.addOptional('entryJunction', '', @ischar);
            p.parse(entryLeft, entryRight, varargin{:});
            entryJunction = p.Results.entryJunction;

            tableLeft = db.getTable(entryLeft);
            tableRight = db.getTable(entryRight);
            if ~isempty(entryJunction)
                tableJunction = db.getTable(entryJunction);
            else
                tableJunction = [];
            end

            rel = DataRelationship('tableLeft', tableLeft, 'tableRight', tableRight, ...
                'tableJunction', tableJunction, ...
                'isManyLeft', true, 'isManyRight', true, p.Unmatched); 
            db.addRelationship(rel);
            
            if ~isempty(tableJunction)
                % a junction relationship connects entryLeft to entryRight through entryJunction
                % this function builds the constituent relationships entryLeft to entryJunction
                % and entryJunction to entryRight. Typically when adding a junction relationship
                % to the database, these constituent 1:1 relationships will be automatically
                % added as well
                [relLeftToJunction, relJunctionToRight] = ...
                    DataRelationship.buildRelationshipsToJunction(...
                    rel, tableLeft, tableRight, tableJunction);
                
                db.addRelationship(relLeftToJunction);
                db.addRelationship(relJunctionToRight);
            end
        end

        function [matchIdx, tableReference] = getRelatedIdx(db, table, referenceName, varargin)
            % return a cell of matches in the referenced table for each
            % entry in table.
            % matchIdx is a table.nEntries x 1 cell array or variably sized vector 
            % of entry idx into tableReference
            % tableReference the table in the database referenced by the
            % referenceName
            %
            % optional param/values:
            % combine = true [default] or false
            %   if true, matchIdx will be a vector of idx
            %   if false, matchIdx be a cell array of idx for each row
            % fillMissingWithNan = true [ default] or false. meaningful
            %   only for combine == true and *toOne relationships.
            % If true, a NaN will be substituted when no match is found in the referenced
            % table, which ensures 1:1 correspondence between rows in table
            % and matchIdx
            p = inputParser;
            p.addParamValue('combine', true, @islogical);
            p.addParamValue('fillMissingWithNaN', true, @islogical);
            p.addParamValue('forceOneToOne', false, @islogical);
            p.parse(varargin{:});
            
            forceOneToOne = p.Results.forceOneToOne;
            combine = p.Results.combine | forceOneToOne;
            fillMissingWithNaN = p.Results.fillMissingWithNaN | forceOneToOne;
         
            relCell = db.findAllRelationships(table.entryName, referenceName);
            
            if isempty(relCell)
                error('Could not find matching relationship');
            end
            
            for i = 1:numel(relCell)
                rel = relCell{i};
                tableReference = db.getTable(rel.entryNameRight);
                if rel.isJunction
                    tableJunction = db.getTable(rel.entryNameJunction);
                else
                    tableJunction = [];
                end

                newMatchIdx = rel.match(table, tableReference, ...
                    'tableJunction', tableJunction, 'combine', combine, ...
                    'fillMissingWithNaN', fillMissingWithNaN, ...
                    'forceOneToOne', forceOneToOne);
                
                if i == 1
                    matchIdx = newMatchIdx;
                else
                    % combine matches from each matching relationship
                    % initially intended for many2many links involving the
                    % same table (i.e. internal links). There will be two
                    % relatinoships binding this table to the junction
                    % table, one on the left and one on the right, but the
                    % original table should have only one "combined"
                    % reference to the junction table
                    if iscell(matchTableCell)
                        % if 'combine' is false
                        matchIdx = cellfun(@(old, new) unique([old new]), ...
                            matchIdx, newMatchIdx, 'UniformOutput', false);
                    else
                        % if 'combine' is true (passed to matchLeftInRight
                        % above)
                        if ~forceOneToOne
                            matchIdx = unique(matchIdx, newMatchIdx);
                        end
                    end
                end
            end
        end
        
        function result = matchRelated(db, table, referenceName, varargin)
            % notable optional param values:
            % combine = boolean (default true)
            %  if false, returns a cell array of match-tables for each entry
            %  in table. if true, returns one table containing all of the
            %  matched rows.
            % fillMissingWithEmpty = boolean (default true). relevant only
            % for combine == true and *toOne relationships. If true, insert
            % an "empty" row into the match table when no matches are
            % found. This ensures that the matched table will correspond
            % 1:1 to the lookup table.
            p = inputParser();
            p.addParamValue('combine', true, @islogical); % true - return single table, false - cell array of tables with matches for each entry in table
            p.addParamValue('fillMissingWithEmpty', true, @islogical);
            p.addParamValue('forceOneToOne', false, @islogical);
            p.parse(varargin{:});
            [matchIdx, tableReference] = db.getRelatedIdx(table, referenceName, ...
                'combine', p.Results.combine, 'fillMissingWithNaN', p.Results.fillMissingWithEmpty, ...
                'forceOneToOne', p.Results.forceOneToOne);
            
            if iscell(matchIdx)
                result = cellfun(@(idx) tableReference.select(idx), matchIdx, 'UniformOutput', false);
            else
                result = tableReference.select(matchIdx);
            end
        end

        function printRelationships(db)
            for i = 1:db.nRelationships
                fprintf('%s', db.relationships{i}.describe());
            end
            fprintf('\n');
        end
    end

    methods % Dynamic property access
        function [value appliedNext] = mapDynamicPropertyAccess(db, name, typeNext, subsNext)
            if db.hasTable(name)
                value = db.getTable(name);
            else
                value = DynamicClass.NotSupported;
            end
            appliedNext = false;
        end
        
        function obj = dynamicPropertyAssign(obj, name, value, s) %#ok<INUSD>
            obj = DynamicClass.NotSupported;
        end
    end

    methods % Views
        function applyView(db, dv, varargin)
            p = inputParser;
            p.addParamValue('reapply', false, @islogical);
            p.parse(varargin{:});
            reapply = p.Results.reapply;
            
            if isa(dv, 'DatabaseView')
                dvCell = {dv};
            elseif iscell(dv)
                dvCell = dv;
            else
                error('Must be a DatabaseView or cell array of DatabaseView');
            end
                
            assert(all(cellfun(@(dv) isa(dv, 'DatabaseView'), dvCell)), ...
                'Must be a DatabaseView instance');

            for iDv = 1:length(dvCell)
                dv = dvCell{iDv};

                apply = true;
                if db.hasViewApplied(dv)
                    if reapply
                        debug('Reapplyling DatabaseView : %s\n', dv.describe());
                        apply = true;
                    else
                        apply = false;
                        debug('Already applied DatabaseView : %s\n', dv.describe());
                    end
                end
                if apply
                    % load required sources
                    db.loadSource(dv.getRequiredSources());

                    % apply required views
                    db.applyView(dv.getRequiredViews());

                    % apply this view
                    if ~reapply
                        debug('Applying DatabaseView : %s\n', dv.describe());
                    end
                    dv.applyToDatabase(db);
                    db.viewsApplied{end+1} = dv;
                end
            end
        end

        function tf = hasViewApplied(db, dv)
            assert(isa(dv, 'DatabaseView'), 'Must be a DatabaseView instance');
            matches = cellfun(@(v) isequal(dv, v), db.viewsApplied);
            tf = any(matches);
        end

        function str = get.viewsAppliedDescription(db)
            names = cellfun(@(dv) dv.describe(), db.viewsApplied, ...
                'UniformOutput', false);
            str = strjoin(names, ', ');
        end
    end

    methods % Data sources
        function loadSource(db, src, varargin)
            p = inputParser;
            p.addRequired('source', @(s) iscell(s) || isa(s, 'DataSource'));
            p.addParameter('reload', false, @islogical);
            p.parse(src, varargin{:});
            src = p.Results.source;
            reload = p.Results.reload;

            if isempty(src)
                return;
            end
            
            if isa(src, 'DataSource')
                srcCell = {src};
            elseif iscell(src)
                srcCell = src;
            else
                error('Must be a DataSource or cell array of DataSource instances');
            end
                
            assert(all(cellfun(@(src) isa(src, 'DataSource'), srcCell)), ...
                'Must be a DataSource instance');

            for iSrc = 1:numel(srcCell)
                src = srcCell{iSrc};

                assert(isa(src, 'DataSource'), 'Must be a DataSource instance');

                if db.hasSourceLoaded(src)
                    if ~reload
                        debug('Already loaded source %s, skipping\n', src.describe());
                        continue;
                    else
                        debug('Reloading source %s\n', src.describe());
                    end
                end

                % check for data sources with the same name
                srcName = src.getName();
                [tf, ~, srcIdx] = db.hasSourceWithName(srcName);
                if tf
                    if ~reload
                        debug('DataSource conflicts with source with name %s, skipping\n', src.getName());
                        continue;
                    else
                        debug('Unloading conflicting source with name %s\n', src.getName());
                        db.removeLoadedSources(srcIdx);
                    end
                elseif db.hasTable(srcName)
                    warning('DataSource conflicts with table with same name %s', srcName);
                end
                    
                if ~reload
                    debug('Loading DataSource : %s\n', src.describe());
                end
                
                % load required sources
                db.loadSource(src.getRequiredSources());
                
                % load this source
                src.loadInDatabase(db);
                db.markSourceLoaded(src); 
            end
        end
        
        function describeSourcesLoaded(db, src)
            for i = 1:numel(db.sourcesLoaded)
                debug('{#FFFF93}%s{none} : %s\n', class(db.sourcesLoaded{i}), db.sourcesLoaded{i}.describe());
            end
        end

        % mark a source loaded in the database, but do not call loadInDatabase
        % i.e. consider it already loaded
        function markSourceLoaded(db, src)
            if isa(src, 'DataSource')
                srcCell = {src};
            elseif iscell(src)
                srcCell = src;
            else
                error('Must be a DataSource or cell array of DataSource instances');
            end
            
            assert(all(cellfun(@(src) isa(src, 'DataSource'), srcCell)), ...
                'Must be a DataSource instance');

            [loaded, ~, ind] = db.hasSourceLoaded(src);
            if ~loaded
                db.sourcesLoaded{end+1} = src;
            else
                db.sourcesLoaded{ind} = src;
            end
        end
        
        function removeLoadedSources(db, idx)
            for i = 1:numel(idx)
                debug('Removing loaded DataSource %s\n', db.sourcesLoaded{idx(i)}.describe());
            end
            db.sourcesLoaded(idx) = [];
        end
        
        function [tf, srcLoaded, ind] = hasSourceLoaded(db, src)
            matches = cellfun(@(s) src.isEquivalent(s), db.sourcesLoaded);
            tf = any(matches);
            if tf
                ind = find(matches, 1, 'first');
                srcLoaded = db.sourcesLoaded{ind};
            else
                srcLoaded = [];
                ind = [];
            end
        end
        
        function [tf, srcCell, ind] = hasSourceWithName(db, name)
            mask = cellfun(@(src) strcmp(src.getName(), name), db.sourcesLoaded);
            tf = any(mask);
            ind = find(mask);
            srcCell = db.sourcesLoaded(ind);
        end
        
        function srcCell = findSourcesByClassName(db, className)
            % return a cell array of all loaded sources src satisfying
            % isa(src, className)
            if ~ischar(className)
                className = class(className);
            end
            
            matches = cellfun(@(s) isa(s, className), db.sourcesLoaded);
            srcCell = db.sourcesLoaded(matches);
        end 

        function str = get.sourcesLoadedDescription(db)
            names = cellfun(@(src) src.describe(), db.sourcesLoaded, ...
                'UniformOutput', false);
            str = strjoin(names, ', ');
        end
        
        function run(db, da, varargin)
            % run analysis
            da.setDatabase(db);
            da.run(varargin{:});
        end
        
        function rerun(db, da, varargin)
            % run analysis
            da.setDatabase(db);
            da.rerun(varargin{:});
        end
    end

    methods(Static)
        function db = loadobj(db)
            assert(isa(db, 'Database'), 'Must load from Database object');

            % set the .database field in all tables, which is marked as transient
            % so that the entire database isn't saved with each table
            tableNames = db.tableMap.keys;
            for i = 1:length(tableNames)
                tableName = tableNames{i};
                db.tableMap(tableName) = db.tableMap(tableName).setDatabase(db);
            end
        end
    end


end
