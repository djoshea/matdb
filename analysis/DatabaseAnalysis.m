classdef DatabaseAnalysis < handle & Cacheable & DataSource

    properties(Dependent, Abstract)
        % this will be populated with the parameters passed to the analysis
        % before any of the methods below are called on the subclass
        param
    end

    properties

        % time which the analysis started running
        timeRun

        % used by callbacks to store information by entry
        currentEntry
        currentEntryIndex

        resultTable

        successByEntry
        exceptionByEntry
        diaryFileByEntry = {};
        logByEntry = {};

        % each element contains a struct with fields
        %   .pathNoExt
        %   .fileNameNoExt
        %   .extensions
        %   .name
        %   .caption
        %   .width
        %   .height
        figureInfoByEntry = {};

        figureRootPaths  = {'~/npl/analysis/', '/net/home/djoshea/npl/analysis'};
        figureExtensions = {'png', 'eps', 'svg'};
    end

    properties(Transient)
        % reference to the current database when running
        database 
    end

    methods(Abstract)
        % return a single word descriptor for this analysis, ignoring parameter
        % settings in param. The results will be stored as a DataTable with this
        % as the entryName
        name = getName(da);
        
        % return the entryName corresponding to the table in the database which this
        % analysis runs on. The DataTable with this entry name will run this analysis
        % once on each entry and map the results via a 1-1 relationship 
        entryName = getMapsEntryName(da);
    
        % run this analysis on one entry, entryTable will be a DataTable instance
        % filtered down to one entry
        resultStruct = runOnEntry(da, entryTable)

    end

    methods % not necessary to override if the defaults are okay
        function tf = isequal(da, other)
            tf = true;
            if ~strcmp(class(da), class(other))
                tf = false;
                return;
            end
            if ~isequal(da.param, other.param)
                tf = false;
                return;
            end
        end

        function tf = getRerunCachedUnsuccessful(da)
            tf = false;
        end

        % returns a list of entryNames that this analysis references
        % this is used when retrieving analysis results from the cache. If a related
        % table has changed, the analysis will be rerun on all entries.
        function list = getReferencesRelatedEntryNames(da)
            list = {};
        end

        % An analysis runs on each entry of a specific data table, and may reference
        % related tables through relationships in the database. When any of these
        % data tables is modified, this could invalidate the results of an analysis
        % for some or all of the entries. However, for caching to be at all useful
        % we simply issue a warning when using cached analysis results that references
        % a datatable that has changed. We assume that all changes have been additive
        % and do not affect the analysis that has already been run. Thus we only 
        % run the analysis on entries that are missing related rows in this analysis.
        % 
        % However, if this will yield incorrect results, you can specify that
        % when certain tables are changed at all, the entire cached analysis 
        % becomes invalid. Return a list of the .entryName of these tables here.
        function list = getEntryNamesChangesInvalidateCache(da)
            list = {};
        end
        
        % return a cell array of DataSource instances that must be loaded before 
        % running this analysis
        function sources = getRequiredSources(da)
            sources = {};
        end
        
        % return a cell array of DatabaseView instances that must be applied before 
        % running this analysis
        function views = getRequiredViews(da)
            views = {};
        end
        
        % filter the data table as necessary before this analysis is run
        % table.entryName will match the result of getMapsEntryName() above
        % 
        % If the filtering pattern is a common one, consider turning it into a 
        % DatabaseView class and returning an instance from getDatabaseViewsToApply()
        function table = preFilterTable(da, table)
            % default does nothing
        end
    end

    methods
        function resultTable = run(da, db, varargin)
            p = inputParser();
            p.addRequired('db', @(db) isa(db, 'Database'));
            p.addParamValue('loadCache', true, @islogical); 
            p.addParamValue('saveCache', true, @islogical); 
            p.parse(db, varargin{:});

            loadCache = p.Results.loadCache;
            saveCache = p.Results.saveCache;

            name = da.getName();
            assert(isvarname(name), 'getName() must return a valid variable name');
            debug('Preparing for analysis : %s\n', name);

            da.database = db;
            da.timeRun = now;
            
            % load all data sources
            db.loadSource(da.getRequiredSources());
            
            % load all data views 
            db.applyView(da.getRequiredViews());

            % get the appropriate table
            entryName = da.getMapsEntryName();
            table = db.getTable(entryName);

            % prefilter the table further (database views also do this)
            table = da.preFilterTable(table);

            % check cache for existing analysis
            if loadCache && da.hasCache()
                debug('Loading analysis from cache\n');
                [da cacheTimestamp] = da.loadFromCache();

                % check whether we should warn about modifications that could
                % theoretically affect the cached analysis but weren't explicitly
                % returned by getEntryNamesChangesInvalidateCache()
                
                references = makecol(da.getReferencesRelatedEntryNames());
                relevantTableList = [entryName; references];
                lastRelevantUpdate = db.getLastUpdated(relevantTableList);

                if cacheTimestamp < lastRelevantUpdate
                    debug('Warning: This DatabaseAnalysis has been loaded from cache, but references tables modified after the cache was written. Use .deleteCache() to force a full re-run.\n');
                end
                 
                loadedFromCache = true;
                
                resultTable = da.integrateIntoDatabase(da.resultTable, db);
                
                % now need to run the analysis on any new entries that haven't been mapped yet.
                hasResults = table.getRelatedCount(name) > 0;
                maskToAnalyze = makecol(~hasResults);

                if da.getRerunCachedUnsuccessful() 
                    maskFailed = makecol(~resultTable.success);
                    debug('Rerunning on %d entries which failed last time\n', nnz(maskFailed));
                    % also reanalyze any rows which were listed as unsuccessful
                    maskToAnalyze = maskToAnalyze | maskFailed;
                end
                resultTableOld = resultTable;
            else
                maskToAnalyze = true(table.nEntries, 1);
                resultTableOld = [];
                loadedFromCache = false;
            end

            % filter those entries to analyze
            tableAlreadyAnalyzed = table.select(~maskToAnalyze);
            tableAnalyze = table.select(maskToAnalyze);
            debug('Running analysis %s on %d %s entries\n', name, ...
                tableAnalyze.nEntries, entryName);
            
            % create slots for by entry information that must be captured from
            % within the mapped function (runOnEntryWrapper)
            da.figureInfoByEntry = cell(tableAnalyze.nEntries, 1);
            da.diaryFileByEntry = cell(tableAnalyze.nEntries, 1);

            if tableAnalyze.nEntries > 0
                % run the analysis
                [resultTable statusByEntry] = tableAnalyze.map(@da.runOnEntryWrapper, ...
                    'entryName', name, 'entryNamePlural', name, 'addToDatabase', false);

                % read from the diary files the output for each entry
                logByEntry = da.loadDiaryFiles();
                figureInfoByEntry = da.figureInfoByEntry;

                % add meta fields to the table
                % 'success' : boolean indicating whether the run was successful
                % 'output' : contains the raw output to the command window
                % 'exception' : contains any exceptions thrown
                % 'figureInfo' : contains a struct array with info about the figures saved
                resultTable = resultTable.addField('success', [statusByEntry.success] > 0, ...
                    'position', 1, 'fieldDescriptor', BooleanField());
                resultTable = resultTable.addField('output', logByEntry, ...
                    'position', 2, 'fieldDescriptor', OutputField());
                resultTable = resultTable.addField('exception', {statusByEntry.exception}, ...
                    'position', 3, 'fieldDescriptor', UnspecifiedField());
                resultTable = resultTable.addField('figureInfo', figureInfoByEntry, ...
                    'position', 4, 'fieldDescriptor', UnspecifiedField());
            else
                resultTable = [];
            end

            % merge the old table and the new table
            if ~isempty(resultTableOld)
                if isempty(resultTable)
                    resultTable = resultTableOld;
                else
                    resultTable = resultTable.addEntriesFrom(resultTableOld);

                    % ensure a 1-1 ordering by simply querying for the results through
                    % the database
                    resultTable = table.(name);
                    %currentOrder = [find(maskAnalyze); find(~maskAnalyze)];
                    %[~, sortIdx] = sort(currentOrder);
                    %resultTable = resultTable.select(sortIdx);
                end
            end

            resultTable = da.integrateIntoDatabase(resultTable, db);

            % now fill in all of the info fields of this class with the full table data
            da.successByEntry = resultTable.getValues('success') > 0;                
            da.exceptionByEntry = resultTable.getValues('exception');
            da.figureInfoByEntry = resultTable.getValues('figureInfo');
            da.logByEntry = resultTable.getValues('output');
            da.resultTable = resultTable;

            % mark loaded in database
            da.database.markSourceLoaded(da);

            % save cache
            if saveCache && tableAnalyze.nEntries > 0
                da.cache();
            end
        end

        function resultStruct = runOnEntryWrapper(da, entry, entryIndex)
            da.currentEntryIndex = entryIndex; 
            da.currentEntry = entry;
            
            % open a temporary file to use as a diary to capture all output
            diary off;
            diaryFile = tempname(); 
            da.diaryFileByEntry{da.currentEntryIndex} = diaryFile; 
            diary(diaryFile);

            resultStruct = da.runOnEntry(entry);

            % if there's an exception, we won't get here, so load all of the 
            % diary files later in run()
            diary('off');
        end

        function resultTable = integrateIntoDatabase(da, resultTable, db)
            resultTable = resultTable.setDatabase(db);
            resultTable.updateInDatabase();
            mapsName = da.getMapsEntryName();
            db.addRelationshipOneToOne(mapsName, resultTable.entryName);
        end

        function logByEntry = loadDiaryFiles(da)
            diary('off');
            logByEntry = cell(length(da.diaryFileByEntry), 1);
            for i = 1:length(da.diaryFileByEntry)
                file = da.diaryFileByEntry{i};
                logByEntry{i} = fileread(file);
            end
        end

        function saveFigure(da, figh, figName, figCaption)
            % use this to save figures while running the analysis
            if nargin < 4
                figCaption = '';
            end

            entryTable = da.currentEntry;

            assert(entryTable.nEntries == 1);
            fileNameNoExt = da.getFigureNameNoExt(entryTable, figName);
            mkdirRecursive(fileparts(fileNameNoExt));

            exts = da.figureExtensions;
            debug('Saving figure %s as %s\n', figName, strjoin(exts, ', '));
            for i = 1:length(exts)
                ext = exts{i};
                fileName = [fileNameNoExt '.' ext];
                if strcmp(ext, 'svg')
                    try
                        plot2svg(fileName, figh);
                    catch exc
                        warning('Error saving to svg');
                        fprintf(exc.getReport());
                    end
                else
                    try
                        exportfig(figh, fileName, 'format', ext, 'resolution', 300);
                    catch exc
                        warning('Error saving to %s', ext);
                        fprintf(exc.getReport());
                    end
                end
            end

            % log figure infomration
            figInfo.pathNoExt = GetFullPath(fileNameNoExt);
            [~, figInfo.fileNameNoExt] = fileparts(figInfo.pathNoExt);
            figInfo.name = figName;
            figInfo.caption = figCaption;
            figInfo.extensions = exts;
            [figInfo.width figInfo.height] = getFigSize(figh);

            % add to figure info cell
            da.figureInfoByEntry{da.currentEntryIndex}(end+1) = orderfields(figInfo);
        end

        function fileName = getFigureNameNoExt(da, entryTable, figName)
            assert(entryTable.nEntries == 1);
            analysisName = da.getName();
            descriptors = entryTable.getKeyFieldValueDescriptors();
            timestamp = datestr(da.timeRun, 'yyyy-mm-dd/HH.MM.SS');

            figureRootPath = getFirstExisting(da.figureRootPaths);
            path = fullfile(figureRootPath, timestamp, analysisName);
            
            figNameFn = @(descriptor) fullfile(path, sprintf('%s.%s', figName, descriptor));
            fileName = figNameFn(descriptors{1}); 
        end

        function viewAsHtml(da)
            fileName = [tempname() '.html'];
            html = da.saveAsHtml(fileName);
            html.openInBrowser();
        end
        
        function html = saveAsHtml(da, fileName)
            html = HTMLDatabaseAnalysisWriter(fileName);
            html.generate(da);
        end

        function disp(da)
            fprintf('DatabaseAnalysis : %s on %s\n\n', da.getName(), da.getMapsEntryName());
        end
    end

    methods % Cacheable instantiations
        % return the cacheName to be used when instance 
        function name = getCacheName(obj)
            name = obj.getName();
        end

        % return the param to be used when caching
        function param = getCacheParam(obj) 
            param = obj.param;
        end

        function timestamp = getCacheValidAfterTimestamp(obj)
            % my data is valid until the last modification timestamp of the 
            if isempty(obj.database)
                % shouldn't happen when running normally, but could if cache functions
                % are called directly
                debug('Warning: Unable to determine whether analysis cache is valid because no .database found');
                % invalidate the cache
                timestamp = Inf;
            else
                % loop through these tables and find the latest modification time
                list = obj.getEntryNamesChangesInvalidateCache();
                
                % ask the database when the latest modification to these tables was
                timestamp = obj.database.getLastUpdated(list);
            end
        end
    end

    methods % DataSource instantiations 
        % return a string describing this datasource
        function str = describe(da)
            str = da.getName();
        end

        % actually load this into the database, assume all dependencies have been loaded
        function loadInDatabase(da, database)
            da.run(database);
        end
    end
end
