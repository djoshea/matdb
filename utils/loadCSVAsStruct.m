function S = loadCSVAsStruct(varargin)
% S = loadCSVAsStruct(varargin)
% Same arguments as loadCSVAsCell

C = loadCSVAsCell(varargin{:});

nRows = size(C, 1);
nCols = size(C, 2);

% get list of column names / fields from first line
headerList = C(1, :);
emptyMask = cellfun(@isempty, headerList);
if any(emptyMask)
    error('Empty column name in row 1, columns %s', num2str(find(emptyMask)));
end

% convert to safe field names for struct
colList = safeFieldName(headerList);

% store elements of cell into struct at each point
for c = 1:nCols
    [S(1:nRows-1).(colList{c})] = deal(C{2:end, c}); 
end

end
