classdef CacheCustomSaveLoad
% interface that CacheManager detects when saving objects to disk that
% enables CacheManager to call out to a custom save and load method rather
% than saving and loading using Matlab's interface.

    methods(Abstract)
        tf = getUseCustomSaveLoad(obj, info);
        
        token = saveCustomToLocation(obj, location);
    end
    
    methods(Abstract, Static)
        data = loadCustomFromLocation(location, token)
    end
    
    methods(Static)
        function tf = checkIfCustomSaveLoadOkay(val)
            tf = false;
            necessaryMethodList = {'getUseCustomSaveLoad', 'saveCustomToLocation', 'loadCustomFromLocation'};
            if isobject(val)
                methodList = methods(val);
                if all(ismember(necessaryMethodList, methodList))
                    % check if okay to use custom save
                    if val.getUseCustomSaveLoad()
                        tf = true;
                    end
                end
            end
        end
    end
    
end