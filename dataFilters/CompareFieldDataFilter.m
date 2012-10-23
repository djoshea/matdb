classdef CompareFieldDataFilter < DataFilter
% implements an abstract one-field compared to one-value type filter

    properties(SetAccess=protected)
        value
    end

    methods(Abstract)
        % return a token describing this comparison, e.g. '==', '>', etc.
        str = getOperatorString(filt);

        % given a vector of -1 (less than), 0 (equal), or 1 (greater than)
        % convert this to a selction mask of entries which satisfy the comparison
        mask = convertCompareSignToMask(filt, compareSign);
    end

    methods
        function filt = CompareFieldDataFilter(varargin)
            filt = filt@DataFilter(varargin{:});
        end

        function initialize(filt, field, value)
            filt.fields = {field};
            filt.value = value;
        end

        % applies this filter to the data values in fieldValues
        function newMask = getMask(filt, fieldToValuesMap, currentMask, dfdMap)
            field = filt.fields{1};
            fldValues = fieldToValuesMap(field);
            compareSign = dfdMap(field).compareValuesTo(fldValues, filt.value);
            newMask = filt.convertCompareSignToMask(compareSign); 
        end

        function str = describe(filt)
            % return a very brief description of what this filter searches for
            if isnumeric(filt.value) || islogical(filt.value)
                value = num2str(filt.value);
            elseif ischar(filt.value)
                value = sprintf('''%s''', filt.value);
            else
                value = sprintf('[%s]', class(filt.value));
            end
            str = sprintf('%s %s %s', filt.fields{1}, filt.getOperatorString(), value);
        end
    end
end
