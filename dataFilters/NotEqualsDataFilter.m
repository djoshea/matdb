classdef NotEqualsDataFilter < MatchDataFilter 
% implements a one-field ~= one-value type filter

    methods(Static)
        function keywords = getKeywords()
            keywords = {'notEquals', '!=', '<>', '~='};
        end
    end

    methods
        function initialize(filt, field, value)
            filt.fields = {field};
            filt.values = {value};
        end

        function newMask = getMask(filt, fieldToValuesMap, currentMask, dfdMap)
            newMask = currentMask;
            iField = 1;
            field = filt.fields{iField};
            fieldValues = fieldToValuesMap(field);
            value = filt.values{iField};
            isEqual = dfdMap(field).valuesEqualTo(fieldValues, value);
            newMask = newMask & ~isEqual; 
        end
    end
end
