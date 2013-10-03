classdef CSVTable < StructTable

    properties
        csvName
    end

    methods
        function dt = CSVTable(varargin)
            dt = dt@StructTable();

            p = inputParser;
            p.KeepUnmatched = true;
            p.addOptional('csvName', '', @(x) isempty(x) || ischar(x));
            p.addParamValue('entryName', '', @ischar);
            p.parse(varargin{:});

            dt.entryName = p.Results.entryName;
            dt.csvName = p.Results.csvName;
            if isempty(dt.csvName)
                % load an empty database, pass remaining args to StructTable
                data = struct([]);
            else
                % assert file existence
                assert(exist(dt.csvName, 'file') == 2, 'Could not find file %s', dt.csvName);

                % now check whether we can loadFromCache 
               
                if dt.hasCache()
                    dt = dt.loadFromCache();
                    debug('Loaded from cache!\n');
                    return;
                else
                    debug('Cache miss!\n');
                    data = loadCSVAsStruct(dt.csvName);
                end
            end
            if nargin > 1
                argList = varargin(2:end);
            else
                argList = {};
            end

            dt = dt.initialize(data, argList{:});
            dt.cache();
        end
    
        % handle cacheable timestamp here based on the modification time of the file
        

    end

    methods(Access=protected)
        function timestamp = getLastUpdated(obj)
            info = dir(obj.csvName); 
            if isempty(info)
                timestamp = now;
            else
                timestamp = info(1).datenum;
            end
        end
    end

    methods % Cacheable override
        function timestamp = getCacheValidAfterTimestamp(obj)
            % invalidate cache when csv is modified
            timestamp = obj.getLastUpdated();
        end
        
        % return the param to be used when caching
        function param = getCacheParam(obj) 
            param.csvName = obj.csvName; 
        end
    end
end
