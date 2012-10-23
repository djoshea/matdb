classdef DataSource < handle & Cacheable

    methods(Abstract)
        % return a string describing this datasource
        str = describe(src);

        % actually load this into the database, assume all dependencies have been loaded
        loadInDatabase(src, database);
    end

    methods
        % return a cell array of other DataSources which must be loaded before
        % this source may be loaded
        function sources = getRequiredSources(src)
            sources = {};
        end
    end

    methods
        function disp(src)
            str = src.describe();
            fprintf('%s', str);
        end
    end

    methods % Cacheable instantiations
        % return the cacheName to be used when instance 
        function name = getCacheName(obj)
            name = obj.describe();
        end

        % return the param to be used when caching
        function param = getCacheParam(obj) 
            param = [];
        end
    end

end
