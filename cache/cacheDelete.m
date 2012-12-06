function cacheDelete(key, varargin)
    p = inputParser;
    p.addRequired('key', @(x) true);
    p.addParamValue('cacheName', 'cacheSave', @ischar);
    p.parse(key, varargin{:});

    cacheName = p.Results.cacheName;
    cacheParam = key; 

    % simple save cache value with a string name
    cm = MatdbSettingsStore.getDefaultCacheManager();
    cm.deleteCache(cacheName, cacheParam);
end
