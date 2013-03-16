function cacheSave(key, value, varargin)
    p = inputParser;
    p.addRequired('key', @(x) @ischar);
    p.addRequired('value', @(x) true);
    p.addParamValue('cacheName', 'cacheSave', @ischar);
    p.parse(key, value, varargin{:});

    cacheName = p.Results.cacheName;
    cacheParam = key; 

    % simple save cache value with a string name
    cm = MatdbSettingsStore.getDefaultCacheManager();
    cm.saveData(cacheName, cacheParam, value);

end
