classdef MatdbSettingsStore < handle
% reads/writes through to environment variables

    properties
        % name of the default cache manager class to use
        defaultCacheManagerName

        % root location of the Matlab cache file
        pathListCache

        % root location for saving figures, analysis html reports, etc.
        pathListAnalysis

        % unix filesystem permissions to set for files created by analysis
        permissionsAnalysisFiles

        % root location for saving csv files
        pathListCSVData
    end
    
    methods(Static)
        function settings = settings(varargin)
            settings = MatdbSettingsStore();
        end

        function instance = loadSettings()
            instance = MatdbSettingsStore();
        end

         function cm = getDefaultCacheManager()
            name = MatdbSettingsStore.getDefaultCacheManagerName();
            assert(~isempty(name), 'Set value of MatdbSettingsdefaultCacheManagerName');
            cm = eval(sprintf('%s()', name));
            cm.preferCleanHash = true;
        end

        function name = getDefaultCacheManagerName()
            name = MatdbSettingsStore.settings.defaultCacheManagerName;
        end

        function pathList = getPathListCache()
            pathList = MatdbSettingsStore.settings.pathListCache;
        end

        function pathList = getPathListAnalysis()
            pathList = GetFullPath(MatdbSettingsStore.settings.pathListAnalysis);
        end

        function pathList = getPathListCSVData()
            pathList = GetFullPath(MatdbSettingsStore.settings.pathListCSVData);
        end
        
        function pathCell = getenvPathList(key)
            t = getenv(key);
            if isempty(t)
                pathCell = {};
                return;
            end
            
            tparts = strsplit(t, ':');
            pathCell = cellfun(@GetFullPath, tparts, 'UniformOutput', false);   
        end
        
        function setenvPathList(key, pathCell)
            value = strjoin(pathCell, ':');
            setenv(key, value);
        end
    end
       
    methods
        function t = get.defaultCacheManagerName(v)
            t = getenv('MATDB_defaultCacheManagerName');
            if isempty(t)
                t = 'CacheManager';
            end
        end

        function set.defaultCacheManagerName(s, v)
            setenv('MATDB_defaultCacheManagerName', v);
        end
        
        function t = get.pathListCache(v)
            t = MatdbSettingsStore.getenvPathList('MATDB_pathListCache');
        end

        function set.pathListCache(s, v)
            MatdbSettingsStore.setenvPathList('MATDB_pathListCache', v);
        end

        function t = get.pathListAnalysis(v)
            t = MatdbSettingsStore.getenvPathList('MATDB_pathListAnalysis');
        end

        function set.pathListAnalysis(s, v)
            MatdbSettingsStore.setenvPathList('MATDB_pathListAnalysis', v);
        end

        function t = get.permissionsAnalysisFiles(v)
            t = getenv('MATDB_permissionsAnalysisFiles');
        end

        function set.permissionsAnalysisFiles(s, v)
            setenv('MATDB_permissionsAnalysisFiles', v);
        end
        
        function t = get.pathListCSVData(v)
            t = MatdbSettingsStore.getenvPathList('MATDB_pathListCSVData');
        end

        function set.pathListCSVData(s, v)
            MatdbSettingsStore.setenvPathList('MATDB_pathListCSVData', v);
        end
    end
end
