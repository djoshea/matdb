classdef EqualsDataFilter < MatchDataFilter 
% implements a one-field == one-value type filter

    methods(Static)
        function keywords = getKeywords()
            keywords = {'equals', '=='};
        end
    end

    methods
        function initialize(filt, field, value)
            filt.fields = {field};
            filt.values = {value};
        end
    end
end
