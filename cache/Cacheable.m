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
            cm = CacheManager();
        end

        function obj = prepareForCache(obj)
            obj = obj;
        end

        function obj = postLoadFromCache(obj, param, timestamp)
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
            
            [objCached timestamp] = cm.loadData(name, param);
            timestampRef = obj.getCacheValidAfterTimestamp();
            
            debug('Cache hit on %s\n', name);

            if timestamp < timestampRef
                error('Cache has expired on %s', name);
            end

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

end
