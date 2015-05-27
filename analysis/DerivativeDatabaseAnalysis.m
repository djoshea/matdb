classdef DerivativeDatabaseAnalysis < DatabaseAnalysis
% DatabaseAnalysis which depends or builds upon or summarizes other
% DatabaseAnalyses which must be loaded into the Database first by the user
% so as to choose the appropriate parameters
    
    methods(Abstract)
        % return a cell string of DatabaseAnalyses which we depend on
        names = getDependentAnalysisClassNames(da);
    end
    
    methods
        function loadDefaultDependentAnalyses(da)
            if isempty(da.database)
                error('Call .setDatabase first');
            end
            
            names = da.getDependentAnalysisClassNames();
            for iA = 1:numel(names)
                daDep = da.getDependentAnalysisFromDatabase(names{iA}, false);
                if ~isempty(daDep)
                    continue;
                end
                debug('Loading default dependent analysis %s\n', names{iA});
                daDep = eval(sprintf('%s()', names{iA}));
                da.database.loadSource(daDep);
            end
        end
        
        % use this method to throw errors if the loaded analyses aren't
        % okay
        function checkLoadedDependentAnalyses(da, daCell)
            
        end
        
        function param = getCacheParamAdditional(da)
            param = struct();
        end
        
        function str = getDescriptionParamAdditional(da)
            str = structToString(da.getCacheParamAdditional());
        end
        
        function [daCell, names] = getDependentAnalysesFromDatabase(da, throwError)
            if nargin < 2
                throwError = true;
            end
            if isempty(da.database)
                daCell = {};
                names = {};
                return;
            end
            names = makecol(da.getDependentAnalysisClassNames());
            daCell = cellvec(numel(names));
            for iA = 1:numel(names)
                daCell{iA} = da.getDependentAnalysisFromDatabase(names{iA}, throwError);
                if isempty(daCell{iA})
                    daCell = {};
                    names = {};
                    return;
                end
            end
            
            daCell = daCell(~cellfun(@isempty, daCell));
            daCell = makecol(daCell);
        end
        
        function daDepend = getDependentAnalysisFromDatabase(da, className, throwError)
            if nargin < 3
                throwError = true;
            end
            
            if isempty(da.database)
                daDepend = [];
                return;
            end
            
            srcList = da.database.findSourcesByClassName(className);
            if isempty(srcList)
                if throwError
                    error('Please load analysis %s in Database first', className);
                else
                    daDepend = [];
                    return;
                end
            end

            % TODO match something else to narrow it down?
            daDepend = srcList{1};
        end
        
        function param = getCacheParam(da)
            [daCell, names] = getDependentAnalysesFromDatabase(da);
            
            thisClass = matlab.lang.makeValidName(class(da));
            param.(thisClass) = da.getCacheParamAdditional();
            
            for iA = 1:numel(daCell)
                name = matlab.lang.makeValidName(names{iA});
                param.(name) = daCell{iA}.getCacheParam();
            end
        end
        
        function str = getDescriptionParam(da)
            str = da.getDescriptionParamAdditional();
            if isempty(da.database)
                return;
            end
            [daCell, names] = da.getDependentAnalysesFromDatabase(false);
            
            if isempty(daCell)
                return;
            end
            strCell = cellfun(@(name, a) sprintf('%s : %s', name, a.getDescriptionParam()), ...
                names, daCell, 'UniformOutput', false);
            strThis = da.getDescriptionParamAdditional();
            
            str = sprintf('%s; %s', strThis, strjoin(strCell, ', '));
        end
        
        % by default, maps the results of the first dependent analysis
        function entryName = getMapsEntryName(da)
            if isempty(da.database)
                entryName = '?';
                return
            end
            daCell = da.getDependentAnalysesFromDatabase(false);
            if isempty(daCell)
                entryName = '?';
            else
                entryName = daCell{1}.getName();
            end
        end
        
        % first loads default dependent analyses where missing, then
        % calls checkLoadedDependentAnalyses to allow the analysis to throw
        % an error if something isn't right
       function readyDatabase(da)
           da.loadDefaultDependentAnalyses();
           readyDatabase@DatabaseAnalysis(da);
           da.checkLoadedDependentAnalyses(da.getDependentAnalysesFromDatabase());
       end
    end

end