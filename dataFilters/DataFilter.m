classdef DataFilter < handle & matlab.mixin.Heterogeneous 
% represents a selection criterion for selecting rows from a data table

    properties
        fields = {}; % cellstr of fields whose values are required to apply this filter
        keepMatches = true; % if true, only matches are kept, if false, only non-matches are kept
    end

    properties(Dependent)
        nFields
    end

    methods(Abstract, Static)
        % a set of unique strings for referencing this filter class from createByKeyword 
        keywords = getKeywords
    end

    methods(Abstract)
        % rather than implement a constructor, handle all construction here
        % this is a workaround to facilitate the functionality in createFromKeyword 
        initialize(varargin)

        % applies this filter to the data values in fieldValues
        % for efficiency, currentMask includes only potentially valid entries after
        % applying other filters. Consequently, only the 1s in currentMask need be
        % set to false in newMask by this function, the 0s can be ignored. It is okay
        % however, if 0s are changed to 1s by this function as well, i.e. currentMask
        % may be ignored entirely
        %
        % This should mark as 1 any trials which are selected by this filters.
        % This function should ignore .keepMatches (filter vs filterOut),
        % which will be handled by DataTable
        %
        % dfdMap is a container.Map : field -> DataFieldDescriptor associated with that field
        newMask = getMask(filt, fieldToValueMap, currentMask, dfdMap)

        % return a very brief description of what this filter searches for
        str = describe(filt)
    end

    methods
        % the constructor is sealed and simply forwards to .initialize
        % implement constructor like behavior inside .initialize in subclasses
        function filt = DataFilter(varargin)
            % allow no arguments to be passed and do nothing
            % if any arguments are passed, forward to initialize
            if nargin > 0
                filt.initialize(varargin{:});
            end
        end

        function nFields = get.nFields(filt)
            nFields = length(filt.fields);
        end
    end

    methods(Static)
        function rebuildKeywordMap()
            DataFilter.getKeywordMap(true);
        end

        function map = getKeywordMap(rebuild)
            persistent keywordMap;
            if isempty(keywordMap) || (nargin > 0 && rebuild)
                debug('Building keyword to DataFilter map...\n');
                keywordMap = DataFilter.buildKeywordMap();
                debug('Found filters for keywords: %s\n', strjoin(keywordMap.keys)); 
            end

            map = keywordMap;
        end

        function filt = createFromKeyword(keyword, varargin)
            assert(ischar(keyword), 'Please provide filter keyword string');
            keywordMap = DataFilter.getKeywordMap();
            assert(keywordMap.isKey(keyword), ...
                'DataFilter with keyword %s not found', keyword);

            % this construction process here is why the initialize method is necessary
            % there's no easy way to create a class based on its string name but pass
            % arbitrary argument lists to its constructor. Instead, we create the class
            % with no arguments to its constructor, and then call initialize to do everything
            % else.
            clsName = keywordMap(keyword);
            filt = eval(clsName);  
            filt.initialize(varargin{:});
        end

        function map = buildKeywordMap()
            % build a map of keyword string --> classname
            map = ValueMap('KeyType', 'char', 'ValueType', 'char');
            
            % find all .m files in the same directory as DataFilter.m
            [thisPath] = fileparts(mfilename('fullpath'));
            fileInfo = dir(fullfile(thisPath, '*.m'));

            % loop through them, determining if they are DataFilters
            for iF = 1:length(fileInfo)
                [~, fileNameNoExt] = fileparts(fileInfo(iF).name);
                
                if exist(fileNameNoExt, 'class') && ...
                    ismember('DataFilter', superclasses(fileNameNoExt))
                    
                    % it's a DataFilter, check whether it's abstract
                    meta = eval(['?' fileNameNoExt]);
                    isAbstract = any([meta.PropertyList.Abstract]) || any([meta.MethodList.Abstract]);
                    if isAbstract
                        continue;
                    end

                    % it's a DataFilter, call getKeyword static  methods
                    keywords = eval([fileNameNoExt '.getKeywords()']);
                    % store each keyword -> class name in map
                    if ischar(keywords)
                        keywords = {keywords};
                    end
                    for i = 1:length(keywords)
                        map(keywords{i}) = fileNameNoExt; 
                    end
                end

            end
        end

    end



end
