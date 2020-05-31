classdef DateTimeField < DataFieldDescriptor

    properties
        dateFormat % used mainly for DataTimeFieldType.Date
        standardDateFormat
        standardDisplayFormat
    end

    methods
        function dfd = DateTimeField(varargin)
            p = inputParser;
            p.addOptional('dateFormat', '', @ischar);
            p.parse(varargin{:});

            dfd.dateFormat = p.Results.dateFormat;
        end

        function str = getStandardDateFormat(dfd) %#ok<MANU>
            str = 'yyyy-mm-dd HH:MM:SS';
        end
        
        function str = getStandardDisplayFormat(dfd) %#ok<MANU>
            str = 'ddd dd mmm yyyy HH:MM:SS';
        end
        
        function f = get.standardDateFormat(dfd)
            f = dfd.getStandardDateFormat();
        end
        
        function f = get.standardDisplayFormat(dfd)
            f = dfd.getStandardDisplayFormat();
        end
            
        function matrix = isScalar(dfd) %#ok<MANU>
            matrix = true;
        end

        % return a string representation of this field's data type
        function str = describe(dfd)
            if ~isempty(dfd.dateFormat)
                format = [' ' dfd.dateFormat];
            else
                format = '';
            end
            str = sprintf('%s%s', class(dfd), format);
        end

        % converts DataFieldType.DateField values to a 1x6 datevec
        function vec = getAsDateVec(dfd, values) %#ok<INUSL>
            vec = datevec(values);
        end

        % converts DataFieldType.DateField values to a scalar datenum
        function num = getAsDateNum(dfd, values)
            if isempty(values)
                num = [];
                return;
            end
            if isnumeric(values) && ~ischar(values)
                if ~isempty(dfd.dateFormat)
                    % might be an all numeric format
                    num = datenum(arrayfun(@num2str, values, 'UniformOutput', false), dfd.dateFormat);
                else
                    num = values;
                end
                return;
            end
            
            % handle cellstr case
            if ~isempty(dfd.dateFormat)
                datenumFn = @(values) datenum(values, dfd.dateFormat);
            else
                datenumFn = @(values) datenum(values);
            end
            
            % replace empty or nan entries with the default value
            % pre conversion
            invalidFn = @(v) isempty(v) || (~ischar(v) && (~isscalar(v) || isnan(v)));
            if iscell(values)
                defaultMask = cellfun(invalidFn, values);
            else
                defaultMask = arrayfun(invalidFn, values);
            end
            % better default value handling
            num = zeros(numel(values), 1);
            if any(~defaultMask)
                num(~defaultMask) = datenumFn(values(~defaultMask));
            end
        end

        function strCell = getAsDateStr(dfd, values, format)
            if nargin < 3
                format = dfd.standardDateFormat;
            end
            strCell = cell(length(values), 1);
            nums = dfd.getAsDateNum(values);
            for i = 1:length(nums)
                value = nums(i);
                if value == 0 || isnan(value)
                    strCell{i} = '';
                else
                    strCell{i} = datestr(value, format);
                end
            end
        end

        % indicates whether this field should be displayed or not
        function tf = isDisplayable(dfd) %#ok<MANU>
            tf = true;
        end

        % converts field values to a string
        function strCell = getAsStrings(dfd, values) 
            strCell = dfd.getAsDateStr(values, dfd.standardDisplayFormat);
        end
        
        function strCell = getAsDisplayStrings(dfd, values) 
            strCell = dfd.getAsStrings(values);
        end

        function strCell = getAsFilenameStrings(dfd, values)
            strCell = dfd.getAsDateStr(values, 'yyyy-mm-dd HH-MM-SS');
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

            nums = dfd.getAsDateNum(values);
            [~, sortIdx] = sort(makecol(nums), 1, sortMode);
        end

        % converts field values to an appropriate format
        function convValues = convertValues(dfd, values) 
            % converts the set of field values in values to a format appropriate
            % for this DataFieldDescriptor.
            
            % convert these to string cell array
            if isempty(values)
                nums = NaN; 
              
            elseif isnumeric(values)
                % keep numeric values as is always. you must manually
                % convert to strings before passing in pure numeric formats
                % like 20120303, since otherwise we can't keep datenums and
                % formatted numbers straight
                nums = values;
                
            elseif iscellstr(values) || ischar(values)
                % convert cells using getAsDateNum
                if ischar(values)
                    values = {values};
                end
                [valid, convValues] = isStringCell(values, 'convertVector', true);
                assert(valid, 'Cannot convert values into string cell array');
                % furthermore, convert the date to a standard date format
                nums = dfd.getAsDateNum(convValues);
                
            elseif iscell(values)
                % convert from cell array of numbers to cell
                nums = cell2mat(values);
            else
                error('Cannot convert values into DateTimeField');
            end
            
            convValues = nums;
        end
        
        function emp = getEmptyValue(dfd, nValues) %#ok<INUSL>
            if nargin < 2
                nValues = 1;
            end
            emp = nan(nValues, 1);
        end

        % uniquifies field values
        function uniqueValues = uniqueValues(dfd, values) %#ok<INUSL>
            % finds the unique values within values according to the data type 
            % specified by this DataFieldDescriptor. Automatically removes empty
            % values and NaN values
           
            uniqueValues = unique(values);
        end

        % compares a list of field values to a reference value and returns -1, 0, 1 for each 
        function compareSign = compareValuesTo(dfd, values, ref)
            % given a list of values from this field, compare each to a reference value
            % ref, and return an array of -1, 0, 1 indicating <, ==, > the ref value

            nums = dfd.getAsDateNum(values);

            try
                refAsNum = datenum(ref);
            catch
                % no luck with auto datevec format, try using the 
                % same format as this field
                refAsNum = dfd.getAsDateNum(ref);
            end

            compareSign = sign(nums - refAsNum);
        end

        function isEqual = valuesEqualTo(dfd, values, ref)
            % given a list of values from this field, compare each to a reference value
            % simply isEqual(i) indicates whether isequal(values(i), i)
            % this is similar to compareValuesTo except it is faster for some 
            % field types if you don't care about the sign of the comparison
                
            nums = dfd.getAsDateNum(values);

            try
                refAsNum = datenum(ref);
            catch
                % no luck with auto datevec format, try using the 
                % same format as this field
                refAsNum = dfd.getAsDateNum(ref);
            end

            isEqual = nums == refAsNum;
        end
        
        function maskMat = valueCompareMulti(dfd, valuesLeft, valuesRight)
            % maskMat(i,j) is true iff valuesLeft(i) == valuesRight(j)
            
            numsLeft = dfd.getAsDateNum(valuesLeft);
            numsRight = dfd.getAsDateNum(valuesRight);
            
            % assumes valuesLeft and valuesRight are both column vectors
            maskMat = pdist2(numsLeft, numsRight, 'hamming') == 0;
        end
    end

    methods(Static) % Static utility methods
        function [tf, dfd] = canDescribeValues(cellValues)
            [tf, format, num] = ...
                isDateStrCell(cellValues, 'allowMultipleFormats', false); %#ok<NASGU>

            if tf
                % all values work with datevec --> date field
                dfd = DateTimeField();
                dfd.dateFormat = format;
            else
                dfd = [];
            end
        end
    end
end
