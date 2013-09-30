classdef NumericField < DataFieldDescriptor

    properties(Dependent)
        matrix % returned as a matrix if true, returned as cell array if false
    end

    methods
        function matrix = get.matrix(dfd)
            matrix = false;
        end

        % return a string representation of this field's data type
        function str = describe(dfd)
            str = 'NumericField';
        end

        % indicates whether this field should be displayed or not
        function tf = isDisplayable(dfd)
            tf = false;
        end

        % converts field values to a string
        function strCell = getAsStrings(dfd, values) 
            strCell = repmat('', sizeof(values));
            return;
            if ndims(values) == 2
                strCell = cellfun(@mat2str, values, 'UniformOutput', false);
            else
                strCell = cellfun(@num2str, values, 'UniformOutput', false);
            end
        end

        % sorts the values in either ascending or descending order
        function sortIdx = sortValues(dfd, values, ascendingOrder)
            error('Sorting not supported for NumericVectorField');
        end

        % converts field values to an appropriate format
        function convValues = convertValues(dfd, values) 
           
            if isempty(values)
                convValues = {};
            elseif ~iscell(values)
                convValues = num2cell(values);
            elseif iscell(values)
                convValues = values;
            else
                error('Values must be either a cell array or numeric vector');
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
        
        function maskMat = valueCompareMulti(dfd, valuesLeft, valuesRight)
            % maskMat(i,j) is true iff valuesLeft(i) == valuesRight(j)
            
            % assumes valuesLeft and valuesRight are both column cell vectors
            
            % build matrix of values like ndgrid
            mLeft = repmat(valuesLeft, 1, numel(valuesRight));
            mRight = repmat(valuesRight', numel(valuesLeft), 1);
            
            maskMat = cellfun(@isequal, mLeft, mRight);
        end
    end

    methods(Static) % Static utility methods
        function [tf, dfd] = canDescribeValues(cellValues)
            tf = cellfun(@(x) isnumeric(x) || islogical(x), cellValues);
            if all(tf)
                dfd = NumericField(); 
            else
                dfd = [];
            end
        end
    end
end

