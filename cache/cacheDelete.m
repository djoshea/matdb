function cacheDelete(key, varargin)
    p = inputParser;
    p.addRequired('key', @ischar);
    p.addParamValue('cacheName', 'cacheSave', @ischar);
    p.parse(key, varargin{:});

    cacheName = p.Results.cacheName;
    cacheParam = key; 

    % simple save cache value with a string name
    cm = MatdbSettingsStore.getDefaultCacheManager();
    cm.deleteCache(cacheName, cacheParam);
end
