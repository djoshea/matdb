function writeStructArrayToCSV(fname, S)

fid = fopen(fname, 'w');

if fid == -1
    error('Could not open %s for writing', fname);
end

fields = fieldnames(S);
nFields = length(fields);
nEntries = length(S);

% write fieldnames
for iF = 1:nFields
    fprintf(fid, '%s', escapeValue(fields{iF}));
    fprintf(fid, ',');
end
fprintf(fid, '\n');

for iE = 1:nEntries
    for iF = 1:nFields
        val = S(iE).(fields{iF});
        fprintf(fid, '%s', escapeValue(val, iE, fields{iF}));
        if iF < nFields
            fprintf(fid, ',');
        end
    end
    fprintf(fid,'\n');
end

fclose(fid);

end

function str = escapeValue(val, iEntry, field)

    if isempty(val)
        str = '';
        return;
    end

    if ~isvector(val)
        error('Matrix arguments not supported: entry %d field %s', iEntry, field);
    end

    if isnumeric(val) || islogical(val)
        if isscalar(val)
            % just convert to string, no quotes necessary
            str = num2str(val);
            wrapInQuotes = false;

        elseif isvector(val)
            % write with separating commas
            str = sprintf('%g, ', val);
            str = str(1:end-2);
            wrapInQuotes = true;

        end
    
    elseif ischar(val)
        str = makerow(val);
        wrapInQuotes = true;
    end

    if wrapInQuotes
        % replace single " with double ""
        str = strrep(str, '"', '""');

        % wrap in quotes
        str = ['"' makerow(str) '"'];
    end
        
end
