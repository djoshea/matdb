function [success, exc] = asyncRunSingle(constData, iResult, opts)
    close all;

    % DatabaseAnalysis has Transient properties that won't
    % appear on the workers, so we reinstall them here
    data_ = constData.Value;
    da = data_.da;
    da.setDatabase(data_.database);
    da.setTableMapped(data_.tableMapped.setDatabase(da.database));

    [valid_, entry] = fetchEntry(da.tableMapped, iResult);
    if ~valid_
        error('Could not find entry');
    end

    % don't want this here, will end up in the diary
%                 printSingleEntryHeader(entry, iAnalyze, iResult)

    % for saveFigure to look at
    entry = entry.setDatabase(data_.database);
    da.setCurrentEntry(entry);
    
    set(0, 'DefaultFigureWindowStyle', 'normal'); % need this in case figures are docked by default - has issues in parpool

    % clear debug's last caller info to get a fresh
    % debug header
    debug();

    try
        %resultStruct = da.runOnEntry(entry, opts.fieldsAnalysis);
        [output, resultStruct] = evalc('da.runOnEntry(entry, opts.fieldsAnalysis)');
        success = true;
        exc = [];
        fprintf('%s', output);
    catch exc
        output = exc.getReport();
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
    
    if success
        missingFields = setdiff(opts.fieldsAnalysis, fieldnames(resultStruct));
        if ~isempty(missingFields)
            str = sprintf('WARNING: analysis on this entry did not return fields: %s\n', ...
                strjoin(missingFields, ', '));
            debug('%s', str);
            output = [output '\n', str];
            
            for iM = 1:numel(missingFields)
                fld = missingFields{iM};
                resultStruct.(fld) = opts.failureEntry.(fld);
            end
        end
        % warn if the analysis returned extraneous fields as a reminder to add them
        % to .getFieldsAnalysis. Fields in dt.fieldsAnalysis but not fieldsAnalysis are okay
        extraFields = setdiff(fieldnames(resultStruct), opts.fieldsAnalysis);
        if ~isempty(extraFields)
            str = sprintf('WARNING: analysis on this entry returned extra fields not listed in .getFieldsAnalysis(): %s\n', ...
                strjoin(extraFields, ', '));
            debug('%s', str);
            output = [output '\n', str];
        end
        
        tcprintf('bright green', 'Analysis ran successfully on this entry\n');

        resultStruct = rmfield(resultStruct, extraFields);        
    else
        tcprintf('red', 'EXCEPTION: %s\n', exc.getReport);
        % no need to add to output already done above
        
        % Blank all fields (even if only some were
        % requested), and set them in the table
        % This is to avoid conclusion or contamination
        % with old results
        resultStruct = opts.failureEntry;
    end
    
    figureInfo = da.figureInfoCurrentEntry;
    close all;
    
    if opts.cacheFieldsIndividually
        flds = fieldnames(resultStruct);
        for iF = 1:length(flds)
            fld = flds{iF};
            % don't keep any values in the table, this way we don't run out of memory as the
            % analysis drags on
            % Displayable field values needed for report generation will be reloaded
            % later on in this function
            resultTable = resultTable.setFieldValue(iResult, fld, resultStruct.(fld), ...
                'saveCache', tre, 'storeInTable', false, 'verbose', opts.verbose);
        end
        
        resultTable = resultTable.setFieldValue(iResult, 'success', success, 'saveCache', true, 'storeInTable', false, 'verbose', opts.verbose);
        resultTable = resultTable.setFieldValue(iResult, 'output', output, 'saveCache', true, 'storeInTable', false, 'verbose', opts.verbose);
        resultTable = resultTable.setFieldValue(iResult, 'runTimestamp', da.timeRun, 'saveCache', true, 'storeInTable', false, 'verbose', opts.verbose);
        resultTable = resultTable.setFieldValue(iResult, 'exception', exc, 'saveCache', true, 'storeInTable', false, 'verbose', opts.verbose);
        resultTable = resultTable.setFieldValue(iResult, 'figureInfo', figureInfo, 'saveCache', true, 'storeInTable', false, 'verbose', opts.verbose); %#ok<NASGU>
    else
        resultStruct.success = success;
        resultStruct.runTimestamp = da.timeRun;
        resultStruct.exception = exc;
        resultStruct.figureInfo = figureInfo;
        resultStruct.output = output;
        [~] = da.resultTable.updateEntry(iResult, resultStruct, 'saveCache', true, 'storeInTable', false, 'verbose', opts.verbose);
    end
   
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
