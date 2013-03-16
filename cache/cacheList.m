function cacheList(varargin)
    p = inputParser;
    p.addParamValue('cacheName', 'cacheSave', @ischar);
    p.parse(varargin{:});

    cacheName = p.Results.cacheName;

    % simple save cache value with a string name
    cm = MatdbSettingsStore.getDefaultCacheManager();
    [paramList timestampList] = cm.getListEntries(cacheName);

    for i = 1:length(paramList)
        name = paramList{i};
        time = timestampList(i);
        
        if ischar(name)
            tcprintf('inline', '%s {bright white}%s\n', datestr(time), name);
        end
    end
end
