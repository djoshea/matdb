classdef (HandleCompatible) Cacheable  

    methods(Abstract)
        % return the cacheName to be used when instance 
        name = getCacheName(obj)

        % return the param to be used when caching
        param = getCacheParam(obj) 
    end

    % COPY THE FOLLOWING INTO YOUR SUBCLASS
    % { 
    
    methods
        function s = saveobj(obj)
            % here we essentially store the fields of obj to a struct
            % which stores the classname of the leaf class in a field that hopefully
            % won't overlap with any class properties. This leaf class field allows
            % us to call the appropriate class constructor inside loadobj.

            classContext = classNameCurrentMethod();
            if ~strcmp(classContext, class(obj))
                error('Method saveobj must be implemented in class %s directly, not run by class %s', class(obj), classContext);
            end

            meta = metaclass(obj);
            propInfo = meta.PropertyList;
            s = struct();
            for iProp = 1:length(propInfo)
                info = propInfo(iProp);
                name = info.Name;
                if info.Dependent && isempty(info.SetMethod)
                    continue;
                end
                if info.Transient || info.Constant
                    continue;
                end
                s.(name) = obj.(name);
            end
        end
    end

    methods(Static)
        % implement loadobj so that Cacheable classes are compatible
        % with fast serialize/deserialize for faster saving to disk 
        function obj = loadobj(s)
            classContext = classNameCurrentMethod();
            if isobject(s)
                %warning('Cacheable loadobj should generally be passed a struct');
                assert(isa(s, classContext), 'Method loadobj called on %s but passed a %s instance. Check that %s implements loadobj directly.', ...
                    classContext, class(s), class(s));

                obj = s;
            elseif isstruct(s)
                leafClassField = Cacheable.leafClassForCacheableField;
                leafClass = s.(leafClassField);

                assert(strcmp(leafClass, classContext), 'Method loadobj called on %s but instance is a serialized %s. Check that %s implements loadobj directly.', ...
                    classContext, leafClass, leafClass);

                meta = metaclass(classContext);
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
                    obj.(name) = s.(name);
                end
            end
        end
    end

    % }

    properties(Constant, Hidden, Access=protected)
        leafClassForCacheableField = 'LEAF_CLASS_FOR_CACHEABLE';
    end

    methods % Methods which subclasses may wish to override 

        % return a cache manager instance
        function cm = getCacheManager(obj);
            cm = MatdbSettingsStore.getDefaultCacheManager();
        end

        function obj = prepareForCache(obj)
            obj = obj;
        end

        % obj is the object newly loaded from cache, preLoadObj is the object 
        % as it existed before loading from the cache. Transfering data from obj
        % to preLoadObj will occur automatically for handle classes AFTER this
        % function is called. preLoadObj is provided only if there is information
        % in the object before calling loadFromCache that you would like to copy
        % to the cache-loaded object obj.
        function obj = postLoadFromCache(obj, param, timestamp, preLoadObj)
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

        function dest = transferToHandle(src, dest)
            % when calling .loadCache() on a Cacheable handle object, we need 
            % a way to make the handle that you are holding into the cached object
            % This function turns src (what you are holding) into dest
            % by copying all transferrable properties over
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

        function obj = transferStructToObject(obj, s)
            % when loadobj(s) receives a struct argument, you can call this method
            % to simply transfer properties over from the struct to the class
            assert(isstruct(s), 'Argument must be a struct');

            meta = metaclass(obj);
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
                obj.(name) = s.(name);
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

end
