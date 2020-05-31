classdef DatabaseAnalysisResultsTable < LoadOnDemandMappedTable

    properties
        analysisParam
        analysisParamDesc
        
        analysis % handle to the database analysis instance that created me
        
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
            p.addParameter('table', [], @(x) isempty(x) || isa(x, 'DataTable')); % can specify the table we map directly, if empty will be pulled from the database
            p.addParameter('maxRows', Inf, @isscalar);

            p.parse(da, varargin{:});
            
            assert(~isempty(da.database), 'Associate the DatabaseAnalysis with a Database first using .setDatabase(db)');
            
            % store parameter info and description info
            dt.analysis = da;
            dt.analysisParam = da.getCacheParam();
            dt.analysisParamDesc = da.getDescriptionParam();

            [dt.fieldsAnalysis, dt.fieldsAnalysisDescriptorMap] = da.getFieldsAnalysisAsValueMap();            
            [dt.fieldsAdditional, dt.fieldsAdditionalDescriptorMap] = da.getFieldsAdditional();

            dt.mapsEntryName = da.getMapsEntryName();
            dt.cacheParam = da.getCacheParam();
            dt.analysisName = da.getName();
            dt.entryName = da.getName();
            dt.entryNamePlural = dt.entryName;
            dt.analysisCacheFieldsIndividually = da.getCacheFieldsIndividually();
            
            dt = initialize@LoadOnDemandMappedTable(dt, 'table', p.Results.table, 'database', da.database, 'maxRows', p.Results.maxRows);
        end
    end

    methods
        function [entryName, entryNamePlural] = getEntryName(dt)
            entryName = dt.analysisName;
            entryNamePlural = entryName;
        end

        function entryName = getMapsEntryName(dt)
            entryName = dt.mapsEntryName;
        end

        % load on demand fields = {additional fields, analysis fields}
        function [fields, fieldDescriptorMap] = getFieldsLoadOnDemand(dt)
            fieldDescriptorMap = dt.fieldsAdditionalDescriptorMap.add(dt.fieldsAnalysisDescriptorMap);
            fields = fieldDescriptorMap.keys;
        end

        function [fields, fieldDescriptorMap] = getFieldsAdditional(dt)
            fieldDescriptorMap = dt.fieldsAdditionalDescriptorMap;
            fields = fieldDescriptorMap.keys;
        end

        function [fields, fieldDescriptorMap] = getFieldsNotLoadOnDemand(dt) %#ok<*MANU>
            fieldDescriptorMap = ValueMap(); 
            fields = {};
        end

        function fields = getFieldsRequestable(dt)
            % here we allow direct request of custom save load
            fields = dt.analysis.getFieldsCustomSaveLoad();
        end

        function fields = getFieldsCacheable(dt)
            fields = dt.getFieldsLoadOnDemand();
        end
        
        function hash = generateHashForEntry(dt, iEntry, cacheName, param)
            % call to DatabaseAnalysis to give it a chance to modify the hash value or regenerate it
            if isa(dt.analysis, 'CleanHashAnalysis')
                % skip computing hash for this since it won't use it, saves time
                hash = '';
            else
                hash = generateHashForEntry@LoadOnDemandMappedTable(dt, iEntry, cacheName, param);
            end
            
            entry = dt.select(iEntry);
            assert(entry.nEntries == 1);
            hash = dt.analysis.generateHashForEntry(entry, hash, cacheName, param);
        end
        
        function prefix = getCacheFilePrefix(dt)
            % call to DatabaseAnalysis to give it a chance to modify the hash value or regenerate it
            prefix = dt.analysis.getCacheFilePrefix();
        end
        
        function lookup = getCustomCacheSuffixForFieldLookup(dt)
            % when CacheCustomSaveLoad is used for a specific results field, this struct specifies the 
            % fieldName --> suffix used instead of the default .custom_fieldName
            lookup = dt.analysis.getCustomCacheSuffixForFieldLookup();
        end

        % here's where you specify where the values for the loaded fields come
        % from. When passed a list of fields, guaranteed to be valid, you generate
        % or load the values of those fields for a specific entry in the mapped table
        % and return a struct containing those field values.
        function valueStruct = loadValuesForEntry(dt, entry, fields)
            % not quite fully implemented yet, need saveValuesForEntry too
            inCustom = ismember(fields, dt.da.getFieldsCustomSaveLoad());
            assert(all(inCustom), 'Fields to load for entry must be listed within custom save load');
            
            valueStruct = dt.analysis.loadValuesCustomForEntry(entry, fields);
        end

        % if true, cacheable fields are written to the cache individually
        % if false, all cacheable fields are written to the cache collectively by entry
        function tf = getCacheFieldsIndividually(dt)
            tf = dt.analysisCacheFieldsIndividually;
        end
        
        function pathCell = getPathToFigures(dt, nameOrMask, varargin)
            p = inputParser();
            p.addParameter('ext', 'fig', @ischar);
            p.parse(varargin{:});
            
            assert(dt.nEntries == 1, 'openFigure only valid for single entries');
            [~, values] = dt.loadFields('fields', {'figureInfo'}, 'storeInTable', false);
            info = values.figureInfo;
            
            if isempty(nameOrMask)
                nameOrMask = truevec(numel(info));
            elseif ischar(nameOrMask)
                nameOrMask = {nameOrMask};
            end
            
            if iscellstr(nameOrMask)
                idx = nanvec(numel(nameOrMask));
                for iReq = 1:numel(nameOrMask)
                    [tf, idx(iReq)] = ismember(nameOrMask{iReq}, {info.name});
                    assert(tf, 'Figure %s not found in figureInfo', nameOrMask{iReq});
                end
            else
                idx = TensorUtils.vectorMaskToIndices(nameOrMask);
            end
            
            % do the opening
            analysisName = dt.analysis.getName(); %#ok<*PROPLC>
            analysisRoot = getFirstExisting(MatdbSettingsStore.settings.pathListAnalysis);
            info = info(idx);
            pathCell = cellvec(numel(info));
            ext = p.Results.ext;
            for iReq = 1:numel(info)
                [tf, idxExt] = ismember(ext, info(iReq).extensions);
                assert(tf, 'Extension %s not found for figure name %s', p.Results.ext, info(iReq).name);
                file = info(iReq).fileList{idxExt};
                
                % reconstruct path relative to the current root
                k = strfind(file, analysisName); 
                file = fullfile(analysisRoot, file(k:end));
                pathCell{iReq} = file;
            end
        end
        
        % figure opening
        function openAllFigures(dt, varargin)
            dt.openFigure('', varargin{:});
        end
        
        % figure opening
        function openFigure(dt, nameOrMask, varargin)
            p = inputParser();
            p.addParameter('ext', 'fig', @ischar);
            p.parse(varargin{:});
            
            if nargin < 2
                nameOrMask = [];
            end
               
            pathCell = dt.getPathToFigures(nameOrMask, 'ext', p.Results.ext);
            
            ext = p.Results.ext;
            for iReq = 1:numel(pathCell)
                file = pathCell{iReq};
                debug('Opening %s\n', file);
                if strcmp(ext, 'fig')
                    open(file);
                else
                    system(sprintf('open %s', escapePathForShell(file)));
                end
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
