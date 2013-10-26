function file = cacheGetFile(key, varargin)
    p = inputParser;
    p.addRequired('key', @(x) true);
    p.addParamValue('cacheName', 'cacheSave', @ischar);
    p.parse(key, varargin{:});

    cacheName = p.Results.cacheName;
    cacheParam = key; 

    % simple save cache value with a string name
    cm = MatdbSettingsStore.getDefaultCacheManager();
    list = cm.getFileListDataForRead(cacheName, cacheParam);
    if isempty(list)
        file = '';
    else
        file = list{1};
    end

end
