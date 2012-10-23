function safeCell = safeFieldName( strCell, varargin )

remove = {'(', ')', '?'}; 

replace = {...
    '=', 'eq'; ...
    '%', 'percent'; ...
};

replaceUnderscores = {' ', '.', ',', '\', '/', '-', '[', ']'};
lowercaseFirst = true; % convert first letter of field name to lowercase
useUnderscores = false; % convert some special characters to underscores instead of deleting them
numericFieldPrefix = 'n';
assignargs(varargin);

if ~iscell(strCell)
    strCell = {strCell};
    returnAsChar = true;
else
    returnAsChar = false;
end

safeCell = cell(size(strCell));
for iStr = 1:length(strCell)
    str = strCell{iStr};
    safe = strtrim(str);

    if useUnderscores
        for i = 1:length(replaceUnderscores)
            replace(end+1, :) = {replaceUnderscores{i}, '_'};
        end
    else
        remove = [remove replaceUnderscores];
    end

    for i = 1:length(remove)
        safe = strrep(safe, remove{i}, '');
    end

    for i = 1:size(replace,1)
        safe = strrep(safe, replace{i,1}, replace{i,2});
    end

    if lowercaseFirst
        safe(1) = lower(safe(1));
    end

    % prefix with numericFieldPrefix if it starts with a number
    if(safe(1) ~= 'j' && safe(1) ~= 'i' && ~isnan(str2double(safe(1))))
        safe = strcat(numericFieldPrefix, safe);
    end

    safeCell{iStr} = safe;
end

if returnAsChar && length(safeCell) == 1
    safeCell = safeCell{1};
end

end

