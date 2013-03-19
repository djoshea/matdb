classdef (HandleCompatible) Cacheable  

    methods(Abstract)
        % return the cacheName to be used when instance 
        name = getCacheName(obj)

        % return the param to be used when caching
        param = getCacheParam(obj) 
    end

    methods % Methods which subclasses may wish to override 

        % return a cache manager instance
        function cm = getCacheManager(obj);
            cm = MatdbSettingsStore.getDefaultCacheManager();
        end

        function obj = prepareForCache(obj, varargin)
            % may optionally accept arguments 'snapshot', true or 'snapshot', false
            obj = obj;
        end

        % obj is the object newly loaded from cache, preLoadObj is the object 
        % as it existed before loading from the cache. Transfering data from obj
        % to preLoadObj will occur automatically for handle classes AFTER this
        % function is called. preLoadObj is provided only if there is information
        % in the object before calling loadFromCache that you would like to copy
        % to the cache-loaded object obj.
        function obj = postLoadFromCache(obj, param, timestamp, preLoadObj, varargin)
            % may optionally accept arguments 'snapshot', true or 'snapshot', false
            obj = obj;
        end

        % return the timestamp to be used when storing the cache,
        % typically now is sufficient
        function timestamp = getCacheTimestamp(obj)
            timestamp = now;
        end

        function timestamp = getCacheValidAfterTimestamp(obj)
            % when implementing this function, DO NOT store the reference timestamp
            % in an non-transient object property, or it will be reset to older
            % values when loading from cache (as the property value stored in the cached 
            % instance will be used)
            timestamp = -Inf;
        end

        function transferToHandle(src, dest)
            assert(isa(dest, class(src)), 'Class names must match exactly');

            meta = metaclass(src);
            propInfo = meta.PropertyList;
            for iProp = 1:length(propInfo)
                info = propInfo(iProp);
                name = info.Name;
                if info.Dependent && isempty(info.SetMethod)
                    continue;
                end
                if info.Transient || info.Constant
                    continue;
                end
                dest.(name) = src.(name);
            end
        end
    end

    methods
        function name = getFullCacheName(obj)
            name = [class(obj) '_' obj.getCacheName()];
        end

        function cache(obj)
            cm = obj.getCacheManager();
            name = obj.getFullCacheName();
            param = obj.getCacheParam();
            timestamp = obj.getCacheTimestamp();
            obj = obj.prepareForCache();

            debug('Cache save on %s\n', name);

            cm.saveData(name, param, obj, 'timestamp', timestamp);
        end

        function tf = hasCache(obj)
            cm = obj.getCacheManager();
            name = obj.getFullCacheName();
            param = obj.getCacheParam();
            timestampRef = obj.getCacheValidAfterTimestamp();
            tf = cm.hasCacheNewerThan(name, param, timestampRef);
        end

        function deleteCache(obj)
            cm = obj.getCacheManager();
            name = obj.getFullCacheName();
            param = obj.getCacheParam();
            cm.deleteCache(name, param);
        end

        function [obj timestamp] = loadFromCache(obj)
            cm = obj.getCacheManager();
            name = obj.getFullCacheName();
            param = obj.getCacheParam();
            
            timestampRef = obj.getCacheValidAfterTimestamp();
            [objCached timestamp] = cm.loadData(name, param);
            if timestamp < timestampRef
                error('Cache has expired on %s', name);
            end

            debug('Cache hit on %s\n', name);

            % call postLoadOnCache function in case subclass has overridden it 
            % we pass along the pre-cache version of obj in case useful.
            objCached = objCached.postLoadFromCache(param, timestamp, obj);

            % when loading a handle class, we must manually transfer
            % all properties to current class (objCached -> obj) because
            % existing handles will reference the old object. We defer
            % to .transferToHandle to do this copying. This method should be
            % overwritten if any special cases arise
            if isa(obj, 'handle')
                objCached.transferToHandle(obj);
            else
                % value classes we handle with a simple assignment 
                obj = objCached;
            end
        end
    end
    
    methods % Snapshot saving, listing, loading
        function cacheName = getCacheNameSnapshots(obj, name)
            cacheName = [obj.getFullCacheName() '_snapshots'];
        end
        
        function cacheParam = getCacheParamSnapshot(obj, name)
            % agglomerate the cacheParam and the snapshot name in one
            param = obj.getCacheParam();
            cacheParam.cacheParam = param;
            cacheParam.snapshotName = name;
        end

        function snapshot(obj, snapshotName)
            % take a named snapshot of the cache
            cm = obj.getCacheManager();
            name = obj.getCacheNameSnapshots();
            param = obj.getCacheParamSnapshot(snapshotName);
            
            timestamp = obj.getCacheTimestamp();
            if nargin(obj.prepareForCache) > 1 
                obj = obj.prepareForCache('snapshot', true);
            else
                obj = obj.prepareForCache();
            end
            debug('Taking snapshot %s : %s\n', name, snapshotName);
            cm.saveData(name, param, obj, 'timestamp', timestamp);
        end
        
        function [names paramList timestampList] = getListSnapshots(obj)
            % list all snapshots taken. Grab the snapshot name and the cache param for each
            cm = obj.getCacheManager();
            name = obj.getCacheNameSnapshots();
            
            [list, timestampList] = cm.getListEntries(name); 
            N = length(list);
            
            [names, paramList] = deal(cell(N, 1));
            for i = 1:N
                names{i} = list{i}.snapshotName;
                paramList{i} = list{i}.cacheParam;
            end
        end
        
        function [names timestampList] = getListSnapshotsMatchingParam(obj)
            % list all snapshots taken, filtered by cacheParam matching my current param 
            param = obj.getCacheParam();
            [names, paramList, timestampList] = getListSnapshots(obj)
            mask = cellfun(@(paramFromFile) cm.checkParamMatch(param, paramFromFile), paramList);
           
            names = names(mask);
            timestampList = timestampList(mask);
        end
        
        function [snapshotName cacheParam timestamp] = getSnapshotMostRecent(obj)
            % look up the name and cacheParam of the most recent snapshot
            cm = obj.getCacheManager();
            [metaNames, info] = cm.getListMetaFiles(obj.getCacheNameSnapshots());
            
            if isempty(metaNames)
                snapshotName = '';
                cacheParam = [];
                timestamp = NaN;
                return;
            end
            [~, indexNewest] = max([info.datenum]);
            
            metaName = metaNames{indexNewest};
            [param, timestamp] = cm.loadFromMetaFile(metaName);
            snapshotName = param.snapshotName;
            cacheParam = param.cacheParam;
        end
        
        function [snapshotName timestamp] = getSnapshotMostRecentMatchingParam(obj, param)
            % look up the name of the most recent snapshot matching my current param
            cm = obj.getCacheManager();
            cacheParam = obj.getCacheParam();
            [metaNames info] = cm.getListMetaFiles(obj.getCacheNameSnapshots());

            if isempty(metaNames)
                snapshotName = '';
                cacheParam = [];
                timestamp = NaN;
                return;
            end

            % sort from newest to oldest
            [~, sortInds] = sort([info.datenum], 2, 'descend');
            metaNames = metaNames(sortInds);
            info = info(sortInds);
            N = length(metaNames);

            % search in order for matching cache param
            for i = 1:N
                metaName = metaNames{i};
                try
                    [param timestamp] = cm.loadFromMetaFile(metaName);
                    snapshotName = param.snapshotName;
                    cacheParamThis = param.cacheParam;
                    
                    if cm.checkParamMatch(cacheParam, cacheParamThis)
                        return;
                    end
                catch exc
                    debug('WARNING: Error loading from cache snapshot meta file\n');
                    fprintf(exc.message);
                end
            end
            
            % not found
            snapshotName = '';
            timestamp = NaN;
        end
        
        function printListSnapshots(obj)
            cm = obj.getCacheManager();
            cacheParam = obj.getCacheParam();
            [names paramList timestampList] = obj.getListSnapshots();
            N = length(names);
            
            for i = 1:N
                matches = cm.checkParamMatch(cacheParam, paramList{i});
                
                tcprintf('inline', '{bright white}%3d {none}: %s {bright yellow}%s', i, datestr(timestampList(i)), names{i});
                if matches
                    tcprintf('inline', '{green} [matches param]\n');
                else
                    fprintf('\n');
                end
            end
        end

        function [obj timestamp] = loadFromSnapshot(obj, snapshotName)
            cm = obj.getCacheManager();
            name = obj.getCacheNameSnapshots();

            if isnumeric(snapshotName)
                % lookup as index into snapshots
                snapshotNames = obj.getListSnapshots();
                snapshotName = snapshotNames{snapshotName};
            end

            param = obj.getCacheParamSnapshot(snapshotName);
            
            timestampRef = obj.getCacheValidAfterTimestamp();
            [objCached timestamp] = cm.loadData(name, param);
            if timestamp < timestampRef
                warning('Snapshot %s has expired on %s', snapshotName, name);
            end

            debug('Loading from snapshot %s : %s\n', name, snapshotName);

            % call postLoadOnCache function in case subclass has overridden it 
            % we pass along the pre-cache version of obj in case useful.
            objCached = objCached.postLoadFromCache(param, timestamp, obj);

            % when loading a handle class, we must manually transfer
            % all properties to current class (objCached -> obj) because
            % existing handles will reference the old object. We defer
            % to .transferToHandle to do this copying. This method should be
            % overwritten if any special cases arise
            if isa(obj, 'handle')
                objCached.transferToHandle(obj);
            else
                % value classes we handle with a simple assignment 
                obj = objCached;
            end
        end
        
        function [obj timestamp] = loadFromSnapshotMostRecent(obj)
            snapshotName = obj.getSnapshotMostRecent();
            if isempty(snapshotName)
                error('No snapshots found');
            end
            [obj timestamp] = obj.loadFromSnapshot(snapshotName);
        end
        
        function [obj timestamp] = loadFromSnapshotMostRecentMatchingParam(obj)
            snapshotName = obj.getSnapshotMostRecentMatchingParam();
            if isempty(snapshotName)
                error('No snapshots found matching cache param');
            end
            [obj timestamp] = obj.loadFromSnapshot(snapshotName);
        end
    end

end
