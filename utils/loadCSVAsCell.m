function cellMat = loadCSVAsCell(varargin)
% Loads in a CSV file as a cell array with data{iRow, iCol} containing cell
% 
% Handles quoted commas, quoted new lines, and double quotes correctly
% Works with Google Docs spreadsheet csv output with default arguments
% 
% cellMat : cell matrix (nRows x nCols) containing the value of each cell
%
% Optional arguments:
%   file: filename to load, if empty, a dialog will prompt the user
%
% Optional parameter/value pairs:
%   filterList : if prompting via dialog, the file type filter list as
%       passed to uigetfile
%   delimiter : the delimiter character [default ',']
%   quote : the quote character [default '"']
%   stripQuotes: strip quotation marks from quoted field values [ default true]
%   convertNumeric : convert numbers and comma separated number lists to
%       scalars and numbers, resepectively. Treats empty values (1,,3),
%       question marks (1,?,3), and 'NaN' as NaNs
% 
    p = inputParser;
    p.addOptional('file', '', @ischar);
    p.addParamValue('filterList', {'*.csv', 'CSV Files (*.csv)'; '*', 'All Files'}, @iscell);
    p.addParamValue('delimiter', ',', @ischar);
    p.addParamValue('quote', '"', @ischar);
    p.addParamValue('stripQuotes', true, @islogical);
    p.addParamValue('convertNumeric', true, @islogical);
    p.parse(varargin{:});
    
    fname = p.Results.file;
    filterList = p.Results.filterList;
    delimiter = p.Results.delimiter;
    quote = p.Results.quote;
    stripQuotes = p.Results.stripQuotes;
    convertNumeric = p.Results.convertNumeric;

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
    text = fileread(fname);

    % split the entire file into a cell array of cells

    % first, find double quotes and mark them as special
    doubleQuoteStart = regexp(text, sprintf('%s%s^%s', quote, quote, quote));
    maskDouble = false(size(text));
    maskDouble(doubleQuoteStart) = true;
    maskDouble(doubleQuoteStart+1) = true;

    maskSingle = text == quote & ~maskDouble;

    % find regions that are quoted by finding regions an odd number of single
    % quotes from the start
    singleQuoteCount = cumsum(maskSingle);
    maskIsQuoted = mod(singleQuoteCount, 2) == 1;

    % find non-quoted line breaks
    if any(text == char(10))
        NEWLINE = char(10);
    else
        NEWLINE = char(13);
    end
    nonQuotedLineBreakMask = (text == NEWLINE) & ~maskIsQuoted;
    nonQuotedDelimMask = (text == delimiter) & ~maskIsQuoted;

    % split into cell array of line contents
    indLineBreak = find(nonQuotedLineBreakMask);
    lineCell = splitVectorAtIndices(text, indLineBreak, 1);
    
    nonQuotedDelimMaskCell = splitVectorAtIndices(nonQuotedDelimMask, indLineBreak, 1);

    % split lines into individual elements
    cellOfCells = cellfun(@(line, mask) splitVectorAtIndices(line, find(mask), 1), ...
        lineCell, nonQuotedDelimMaskCell, 'UniformOutput', false);

    % filter blank lines
    lineMask = cellfun(@numel, lineCell) > 0;
    cellOfCells = cellOfCells(lineMask);
    nRows = numel(cellOfCells);
    
    % split into row/column cell matrix
    nColsPerLine = cellfun(@numel, cellOfCells);
    nCols = max(nColsPerLine);

    % populate the rows of the cell matrix
    cellMat = cell(nRows, nCols);
    for r = 1:nRows
        cellMat(r, 1:nColsPerLine(r)) = cellOfCells{r};
    end
    
    % strip quoted field values
    if stripQuotes
        cellMat = cellfun(@(str) stripQuotesFromString(str, quote), cellMat, 'UniformOutput', false);
    end
    
    if convertNumeric
        cellMat = cellfun(@(str) convertNumericList(str), cellMat, 'UniformOutput', false);
    end
    
end

function tokens = splitVectorAtIndices(vec, idx, delimSize)
% tokens = splitVectorAtIndices(vec, idx, delimSize=1)
% splits a vector into N pieces where length(idx) == N-1
% by taking: 
% tokens{1} = vec(1:idx(1)-1), 
% tokens{2} = vec(idx(1)+delimSize:idx(2)-1); 
% ...
% tokens{numel(idx)+1} = vec(idx(1)+delimSize:end);
%
% Effectively, the values at vec(idx) will be removed and used
% to split the vector into tokens

    if nargin < 3
        delimSize = 3;
    end
    
    if isempty(idx)
        if isempty(vec)
            tokens = {};
        else
            tokens = {vec};
        end
        return;
    end

    nDelim = numel(idx);
    tokenSizes = [idx(1)-1, diff(idx)-delimSize, numel(vec)-idx(end)-delimSize+1];
    nTokens = numel(tokenSizes);

    splitSizes = nanvec(nTokens + nDelim);
    splitSizes(1:2:end) = tokenSizes;
    splitSizes(2:2:end) = delimSize;

    tokens = mat2cell(vec, 1, splitSizes);
    tokens = tokens(1:2:end)';

end

function str = stripQuotesFromString(str, quote)
% convert '"quoted"' to 'quoted'

    str = strtrim(str);
    if length(str) >= 2 && str(1) == quote && str(end) == quote
        str = str(2:end-1);
    end
end

function result = convertNumericList(str)
% numList = convertNumericList(str)
%   Given a number or list of numbers like '2, 3, 5.1', returns a list [2
%   3 5.1]. If the list cannot be parsed as a number, returns the original
%   string. Valid separators include , and ;
%   The string may use '?', 'nan' (case-insensitive), or '' as numbers in
%   the list, which will be replaced by NaN in the output.
%   e.g. '1,,3,?,NaN, 6' --> [1 NaN 3 NaN NaN 6]

    % tokenize by commas
    regex = '(?<value>[^,^;]*),?';
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
        % need to be either blank, '?', 'nan', or a number
        if ~all( ~isnan(numList) | valuesIsEmpty | strcmp(values,'?') | strcmpi(values, 'nan'))
            numList = [];
        end
    end
    
    if isempty(numList)
        result = str;
    else
        result = numList;
    end
        
end
