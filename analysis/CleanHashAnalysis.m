classdef CleanHashAnalysis < DatabaseAnalysis
    methods
        % you may wish to override this if you want cache param to affect
        % the hash at all, otherwise different param settings will
        % overwrite each other
        function str = generateHashSuffixForParam(da, cacheParam, hash)
            str = '';
        end
        
        function hash = generateHashForEntry(da, entry, hash, cacheName, cacheParam) %#ok<*INUSD,*INUSL>
            % by default, keep hash as it is, but analysis can choose to redefine the hash however it wants
            % taking on the risk of non-uniqueness. A common overwrite would be to use entry.getKeyFieldValueDescriptors() {1}
            % and then factor in param 
            paramStr = da.generateHashSuffixForParam(cacheParam, hash);
            desc = entry.getKeyFieldValueDescriptors();
            hash = [desc{1} paramStr];
        end
        
        function prefix = getCacheFilePrefix(da) %#ok<*MANU>
            prefix = '';
        end
    end
end
