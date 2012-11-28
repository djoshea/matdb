function tf = cacheExists(key, varargin)
    % simple caching with a string name
    p = inputParser;
    p.addRequired('key', @ischar);
    p.addParamValue('cacheName', 'cacheSave', @ischar);
    p.parse(key, varargin{:});

    cacheName = p.Results.cacheName;
    cacheParam = p.Results.key;

    cm = MatdbSettingsStore.getDefaultCacheManager();
    tf = cm.cacheExists(cacheName, cacheParam);
end
