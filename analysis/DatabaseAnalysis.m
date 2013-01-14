classdef DatabaseAnalysis < handle & DataSource

    properties(SetAccess=protected)
        % time which the analysis started running
        timeRun

        % has this analysis run already?
        hasRun

        % is the analysis currently running? used by internal functions
        % to allow error-free calling of runOnEntry outside of .run()
        isRunning = false;

        % the result table will be an instance of DatabaseAnalysisResultsTable 
        resultTable

        % will be populated post analysis. All of this info is in .resultTable as well
        successByEntry
        exceptionByEntry
        logByEntry

        % each element contains a struct with fields
        %   .pathNoExt
        %   .fileNameNoExt
        %   .extensions
        %   .name
        %   .caption
        %   .width
        %   .height
        figureInfoByEntry = {};
    end

    properties
        figureExtensions = {'fig', 'png', 'eps', 'svg'};
    end
    
    properties(Access=protected)
        figureInfoCurrentEntry
        currentEntry
    end

    properties(Transient, SetAccess=protected)
        % reference to the current database when running
        database 
    end

    properties(Dependent)
        fieldsAnalysis 
        pathAnalysis 
        pathCurrent
        pathFigures
        htmlFile
    end

    methods(Abstract)
        % return a single word descriptor for this analysis, ignoring parameter
        % settings in param. The results will be stored as a DataTable with this
        % as the entryName
        name = getName(da);

        % return the param to be used when caching
        param = getCacheParam(da);
        
        % return the entryName corresponding to the table in the database which this
        % analysis runs on. The DataTable with this entry name will run this analysis
        % once on each entry and map the results via a 1-1 relationship 
        entryName = getMapsEntryName(da);
    
        % return a list of fields generated by the analysis. These need to be declared
        % ahead of time to simplify many of the caching related features.
        [fields fieldDescriptorMap] = getFieldsAnalysis(da);

        % run this analysis on one entry, entryTable will be a DataTable instance
        % filtered down to one entry
        resultStruct = runOnEntry(da, entry, fields)

    end

    methods % not necessary to override if the defaults are okay

        % determine if this DatabaseAnalysis instance is equivalent to other,
        % an instance which has already been loaded in the Database.
        function tf = isequal(da, other)
            tf = true;
            if ~strcmp(class(da), class(other))
                tf = false;
                return;
            end
            if ~isequal(da.getCacheParam(), other.getCacheParam())
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
        
        % return a cell array of DataSource instances that must be loaded a priori,
        % These sources will ALWAYS be run, even when all analysis can be loaded 
        % from cache. If a source is needed only when doing new analysis, e.g.
        % another analysis this builds upon, include it in getRequiredSourcesForAnalysis
        % instead.
        function sources = getRequiredSources(da)
            sources = {};
        end

        % return a cell array of DataSource instances that must be loaded ONLY
        % when new analysis is to actually be run (not just loading from cache)
        function sources = getRequiredSourcesForAnalysis(da)
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

        % return a list of additional meta fields that resultTable will contain
        % in addition to the analysis field and keyFields
        function [fields fieldDescriptorMap] = getFieldsAdditional(da, table)
            fieldDescriptorMap = ValueMap('KeyType', 'char', 'ValueType', 'any');
            fieldDescriptorMap('success') = BooleanField();
            fieldDescriptorMap('output') = OutputField();
            fieldDescriptorMap('runTimestamp') = DateTimeField();
            fieldDescriptorMap('exception') = UnspecifiedField();
            fieldDescriptorMap('figureInfo') = UnspecifiedField();
            fields = fieldDescriptorMap.keys;
        end
    end

    methods % Constructor
        function da = DatabaseAnalysis(varargin)
            p = inputParser;
            p.addOptional('database', [], @(x) isa(x, 'Database'));
            p.parse(varargin{:});

            da.database = p.Results.database;
        end 
    end

    methods
        function checkHasRun(da)
            if ~da.hasRun
                error('Analysis has not yet been run. Please call .run(database) first.');
            end
        end

        function run(da, varargin)
            p = inputParser();
            p.addParamValue('database', [], @(db) isempty(db) || isa(db, 'Database'));
            % optionally select subset of fields for analysis
            p.addParamValue('fields', da.fieldsAnalysis, @iscellstr); 
            % check the cache for existing analysis values
            p.addParamValue('loadCache', true, @islogical); 
            % save computed analysis values to the cache
            p.addParamValue('saveCache', true, @islogical); 
            % rerun any failed entries from prior runs, true value supersedes
            % .getRerunFailed() method return value, which is the class default
            p.addParamValue('rerunFailed', false, @islogical); 
            % don't run any new analysis, just load whatever possible from the cache
            p.addParamValue('loadCacheOnly', false, @islogical);
            % wrap the runOnEntry method in a try/catch block so that errors
            % on one entry don't halt the analysis
            p.addParamValue('catchErrors', true, @islogical);
            % generate a new report and figures folder even if no new analysis
            % was run, useful if issues encountered with report generation
            p.addParamValue('forceReport', false, @islogical);
            p.parse(varargin{:});

            fieldsAnalysis = p.Results.fields;
            loadCache = p.Results.loadCache;
            saveCache = p.Results.saveCache;
            rerunFailed = p.Results.rerunFailed;
            loadCacheOnly = p.Results.loadCacheOnly;
            catchErrors = p.Results.catchErrors;
            forceReport = p.Results.forceReport;
            db = p.Results.database;

            % get analysis name
            name = da.getName();
            assert(isvarname(name), 'getName() must return a valid variable name');
            debug('Preparing for analysis : %s\n', name);

            if ~isempty(db)
                da.database = db;
            elseif isempty(db) && isempty(da.database)
                error('Please set .database or provide ''database'' param value');
            else
                db = da.database;
            end

            da.isRunning = true;

            % mark run timestamp consistently for all entries
            % we'll keep this timestamp unless we don't end up doing any new
            % analysis, then we'll just pick the most recent prior timestamp
            da.timeRun = now;
            fieldsAdditional = da.getFieldsAdditional();

            [allFieldsAnalysis allDFDAnalysis] = da.getFieldsAnalysis();
            for iField = 1:length(fieldsAnalysis)
                dfd = allDFDAnalysis(fieldsAnalysis{iField});
                fieldsAnalysisIsDisplayable(iField) = dfd.isDisplayable();
            end

            % keep track of whether we need to re-cache the result table 
            resultTableChanged = false;
            
            % load all data sources
            db.loadSource(da.getRequiredSources());
            
            % load all data views 
            db.applyView(da.getRequiredViews());

            % get the appropriate table to map
            entryName = da.getMapsEntryName();
            table = db.getTable(entryName);
            % enforce singular for 1:1 relationship to work
            entryName = table.entryName;

            % prefilter the table further if requested (database views also do this)
            table = da.preFilterTable(table);

            % build the resultTable as a LoadOnDemandTable
            % this will be a skeleton containing all of the fields for the analysis
            % none of which will be loaded initially
            resultTable = DatabaseAnalysisResultsTable(da);
            da.database.addRelationshipOneToOne(resultTable.entryName, entryName); 

            % mask by entry of which entries must be run
            maskToAnalyze = true(resultTable.nEntries, 1);
            
            % here we ask resultTable to check cache existence and timestamps
            % for all entries in the table. Timestamps are checked against
            if loadCache
                % load the table itself from cache and copy over additional field
                % values from the cache hit if present
                %if resultTable.hasCache()
                    % LoadOnDemandMappedTable will automatically add all rows in
                    % resultTable that are missing in the cached copy (i.e. rows
                    % in the mapped table that were added after the cache was generated).
                    % 
                    % So we don't need to worry about adding these missing rows

                    % IMPORTANT
                    % for now, all fields are cached to disk, so this step is unnecessary
                    % uncomment this if any fields are cached with the table
                    % because then loadFromCache will need to be called to retrieve
                    % these values. All fields currently are loaded by the .loadFields()
                    % call below.
                    % 
                    % resultTable = resultTable.loadFromCache();
                %end

                % now we search for field values in fieldsAnalysis in the cache
                debug('Checking cached field timestamps\n');

                % check the cache timestamps to determine
                % which entry x field cells are out of date 
                resultTable = resultTable.loadFields('loadCacheTimestampsOnly', true);
                % load success so that we can check failed entries later
                resultTable = resultTable.loadFields('fields', 'success', 'loadCacheOnly', true);
                resultTable = resultTable.updateInDatabase();
                cacheTimestamps = resultTable.cacheTimestampsByEntry;

                % check for modifications to related tables that should invalidate
                % the cached results. Entries with cached fields older than the 
                % most recent modification to the related entry names will be 
                % re run. The list of table entryNames to check is returned by
                % da.getEntryNamesChangesInvalidateCache()
                %
                % Also for the list of referenced entry names  returned by 
                % da.getReferencesRelatedEntryNames(), generate a warning 
                % if the cache is older than this value, but don't re run it
                tableListCacheWarning = makecol(da.getReferencesRelatedEntryNames());
                tableListCacheInvalidate = makecol(da.getEntryNamesChangesInvalidateCache());

                maskCacheInvalidates = false(resultTable.nEntries, 1);
                
                if ~isempty(tableListCacheWarning) || ~isempty(tableListCacheInvalidate)
                    % get the most recent update for each table list
                    cacheWarningReference = db.getLastUpdated(tableListCacheWarning);
                    cacheInvalidateReference = db.getLastUpdated(tableListCacheInvalidate);

                    cacheWarningEntryCount = 0;
                    for iField = 1:length(fieldsAnalysis)
                        field = fieldsAnalysis{iField};
                        for iEntry = 1:resultTable.nEntries
                            timestamp = cacheTimestamps(iEntry).(field);
                            if isempty(timestamp) || timestamp < cacheWarningReference 
                                cacheWarningEntryCount = cacheWarningEntryCount + 1;
                            end
                            if isempty(timestamp) || timestamp < cacheInvalidateReference
                                maskCacheInvalidates(iEntry) = true;
                            end
                        end
                    end
                    if cacheWarningEntryCount > 0 
                        debug('Warning: This DatabaseAnalysis has % entries with cached field values older than\nthe modification time of tables this analysis references (see getReferencesRelatedEntryNames()).\nUse .deleteCache() or call with ''loadCache'', false to force a full re-run.\n', ...
                            cacheWarningEntryCount);
                    end
                    if any(maskCacheInvalidates)
                        debug('Warning: This DatabaseAnalysis has % entries with cached field values older than\nthe modification time of tables this analysis depends upon (see getEntryNamesChangesInvalidatesCache()).\nUse .deleteCache() or call with ''loadCache'', false to force a full re-run.\n', ...
                            nnz(maskCacheInvalidates));
                    end
                end
                
                % now we determine which entries have fully cached field values
                % and thus need not be rerun
                timestampsByEntry = resultTable.cacheTimestampsByEntry;
                for iEntry = 1:resultTable.nEntries
                    allLoaded = true; 
                    for iField = 1:length(fieldsAnalysis)
                        field = fieldsAnalysis{iField};
                        if isempty(timestampsByEntry(iEntry).(field))
                            allLoaded = false;
                            break;
                        end
                    end

                    % reanalyze if any fields are missing, or if the cache is invalid
                    maskToAnalyze(iEntry) = ~allLoaded || maskCacheInvalidates(iEntry);

                    % check whether this row has ever been run in the cache
                    % which is useful when the analysis does not use fields
                    if isempty(resultTable{iEntry}.runTimestamp)
                        maskToAnalyze(iEntry) = true;
                    end
                end

                debug('Valid cached field values found for %d of %d entries\n', nnz(~maskToAnalyze), length(maskToAnalyze));
            end

            % NOTE: At this point you cannot assume that resultsTable and table (the mapped table)
            % are in the same order. They simply have the same number of rows mapped via
            % key field equivalence (1:1 relationship)

            % here we analyze entries that haven't been loaded from cache
            if ~loadCacheOnly
                % do we re-run failed runs from last time
                if da.getRerunCachedUnsuccessful() || rerunFailed
                    maskFailed = makecol(~resultTable.success);
                    debug('Rerunning on %d entries which failed last time\n', nnz(maskFailed));
                    % also reanalyze any rows which were listed as unsuccessful
                    maskToAnalyze = maskToAnalyze | maskFailed;
                end

                savedAutoApply = resultTable.autoApply;
                resultTable = resultTable.setAutoApply(false);
                
                nAnalyze = nnz(maskToAnalyze);
                if nAnalyze > 0
                    idxAnalyze = find(maskToAnalyze);

                    resultTableChanged = true;
                    
                    debug('Running analysis %s on %d of %d %s entries\n', name, ...
                        nAnalyze, table.nEntries, entryName);
                    
                    % load sources required ONLY for new analysis
                    da.database.loadSource(da.getRequiredSourcesForAnalysis());
                    
                    % actually run the analysis
                    for iAnalyze = 1:nAnalyze
                        iResult = idxAnalyze(iAnalyze);

                        % find the corresponding entry in the mapped table via the database
                        if maskToAnalyze(iResult)
                            resultEntry = resultTable(iResult).apply();
                            entry = resultEntry.getRelated(entryName);
                            if entry.nEntries > 1
                                debug('WARNING: Multiple matches for analysis row, check uniqueness of keyField tuples in table %s. Choosing first.\n', entryName);
                                entry = entry.select(1);
                            elseif entry.nEntries == 0
                                % this likely indicates a bug in building / loading resultTable from cache
                                debug('WARNNG: Could not find match for resultTable row in order to do analysis');
                                success = false;
                            end
                        end

                        description = entry.getKeyFieldValueDescriptors();
                        description = description{1};
                        progressStr = sprintf('[%4.1f %%]', iAnalyze/nAnalyze*100);
                        fprintf('\n');
                        tcprintf('bright yellow', '____________________________________________________\n');
                        tcprintf('bright yellow', '%s Running analysis on %s\n', progressStr, description);
                        tcprintf('bright yellow', '____________________________________________________\n');
                        fprintf('\n');
                        
                        % for saveFigure to look at 
                        da.currentEntry = entry;

                        % open a temporary file to use as a diary to capture all output
                        diary off;
                        diaryFile = tempname(); 
                        diary(diaryFile);

                        % clear the figure info for saveFigure to use
                        da.figureInfoCurrentEntry = [];

                        % try calling the runOnEntry callback
                        if catchErrors
                            try
                                resultStruct = da.runOnEntry(entry, fieldsAnalysis); 
                                exc = [];
                                success = true;
                            catch exc 
                                tcprintf('red', 'EXCEPTION: %s\n', exc.getReport);
                                success = false;
                            end
                        else
                            resultStruct = da.runOnEntry(entry, fieldsAnalysis); 
                            exc = [];
                            success = true;
                        end

                        % warn if not all fields requested were returned
                        % use the requested list fieldsAnalysis, a subset of dt.fieldsAnalysis
                        if success
                            missingFields = setdiff(fieldsAnalysis, fieldnames(resultStruct));
                            if ~isempty(missingFields)
                                debug('WARNING: analysis on this entry did not return fields: %s\n', ...
                                    strjoin(missingFields, ', '));
                            end
                            % warn if the analysis returned extraneous fields as a reminder to add them
                            % to .getFieldsAnalysis. Fields in dt.fieldsAnalysis but not fieldsAnalysis are okay
                            extraFields = setdiff(fieldnames(resultStruct), da.fieldsAnalysis);
                            if ~isempty(missingFields)
                                debug('WARNING: analysis on this entry returned extra fields not listed in .getFieldsAnalysis(): %s\n', ...
                                    strjoin(extraFields, ', '));
                            end
                        end

                        % load the output from the diary file
                        diary('off');
                        output = fileread(diaryFile);
                        % don't clutter with temp files
                        if exist(diaryFile, 'file')
                            delete(diaryFile);
                        end

                        if success
                            tcprintf('light green', 'Analysis ran successfully on this entry\n');
                            % Copy only fieldsAnalysis that were returned.
                            % Fields in dt.fieldsAnalysis but not fieldsAnalysis are okay
                            [fieldsCopy fieldsReturnedMask] = intersect(da.fieldsAnalysis, fieldnames(resultStruct));
                            fieldsCopyIsDisplayable = fieldsAnalysisIsDisplayable(fieldsReturnedMask); 
                            for iField = 1:length(fieldsCopy)
                                field = fieldsCopy{iField};
                                % don't keep any values in the table, this way we don't run out of memory as the
                                % analysis drags on
                                % Displayable field values needed for report generation will be reloaded
                                % later on in this function
                                resultTable = resultTable.setFieldValue(iResult, field, resultStruct.(field), ...
                                    'saveCache', saveCache, 'storeInTable', false);
                            end
                        end

                        % set all of the additional field values
                        resultTable = resultTable.setFieldValue(iResult, 'success', success, 'saveCache', saveCache);
                        resultTable = resultTable.setFieldValue(iResult, 'output', output, 'saveCache', saveCache);
                        resultTable = resultTable.setFieldValue(iResult, 'runTimestamp', da.timeRun, 'saveCache', saveCache);
                        resultTable = resultTable.setFieldValue(iResult, 'exception', exc, 'saveCache', saveCache);
                        resultTable = resultTable.setFieldValue(iResult, 'figureInfo', da.figureInfoCurrentEntry, 'saveCache', saveCache);
                    end
                end

                resultTable = resultTable.apply();
                resultTable = resultTable.setAutoApply(savedAutoApply);
            end

            resultTable.updateInDatabase();

            % now fill in all of the info fields of this class with the full table data
            da.successByEntry = resultTable.getValues('success') > 0;                
            da.exceptionByEntry = resultTable.getValues('exception');
            da.figureInfoByEntry = resultTable.getValues('figureInfo');
            da.logByEntry = resultTable.getValues('output');
            da.resultTable = resultTable;

            % mark loaded in database
            da.database.markSourceLoaded(da);

            if ~resultTableChanged && ~forceReport
                % if we haven't run new analysis, no need to build a report
                % so just use the timestamp from the most recent prior run
                dfd = da.resultTable.fieldDescriptorMap('runTimestamp');
                timeRunList = dfd.getAsDateNum(da.resultTable.getValues('runTimestamp'));
                if ~isempty(timeRunList)
                    da.timeRun = max(timeRunList);
                end
            else
                % here we're writing the report
                % before we do this, we need to load the values of all displayable fields
                % and additional fields used in the report
                fieldsAnalysisDisplayable = intersect(da.resultTable.fieldsAnalysis, da.resultTable.fieldsDisplayable);
                fieldsToLoad = union(fieldsAnalysisDisplayable,  da.resultTable.fieldsAdditional);
                da.resultTable = da.resultTable.loadFields('fields', fieldsToLoad, 'loadCacheOnly', true);
                da.resultTable.updateInDatabase();
                
                % make sure analysis path exists
                mkdirRecursive(da.pathAnalysis);
                chmod(MatdbSettingsStore.settings.permissionsAnalysisFiles, da.pathAnalysis);
                if exist(da.pathFigures, 'dir')
                    chmod(MatdbSettingsStore.settings.permissionsAnalysisFiles, da.pathFigures);
                    for i = 1:length(da.figureExtensions)
                        path = fullfile(da.pathFigures, da.figureExtensions{i});
                        if exist(path, 'dir')
                            chmod(MatdbSettingsStore.settings.permissionsAnalysisFiles, path);
                        end
                    end
                end

                % sym link figures from prior runs to the current analysis folder
                da.linkOldFigures('saveCache', saveCache);
                % save the html report (which will copy resources folder over too)
                da.saveAsHtml();

                % link from analysisName.html to index.html for easy browsing
                da.linkHtmlAsIndex();

                % link this timestamped directory to current for easy browsing
                da.linkAsCurrent();

            end

            if saveCache && resultTableChanged
                % this isn't necessary right now as all values in the table are cached
                % separetely from the table. You must uncomment this if there are field values
                % saved with the table in the future (as well as the section above where 
                % the resultTable is loaded from cache)
                %
                % Cached field values have been cached as they were generated already
                % da.resultTable.cache('cacheValues', false);
            end

            da.hasRun = true;
            da.isRunning = false;
        end

        function saveFigure(da, figh, figName, figCaption)
            % use this to save figures while running the analysis
            if nargin < 4
                figCaption = '';
            end

            drawnow;
            if isempty(da.isRunning) || ~da.isRunning
                debug('Figure %s would be saved when run via .run()\n', figName);
                return;
            end

            entryTable = da.currentEntry;

            assert(entryTable.nEntries == 1);

            exts = da.figureExtensions;
            nExts = length(exts);
            success = false(nExts, 1);
            fileList = cell(nExts, 1);
            tcprintf('light cyan', 'Saving figure %s as %s\n', figName, strjoin(exts, ', '));
            for i = 1:nExts
                ext = exts{i};
                fileName = da.getFigureName(entryTable, figName, ext);
                mkdirRecursive(fileparts(fileName));
                if strcmp(ext, 'svg')
                    % Save SVG
                    try
                        plot2svg(fileName, figh);
                        success(i) = true;
                    catch exc
                        tcprintf('light red', 'WARNING: Error saving to svg\n');
                        tcprintf('light red', exc.getReport());
                    end
                elseif strcmp(ext, 'fig')
                    % Save FIG
                    try
                        saveas(figh, fileName);
                        success(i) = true;
                    catch exc
                        tcprintf('light red', 'WARNING: Error saving to fig\n');
                        tcprintf('light red', exc.getReport());
                    end
                else
                    % Save PNG, EPS, etc.
                    try
                        exportfig(figh, fileName, 'format', ext, 'resolution', 300);
                        success(i) = true;
                    catch exc
                        tcprintf('light red', 'WARNING: Error saving to %s', ext);
                        tcprintf('light red', exc.getReport());
                        fprintf('\n');
                    end
                end
                fileList{i} = GetFullPath(fileName);
            end

            % log figure infomration
            figInfo.name = figName;
            figInfo.caption = figCaption;
            [figInfo.width figInfo.height] = getFigSize(figh);
            figInfo.extensions = exts;
            figInfo.fileLinkList = fileList;
            figInfo.fileList = fileList;
            figInfo.saveSuccessful = success;
            figInfo = orderfields(figInfo);

            % add to figure info cell
            if isempty(da.figureInfoCurrentEntry)
                da.figureInfoCurrentEntry = figInfo;
            else
                da.figureInfoCurrentEntry(end+1) = figInfo;
            end
        end

        function fileName = getFigureName(da, entryTable, figName, ext)
            % construct figure name that looks like:
            % {{analysisRoot}}/figures/ext/figName.{{keyField descriptors}}.ext
            assert(entryTable.nEntries == 1);
            descriptors = entryTable.getKeyFieldValueDescriptors();

            path = fullfile(da.pathFigures, ext);
            fileName = fullfile(path, sprintf('%s.%s.%s', figName, descriptors{1}, ext));
            fileName = GetFullPath(fileName);
        end

        % create a symlink to index.html
        function linkHtmlAsIndex(da)
            da.checkHasRun();
            htmlFile = da.htmlFile;
            filePath = fileparts(htmlFile);
            indexLink = fullfile(filePath, 'index.html');
            if exist(indexLink, 'file')
                cmd = sprintf('rm "%s"', indexLink);
                [status, message] = unix(cmd);
                if status
                    fprintf('Error replacing index.html symlink:\n');
                    fprintf('%s\n', message);
                end
            end
            makeSymLink(htmlFile, indexLink);
            chmod(MatdbSettingsStore.settings.permissionsAnalysisFiles, indexLink);
        end

        % symlink my analysis directory to "current" for ease of navigation
        function linkAsCurrent(da)
            da.checkHasRun();
            currentPath = GetFullPath(da.pathCurrent);
            thisPath = GetFullPath(da.pathAnalysis);
            if exist(currentPath, 'dir')
                cmd = sprintf('rm "%s"', currentPath);
                [status, message] = unix(cmd);
                if status
                    fprintf('Error replacing current symlink:\n');
                    fprintf('%s\n', message);
                end
            end
            makeSymLink(thisPath, currentPath);
            chmod(MatdbSettingsStore.settings.permissionsAnalysisFiles, currentPath);
        end

        % symlink all figures loaded from cache that are not saved in the same
        % directory as the most recently generated figures
        function linkOldFigures(da, varargin)
            p = inputParser;
            p.addParamValue('saveCache', true, @islogical);
            p.parse(varargin{:});
            saveCache = p.Results.saveCache;
            da.checkHasRun();

            if ~isunix && ~ismac 
                % TODO add support for windows nt junctions 
                return;
            end

            debug('Creating symbolic links to figures saved in earlier runs\n');
            figurePath = da.pathFigures;
            nEntries = da.resultTable.nEntries;

            for iEntry = 1:nEntries
                entry = da.resultTable(iEntry);
                info = entry.getValue('figureInfo');
                madeChanges = false;

                for iFigure = 1:length(info)
                    figInfo = info(iFigure);
                    for iExt = 1:length(figInfo.extensions)
                        mostRecentLink = figInfo.fileLinkList{iExt};
                        thisRunLocation = da.getFigureName(entry, figInfo.name, figInfo.extensions{iExt}); 

                        if ~strcmp(mostRecentLink, thisRunLocation)
                            % point the symlink at the original file, not at the most recent link
                            % to avoid cascading symlinks
                            actualFile = figInfo.fileList{iExt};
                            success = makeSymLink(actualFile, thisRunLocation);
                            if success
                                % change the figure info link location, not the actual file path
                                info(iFigure).fileLinkList{iExt} = thisRunLocation;
                                madeChanges = true;
                                
                                % expose permissions on the symlink and the
                                % original file, just in case
                                chmod(MatdbSettingsStore.settings.permissionsAnalysisFiles, {actualFile, thisRunLocation});
                            end
                        end
                    end
                end

                % update the figure info in the result table
                if madeChanges
                    da.resultTable = da.resultTable.setFieldValue(iEntry, 'figureInfo', ...
                        info, 'saveCache', saveCache);
                end
            end

        end

        function viewAsHtml(da)
            da.checkHasRun();
            fileName = da.htmlFile; 
            if ~exist(fileName, 'file')
                html = da.saveAsHtml();
            end
            HTMLWriter.openFileInBrowser(fileName);
        end
        
        function html = saveAsHtml(da)
            da.checkHasRun();
            fileName = da.htmlFile;
            debug('Saving HTML Report to %s\n', fileName);
            html = HTMLDatabaseAnalysisWriter(fileName);
            html.generate(da);
            chmod(MatdbSettingsStore.settings.permissionsAnalysisFiles, html.fileName);
            chmod(MatdbSettingsStore.settings.permissionsAnalysisFiles, html.resourcesPathStore, 'recursive', true);
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

    methods % Dependent properties
        function path = get.pathAnalysis(da)
            da.checkHasRun();
            if isempty(da.timeRun)
                path = '';
            else
                root = getFirstExisting(MatdbSettingsStore.settings.pathListAnalysis);
                name = da.getName();
                timestr = datestr(da.timeRun, 'yyyy-mm-dd HH.MM.SS');
                path = GetFullPath(fullfile(root, name, timestr));
            end
        end

        function path = get.pathCurrent(da)
            root = getFirstExisting(MatdbSettingsStore.settings.pathListAnalysis);
            name = da.getName();
            path = GetFullPath(fullfile(root, name, 'current'));
        end

        function path = get.pathFigures(da)
            path = GetFullPath(fullfile(da.pathAnalysis, 'figures'));
        end

        function fields = get.fieldsAnalysis(da)
            fields = da.getFieldsAnalysis();
        end

        function htmlFile = get.htmlFile(da)
            name = da.getName();
            path = da.pathAnalysis;
            fname = sprintf('%s.html', name);
            htmlFile = GetFullPath(fullfile(path,fname));
        end
    end

    methods % DataSource instantiations 
        % return a string describing this datasource
        function str = describe(da)
            str = da.getName();
        end

        % actually load this into the database, assume all dependencies have been loaded
        function loadInDatabase(da, database)
            da.database = database;
            da.run('loadCache', true, 'loadCacheOnly', true);
        end

        function deleteCache(da)
            if isempty(da.resultTable);
                r = DatabaseAnalysisResultsTable(da);
            else 
                r = da.resultTable;
            end
            r.deleteCache();
        end
    end
end
