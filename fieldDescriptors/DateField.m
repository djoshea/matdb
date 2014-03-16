classdef DateField < DateTimeField

    methods
        function dfd = DateField(varargin)
            p = inputParser;
            p.addOptional('dateFormat', '', @ischar);
            p.parse(varargin{:});

            dfd.dateFormat = p.Results.dateFormat;
        end
        
        function str = getStandardDateFormat(dfd) %#ok<MANU>
            str = 'yyyy-mm-dd';
        end
        
        function str = getStandardDisplayFormat(dfd) %#ok<MANU>
            str = 'dd mmm yyyy';
        end

        % converts DataFieldType.DateField values to a 1x6 datevec
        function vec = getAsDateVec(dfd, values)
            values = floor(values);
            vec = getAsDateVec@DateTimeField(dfd, values);
        end

        % converts DataFieldType.DateField values to a scalar datenum
        function num = getAsDateNum(dfd, values)
            num = getAsDateNum@DateTimeField(dfd, values);
            num = floor(num);
        end

        function strCell = getAsDateStr(dfd, values, format)
            values = floor(values);
            strCell = getAsDateStr@DateTimeField(dfd, values, format);
        end

        % sorts the values in either ascending or descending order
        function sortIdx = sortValues(dfd, values, ascendingOrder)
            values = floor(values);
            sortIdx = sortValues@DateTimeField(dfd, values, ascendingOrder);
        end

        % converts field values to an appropriate format
        function convValues = convertValues(dfd, values) 
            convValues = convertValues@DateTimeField(dfd, values);
        end

        % uniquifies field values
        function values = uniqueValues(dfd, values)
            % finds the unique values within values according to the data type 
            % specified by this DataFieldDescriptor. Automatically removes empty
            % values and NaN values
           
            values = floor(values);
            values = uniqueValues@DateTimeField(dfd, values);
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

            % drop the time component to only compare dates
            refAsNum = floor(refAsNum);
            
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

            % drop the time component to only compare dates
            refAsNum = floor(refAsNum);

            isEqual = nums == refAsNum;
        end
        
        function maskMat = valueCompareMulti(dfd, valuesLeft, valuesRight)
            % maskMat(i,j) is true iff valuesLeft(i) == valuesRight(j)
            
            numsLeft = floor(dfd.getAsDateNum(valuesLeft));
            numsRight = floor(dfd.getAsDateNum(valuesRight));
            
            % assumes valuesLeft and valuesRight are both column vectors
            maskMat = pdist2(numsLeft, numsRight, 'hamming') == 0;
        end
    end

    methods(Static) % Static utility methods
        function [tf, dfd] = canDescribeValues(cellValues)
            if isnumeric(cellValues)
                tf = true;
                format = [];
                num = cellValues;
            else
                [tf, format, num] = isDateStrCell(cellValues, 'allowMultipleFormats', false);
            end
            
            if tf
                % all entries are date strings, are they even days with no time offset?
                if isequaln(floor(num), num)
                    % all values work with datevec --> date field
                    dfd = DateField();
                    dfd.dateFormat = format;
                else
                    % better suited for DateTimeField 
                    tf = false;
                    dfd = [];
                end
            else
                dfd = [];
            end
        end
    end
end
