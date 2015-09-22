function data = cacheLoad(key, varargin)
    p = inputParser;
    p.addRequired('key', @(x) true);
    p.addParamValue('cacheName', 'cacheSave', @ischar);
    p.addParamValue('verbose', false, @islogical);
    p.parse(key, varargin{:});

    cacheName = p.Results.cacheName;
    cacheParam = key; 

    % simple save cache value with a string name
    cm = MatdbSettingsStore.getDefaultCacheManager();
    if ~cm.cacheExists(cacheName, cacheParam, 'verbose', p.Results.verbose);
        error('Cached value %s not found', key);
    else
        data = cm.loadData(cacheName, cacheParam, 'verbose', p.Results.verbose);
    end

end
