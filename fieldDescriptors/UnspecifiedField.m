classdef UnspecifiedField < DataFieldDescriptor

    properties(Dependent)
        matrix % returned as a matrix if true, returned as cell array if false
    end

    methods
        function matrix = get.matrix(dfd)
            matrix = false;
        end

        % return a string representation of this field's data type
        function str = describe(dfd)
            str = 'UnspecifiedField';
        end

        % indicates whether this field should be displayed or not
        function tf = isDisplayable(dfd)
            tf = false;
        end

        % converts field values to a string
        function strCell = getAsStrings(dfd, values) 
            for i = 1:length(values)
                if isempty(values{i})
                    strCell{i} = '[ ]';
                else
                    sizeStr = vector2str(size(values{i}), 'separator', 'x');
                    strCell{i} = sprintf('[%s %s]', sizeStr, class(values{i}));
                end
            end
            %error('getAsStrings not supported for UnspecifiedField');
        end

        % sorts the values in either ascending or descending order
        function sortIdx = sortValues(dfd, values, ascendingOrder)
            % on the basis of this field type, sort the values provided in values
            % (numeric or cell array) either in ascending or descending (inAscending = false)
            % order, maintaining the existing ordering if there is a tie
            %
            % sortIdx is the sort order, i.e. values(sortIdx) is in sorted order

            error('sortValues not supported for UnspecifiedField');
        end

        % converts field values to an appropriate format
        function convValues = convertValues(dfd, values) 
            % converts the set of field values in values to a format appropriate
            % for this DataFieldDescriptor.
           
            convValues = makecol(values);
        end

        % uniquifies field values
        function uniqueValues = uniqueValues(dfd, values)
            % finds the unique values within values according to the data type 
            % specified by this DataFieldDescriptor. Automatically removes empty
            % values and NaN values

            error('uniqueValues not supported for UnspecifiedField');
        end

        % compares a list of field values to a reference value and returns -1, 0, 1 for each 
        function compareSign = compareValuesTo(dfd, values, ref)
            % given a list of values from this field, compare each to a reference value
            % ref, and return an array of -1, 0, 1 indicating <, ==, > the ref value

            error('compareValuesTo not supported for UnspecifiedField');
        end

        function isEqual = valuesEqualTo(dfd, values, ref)
            error('valuesEqualTo not supported for UnspecifiedField');
        end

    end

    methods(Static) % Static utility methods
        function [tf dfd] = canDescribeValues(cellValues)
            tf = true;
            dfd = UnspecifiedField();
        end
    end
end
