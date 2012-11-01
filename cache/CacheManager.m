classdef CacheManager < handle
    properties(Dependent)
        cacheRootList;
    end

    methods
        function rootList = get.cacheRootList(cm)
            rootList = cm.getCacheRootList();
        end
    end

    methods % methods a subclass might wish to override
        function rootList = getCacheRootList(cm)
            rootList = { ...
                '/Users/djoshea/npl/cache/', 
                '/net/share/people/djoshea/cache' };
            rootList = { ...
                '/Users/djoshea/npl/cache/' };
        end

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
            data = cm.getFileDataForRead(cacheName, param);
            meta = cm.getFileMetaForRead(cacheName, param);

            tf = ~isempty(data) && ~isempty(meta);
        end

        function [timestamp indexNewest] = retrieveTimestamp(cm, cacheName, param)
            fileList = cm.getFileListMetaForRead(cacheName, param);
            if isempty(fileList)
                timestamp = [];
                return;
            end
               
            timestamp = [];
            indexNewest = [];

            for iFile = 1:length(fileList)
                file = fileList{iFile};
                varsToLoad = {'timestamp', 'param'};
                contents = load(file, varsToLoad{:});

                % check has contents 
                if ~isempty(setdiff(varsToLoad, fieldnames(contents)))
                    warning('Cache file %s is invalid', file);
                    continue;
                end

                if ~cm.checkParamMatch(contents.param, param)
                    warning('Cache param in %s does not match', file);
                    continue;
                end

                if isempty(timestamp) || contents.timestamp > timestamp
                    timestamp = contents.timestamp;
                    indexNewest = iFile;
                end
            end
        end

        function tf = hasCacheNewerThan(cm, cacheName, param, refTimestamp)
            timestamp = cm.retrieveTimestamp(cacheName, param);
            tf = ~isempty(timestamp) && timestamp > refTimestamp;
        end

        function [data timestamp] = loadData(cm, cacheName, param)
            fileList = cm.getFileListDataForRead(cacheName, param);
            if isempty(fileList)
                error('No cache files found');
            end

            % load the data file with the newest timestamp
            [~, indexNewest] = cm.retrieveTimestamp(cacheName, param);
            file = fileList{indexNewest};
            varsToLoad = {'data', 'timestamp', 'param'};
            contents = load(file, varsToLoad{:});

            % check has contents 
            if ~isempty(setdiff(varsToLoad, fieldnames(contents)))
                error('Cache file %s is invalid', file);
            end

            % check params match
            if ~cm.checkParamMatch(contents.param, param)
                error('Cache param in %s does not match', file);
            end

            data = contents.data;
            timestamp = contents.timestamp;
        end 

        function saveData(cm, cacheName, param, data, varargin)
            p = inputParser;
            p.addRequired('cacheName', @ischar);
            p.addRequired('param', @(x) true);
            p.addRequired('data', @(x) true);
            p.addParamValue('timestamp', now, @isscalar);
            p.parse(cacheName, param, data, varargin{:});
            timestamp = p.Results.timestamp;

            fileMeta = cm.getFileMetaForWrite(cacheName, param);
            fileData = cm.getFileDataForWrite(cacheName, param);
            mkdirRecursive(fileparts(fileMeta));

            %debug('Saving cache meta %s\n', fileMeta);
            save(fileMeta, 'param', 'timestamp');
            %debug('Saving cache data %s\n', fileData);
            save(fileData, '-v7.3', 'data', 'param', 'timestamp');
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
