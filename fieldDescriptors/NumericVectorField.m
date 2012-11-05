classdef NumericVectorField < DataFieldDescriptor

    properties(Dependent)
        matrix % returned as a matrix if true, returned as cell array if false
    end

    methods
        function matrix = get.matrix(dfd)
            matrix = false;
        end

        % return a string representation of this field's data type
        function str = describe(dfd)
            str = 'NumericVectorField';
        end

        % indicates whether this field should be displayed or not
        function tf = isDisplayable(dfd)
            tf = true;
        end

        % converts field values to a string
        function strCell = getAsStrings(dfd, values) 
            strCell = vector2str(values);
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

            % use first value of vector
            values = cellfun(@(x) x(1), values);
            [~, sortIdx] = sort(values, 1, sortMode); 
        end

        % converts field values to an appropriate format
        function convValues = convertValues(dfd, values) 
            % converts the set of field values in values to a format appropriate
            % for this DataFieldDescriptor.
            %
            assert(isvector(values), 'Values must be a vector');
            if ~iscell(values)
                if isnumeric(values) || islogical(values)
                    convValues = num2cell(values);
                else
                    error('Values must be either a cell array or numeric vector');
                end
            else
                [tf convValues] = isVectorCell(values);
                assert(tf, 'Unable to convert values to NumericVectorField');
            end
                    
            convValues = makecol(convValues);
        end

        % uniquifies field values
        function uniqueValues = uniqueValues(dfd, values)
            % finds the unique values within values according to the data type 
            % specified by this DataFieldDescriptor. Automatically removes empty
            % values and NaN values
            %
            if ~iscell(values)
                values = num2cell(values);
            end
            uniqueValues = uniqueCell(values, 'removeEmpty', true);
        end

        % compares a list of field values to a reference value and returns -1, 0, 1 for each 
        function compareSign = compareValuesTo(dfd, values, ref)
            % given a list of values from this field, compare each to a reference value
            % ref, and return an array of -1, 0, 1 indicating <, ==, > the ref value
            error('Comparison not supported for NumericVectorField');
        end

        function isEqual = valuesEqualTo(dfd, values, ref)
            % given a list of values from this field, compare each to a reference value
            % simply isEqual(i) indicates whether isequal(values(i), i)
            % this is similar to compareValuesTo except it is faster for some 
            % field types if you don't care about the sign of the comparison

            if iscell(values)
                isEqual = cellfun(@(x) isequal(x, ref), values);
            else
                isEqual = arrayfun(@(x) (isnan(x) && isnan(ref)) || isequal(x, ref), values);
            end
        end
    end

    methods(Static) % Static utility methods
        function [tf dfd] = canDescribeValues(cellValues)
            tf = isVectorCell(cellValues);
            if tf 
                dfd = NumericVectorField(); 
            else
                dfd = [];
            end
        end
    end
end
