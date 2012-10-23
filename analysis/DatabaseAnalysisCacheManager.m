classdef DatabaseAnalysisCacheManager < CacheManager

    properties(Dependent)
        cacheRootList;
    end

    methods
        function root = get.cacheRootList(cm)
            root = {'/Users/djoshea/data/cache/analysis'};
        end
    end

end
