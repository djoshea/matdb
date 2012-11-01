classdef DatabaseAnalysisResultsTable < LoadOnDemandMappedTable

    properties
        databaseAnalysisClass 
        mapsEntryName
        fieldsAnalysis
        fieldsAnalysisDescriptorMap
        fieldsAdditional
        fieldsAdditionalDescriptorMap
        cacheParam; % copy of DatabaseAnalysis's cache param for Cacheable
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
            
            [dt.fieldsAnalysis dt.fieldsAnalysisDescriptorMap] = da.getFieldsAnalysis();
            [dt.fieldsAdditional dt.fieldsAdditionalDescriptorMap] = da.getFieldsAdditional();
            dt.mapsEntryName = da.getMapsEntryName();
            dt.cacheParam = da.getCacheParam();
            dt.entryName = da.getMapsEntryName();
            dt.entryNamePlural = da.getMapsEntryName();
            dt = initialize@LoadOnDemandMappedTable(dt, 'database', da.database);
        end
    end

    methods
        function entryName = getMapsEntryName(dt)
            entryName = dt.mapsEntryName;
        end

        function [fields fieldDescriptorMap] = getFieldsLoadOnDemand(dt)
            fieldDescriptorMap = dt.fieldsAnalysisDescriptorMap;
            fields = fieldDescriptorMap.keys;
        end

        function [fields fieldDescriptorMap] = getFieldsAdditional(dt)
            fieldDescriptorMap = dt.fieldsAdditionalDescriptorMap;
            fields = fieldDescriptorMap.keys;
        end

        function fields = getFieldsCacheable(dt)
            fields = dt.fieldsAnalysis;
        end

        % here's where you specify where the values for the loaded fields come
        % from. When passed a list of fields, guaranteed to be valid, you generate
        % or load the values of those fields for a specific entry in the mapped table
        % and return a struct containing those field values.
        function valueStruct = loadValuesForEntry(dt, entry, fields)
            error('Request for value of field %s unsupported, should have been loaded already or found in cache');
        end

        % augment the set field value method with one that automatically caches
        % the new value to disk
        function dt = setFieldValue(dt, idx, field, value, varargin)
            p = inputParser;
            p.addParamValue('saveCache', true, @islogical);
            p.addParamValue('markLoaded', true, @islogical);
            p.parse(varargin{:});
            saveCache = p.Results.saveCache;
            markLoaded = p.Results.markLoaded;

            dt.warnIfNoArgOut(nargout);
            dt = setFieldValue@LoadOnDemandMappedTable(dt, idx, field, value);

            if markLoaded && ismember(field, dt.fieldsLoadOnDemand)
                dt.loadedByEntry(idx).(field) = true;
            end

            if saveCache && ismember(field, dt.fieldsCacheable)  
                dt.cacheFieldValue(idx, field);
            end
        end
    end

    methods % Cacheable overrides
        % return the param to be used when caching
        function param = getCacheParam(dt) 
            param = dt.cacheParam;
        end
    end
end
