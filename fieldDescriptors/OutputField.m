classdef OutputField < StringField 
    % exactly like StringField, except it strips ansi escape codes
    % in getAsStrings and getAsDisplayStrings

    methods
        % return a string representation of this field's data type
        function str = describe(dfd)
            str = 'OutputField';
        end

        function strCell = getAsStrings(dfd, values) 
            % converts field values to a string, strip ansi escape codes
            strCell = stripAnsi(values);
        end

        function lineCounts = getLineCounts(dfd, values)
            % return the number of line breaks in each string in values
            lineCountFn = @(output) nnz(output == char(13) | output == char(10));
            if ~iscell(values)
                values = {values};
            end
            lineCounts = cellfun(lineCountFn, values);
        end
    end

end
