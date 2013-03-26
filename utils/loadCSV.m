function [list rowsInvalid] = loadCSV(fname, varargin)
% loads in a generic grid databse (like a CSV file) and optionally does basic validation

% valid is a struct where each field's name is a field name in the file's column list
% and the value is a cell array of acceptable strings for this field to take
par.includeLineNum = false;
par.valid = []; 
par.filterList = {'*.csv', 'CSV File'};
par.delimiter = ',';
par.skipHeaderLines = 0;
par.colList = []; % specify this to use this list and process the first line as data
par.inclusionField = 'include';
par.includeLineNumber = false; % include .lineNum field containing line of csv file each entry came from?
assignargs(par, varargin);

% interactively request for the file if not passed
if(~exist('fname','var') || isempty(fname))
   [file path] = uigetfile(filterList, ...
        'Choose the Database File to Load');
    if isequal(file,0) || isequal(path,0)
        fprintf('Warning: No CSV file chosen. Aborting.');
        list = [];
        allValid = 0;
        return;
    end

    fname = strcat(path,file);
end

fprintf('Loading database from %s...\n', fname);
fid = fopen(fname,'r');

% skip the first lines if requested
for skip = 1:skipHeaderLines
    fgetl(fid);
end

% if not specified already, get list of column names / fields from first line
if(isempty(colList))
    header = fgetl(fid);
    headerList = splitCsvLine(header);
    
    emptyMask = cellfun(@isempty, headerList);
    headerList = headerList(~emptyMask);
    colList = safeFieldName(headerList);
end

list = [];
rowsInvalid = 0;

% loop through each line and place each value into the field for that column
invalidFieldList = {};
lineNum = skipHeaderLines+1;
listIndex = 0;
while true
    lineNum = lineNum + 1;
    listIndex = listIndex+1;
    origln = fgetl(fid);
    ln = origln;
    if ~ischar(ln), break, end

    if isempty(ln)
        continue;
    end
    
    if includeLineNumber
        list(listIndex).lineNum = lineNum;
    end
    if(~isempty(valid))
        list(listIndex).isValid = 1;
    end
    
    % split the line by commas
    fldValues = splitCsvLine(ln);

    for iFld = 1:length(colList)
        val = fldValues{iFld};
        
        % convert to number if possible
        numList = convertNumericList(val);
        if(~isempty(numList))
            val = numList;
        else
            val = strtrim(val);
        end

        fldName = colList{iFld};
        list(listIndex).(fldName) = val;
    end

    % check the inlcusion field to see if this should get included
    if(isfield(list(listIndex), inclusionField) && ~strcmp('1', num2str(list(listIndex).(inclusionField))))
        listIndex = listIndex - 1;
        continue;
    end
       
    % perform data validation?
    if(~isempty(valid))
        validateFields = fieldnames(valid);
        for v = 1:length(validateFields)
            fldName = validateFields{v};
            validValues = valid.(fldName);
            
            fldValue = num2str(list(listIndex).(fldName));
            if(iscell(validValues))
                % see if the field value is one of the prescribed list of valid values
                isValid = ismember(fldValue, validValues);
            elseif(isstruct(validValues) && isfield(validValues, 'dateFormat'))
                % test to see if the field value is acceptable given the dateFormat
                try
                    datenum(fldValue, validValues.dateFormat);
                    isValid = 1;
                catch
                    isValid = 0;
                end
            else
                error('Unrecognized validation rule on field %s', fldName);
            end
            
            % check the validity of this field's value against valid struct
            if(~isValid)
                % invalid value: display warning
                fprintf('Warning: Line %4d: Invalid "%s" value "%s"\n', ...
                    lineNum, fldName, num2str(fldValue));
                
                % add to list of invalid fields
                if(~ismember(fldName, invalidFieldList))
                    invalidFieldList{end+1} = fldName;
                end
                
                % mark row as invalid
                list(listIndex).isValid = 0;
                
                % increment the invalid rows counter
                rowsInvalid = rowsInvalid + 1;
            end
        end
    
        if(~isempty(invalidFieldList))
            fprintf('\n%d invalid rows. Expected values for invalid fields:\n', rowsInvalid);
            invalidFieldList = sort(invalidFieldList);
            for i = 1:length(invalidFieldList)
                validValues = valid.(invalidFieldList{i});
                fprintf('%s:\n', invalidFieldList{i})
                if(isstruct(validValues) && isfield(validValues, 'dateFormat'))
                    fprintf('\tDate matching format %s\n', validValues.dateFormat);
                elseif(iscell(validValues))
                    cellfun(@(str) fprintf('\t%s\n', str), validValues);
                end
                fprintf('\n');
            end
        end
    end
end

fclose(fid);

end

function vals = splitCsvLine(str)
% this regex splits a line from a csv file assuming the following characteristics:
%   fields are separated by commas
%   if a field contains a , character or a " character, it will be surrounded in "around the value"
%   and " characters will be converted to ""
%  
%  e.g. val1,val2,"has a , character","has a ""quoted value"""

    csvSplitRegex = '(?<value>([^",]*)|("(""|[^"])+"))(,|$)';

    parsed = regexp(str, csvSplitRegex, 'names');

    fieldStrings = makecol({parsed.value});

    % remove outer quotes
    vals = regexprep(fieldStrings, '^"(.*)"$', '$1');

    % unescape "" as "
    vals = strrep(vals, '""', '"');

    % if last character is ',' then add a blank field
    if str(end) == ','
        vals{end+1} = '';
    end
end

function numList = convertNumericList(str)
    % numList = convertNumericList(str)
    %   Given a number or list of numbers like '2,3,5.1', returns a list
    %   [2 3 5.1]. If the list cannot be parsed as a number, returns []

    % tokenize by commas
    regex = '(?<value>[^,]*),?';
    parsed = regexp(str, regex, 'names');
    
    % if last character is ',' then add a blank field
    if ~isempty(str) && str(end) == ','
        parsed(end+1).value = '';
    end
    
    values = strtrim({parsed.value});
    valuesIsEmpty = cellfun(@isempty, values);
        
    if isempty(parsed)
        numList = [];
    else
        numList = makerow(cellfun(@str2double, {parsed.value}));
        % for us to accept this as a list of numbers, all of the values
        % need to be either blank, '?', or a number
        if ~all( ~isnan(numList) | valuesIsEmpty | strcmp(values,'?'))
            numList = [];
        end
    end
end

