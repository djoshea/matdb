classdef IndexSelectDataFilter < DataFilter
% selects entries by idx (either logical or idx) 

    properties(SetAccess=protected)
        idx 
    end

    methods(Static)
        function keywords = getKeywords()
            keywords = {'idx', 'rows', '()'};
        end
    end

    methods
        function filt = IndexSelectDataFilter(varargin)
            filt = filt@DataFilter(varargin{:});
        end

        function initialize(filt, idx)
            filt.idx = idx;
        end

        % applies this filter to the data values in fieldValues
        function newMask = getMask(filt, fieldToValuesMap, currentMask, dfdMap)
            if islogical(filt.idx)
                assert(length(filt.idx) == length(currentMask), 'Selection mask is not the correct size');
                newMask = filt.idx;
            else
                newMask = false(size(currentMask));
                newMask(filt.idx) = true;
                assert(length(currentMask) == length(newMask), 'Selection indices out of range');
            end
        end

        function str = describe(filt)
            % return a very brief description of what this filter searches for
            str = sprintf('select %d entries', nnz(filt.idx));
        end
    end
end
