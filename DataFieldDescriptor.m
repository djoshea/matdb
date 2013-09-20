classdef DataFieldDescriptor < handle

    properties(Abstract, Dependent)
        matrix % returned as a matrix if true, returned as cell array if false
    end

    methods
        function dfd = DataFieldDescriptor(varargin)

        end
    end

    methods(Abstract)
        str = describe(dfd);
        
        % indicates whether this field should be displayed or not
        tf = isDisplayable(dfd);

        % convert the values of this field into a cell array of strings
        % typically used by getAsDisplayStrings
        strCell = getAsStrings(dfd, values);

        % sorts the values in either ascending or descending order
        sortIdx = sortValues(dfd, values, ascendingOrder);

        % converts the set of field values in values to a format appropriate
        % for this DataFieldDescriptor.
        convValues = convertValues(dfd, values);

        % uniquifies field values
        uniqueValues = uniqueValues(dfd, values);

        % compares a list of field values to a reference value and returns -1, 0, 1 for each 
        compareSign = compareValuesTo(dfd, values, ref);

        % given a list of values from this field, compare each to a reference value
        % simply isEqual(i) indicates whether isequal(values(i), i)
        % this is similar to compareValuesTo except it is faster for some 
        % field types if you don't care about the sign of the comparison
        isEqual = valuesEqualTo(dfd, values, ref);
    end

    methods(Static, Abstract)
        [tf dfd] = canDescribeValues(cellValues);
    end

    methods
        % displays .describe()
        function disp(dfd)
            if dfd.matrix
                as = 'matrix';
            else
                as = 'cell';
            end
            fprintf('%s (as %s)\n\n', dfd.describe(), as);
        end

        function strCell = getAsDisplayStrings(dfd, values)
            maxLength = 12;

            if ~dfd.isDisplayable()
                error('This %s field is not displayable', char(dfd.type));
            end
            strCell = dfd.getAsStrings(values);
           
            % abbreviate to max length
            strLen = cellfun(@length, strCell);
            tooLong = strLen > maxLength; 
            strCell(tooLong) = cellfun(@(x) [x(1:maxLength-2) '..'], ...
                strCell(tooLong), 'UniformOutput', false);
        end

        function strCell = getAsFilenameStrings(dfd, values)
            strCell = dfd.getAsStrings(values);
        end
        
        function emptyValue = getEmptyValueElement(dfd)
            emptyValue = dfd.getEmptyValue();
            if iscell(emptyValue)
                emptyValue = emptyValue{1};
            end
        end

        function emptyValue = getEmptyValue(dfd, nValues)
            if nargin < 2
                nValues = 1;
            end
            
            if nValues == 0
                if dfd.matrix
                    emptyValue = [];
                else
                    emptyValue = {};
                end
                return;
            end

            % for simplicity, use convert values to take care of this for us
            % we just pass it an array of the correct size
            origEmpty = cell(nValues, 1);
            emptyValue = dfd.convertValues(origEmpty);
        end
    end

    methods(Static) % Static utility methods
        function dfd = inferFromValues(values) 
            % return a DataFieldDescriptor instance which attempts to describes 
            % the field whose values are in values. i.e. if values contains
            % all scalars, it will be a Scalar field. if values contains date strings
            % it will be a Date field with the format string inferred automatically, etc.
            %
            % values may be either an array or cell array

            assert(isvector(values), 'Values must be a vector');

            % convert to cell array
            cellValues = makecol(values);
            if ~iscell(cellValues)
                cellValues = num2cell(cellValues);
            end

            classesToTry = {'ScalarField', 'DateField', 'DateTimeField', ...
                'NumericVectorField', 'StringField'};

            for iClass = 1:length(classesToTry)
                className = classesToTry{iClass};
                fn = str2func([className '.canDescribeValues']);
                [tf dfd] = fn(cellValues);
                if tf
                    return;
                end
            end

            dfd = UnspecifiedField();
        end
    end
end
