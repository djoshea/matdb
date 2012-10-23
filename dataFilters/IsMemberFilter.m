classdef IsMemberFilter < DataFilter

    properties(SetAccess=protected)
        values
    end

    methods(Static)
        function keywords = getKeywords()
            keywords = {'ismember'};
        end
    end

    methods
        function filt = IsMemberFilter(varargin)
            filt = filt@DataFilter(varargin{:});
        end

        function initialize(filt, field, values)
            filt.fields = {field}; 
            filt.values = values;
        end

        % applies this filter to the data values in fieldValues
        function newMask = getMask(filt, fieldToValuesMap, currentMask, dfdMap)
            newMask = currentMask;
            field = filt.fields{1};
            values = filt.values;
            fieldValues = fieldToValuesMap(field);
            dfd = dfdMap(field);

            if iscell(fieldValues)
                containsMask = cellfun(@(x) ismember(x, values), fieldValues);
            else
                containsMask = arrayfun(@(x) ismember(x, values), fieldValues);
            end
            
            newMask = newMask & containsMask;
        end

        % return a very brief description of what this filter searches for
        function str = describe(filt)
            if iscell(filt.values)
                valueStr = strjoin(filt.values);
            else
                valueStr = vector2str(filt.values);
            end
            str = sprintf('%s ismember %s', filt.field, valueStr);
        end
    end
end
