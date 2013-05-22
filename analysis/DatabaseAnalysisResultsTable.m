classdef DatabaseAnalysisResultsTable < LoadOnDemandMappedTable

    properties
        analysisParam
        analysisParamDesc
        
        databaseAnalysisClass 
        analysisName 
        mapsEntryName
        fieldsAnalysis
        fieldsAnalysisDescriptorMap
        fieldsAdditional
        fieldsAdditionalDescriptorMap
        cacheParam; % copy of DatabaseAnalysis's cache param for Cacheable

        analysisCacheFieldsIndividually
    end

    methods
        function dt = DatabaseAnalysisResultsTable(varargin)
            dt = dt@LoadOnDemandMappedTable();

            if ~isempty(varargin)
                dt = dt.initialize(varargin{:});
            end
        end

        function dt = initialize(dt, da, varargin)
            % the main usage of initialize (and therefore the constructor)
            % is to convert from an existing DataTable into this class
            p = inputParser;
            p.KeepUnmatched = true;
            p.addRequired('da', @(da) isa(da, 'DatabaseAnalysis'));

            p.parse(da, varargin{:});
            
            assert(~isempty(da.database), 'Associate the DatabaseAnalysis with a Database first using .setDatabase(db)');
            
            % store parameter info and description info
            dt.analysisParam = da.getCacheParam();
            dt.analysisParamDesc = da.getDescriptionParam();
            
            [dt.fieldsAnalysis dt.fieldsAnalysisDescriptorMap] = da.getFieldsAnalysis();
            [dt.fieldsAdditional dt.fieldsAdditionalDescriptorMap] = da.getFieldsAdditional();
            dt.mapsEntryName = da.getMapsEntryName();
            dt.cacheParam = da.getCacheParam();
            dt.analysisName = da.getName();
            dt.entryName = da.getName();
            dt.entryNamePlural = dt.entryName;
            dt.analysisCacheFieldsIndividually = da.getCacheFieldsIndividually();
            
            dt = initialize@LoadOnDemandMappedTable(dt, 'database', da.database);
        end
    end

    methods
        function [entryName entryNamePlural] = getEntryName(dt)
            entryName = dt.analysisName;
            entryNamePlural = entryName;
        end

        function entryName = getMapsEntryName(dt)
            entryName = dt.mapsEntryName;
        end

        % load on demand fields = {additional fields, analysis fields}
        function [fields fieldDescriptorMap] = getFieldsLoadOnDemand(dt)
            fieldDescriptorMap = dt.fieldsAdditionalDescriptorMap.add(dt.fieldsAnalysisDescriptorMap);
            fields = fieldDescriptorMap.keys;
        end

        function [fields fieldDescriptorMap] = getFieldsAdditional(dt)
            fieldDescriptorMap = dt.fieldsAdditionalDescriptorMap;
            fields = fieldDescriptorMap.keys;
        end

        function [fields fieldDescriptorMap] = getFieldsNotLoadOnDemand(dt)
            fieldDescriptorMap = ValueMap(); 
            fields = {};
        end

        function fields = getFieldsRequestable(dt)
            % enforce that we never generate field values here, we only load from cache
            fields = {};
        end

        function fields = getFieldsCacheable(dt)
            fields = dt.getFieldsLoadOnDemand();
        end

        % here's where you specify where the values for the loaded fields come
        % from. When passed a list of fields, guaranteed to be valid, you generate
        % or load the values of those fields for a specific entry in the mapped table
        % and return a struct containing those field values.
        function valueStruct = loadValuesForEntry(dt, entry, fields)
            error('Request for value of field %s unsupported, should have been loaded already or found in cache');
        end

        % if true, cacheable fields are written to the cache individually
        % if false, all cacheable fields are written to the cache collectively by entry
        function tf = getCacheFieldsIndividually(dt)
            tf = dt.analysisCacheFieldsIndividually;
        end
    end

    methods % Cacheable overrides
        % return the param to be used when caching
        function param = getCacheParam(dt) 
            param = dt.cacheParam;
        end
    end
end
