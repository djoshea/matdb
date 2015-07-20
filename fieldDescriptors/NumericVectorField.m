classdef NumericVectorField < DataFieldDescriptor

    methods
        function matrix = isScalar(dfd)
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
            values = cellfun(@getFirstOrNaN, values);
            [~, sortIdx] = sort(values, 1, sortMode); 
            
            function v = getFirstOrNaN(vec)
                if isempty(vec)
                    v = NaN;
                else
                    v = vec(1);
                end
            end
        end

        % converts field values to an appropriate format
        function convValues = convertValues(dfd, values) 
            % converts the set of field values in values to a format appropriate
            % for this DataFieldDescriptor.
            %
            assert(isempty(values) || isvector(values), 'Values must be a vector');
            if isempty(values)
                convValues = [];
            elseif ~iscell(values)
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
        
        function maskMat = valueCompareMulti(dfd, valuesLeft, valuesRight)
            % maskMat(i,j) is true iff valuesLeft(i) == valuesRight(j)
            % this is optimized for the case where either cell is a scalar
            
            % assumes valuesLeft and valuesRight are both column cell vectors
            maskMat = false(numel(valuesLeft), numel(valuesRight));
            
            % first try comparing the cross-terms where both are scalar
            numelLeft = cellfun(@numel, valuesLeft);
            numelRight = cellfun(@numel, valuesRight);
            scalarLeft = numelLeft==1;
            scalarRight = numelRight==1;
            maskMat(bsxfun(@and, scalarLeft, scalarRight')) = bsxfun(@eq, cell2mat(valuesLeft(scalarLeft)),  cell2mat(valuesRight(scalarRight))');
            
%           % and then compare the terms where neither is scalar but both
%           have the same length
            notScalarLeft = find(~scalarLeft);
            for iiLeft = 1:numel(notScalarLeft)
                idxLeft = notScalarLeft(iiLeft);
                nLeft = numelLeft(idxLeft);
                vLeft = valuesLeft{idxLeft};
                
                possibleRight = find(numelRight == nLeft);
                maskMat(idxLeft, possibleRight) = cellfun(@(vRight) isequal(vLeft, vRight), valuesRight(possibleRight));
            end
            
            % old way of doing this
%             mLeft = repmat(valuesLeft(~maskScalarLeft), 1, numel(valuesRight));
%             mRight = repmat(valuesRight(~maskScalarRight)', numel(valuesLeft), 1);
%             
%             maskMat = cellfun(@isequal, mLeft, mRight);
%             maskMat(bsxfun(@and, ~maskScalarLeft, ~maskScalarRight)) = isequalNeither;

%             maskMat(bsxfun(@and, maskScalarLeft, maskScalarRight)

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

