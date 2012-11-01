classdef Database < DynamicClass & handle

    properties(Hidden)
        tableMap % containers.Map : entryName --> Table
        relationships 
        singularToPluralMap
        pluralToSingularMap

        viewsApplied = {};
        sourcesLoaded = {};
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
                warning('Database already has table with entryName %s, overwriting', entryName);
                % remove old keys
                oldPlural = db.singularToPluralMap(entryName);
                db.pluralToSingularMap.remove(oldPlural);
                db.singularToPluralMap.remove(entryName);
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
                db.updateTable(combined);
            else
                db.addTable(table);
            end
        end

        function table = updateTable(db, table, varargin)
            % replace the current table with 
            assert(isa(table, 'DataTable'), 'table must be a DataTable instance');
            entryName = table.entryName;

            if ~db.hasTable(entryName)
                db.addTable(table, varargin{:});
            else
                oldTable = db.tableMap(entryName);
                assert(isempty(setxor(oldTable.keyFields, table.keyFields)), ...
                    'Key fields of new table must match existing');

                table = table.setDatabase(db);
                db.tableMap(entryName) = table;
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
        
        function tableEntryNameList = get.tableEntryNameList(db)
            tableEntryNameList = db.pluralToSingularMap.keys;
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

        function [tf entryName] = hasTable(db, entryName)
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
        function [referenceNames] = listRelationshipsWith(db, entryName)
            referenceNames = {};
            for iRel = 1:db.nRelationships
                rel = db.relationships{iRel};
                [tf referenceName] = rel.involvesEntryName(entryName);
                if tf
                    referenceNames = [referenceNames referenceName];
                end
            end
        end

        function [matchRel leftToRight] = findRelationship(db, entryName, referenceName)
            % determine whether a relationship from table with entryName referring
            % to the other table as referenceName is found within db.relationships
            % Return the relationship if found or [] if not found

            for iRel = 1:db.nRelationships
                rel = db.relationships{iRel};
                [tf leftToRight] = rel.matchesEntryNameAndReference(entryName, referenceName);
                if tf
                    matchRel = rel;
                    return;
                end
            end

            % not found
            matchRel = [];
            leftToRight = [];
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
            if db.hasRelationship(rel.entryNameLeft, rel.referenceLeftForRight)
                %warning('Overwriting existing relationship %s -> %s', ...
                %    rel.entryNameLeft, rel.referenceLeftForRight);
                db.removeRelationship(rel.entryNameLeft, rel.referenceLeftForRight);
            end

            if db.hasRelationship(rel.entryNameRight, rel.referenceRightForLeft)
                warning('Overwriting existing relationship %s -> %s', ...
                    rel.entryNameRight, rel.referenceRightForLeft);
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

            debug('Adding %s\n', rel.describe());

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

        function addRelationshipManyToMany(db, entryLeft, entryRight, entryJunction, varargin)
            p = inputParser;
            p.KeepUnmatched = true;
            p.addRequired('entryLeft', @ischar);
            p.addRequired('entryRight', @ischar);
            p.addRequired('entryJunction', @ischar);
            p.parse(entryLeft, entryRight, entryJunction, varargin{:});

            tableLeft = db.getTable(entryLeft);
            tableRight = db.getTable(entryRight);
            tableJunction = db.getTable(entryJunction);

            rel = DataRelationship('tableLeft', tableLeft, 'tableRight', tableRight, ...
                'tableJunction', tableJunction, ...
                'isManyLeft', true, 'isManyRight', true, p.Unmatched); 

            db.addRelationship(rel);
        end

        function matchTableCell = matchRelated(db, table, referenceName, varargin)
            [rel leftToRight]  = db.findRelationship(table.entryName, referenceName);

            if leftToRight
                tableReference = db.getTable(rel.entryNameRight);
                if rel.isJunction
                    tableJunction = db.getTable(rel.entryNameJunction);
                    matchTableCell = rel.matchLeftInRight(table, tableReference, ...
                        'tableJunction', tableJunction, varargin{:});
                else
                    matchTableCell = rel.matchLeftInRight(table, tableReference, varargin{:});
                end
            else
                tableReference = db.getTable(rel.entryNameLeft);
                if rel.isJunction
                    tableJunction = db.getTable(rel.entryNameJunction);
                    matchTableCell = rel.matchRightInLeft(tableReference, table, ...
                        'tableJunction', tableJunction, varargin{:});
                else
                    matchTableCell = rel.matchRightInLeft(tableReference, table, varargin{:});
                end
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
    end

    methods % Views
        function applyView(db, dv)
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

                if db.hasViewApplied(dv)
                    debug('Already applied\n');
                else
                    % load required sources
                    db.loadSource(dv.getRequiredSources());

                    % apply required views
                    db.applyView(dv.getRequiredViews());

                    % apply this view
                    debug('Applying DatabaseView : %s\n', dv.describe());
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
        function loadSource(db, src)
            if isa(src, 'DataSource')
                srcCell = {src};
            elseif iscell(src)
                srcCell = src;
            else
                error('Must be a DataSource or cell array of DataSource instances');
            end
                
            assert(all(cellfun(@(src) isa(src, 'DataSource'), srcCell)), ...
                'Must be a DataSource instance');

            for iSrc = 1:length(srcCell)
                src = srcCell{iSrc};

                assert(isa(src, 'DataSource'), 'Must be a DataSource instance');

                if db.hasSourceLoaded(src)
                    debug('Already loaded source %s, skipping\n', src.describe());
                else
                    debug('Loading DataSource : %s\n', src.describe());
                    % load required sources
                    db.loadSource(src.getRequiredSources());

                    % load this source
                    src.loadInDatabase(db);
                    db.markSourceLoaded(src); 
                end
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

            if ~db.hasSourceLoaded(src)
                db.sourcesLoaded{end+1} = src;
            end
        end

        function tf = hasSourceLoaded(db, src)
            matches = cellfun(@(s) isequal(src, s), db.sourcesLoaded);
            tf = any(matches);
        end

        function str = get.sourcesLoadedDescription(db)
            names = cellfun(@(src) src.describe(), db.sourcesLoaded, ...
                'UniformOutput', false);
            str = strjoin(names, ', ');
        end
    end


end
