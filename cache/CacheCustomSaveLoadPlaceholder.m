classdef CacheCustomSaveLoadPlaceholder < handle
   
    properties
        className
        token
    end
    
    methods
        function p = CacheCustomSaveLoadPlaceholder(val, token)
            p.className = class(val);
            p.token = token;
        end
            
        function val = doCustomLoadFromLocation(p, location, varargin)
            loadFn = str2func([p.className '.loadCustomFromLocation']);
            val = loadFn(location, p.token, varargin{:});
        end
    end
end