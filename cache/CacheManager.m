classdef CacheManager < handle
    properties
        cachedCacheRootList
    end
    
    properties(Dependent)
        cacheRootList;
    end

    methods
        function rootList = get.cacheRootList(cm)
            if isempty(cm.cachedCacheRootList)
                cm.cachedCacheRootList = MatdbSettingsStore.settings.pathListCache;
            end
            rootList = cm.cachedCacheRootList;
        end
    end

    methods % methods a subclass might wish to override
        function [tf, reason] = isParamValid(cm, param) %#ok<INUSD>
            % determine whether the provided param is acceptable
            tf = true;
            reason = '';
        end

        function assertParamValid(cm, param)
            [tf, reason] = cm.isParamValid(param);
            assert(tf, 'Cache param invalid: %s', reason);
        end

        function tf = checkParamMatch(cm, paramInFile, paramRef)
            cm.assertParamValid(paramInFile);
            cm.assertParamValid(paramRef);
            tf = isequaln(paramInFile, paramRef);
        end

        function str = hashParam(cm, cacheName, param)
            % run param through DataHash to get a hexadecimal hash key
            % cache the last param and result to avoid calling DataHash
            % twice when saving/loading (once for meta, once for data)
            persistent pLastParam;
            persistent pLastHash;
            
            if ~isempty(pLastHash) && cm.checkParamMatch(pLastParam, param)
                str = pLastHash;
            else
                opts.Method = 'SHA-1';
                opts.Format = 'hex'; 
                hashData.param = param;
                hashData.cacheName = cacheName;
                str = DataHash(hashData, opts);
                
                % cache for next time
                pLastHash = str;
                pLastParam = param;
            end
        end
    end

    methods % methods that should remain public
        function printDebugHashMessage(cm, message, cacheName, param)
            debug('%s name = %s:\n', message, cacheName);
            if isstruct(param)
                structdisp(param);
            elseif iscell(param)
                celldisp(param);
            else
                display(param);
            end
        end
        
        function tf = cacheExists(cm, cacheName, param, varargin)
            data = cm.getFileListDataForRead(cacheName, param, varargin{:});
            meta = cm.getFileListMetaForRead(cacheName, param, varargin{:});
            tf = ~isempty(data) && ~isempty(meta);
        end

        % retrieve the timestamp from the newest meta file
        function [timestamp, indexNewest] = retrieveTimestamp(cm, cacheName, param, varargin)
            [indexNewest, timestamp, ~] = cm.retrieveMeta(cacheName, param, varargin{:});
        end

        % retrieve all meta info from the newest meta file
        function [indexNewest, timestamp, separateFields] = retrieveMeta(cm, cacheName, param, varargin)
            p = inputParser();
            p.addParamValue('verbose', false, @isscalar);
            p.KeepUnmatched = true;
            p.parse(varargin{:});
            
            fileList = cm.getFileListMetaForRead(cacheName, param, varargin{:});
            if isempty(fileList)
                indexNewest = [];
                timestamp = [];
                separateFields = [];
                return;
            end
               
            % which meta file in fileList is newest? this determines which
            % data file will be loaded, as the lists are matched
            indexNewest = [];

            % timestamp on the newest meta file
            timestamp = [];
            
            % does this file store separate struct fields as separate variables?
            separateFields = false;

            % turn off value not found warnings
            warnId = 'MATLAB:load:variableNotFound';
            warnStatus = warning('off', warnId);

            for iFile = 1:length(fileList)
                file = fileList{iFile};
                varsToLoad = {'timestamp', 'param', 'separateFields'};
                varsRequired = {'timestamp', 'param'};

                if p.Results.verbose
                    debug('Loading meta file %s\n', file);
                end
                contents = load(file, varsToLoad{:});

                % check has contents 
                if ~isempty(setdiff(varsRequired, fieldnames(contents)))
                    warning('Cache file %s is invalid', file);
                    continue;
                end

                if ~isempty(param) && ~isempty(contents.param) && ~cm.checkParamMatch(contents.param, param)
                    % earlier versions wouldn't save the params if
                    % precomputed
                    warning('Cache param in %s does not match', file);
                    continue;
                end
                
                if p.Results.verbose
                    debug('Meta file has timestamp %s\n', datestr(contents.timestamp));
                end
                if isempty(timestamp) || contents.timestamp > timestamp
                    % this is the current newest meta file
                    timestamp = contents.timestamp;
                    indexNewest = iFile;

                    % retrieve separateFields, default to false
                    if isfield(contents, 'separateFields')
                        separateFields = contents.separateFields;
                    else
                        separateFields = false;
                    end
                end
            end

            % restore warning
            warning(warnStatus);
        end

        function [tf, timestamp] = hasCacheNewerThan(cm, cacheName, param, refTimestamp, varargin)
            timestamp = cm.retrieveTimestamp(cacheName, param, varargin{:});
            tf = ~isempty(timestamp) && timestamp > refTimestamp;
        end

        function [data, timestamp] = loadData(cm, cacheName, param, varargin)
            p = inputParser;
            p.addRequired('cacheName', @ischar);
            p.addRequired('param', @(x) true);
            p.addParamValue('fields', {}, @iscellstr);
            p.addParamValue('verbose', false, @isscalar);
            p.addParamValue('hash', '', @ischar);
            p.parse(cacheName, param, varargin{:});
            
            fields = p.Results.fields;
            
            if p.Results.verbose
                if isempty(p.Results.hash)
                    cm.printDebugHashMessage('LoadData with', cacheName, param);
                else
                    debug('LoadData with manual hash %s\n', p.Results.hash);
                end
            end

            fileList = cm.getFileListDataForRead(cacheName, param, 'hash', p.Results.hash, 'verbose', p.Results.verbose);
            if isempty(fileList)
                % no cache files found
                data = [];
                timestamp = NaN;
                if p.Results.verbose
                    debug('No cache files found to read\n');
                end
                return;
                % error('No cache files found');
            end

            % load the data file with the newest timestamp
            [indexNewest, timestamp, separateFields] = cm.retrieveMeta(cacheName, param, 'verbose', p.Results.verbose, 'hash', p.Results.hash, p.Unmatched);
            if isempty(indexNewest)
                % must have data but not meta
                warning('Data file found without corresponding meta file: \n%s\n', strjoin(fileList, '\n'));
                data = [];
                timestamp = NaN;
                return;
            end
            file = fileList{indexNewest};
            
            % turn off value not found warnings
            warnId = 'MATLAB:load:variableNotFound';
            warnStatus = warning('off', warnId);
            
            if separateFields
                % struct stored as separate fields
                if ~isempty(fields)
                    % load only specific fields
                    varsToLoad = fields;
                else
                    % no fields specified, load all
                    varsToLoad = {};
                end

                if p.Results.verbose
                    debug('Loading data file with separated fields %s\n', file);
                end
                data = load(file, varsToLoad{:});

            else
                % single value in 'data'
                varsToLoad = {'data'};
                contents = load(file, varsToLoad{:}); 
                
                % check has contents 
                if ~isempty(setdiff(varsToLoad, fieldnames(contents)))
                    error('Cache file %s is invalid', file);
                end

                data = contents.data;
            end
            
            if isempty(data)
                % no cache files found
                data = [];
                timestamp = NaN;
                if p.Results.verbose
                    debug('Data read from cache data file is empty\n');
                end
                return;
            end

            % check the contents of data (or the fields itself) for
            % CacheCustomSaveLoadPlaceholder
            if isstruct(data)
                flds = fieldnames(data);
                for iFld = 1:numel(flds)
                    val = data.(flds{iFld});
                    if isa(val, 'CacheCustomSaveLoadPlaceholder')
                        if p.Results.verbose
                            debug('Loading using CacheCustomSaveLoad on field %s\n', flds{iFld});
                        end
                        location = cm.getPathCustomFromHashFileName(file, flds{iFld});
                        data.(flds{iFld}) = val.doCustomLoadFromLocation(location);
                    end
                end
            elseif isa(data, 'CacheCustomSaveLoadPlaceholder')
                if p.Results.verbose
                    debug('Loading using CacheCustomSaveLoad\n');
                end
                location = cm.getPathCustomFromHashFileName(file);
                data = data.doCustomLoadFromLocation(location);
            end
            
            % restore warning
            warning(warnStatus);
        end 

        function timestamp = saveData(cm, cacheName, param, data, varargin)
            p = inputParser;
            p.addRequired('cacheName', @ischar); 
            p.addRequired('param', @(x) true);
            p.addRequired('data', @(x) true);
            p.addParamValue('verbose', false, @isscalar);
            p.addParamValue('hash', '', @ischar);
            p.addParamValue('timestamp', now, @isscalar); % default timestamp is now, but can be overridden 
            
            % optional means of saving a struct array's fields as separate variables
            % within the same mat file, allowing for individual fields to be
            % selectively loaded easily
            p.addParamValue('separateFields', false, @islogical);
            p.parse(cacheName, param, data, varargin{:});
            
            if p.Results.verbose
                if isempty(p.Results.hash)
                    cm.printDebugHashMessage('SaveData with ', cacheName, param);
                else
                    debug('Saving data using manual hash %s\n', p.Results.hash);
                end
            end
            
            timestamp = p.Results.timestamp;
            separateFields = p.Results.separateFields;

            fileMeta = cm.getFileMetaForWrite(cacheName, param, 'hash', p.Results.hash);
            fileData = cm.getFileDataForWrite(cacheName, param, 'hash', p.Results.hash);
            mkdirRecursive(fileparts(fileMeta));

            if separateFields
                fields = fieldnames(data); %#ok<NASGU>
            else
                fields = {}; %#ok<NASGU>
            end
            
            % Save cache meta file
            if p.Results.verbose
                debug('Saving cache meta %s\n', fileMeta);
            end
            save(fileMeta, 'param', 'timestamp', 'separateFields', 'fields');

            % now we respect objects which inherit the interface
            % CacheSaveLoad. we check each value to determine if this
            % is the case (or if the methods of CacheCustomSaveLoad are
            % implemented directly, so that classes need not explicitly
            % inherit from CacheCustomSaveLoad). Then we poll each object
            % to see whether custom saving is active. Then we custom save
            % each object, and replace it with a CacheCustomSavePlaceholder
            % that will tell us what to do when loading
            
            if isstruct(data) && ~isempty(data)
                flds = fieldnames(data);
                for iFld = 1:numel(flds)
                    val = data.(flds{iFld});
                    
                    if CacheCustomSaveLoad.checkIfCustomSaveLoadOkay(val)
                        if p.Results.verbose
                            debug('Deferring to CacheCustomSaveLoad for save on field %s\n', flds{iFld});
                        end
                        customLocation = cm.getPathCustomFromHashFileName(fileMeta, flds{iFld});
                        token = val.saveCustomToLocation(customLocation);
                        
                        % replace original with placeholder
                        data.(flds{iFld}) = CacheCustomSaveLoadPlaceholder(val, token);
                    else
%                         if p.Results.verbose
%                             debug('Not using CacheCustomSaveLoad for save on field %s, checkIfCustomSaveLoadOkay returned false\n', flds{iFld});
%                         end
                    end
                end
            else
                % check the main value itself
                if CacheCustomSaveLoad.checkIfCustomSaveLoadOkay(data)
                    if p.Results.verbose
                        debug('Deferring to CacheCustomSaveLoad for save\n');
                    end
                    customLocation = cm.getPathCustomFromHashFileName(fileMeta);
                    token = data.saveCustomToLocation(customLocation);
                    
                    % replace original with placeholder
                    data = CacheCustomSaveLoadPlaceholder(data, token);
                else
%                     if p.Results.verbose
%                         debug('Not using CacheCustomSaveLoad for save, checkIfCustomSaveLoadOkay returned false\n');
%                     end
                end
            end
                
            % save cache data file
            %debug('Saving cache data %s\n', fileData);
            if separateFields
                assert(isstruct(data) && isscalar(data), 'Data must be a scalar struct in order to save fields');
                % save each field separately and include a variable
                if p.Results.verbose
                    debug('Saving data file with struct fields %s\n', fileData);
                end
                saveLarge(fileData, '-struct', 'data');
                %save(fileData, '-struct', 'data');
            else
                if p.Results.verbose
                    debug('Saving data file %s\n', fileData);
                end
                saveLarge(fileData, 'data');
                %save(fileData, 'data');
            end 
        end
    end
    
    methods 
        function deleteCache(cm, cacheName, param, varargin)
            % delete cache files everywhere they exist for a specific entry
            fileListData = cm.getFileListDataForRead(cacheName, param, varargin{:});
            fileListMeta = cm.getFileListMetaForRead(cacheName, param, varargin{:});
            fileList = [fileListData; fileListMeta];
            for iFile = 1:length(fileList)
                file = fileList{iFile};
                if exist(file, 'file')
                    debug('Deleting cache file %s\n', file);
                    delete(file);
                end
            end
            
            % delete all custom locations for any possible fields
            fileListFull = cm.getFileListMeta(cacheName, param, '', varargin{:});
            for iLoc = 1:length(fileListFull)
                pathCustom = cm.getPathCustomFromHashFileName(fileListFull{iLoc});
                if exist(pathCustom, 'dir')
                    debug('Deleting custom save/load directory %s\n', pathCustom);
                    rmdir(pathCustom, 's');
                end
                
                pathCustomWildcardAllFields = cm.getPathCustomFromHashFileName(fileListFull{iLoc}, '*');
                searchResults = dir(pathCustomWildcardAllFields);
                
                for iR = 1:numel(searchResults)
                    pathCustom = fullfile(fileparts(fileListFull{1}), searchResults(iR).name);
                    debug('Deleting custom save/load directory %s\n', pathCustom);
                    rmdir(pathCustom, 's');
                end
            end
        end

        function fileList = getFileListData(cm, cacheName, param, varargin)
            % get full list of all possible file locations for data .mat
            % not all may exist
            cm.assertParamValid(param);
            
            p = inputParser;
            p.addOptional('root', '', @(x) ischar(x) || iscell(x));
            p.addParamValue('hash', '', @ischar);
            p.addParamValue('verbose', false, @isscalar);
            p.parse(varargin{:});
            rootList = p.Results.root;

            % list of all existing data cache files
            if isempty(rootList)
                rootList = cm.cacheRootList;
            end
            if ischar(rootList)
                rootList = {rootList};
            end
            if isempty(p.Results.hash)
                hash = cm.hashParam(cacheName, param);
            else
                hash = p.Results.hash;
            end
            fileName = ['cache_' hash '.data.mat'];
            if length(rootList) == 1
                %fileList = {fullfile(rootList{1}, cacheName, fileName)};
                fileList = {[ rootList{1}, filesep(), cacheName, filesep, fileName ]};
            else
                fileList = fullfileMulti(rootList, cacheName, fileName);
            end
            
            if p.Results.verbose
                debug('File list data candidates:\n%s\n', strjoin(fileList, '\n'));
            end
        end

        function fileList = getFileListDataForRead(cm, cacheName, param, varargin)
            p = inputParser;
            p.addParamValue('verbose', false, @isscalar);
            p.KeepUnmatched = true;
            p.parse(varargin{:});
            fileList = cm.getFileListData(cacheName, param, '', varargin{:});
            fileList = cm.filterExisting(fileList);
            if p.Results.verbose
                debug('File list data for read:\n%s\n', strjoin(fileList, '\n'));
            end
        end

        function file = getFileDataForWrite(cm, cacheName, param, varargin)
            % data cache file in the first root folder that exists
            root = getFirstExisting(cm.cacheRootList);
            if isempty(root)
                error('No cacheRoot in cacheRootList {%s} exists', strjoin(cm.cacheRootList));
            end
            file = cm.getFileListData(cacheName, param, root, varargin{:});
            file = file{1};
        end
        
        function pathCustom = getPathCustomFromHashFileName(cm, metaFile, field)
             % strip off the .data.mat and add _custom_FIELD
            [root, name] = fileparts(metaFile);
            [root, name] = fileparts(fullfile(root, name));
            if nargin < 3 || isempty(field)
                pathCustom = fullfile(root, sprintf([name '.custom']));
            else
                pathCustom = fullfile(root, sprintf([name '.custom_%s'], field));
            end
        end
        
        function fileList = getFileListMeta(cm, cacheName, param, varargin) 
            p = inputParser;
            p.addOptional('root', '', @(x) ischar(x) || iscell(x));
            p.addParamValue('hash', '', @ischar);
            p.addParamValue('verbose', false, @isscalar);
            
            p.parse(varargin{:});
            rootList = p.Results.root;

            % list of all existing data cache files
            if isempty(rootList)
                rootList = cm.cacheRootList;
            end
            if ischar(rootList)
                rootList = {rootList};
            end
            
            cm.assertParamValid(param);
            
            if isempty(p.Results.hash)
                hash = cm.hashParam(cacheName, param);
            else
                hash = p.Results.hash;
            end
            fileName = ['cache_' hash '.meta.mat'];
            
            if length(rootList) == 1
                fileList = {[rootList{1}, filesep(), cacheName, filesep, fileName]};
            else
                fileList = fullfileMulti(rootList, cacheName, fileName);
            end
            
            if p.Results.verbose
                debug('File list meta candidates:\n%s\n', strjoin(fileList, '\n'));
            end
        end

        function fileList = getFileListMetaForRead(cm, cacheName, param, varargin)
            % list of all existing meta cache files
            fileList = cm.getFileListMeta(cacheName, param, '', varargin{:});
            fileList = cm.filterExisting(fileList);
        end

        function file = getFileMetaForWrite(cm, cacheName, param, varargin)
            % meta cache file in the first root folder that exists
            root = getFirstExisting(cm.cacheRootList);
            if isempty(root)
                error('No cacheRoot in cacheRootList exists\n%s\n', strjoin(cm.cacheRootList, '\n'));
            end
            file = cm.getFileListMeta(cacheName, param, root, varargin{:});
            file = file{1};
        end

        function list = filterExisting(cm, list)
            existing = cellfun(@(file) exist(file, 'file') == 2, list);
            list = list(existing);
        end
    end
    
    methods % Cache operations operating on all entries: indexing, delete all, etc. 
        function [names, info] = getListMetaFiles(cm, cacheName)
            rootList = cm.cacheRootList;
            filePattern = 'cache_*.meta.mat';
            fileList = fullfileMulti(rootList, cacheName, filePattern);
            
            info = multiDir(fileList);
            names = {info.name};
        end
        
        function [param, timestamp] = loadFromMetaFile(cm, fileName)
            meta = load(fileName, 'param', 'timestamp');
            param = meta.param;
            timestamp = meta.timestamp;
        end
        
        function [names, info] = getListDataFiles(cm, cacheName)
            rootList = cm.cacheRootList;
            filePattern = 'cache_*.data.mat';
            fileList = fullfileMulti(rootList, cacheName, filePattern);
            
            info = multiDir(fileList);
            names = {info.name};
        end
        
        function [paramList, timestampList] = getListEntries(cm, cacheName)
            % load the params stored in every entry in the cache by loading
            % every meta file
            names = cm.getListMetaFiles(cacheName);
            N = length(names);
            paramList = cell(N, 1);
            timestampList = nan(N, 1);
            validMask = true(N, 1);
            for i = 1:N
                try
                    meta = load(names{i}, 'param', 'timestamp');
                catch exc
                    debug('WARNING: Error loading from meta file %s\n', names{i});
                    fprintf(exc.message);
                    fprintf('\n');
                    validMask(i) = false;
                    continue;
                end
                paramList{i} = meta.param;
                timestampList(i) = meta.timestamp;
            end
            
            paramList = paramList(validMask);
            timestampList = timestampList(validMask);
            
            % sort by most recent first
            [timestampList, sortInd] = sort(timestampList, 1, 'descend');
            paramList = paramList(sortInd);
        end
    end

end
