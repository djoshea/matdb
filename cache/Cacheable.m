classdef (HandleCompatible) Cacheable  
% Cacheable defines an interfaces for classes whose data can be saved and loaded
% from a cache via a CacheManager instance. It enables class instances to load their
% data "in place" from the cache. Typically key properties of the class will be 
% set so as to uniquely identify the exact cache location where the rest of the
% classes data will be stored. These key property values will be returned by 
% the getCacheParam function. When you call .saveCache on this 
% instance, the instance data will saved to cache, much like a call to cache().
% When you call .loadFromCache(), the instance data will be loaded from cache.
% 
% Requirements for subclasses:
%   * Implement the Abstract methods below:
%       getCacheParam returns whatever uniquely identifies the cache item used to 
%         store data for the particular class. This typically will aggregate the 
%         values of properties which identify the cache to use or load from. 
%   * Support a call to an empty constructor
%   * Grant Cacheable read/write access to all protected properties by using
%       access lists, e.g.: 
%       properties(Access=?Cacheable)    % instead of Access=protected
%       properties(SetAccess=?Cacheable) % instead of SetAccess=protected
%       properties(GetAccess=?Cacheable) % instead of GetAccess=protected
%

    methods(Abstract)
        % return the param to be used when caching
        param = getCacheParam(obj) 
    end

    methods
        % return the cacheName to be used when instance 
        function name = getCacheName(obj)
            name = class(obj);
        end
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

        function timestamp = getCacheValidAfterTimestamp(obj)
            % when implementing this function, DO NOT store the reference timestamp
            % in an non-transient object property, or it will be reset to older
            % values when loading from cache (as the property value stored in the cached 
            % instance will be used)
            timestamp = -Inf;
        end
    end

    methods % Methods which subclasses are unlikely to override
        % return the timestamp to be used when storing the cache,
        % typically now is sufficient
        function timestamp = getCacheTimestamp(obj)
            timestamp = now;
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

    methods % Caching methods
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

    properties(Constant, Hidden, Access=protected)
        % used by saveobj and loadobj to know which subclass was cached
        % Since loadobj is a Static method, it needs a means of calling the leaf
        % class constructor to create a new object
        leafClassForCacheableField = 'LEAF_CLASS_FOR_CACHEABLE';
    end

    methods % saveobj
        function s = saveobj(obj)
            % here we essentially store the fields of obj to a struct
            % which stores the classname of the leaf class in a field that hopefully
            % won't overlap with any class properties. This leaf class field allows
            % us to call the appropriate class constructor inside loadobj.

            % old solution: require EVERY leaf class to implement saveobj
            %classContext = classNameCurrentMethod();
            %if ~strcmp(classContext, class(obj))
            %    warning('Method saveobj must be implemented in class %s directly, not run by class %s', class(obj), classContext);
            %end

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
                % try reading this property, catch GetProhibited errors
                try
                    s.(name) = obj.(name);
                catch exc
                    if strcmp(exc.identifier, 'MATLAB:class:GetProhibited') 
                        error('Cacheable could not get value of property %s. Please add Cacheable to the access list for all properties.', name);
                    else
                        rethrow(exc);
                    end
                end
            end

            % write the classname into the saved struct so loadobj can access it
            leafClassField = Cacheable.leafClassForCacheableField;
            s.(leafClassField) = class(obj);
            debug('In Cacheable.saveobj()\n');
        end
    end

    methods(Static) % loadobj
        % implement loadobj so that Cacheable classes are compatible
        % with fast serialize/deserialize for faster saving to disk 
        function obj = loadobj(s)
            % old solution: require EVERY leaf class to implement loadobj
            %classContext = classNameCurrentMethod();
            if isobject(s)
                %warning('Cacheable loadobj should generally be passed a struct');
                %assert(isa(s, classContext), 'Method loadobj called on %s but passed a %s instance. Check that %s implements loadobj directly.', ...
                %    classContext, class(s), class(s));
                
                % simple pass thru
                obj = s;

            elseif isstruct(s)
                % grab the leaf class name which was added by saveobj
                leafClassField = Cacheable.leafClassForCacheableField;

                if ~isfield(s, leafClassField)
                    error('Saved cacheable instance is missing class name identifier. Check that Cacheable.saveobj() is being called on save');
                end
                    
                leafClass = s.(leafClassField);

                %assert(strcmp(leafClass, classContext), 'Method loadobj called on %s but instance is a serialized %s. Check that %s implements loadobj directly.', ...
                %    classContext, leafClass, leafClass);
                
                % use the leaf class to call the constructor
                constructor = str2func(leafClass);
                % call constructor with empty arguments
                obj = constructor();

                meta = meta.class.fromName(leafClass);
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
                    try
                        obj.(name) = s.(name);
                    catch exc
                        if strcmp(exc.identifier, 'MATLAB:class:SetProhibited') 
                            error('Cacheable could not set value of property %s. Please add Cacheable to the access list for all properties.', name);
                        else
                            rethrow(exc);
                        end
                    end
                end
            end
        end
    end


end
