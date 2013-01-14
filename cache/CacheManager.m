classdef CacheManager < handle
    properties(Dependent)
        cacheRootList;
    end

    methods
        function rootList = get.cacheRootList(cm)
            rootList = MatdbSettingsStore.settings.pathListCache;
        end
    end

    methods % methods a subclass might wish to override
        function [tf reason] = isParamValid(cm, param)
            % determine whether the provided param is acceptable
            tf = true;
            reason = '';
        end

        function assertParamValid(cm, param)
            [tf reason] = cm.isParamValid(param);
            assert(tf, 'Cache param invalid: %s', reason);
        end

        function tf = checkParamMatch(cm, paramInFile, paramRef)
            cm.assertParamValid(paramInFile);
            cm.assertParamValid(paramRef);
            tf = isequal(paramInFile, paramRef);
        end

        function str = hashParam(cm, cacheName, param)
            opts.Method = 'SHA-1';
            opts.Format = 'hex'; 

            hashData.param = param;
            hashData.cacheName = cacheName;
            str = DataHash(hashData, opts);
        end
    end

    methods % methods that should remain public
        function tf = cacheExists(cm, cacheName, param)
            data = cm.getFileListDataForRead(cacheName, param);
            meta = cm.getFileListMetaForRead(cacheName, param);

            tf = ~isempty(data) && ~isempty(meta);
        end

        % retrieve the timestamp from the newest meta file
        function [timestamp indexNewest] = retrieveTimestamp(cm, cacheName, param)
            [indexNewest, timestamp, isSeparate] = retrieveMeta(cm, cacheName, param);
        end

        % retrieve all meta info from the newest meta file
        function [indexNewest timestamp separateFields] = retrieveMeta(cm, cacheName, param)
            fileList = cm.getFileListMetaForRead(cacheName, param);
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

                contents = load(file, varsToLoad{:});

                % check has contents 
                if ~isempty(setdiff(varsRequired, fieldnames(contents)))
                    warning('Cache file %s is invalid', file);
                    continue;
                end

                if ~cm.checkParamMatch(contents.param, param)
                    warning('Cache param in %s does not match', file);
                    continue;
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

        function [tf timestamp] = hasCacheNewerThan(cm, cacheName, param, refTimestamp)
            timestamp = cm.retrieveTimestamp(cacheName, param);
            tf = ~isempty(timestamp) && timestamp > refTimestamp;
        end

        function [data timestamp] = loadData(cm, cacheName, param, varargin)
            p = inputParser;
            p.addRequired('cacheName', @ischar);
            p.addRequired('param', @(x) true);
            p.addParamValue('fields', {}, @iscellstr);
            p.parse(cacheName, param, varargin{:});
            fields = p.Results.fields;

            fileList = cm.getFileListDataForRead(cacheName, param);
            if isempty(fileList)
                error('No cache files found');
            end

            % load the data file with the newest timestamp
            [indexNewest, timestamp, separateFields] = cm.retrieveMeta(cacheName, param);
            file = fileList{indexNewest};

            if separateFields
                % struct stored as separate fields
                if ~isempty(fields)
                    % load only specific fields
                    varsToLoad = fields;
                else
                    % no fields specified, load all
                    varsToLoad = {};
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
        end 

        function timestamp = saveData(cm, cacheName, param, data, varargin)
            p = inputParser;
            p.addRequired('cacheName', @ischar); 
            p.addRequired('param', @(x) true);
            p.addRequired('data', @(x) true);

            % default timestamp is now, but can be overridden 
            p.addParamValue('timestamp', now, @isscalar);
            
            % optional means of saving a struct array's fields as separate variables
            % within the same mat file, allowing for individual fields to be
            % selectively loaded easily
            p.addParamValue('separateFields', false, @islogical);

            p.parse(cacheName, param, data, varargin{:});
            timestamp = p.Results.timestamp;
            separateFields = p.Results.separateFields;

            fileMeta = cm.getFileMetaForWrite(cacheName, param);
            fileData = cm.getFileDataForWrite(cacheName, param);
            mkdirRecursive(fileparts(fileMeta));

            % Save cache meta file
            %debug('Saving cache meta %s\n', fileMeta);
            save(fileMeta, 'param', 'timestamp', 'separateFields');

            % save cache data file
            %debug('Saving cache data %s\n', fileData);
            if separateFields
                assert(isstruct(data) && isscalar(data), 'Data must be a scalar struct in order to save fields');
                % save each field separately and include a variable
                saveLarge(fileData, '-struct', 'data');
            else
                saveLarge(fileData, 'data');
            end

            
        end
    end
    
    methods 
        function deleteCache(cm, cacheName, param)
            % delete cache files everywhere they exist
            fileListData = cm.getFileListDataForRead(cacheName, param);
            fileListMeta = cm.getFileListMetaForRead(cacheName, param);
            fileList = [fileListData; fileListMeta];
            for iFile = 1:length(fileList)
                file = fileList{iFile};
                if exist(file, 'file')
                    debug('Deleting cache file %s\n', file);
                    delete(file);
                end
            end
        end

        function fileList = getFileListData(cm, cacheName, param, root) 
            cm.assertParamValid(param);

            % list of all existing data cache files
            if nargin == 4
                rootList = {root};
            else
                rootList = cm.cacheRootList;
            end
            hash = cm.hashParam(cacheName, param);
            fileName = ['cache_' hash '.data.mat'];
            fileList = fullfileMulti(rootList, cacheName, fileName);
        end

        function fileList = getFileListDataForRead(cm, cacheName, param)
            fileList = cm.getFileListData(cacheName, param);
            fileList = cm.filterExisting(fileList);
        end

        function file = getFileDataForWrite(cm, cacheName, param)
            % data cache file in the first root folder that exists
            root = getFirstExisting(cm.cacheRootList);
            if isempty(root)
                error('No cacheRoot in cacheRootList {%s} exists', strjoin(cm.cacheRootList));
            end
            file = cm.getFileListData(cacheName, param, root);
            file = file{1};
        end
        
        function fileList = getFileListMeta(cm, cacheName, param, root) 
            cm.assertParamValid(param);
            
            if nargin == 4
                rootList = {root};
            else
                rootList = cm.cacheRootList;
            end
            hash = cm.hashParam(cacheName, param);
            fileName = ['cache_' hash '.meta.mat'];
            fileList = fullfileMulti(rootList, cacheName, fileName);
        end

        function fileList = getFileListMetaForRead(cm, cacheName, param)
            % list of all existing meta cache files
            fileList = cm.getFileListMeta(cacheName, param);
            fileList = cm.filterExisting(fileList);
        end

        function file = getFileMetaForWrite(cm, cacheName, param)
            % meta cache file in the first root folder that exists
            root = getFirstExisting(cm.cacheRootList);
            if isempty(root)
                error('No cacheRoot in cacheRootList {%s} exists', strjoin(cm.cacheRootList));
            end
            file = cm.getFileListMeta(cacheName, param, root);
            file = file{1};
        end

        function list = filterExisting(cm, list)
            existing = cellfun(@(file) exist(file, 'file') == 2, list);
            list = list(existing);
        end
    end

end
