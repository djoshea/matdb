classdef LessThanDataFilter < CompareFieldDataFilter
% implements a one-field < one-value type filter

    methods(Static)
        function keywords = getKeywords()
            keywords = {'lt', 'lessThan', '<'};
        end
    end

    methods
        % return a token describing this comparison, e.g. '==', '>', etc.
        function str = getOperatorString(filt)
            str = '<';
        end
        
        % given a vector of -1 (less than), 0 (equal), or 1 (greater than)
        % convert this to a selction mask of entries which satisfy the comparison
        function mask = convertCompareSignToMask(filt, compareSign)
            mask = compareSign == -1;
        end
    end
end
