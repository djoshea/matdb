classdef StringIgnoreCaseFilter < DataFilter

    properties(SetAccess=protected)
        value
    end

    methods(Static)
        function keywords = getKeywords()
            keywords = {'matchesIgnoreCase', 'strcmpi'};
        end
    end

    methods
        function filt = StringIgnoreCaseFilter(varargin)
            filt = filt@DataFilter(varargin{:});
        end

        function initialize(filt, field, value)
            assert(ischar(value), 'Value must be a string');
            filt.fields = {field}; 
            filt.value = value;
        end

        % applies this filter to the data values in fieldValues
        function newMask = getMask(filt, fieldToValuesMap, currentMask, dfdMap)
            newMask = currentMask;
            field = filt.fields{1};
            value = filt.value;
            fieldValues = fieldToValuesMap(field);
            dfd = dfdMap(field);
            assert(isa(dfd, 'StringField'), 'StringIgnoreCase filter only usable for string fields');

            matchesMask = strcmpi(fieldValues, value);
            
            newMask = newMask & matchesMask;
        end

        % return a very brief description of what this filter searches for
        function str = describe(filt)
            str = sprintf('%s matches (ignoring case) "%s"', filt.field, filt.value);
        end
    end
end
