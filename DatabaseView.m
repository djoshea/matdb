classdef DatabaseView < handle
    
    methods(Abstract)
        % return a single word description of this view
        str = describe(dv);

        % apply the view to the database
        applyToDatabase(dv, database);
    end

    methods
        % return a cell array of other DataSources which must be loaded before
        % this view may be applied 
        function sources = getRequiredSources(dv)
            sources = {};
        end

        % return a cell array of other DatabaseViews which must be applied before
        % this view may be applied 
        function views = getRequiredViews(dv)
            views = {};
        end
    end

    methods
        function disp(dv)
            str = dv.describe();
            fprintf('%s\n\n', str);
        end
    end

end
