function [success, exc, resultStruct, figureInfo] = asyncRunSingle(constData, iResult, opts)
    close all;

    % DatabaseAnalysis has Transient properties that won't
    % appear on the workers, so we reinstall them here
    data_ = constData.Value;
    da_ = data_.da;
    da_.setDatabase(data_.database);
    da_.setTableMapped(data_.tableMapped.setDatabase(da_.database));

    [valid_, entry_] = fetchEntry(da_.tableMapped, iResult);
    if ~valid_
        error('Could not find entry');
    end

    % don't want this here, will end up in the diary
%                 printSingleEntryHeader(entry_, iAnalyze, iResult)

    % for saveFigure to look at
    da_.setCurrentEntry(entry_);
    set(0, 'DefaultFigureWindowStyle', 'normal'); % need this in case figures are docked by default - has issues in parpool

    % clear debug's last caller info to get a fresh
    % debug header
    debug();

    try
        resultStruct = da_.runOnEntry(entry_, opts.fieldsAnalysis);
        success = true;
        exc = [];
    catch exc
        resultStruct = struct();
        success = false;
    end

    if isempty(resultStruct)
        resultStruct = struct();
    end
    if ~isstruct(resultStruct)
        exc = MException('matdb:DatabaseAnalysis:ReturnNonStruct', 'runOnEntry did not return a struct');
        success = false;
    end

    figureInfo = da_.figureInfoCurrentEntry;

    close all;
end

function [valid, entry] = fetchEntry(table, iResult)
    entry = table.select(iResult);

    if entry.nEntries > 1
        debug('WARNING: Multiple matches for analysis row, check uniqueness of keyField tuples in table %s. Choosing first.\n', entryName);
        entry = entry.select(1);
        valid = true;
    elseif entry.nEntries == 0
        % this likely indicates a bug in building / loading resultTable from cache
        debug('WARNING: Could not find match for resultTable row in order to do analysis');
        valid = false;
    else
        valid = true;
    end

end