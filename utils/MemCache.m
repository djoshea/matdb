classdef MemCache < handle
% this class holds a limited capacity of key-value records in memory, a
% sort of recency cache. keys and values can be anything, keys are hashed
% via DataHash.

    properties(SetAccess=protected)
        capacity
    end
    
    properties(Dependent)
        nKeys
    end
    
    properties(SetAccess=protected)
        hashKeys = {};
        values = {};
    end
    
    
    methods
        function mc = MemCache(capacity)
            assert(capacity > 0);
            mc.capacity = capacity;
        end
        
        function n = get.nKeys(mc)
            n = numel(mc.hashKeys);
        end
        
        function store(mc, key, value) 
            % check whether we've hit capacity and delete the least
            % recently added key
            
            hashKey = mc.hash(key);
            
            [hasKey, keyIdx] = ismember(hashKey, mc.hashKeys);
            
            if ~hasKey
                if mc.nKeys >= mc.capacity
                    mc.hashKeys = mc.hashKeys(2:end);
                    mc.values = mc.values(2:end);
                end
                
                keyIdx = numel(mc.hashKeys) + 1;
            end

            mc.hashKeys{keyIdx} = hashKey;
            mc.values{keyIdx} = value;    
        end
        
        function h = hash(~, key)
            opts.Method = 'MD5';
            opts.format = 'hex';
            h = DataHash(key, opts);
        end
        
        function value = retrieve(mc, key)
            hashKey = mc.hash(key);
            [hasKey, idx] = ismember(hashKey, mc.hashKeys);
            
            if hasKey
                value = mc.values{idx};
            else
                value = [];
            end
        end
        
        function remove(mc, key)
            hashKey = mc.hash(key);
            [hasKey, idx] = ismember(hashKey, mc.hashKeys);
            if hasKey
                mc.hashKeys(idx) = {};
                mc.values(idx) = {};
            end
        end
        
        function tf = has(mc, key)
            hashKey = mc.hash(key);
            tf = ismember(hashKey, mc.hashKeys);
        end
        
    end
        
    
end