classdef MatchDataFilter < DataFilter
% implements an abstract one-field compared to one-value type filter

    properties(SetAccess=protected)
        values
    end

    methods(Static)
        function keywords = getKeywords()
            keywords = {'match'};
        end
    end

    methods
        function filt = MatchDataFilter(varargin)
            filt = filt@DataFilter(varargin{:});
        end

        function initialize(filt, varargin)
            p = inputParser;
            p.KeepUnmatched = true;
            p.parse(varargin{:});
            filt.fields = fieldnames(p.Unmatched);
            filt.values = cellfun(@(field) p.Unmatched.(field), filt.fields, 'UniformOutput', false);
        end

        % applies this filter to the data values in fieldValues
        function newMask = getMask(filt, fieldToValuesMap, currentMask, dfdMap)
            newMask = currentMask;
            for iField = 1:filt.nFields
                field = filt.fields{iField};
                fieldValues = fieldToValuesMap(field);
                value = filt.values{iField};
                isEqual = dfdMap(field).valuesEqualTo(fieldValues, value);
                newMask = newMask & isEqual; 
            end
        end

        % return a very brief description of what this filter searches for
        function str = describe(filt)
            strCell = cell(filt.nFields, 1);
            for iField = 1:filt.nFields
                field = filt.fields{iField};
                value = filt.values{iField};
                if isnumeric(value) || islogical(value)
                    value = num2str(value);
                elseif ischar(value)
                    value = sprintf('''%s''', value);
                else
                    value = sprintf('[%s]', class(value));
                end
                strCell{iField} = sprintf('%s=%s', field, value);
            end

            str = strjoin(strCell, ', ');
        end
    end
end
