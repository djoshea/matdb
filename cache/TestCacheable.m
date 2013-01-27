classdef TestCacheable < Cacheable 
    properties
        id = 1;
    end

    properties(SetAccess=?Cacheable)
        noWrite 
   end

    properties(GetAccess=?Cacheable)
        noRead
    end

    properties(Access=?Cacheable)
        neither = 5;
    end

    methods
        % return the cacheName to be used when instance 
        function name = getCacheName(obj)
            name = 'TestCacheable';
        end

        % return the param to be used when caching
        function param = getCacheParam(obj) 
            param = obj.id;
        end
    end
end
