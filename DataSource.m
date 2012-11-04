classdef DataSource < handle 

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
            fprintf('%s\n\n', str);
        end
    end

    methods % Cacheable instantiations, in case Cacheable is added going forward
        % return the cacheName to be used when instance 
        function name = getCacheName(obj)
            name = obj.describe();
        end
    end

end
