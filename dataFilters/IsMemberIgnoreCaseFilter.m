classdef IsMemberIgnoreCaseFilter < DataFilter

    properties(SetAccess=protected)
        values
    end

    methods(Static)
        function keywords = getKeywords()
            keywords = {'ismemberi'};
        end
    end

    methods
        function filt = IsMemberIgnoreCaseFilter(varargin)
            filt = filt@DataFilter(varargin{:});
        end

        function initialize(filt, field, values)
            filt.fields = {field}; 
            if ~iscell(values)
                values = {values};
            end
            filt.values = values;
        end

        % applies this filter to the data values in fieldValues
        function newMask = getMask(filt, fieldToValuesMap, currentMask, dfdMap)
            newMask = currentMask;
            field = filt.fields{1};
            values = filt.values; %#ok<*PROPLC>
            
            fieldValues = fieldToValuesMap(field);
            dfd = dfdMap(field);
            assert(isa(dfd, 'StringField'), 'StringIgnoreCase filter only usable for string fields');

            values = cellfun(@lower, values, 'UniformOutput', false);
            fieldValues = cellfun(@lower, fieldValues, 'UniformOutput', false);
            
            matchesMask = ismember(fieldValues, values);
            
            newMask = newMask & matchesMask;
        end

        % return a very brief description of what this filter searches for
        function str = describe(filt)
            if iscell(filt.values)
                valueStr = strjoin(filt.values);
            else
                valueStr = vector2str(filt.values);
            end
            str = sprintf('%s ismemberi %s', filt.field, valueStr);
        end
    end
end
