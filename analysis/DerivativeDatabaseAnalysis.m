classdef DerivativeDatabaseAnalysis < DatabaseAnalysis
% DatabaseAnalysis which depends or builds upon or summarizes other
% DatabaseAnalyses which must be loaded into the Database first by the user
% so as to choose the appropriate parameters
    
    methods(Abstract)
        % return a cell string of DatabaseAnalyses which we depend on
        names = getDependentAnalysisClassNames(da);
        
        param = getCacheParamAdditional(da);
        
        str = getDescriptionParamAdditional(da);
    end
    
    methods
        function [daCell names] = getDependentAnalysesFromDatabase(da)
            names = da.getDependentAnalysisClassNames();
            for iA = 1:numel(names)
                daCell{iA} = da.getDependentAnalysisFromDatabase(names{iA});
            end
        end
        
        function daDepend = getDependentAnalysisFromDatabase(da, className)
            if isempty(da.database)
                error('Please call .setDatabase(db) first');
            end
            
            srcList = da.database.findSourcesByClassName(className);
            if isempty(srcList)
                error('Please load analysis %s in Database first', className);
            end

            % TODO match something else to narrow it down?
            daDepend = srcList{1};
        end
        
        function param = getCacheParam(da)
            [daCell, names] = getDependentAnalysesFromDatabase(da);
            
            thisClass = class(da);
            param.(thisClass) = da.getCacheParamAdditional();
            
            for iA = 1:numel(daCell)
                param.(names{iA}) = daCell{iA}.getCacheParam();
            end
        end
        
        function str = getDescriptionParam(da)
            [daCell, names] = getDependentAnalysesFromDatabase(da);
            
            strCell = cellfun(@(name, a) sprintf('%s : %s', name, a.getDescriptionParam()), ...
                names, daCell, 'UniformOutput', false);
            strThis = da.getDescriptionParamAdditional();
            
            str = sprintf('%s; {%s}', strThis, strjoin(strCell, ', '));
        end
    end

end