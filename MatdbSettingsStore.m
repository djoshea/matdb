classdef MatdbSettingsStore < handle
% Save an instance of this class as matdbSettings.mat
% anywhere on the matlab path (although typically outside of the git repo).
% after filling out the path fields below. It will be loaded automatically
% by setPathMatdb.m when it is called (presumably by startup.m) 
% 
% The reason for setting paths here is to accomodate this code being run on 
% several different locations, each with its own cache.

    % SET THESE PROPERTIES AND SAVE SOMEWHERE ON PATH AS matdbSettings.mat
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
        % load on demand
        function settings = settings(varargin)
            persistent pSettings;
            if ~isempty(varargin) && isa(varargin{1}, 'MatdbSettingsStore')
                pSettings = varargin{1};
            end
            if isempty(pSettings)
                pSettings = MatdbSettingsStore.loadSettings();
            end
            settings = pSettings; 
        end

        function instance = loadSettings()
            try
                data = load('matdbSettings.mat');
                msg = 'matdbSettings.mat should contain an instance of MatdbSettingsStore named matdbSettings';
                assert(isfield(data, 'matdbSettings'), msg);
                instance = data.matdbSettings;
                assert(isa(instance, 'MatdbSettingsStore'), msg);
            catch
                error('ERROR: Could not locate matdbSettings.mat on path. See MatdbSettingsStore');
            end

            % update the persisent cache inside .settings
            MatdbSettingsStore.settings(instance);
        end

        % STATIC ACCESSORS FOR SAVED VALUES
        function cm = getDefaultCacheManager()
            name = MatdbSettingsStore.getDefaultCacheManagerName();
            cm = eval(sprintf('%s()', name));
        end

        function name = getDefaultCacheManagerName()
            name = MatdbSettingsStore.loadSettings.defaultCacheManagerName;
            if isempty(name)
                name = 'CacheManager';
            end
        end

        function pathList = getPathListCache()
            pathList = GetFullPath(MatdbSettingsStore.loadSettings.pathListCache);
        end

        function pathList = getPathListAnalysis()
            pathList = GetFullPath(MatdbSettingsStore.loadSettings.pathListAnalysis);
        end

        function pathList = getPathListCSVData()
            pathList = GetFullPath(MatdbSettingsStore.loadSettings.pathListCSVData);
        end
    end

    methods
        function saveSettings(matdbSettings, path)
            if nargin < 2
                error('Usage: .saveSettings(path)');
            end
            filename = fullfile(path, 'matdbSettings.mat');
            save(filename, 'matdbSettings');
            debug('MatdbSettings saved to %s\n', filename);
            
            % update the persisent cache inside .settings
            MatdbSettingsStore.settings(matdbSettings);
        end
    end
end

