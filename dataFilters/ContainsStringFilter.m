classdef ContainsStringFilter < DataFilter

    properties(SetAccess=protected)
        value
    end

    methods(Static)
        function keywords = getKeywords()
            keywords = {'contains'};
        end
    end

    methods
        function filt = ContainsStringFilter(varargin)
            filt = filt@DataFilter(varargin{:});
        end

        function initialize(filt, field, contains)
            filt.fields = {field}; 
            filt.value = contains;
        end

        % applies this filter to the data values in fieldValues
        function newMask = getMask(filt, fieldToValuesMap, currentMask, dfdMap)
            newMask = currentMask;
            field = filt.fields{1};
            value = filt.value;
            fieldValues = fieldToValuesMap(field);
            dfd = dfdMap(field);
            assert(isa(dfd, 'StringField'), 'Contains filter only works for string fields');

            containsMask = cellfun(@(x) ~isempty(x), strfind(fieldValues, value));
            
            newMask = newMask & containsMask;
        end

        % return a very brief description of what this filter searches for
        function str = describe(filt)
            str = sprintf('%s contains "%s"', filt.field, filt.value);
        end
    end
end
