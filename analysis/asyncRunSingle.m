function [success, exc] = asyncRunSingle(constData, iResult, opts)
    close all;
    
%     p = gcp
%     
%     q = p.FevalQueue
%     q.RunningFutures(1).Diary
    
%     
%     task = getCurrentTask()
%     
%     root = distcomp.getdistcompobjectroot
%     class(root)
%     get(root)
%     getundoc(root)
%     job = root.CurrentJob
%     getundoc(job)
%     
%     w = getCurrentWorker
%     getundoc(w)

%     return;
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
     
    resultStruct.success = success;
    resultStruct.runTimestamp = da.timeRun;
    resultStruct.exception = exc;
    resultStruct.figureInfo = figureInfo;
    resultStruct.output = output;
    [~] = da.resultTable.updateEntry(iResult, resultStruct, 'saveCache', true, 'storeInTable', false, 'verbose', opts.verbose);

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
