classdef StringField < DataFieldDescriptor

    properties(Dependent)
        matrix % returned as a matrix if true, returned as cell array if false
    end

    methods
        function matrix = get.matrix(dfd)
            matrix = false;
        end

        % return a string representation of this field's data type
        function str = describe(dfd)
            str = 'StringField';
        end

        % indicates whether this field should be displayed or not
        function tf = isDisplayable(dfd)
            tf = true;
        end

        % converts field values to a string
        function strCell = getAsStrings(dfd, values) 
            strCell = values;
        end

        % sorts the values in either ascending or descending order
        function sortIdx = sortValues(dfd, values, ascendingOrder)
            % on the basis of this field type, sort the values provided in values
            % (numeric or cell array) either in ascending or descending (inAscending = false)
            % order, maintaining the existing ordering if there is a tie
            %
            % sortIdx is the sort order, i.e. values(sortIdx) is in sorted order

            if isempty(values)
                sortIdx = [];
                return;
            end
            
            values = makecol(values);
            if ascendingOrder 
                sortMode = 'ascend';
            else
                sortMode = 'descend';
            end
           
            % need a special sort function here
            % because sort does not sort strings in reverse order
            [~, sortIdx] = sortStrings(values, sortMode); 
        end

        % converts field values to an appropriate format
        function convValues = convertValues(dfd, values) 
            % converts the set of field values in values to a format appropriate
            % for this DataFieldDescriptor.
            
            % convert these to string cell array
            if ischar(values)
                convValues = {values};
            elseif isempty(values) || iscell(values)
                [valid convValues] = isStringCell(values, 'convertVector', true);
                assert(valid, 'Cannot convert values into string cell array');
            else
                error('Cannot convert values into string cell array');
            end

            convValues = makecol(convValues);
        end

        % uniquifies field values
        function uniqueValues = uniqueValues(dfd, values)
            % finds the unique values within values according to the data type 
            % specified by this DataFieldDescriptor. Automatically removes empty
            % values and NaN values
            uniqueValues = unique(values);
        end

        % compares a list of field values to a reference value and returns -1, 0, 1 for each 
        function compareSign = compareValuesTo(dfd, values, ref)
            % given a list of values from this field, compare each to a reference value
            % ref, and return an array of -1, 0, 1 indicating <, ==, > the ref value
            
            % use sort to sort ref into values 
            assert(ischar(ref), 'Comparison must be with a string');
            combined = [{ref}; makecol(values)];
            [~, idx] = sort(combined);

            % find the reference in the sorted list
            idxRef = find(idx == 1);
            idxBefore = idx(1:idxRef-1) - 1;
            idxAfter = idx(idxRef+1:end) - 1;

            % mark the sign based on position relative to reference
            compareSign = nan(size(values)); 
            compareSign(idxBefore) = -1;
            compareSign(idxAfter) = 1;
            compareSign(strcmp(values, ref)) = 0;
        end

        function isEqual = valuesEqualTo(dfd, values, ref)
            % given a list of values from this field, compare each to a reference value
            % simply isEqual(i) indicates whether isequal(values(i), i)
            % this is similar to compareValuesTo except it is faster for some 
            % field types if you don't care about the sign of the comparison

            % use sort to sort ref into values 
            isEqual = strcmp(values, ref);
        end
    end

    methods(Static) % Static utility methods
        function [tf dfd] = canDescribeValues(cellValues)
            tf = isStringCell(cellValues, 'convertVector', true);
            % all values can be converted to strings --> string field
            dfd = StringField(); 
        end
    end
end
