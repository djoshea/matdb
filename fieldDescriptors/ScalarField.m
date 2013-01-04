classdef ScalarField < DataFieldDescriptor 

    properties(Dependent)
        matrix % returned as a matrix if true, returned as cell array if false
    end

    methods
        function matrix = get.matrix(dfd)
            matrix = true;
        end

        % return a string representation of this field's data type
        function str = describe(dfd)
            str = 'ScalarField'; 
        end

        % indicates whether this field should be displayed or not
        function tf = isDisplayable(dfd)
            tf = true;
        end

        % converts field values to a string
        function strCell = getAsStrings(dfd, values) 
            strCell = arrayfun(@num2str, values, 'UniformOutput', false);
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

            [~, sortIdx] = sort(values, 1, sortMode); 
        end

        % converts field values to an appropriate format
        function convValues = convertValues(dfd, values) 
            % converts the set of field values in values to a format appropriate
            % for this DataFieldDescriptor.

            % convert these to numeric array
            if isempty(values)
                convValues = NaN;
            elseif iscell(values)
                [valid convValues] = isScalarCell(values);
                assert(valid, 'Cannot convert values into numeric array');
            elseif isnumeric(values) || islogical(values) 
                convValues = values;
            else
                error('Cannot convert values into numeric array');
            end

            convValues = makecol(convValues);
        end

        % uniquifies field values
        function uniqueValues = uniqueValues(dfd, values)
            % finds the unique values within values according to the data type 
            % specified by this DataFieldDescriptor. Automatically removes empty
            % values and NaN values
            %
            % ScalarField, DateNumField : removenan(unique())
            % StringField, DateField : unique()
            % NumericVectorField, StringArrayField : uniqueCell()
           
            uniqueValues = removenan(unique(values));

        end

        % compares a list of field values to a reference value and returns -1, 0, 1 for each 
        function compareSign = compareValuesTo(dfd, values, ref)
            % given a list of values from this field, compare each to a reference value
            % ref, and return an array of -1, 0, 1 indicating <, ==, > the ref value

            compareSign = sign(values - ref);
        end

        function isEqual = valuesEqualTo(dfd, values, ref)
            % given a list of values from this field, compare each to a reference value
            % simply isEqual(i) indicates whether isequal(values(i), i)
            % this is similar to compareValuesTo except it is faster for some 
            % field types if you don't care about the sign of the comparison

            if ~isscalar(ref)
                debug('Warning: comparing scalar to vector for now yields no matches\n');
                isEqual = false(size(values));
            else
                isEqual = (isnan(values) & isnan(ref)) | (values == ref);
            end
        end
    end

    methods(Static) % Static utility methods
        function [tf dfd] = canDescribeValues(cellValues)
            tf = isScalarCell(cellValues);
           
            if tf
                % all values can be converted to strings --> string field
                dfd = ScalarField();
            else
                dfd = [];
            end
        end
    end
end
