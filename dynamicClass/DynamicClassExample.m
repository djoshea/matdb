classdef DynamicClassExample < DynamicClass

    properties
        map
    end

    methods

        function obj = DynamicClassExample()
            obj.map = containers.Map('KeyType', 'char', 'ValueType', 'double');
            obj.store('key1', 1);
            obj.store('key2', 2); 
            obj.store('key3', 3);
        end

        function obj = store(obj, key, value)
            obj.map(key) = value;
        end

        function value = getValue(obj, key)
            value = obj.map(key);
        end

        % access values using obj.key
        function [value appliedNext] = mapDynamicPropertyAccess(obj, name, typeNext, subsNext)
            if obj.map.isKey(name)
                value = obj.map(name);
            else
                value = DynamicClass.NotSupported;
            end
            appliedNext = false;
        end

        % access values using obj.getkey()
        function fn = mapDynamicMethod(obj, name)
            keys = obj.map.keys;
            methodNames = cellfun(@(key) ['get' key], keys, ...
                'UniformOutput', false);
            [tf loc] = ismember(name, methodNames);
            if tf
                key = keys{loc};
                fn = @() obj.getValue(key);
            else
                fn = DynamicClass.NotSupported;
            end
        end
           
        % access values(i) using obj(i)
        function [value appliedNext] = parenIndex(obj, subs, typeNext, subsNext)
            values = obj.map.values;
            value = values{subs{:}};
            appliedNext = false;
        end

        % access keys{i} using obj{i}
        function [valueCell appliedNext] = cellIndex(obj, subs, typeNext, subsNext)
            valueCell = obj.map.keys;
            valueCell = valueCell(subs{:});
            appliedNext = false;
        end

        function obj = dynamicPropertyAssign(obj, name, value, s)
            obj.store(name, value);
        end
    end
end
