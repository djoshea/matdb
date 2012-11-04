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
        % root location of the Matlab cache file 
        pathListCache

        % root location for saving figures, analysis html reports, etc. 
        pathListAnalysis

        % root location for saving csv files 
        pathListCSVData
    end

    methods(Static)
        % load on demand
        function settings = settings()
            persistent pSettings;
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
        end
    end
end

